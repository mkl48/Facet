-- Facet
-- VoxelController/init.luau
-- Plinko Labs
--
-- Returned by Facet.Define(). Owns one Shatter pipeline: resolve candidate parts -> (optionally)
-- classify them against a Hitbox -> voxelize -> apply Effects -> run Cleanup -> fire Result
-- through the PendingResult chain. The public shape (Define, Host, RuntimeType, Shatter,
-- Hitbox/Effects/Cleanup, Result.Voxels.Whole/Partial/Extra) is final. Spatial lookup runs
-- through a per-call Octree (so it works for any candidate regardless of CanQuery/workspace
-- placement) and all four QueryTypes are wired up; cells that land outside the hitbox (kind
-- "Extra") are greedy-meshed into a handful of boxes, while cells the player is meant to see
-- fragment ("Partial"/no-hitbox) stay one piece per cell. Multithreaded slicing across Actors
-- for Relative controllers is the one item still NOT implemented - see Voxelize.luau.

local Enums = require(script.Parent.Enums)
local PendingResult = require(script.PendingResult)
local VoxelModule = require(script.Voxel)
local Voxelize = require(script.Voxelize)
local Octree = require(script.Octree)

local Voxel = VoxelModule.new
local applyEffects = VoxelModule.applyEffects

-- Every voxel produced from slicing a part lands under workspace._Bin.Voxels.<PartName>,
-- grouped by the original part's Name, instead of back into wherever the part used to live -
-- keeps debris out of the place hierarchy the rest of the game depends on, and keeps every
-- hit on the same part collected in one Model across calls.
local function voxelGroupFor(name: string): Model
	local bin = workspace:FindFirstChild("_Bin")
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = "_Bin"
		bin.Parent = workspace
	end

	local voxels = bin:FindFirstChild("Voxels")
	if not voxels then
		voxels = Instance.new("Folder")
		voxels.Name = "Voxels"
		voxels.Parent = bin
	end

	local group = voxels:FindFirstChild(name)
	if not group or not group:IsA("Model") then
		group = Instance.new("Model")
		group.Name = name
		group.Parent = voxels
	end

	return group :: Model
end

export type HitboxConfig = {
	Size: Vector3?,
	CFrame: CFrame?,
	ViewVector: Vector3?,
	Color: Color3?,
	QueryType: Enums.QueryType?,
	HitboxType: Enums.HitboxType?,
	Shape: Enum.PartType?,
	Copy: Instance?,
}

export type ShatterConfig = {
	Hitbox: HitboxConfig?,
	Effects: { [string]: any }?,
	Cleanup: (Enums.Cleanup | ((any) -> ()))?,
	-- Seconds the Cleanup tween takes (Fade/Rebuild only - Destroy is instant and ignores
	-- this). Defaults to 0.5 for Fade, 0.6 for Rebuild when omitted.
	CleanupDuration: number?,
}

export type DefineConfig = {
	Type: Enums.ControllerType,
	RuntimeType: Enums.RuntimeType?,
	Host: Instance?,
	MinimumVoxelSize: number?,
	RecommendedVoxelSize: number?,
	Drivers: { VoxelizationMethod: string? }?,
	VoxelSize: number?,
}

-- The actual instance Facet.Define()/VoxelController.new() hands back. Typed explicitly (and
-- returned through this type, not `any`) so callers get real Intellisense on `:Shatter()`,
-- `:Start()`, `:Destroy()`, and the controller's own fields instead of `any`.
export type VoxelController = {
	Type: Enums.ControllerType,
	RuntimeType: Enums.RuntimeType,
	Host: Instance?,
	Drivers: { VoxelizationMethod: string? }?,
	MinimumVoxelSize: number?,
	RecommendedVoxelSize: number?,
	VoxelSize: number?,
	Shatter: (self: VoxelController, a: Instance | ShatterConfig, b: ShatterConfig?) -> PendingResult.PendingResult,
	Start: (self: VoxelController) -> (),
	Destroy: (self: VoxelController) -> (),
}

local VoxelController = {}
VoxelController.__index = VoxelController

function VoxelController.new(config: DefineConfig): VoxelController
	assert(config.Type == Enums.ControllerType.Relative or config.Type == Enums.ControllerType.Absolute, "Define requires Type to be Enums.ControllerType.Relative or .Absolute")

	local self = setmetatable({
		Type = config.Type,
		RuntimeType = config.RuntimeType or Enums.RuntimeType.Instant,
		Host = config.Host,
		Drivers = config.Drivers,
		_queue = {},
		_started = false,
	}, VoxelController)

	if config.Type == Enums.ControllerType.Relative then
		assert(config.RecommendedVoxelSize, "Relative controllers require RecommendedVoxelSize")
		self.RecommendedVoxelSize = config.RecommendedVoxelSize
		-- falls back to Recommended (no shrink) when Minimum isn't given
		self.MinimumVoxelSize = config.MinimumVoxelSize or config.RecommendedVoxelSize
	else
		assert(config.VoxelSize, "Absolute controllers require VoxelSize")
		self.VoxelSize = config.VoxelSize
	end

	return (self :: any) :: VoxelController
end

function VoxelController:_voxelSizeFor(part: BasePart): number
	if self.Type == Enums.ControllerType.Absolute then
		return Voxelize.resolveVoxelSize(part, { Absolute = self.VoxelSize })
	end
	return Voxelize.resolveRelativeSize(part, self.RecommendedVoxelSize, self.MinimumVoxelSize)
end

function VoxelController:_resolveCandidateParts(target: Instance): { BasePart }
	if target:IsA("BasePart") then
		return { target }
	end
	local parts = {}
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function boundingSphereRadius(part: BasePart): number
	return part.Size.Magnitude / 2
end

-- Exact overlap tests, one per QueryType shape. Octree:Query() already narrowed the candidate
-- list to a broad-phase sphere match - these decide the real geometry.
function VoxelController:_intersectsBox(part: BasePart, cframe: CFrame, size: Vector3): boolean
	local relative = cframe:PointToObjectSpace(part.Position)
	local half = size / 2
	local clamped = Vector3.new(
		math.clamp(relative.X, -half.X, half.X),
		math.clamp(relative.Y, -half.Y, half.Y),
		math.clamp(relative.Z, -half.Z, half.Z)
	)
	return (relative - clamped).Magnitude <= boundingSphereRadius(part)
end

function VoxelController:_intersectsSphere(part: BasePart, center: Vector3, radius: number): boolean
	return (part.Position - center).Magnitude <= radius + boundingSphereRadius(part)
end

-- Region behaves like Box but axis-aligned in world space (CFrame rotation ignored) - this
-- mirrors Roblox's own Region3, which has no orientation.
function VoxelController:_intersectsRegion(part: BasePart, position: Vector3, size: Vector3): boolean
	local relative = part.Position - position
	local half = size / 2
	local clamped = Vector3.new(
		math.clamp(relative.X, -half.X, half.X),
		math.clamp(relative.Y, -half.Y, half.Y),
		math.clamp(relative.Z, -half.Z, half.Z)
	)
	return (relative - clamped).Magnitude <= boundingSphereRadius(part)
end

-- Same shapes as the part-overlap tests above, but for a single point - used to classify
-- individual grid cells (Partial vs Extra) once a part has already matched the hitbox.
function VoxelController:_pointInsideHitbox(point: Vector3, hitbox: HitboxConfig): boolean
	local size = hitbox.Size or Vector3.new(4, 4, 4)
	local cframe = hitbox.CFrame or CFrame.new()
	local queryType = hitbox.QueryType or Enums.QueryType.Box

	if queryType == Enums.QueryType.Sphere then
		return (point - cframe.Position).Magnitude <= size.X / 2
	end

	local relative = if queryType == Enums.QueryType.Region then point - cframe.Position else cframe:PointToObjectSpace(point)
	local half = size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

function VoxelController:_isFullyContained(part: BasePart, hitbox: HitboxConfig): boolean
	local size = hitbox.Size or Vector3.new(4, 4, 4)
	local cframe = hitbox.CFrame or CFrame.new()
	local queryType = hitbox.QueryType or Enums.QueryType.Box
	local partHalf = boundingSphereRadius(part)

	if queryType == Enums.QueryType.Sphere then
		return (part.Position - cframe.Position).Magnitude + partHalf <= size.X / 2
	end

	local relative = if queryType == Enums.QueryType.Region then part.Position - cframe.Position else cframe:PointToObjectSpace(part.Position)
	local half = size / 2
	return math.abs(relative.X) + partHalf <= half.X
		and math.abs(relative.Y) + partHalf <= half.Y
		and math.abs(relative.Z) + partHalf <= half.Z
end

-- Resolves which candidates the hitbox actually catches. Box/Sphere/Region all go through the
-- Octree broad-phase first; Raycast has no volume to broad-phase against an Octree leaf set, so
-- it casts straight through the engine (single closest hit - see the Raycast caveat in README).
function VoxelController:_queryHitbox(hitbox: HitboxConfig, candidates: { BasePart }): { BasePart }
	local queryType = hitbox.QueryType or Enums.QueryType.Box
	local size = hitbox.Size or Vector3.new(4, 4, 4)
	local cframe = hitbox.CFrame or CFrame.new()

	if queryType == Enums.QueryType.Raycast then
		local direction = hitbox.ViewVector or cframe.LookVector
		local length = if size.Z > 0 then size.Z else math.max(direction.Magnitude, 1)
		direction = if direction.Magnitude > 1e-3 then direction.Unit * length else cframe.LookVector * length

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = candidates
		local result = workspace:Raycast(cframe.Position, direction, params)
		if result and result.Instance then
			return { result.Instance :: BasePart }
		end
		return {}
	end

	local octree = Octree.fromParts(candidates)
	local broad = octree:Query(cframe.Position, size.Magnitude / 2)
	local matches = {}
	for _, part in broad do
		local hit
		if queryType == Enums.QueryType.Sphere then
			hit = self:_intersectsSphere(part, cframe.Position, size.X / 2)
		elseif queryType == Enums.QueryType.Region then
			hit = self:_intersectsRegion(part, cframe.Position, size)
		else
			hit = self:_intersectsBox(part, cframe, size)
		end
		if hit then
			table.insert(matches, part)
		end
	end
	return matches
end

-- Slices `part` and wraps each piece as a Voxel. `classify(worldPosition)` returns "Partial" or
-- "Extra" (defaults every cell to "Partial" when there's no hitbox to classify against). Only
-- "Extra" cells - produced but not actually wanted - get greedy-meshed into larger boxes; every
-- other cell stays one instance per grid cell, since that's the visible debris Shatter exists
-- to produce.
function VoxelController:_voxelizePart(part: BasePart, config: ShatterConfig, origin: Vector3?, classify: ((Vector3) -> string)?)
	local voxelSize = (config :: any).Size or self:_voxelSizeFor(part)
	local grid = Voxelize.buildGrid(part, voxelSize)
	local resolvedClassify = classify or function()
		return "Partial"
	end

	local parent = voxelGroupFor(part.Name)
	local wasAnchored = part.Anchored
	local produced: { [string]: { any } } = { Whole = {}, Partial = {}, Extra = {} }

	local function emit(cframe: CFrame, size: Vector3, kind: string)
		local instance = Instance.new("Part")
		instance.Size = size
		instance.CFrame = cframe
		instance.Color = grid.Color
		instance.Material = grid.Material
		instance.Anchored = wasAnchored
		instance.Parent = parent

		applyEffects(instance, config.Effects, origin or part.Position)
		table.insert(produced[kind], Voxel(instance, kind, self))
	end

	local merged = Voxelize.greedyMesh(grid, function(pos)
		return if resolvedClassify(pos) == "Extra" then "Extra" else nil
	end)
	for _, data in merged do
		emit(data.CFrame, data.Size, data.Kind)
	end

	for x = 0, grid.CountX - 1 do
		for y = 0, grid.CountY - 1 do
			for z = 0, grid.CountZ - 1 do
				local pos = Voxelize.cellPosition(grid, x, y, z)
				local kind = resolvedClassify(pos)
				if kind ~= "Extra" then
					local cframe = grid.Origin * CFrame.new((x + 0.5) * grid.StepX, (y + 0.5) * grid.StepY, (z + 0.5) * grid.StepZ)
					emit(cframe, Vector3.new(grid.StepX, grid.StepY, grid.StepZ), kind)
				end
			end
		end
	end

	part:Destroy()
	return produced
end

function VoxelController:_runShatter(target: Instance, config: ShatterConfig, pending: PendingResult.PendingResult)
	local candidates = self:_resolveCandidateParts(target)
	local buckets = { Whole = {}, Partial = {}, Extra = {} }
	local hitbox = config.Hitbox

	if not hitbox then
		for _, part in candidates do
			local produced = self:_voxelizePart(part, config, part.Position)
			table.move(produced.Partial, 1, #produced.Partial, #buckets.Partial + 1, buckets.Partial)
		end
	else
		local cframe = hitbox.CFrame or CFrame.new()
		local hitboxType = hitbox.HitboxType or Enums.HitboxType.Partial
		local overlapping = self:_queryHitbox(hitbox, candidates)

		for _, part in overlapping do
			if hitboxType == Enums.HitboxType.Whole and self:_isFullyContained(part, hitbox) then
				table.insert(buckets.Whole, Voxel(part, Enums.HitboxType.Whole, self))
			else
				local produced = self:_voxelizePart(part, config, cframe.Position, function(pos)
					return if self:_pointInsideHitbox(pos, hitbox) then "Partial" else "Extra"
				end)
				table.move(produced.Partial, 1, #produced.Partial, #buckets.Partial + 1, buckets.Partial)
				table.move(produced.Extra, 1, #produced.Extra, #buckets.Extra + 1, buckets.Extra)
			end
		end
	end

	local result = {
		Voxels = buckets,
		Instance = target,
	}

	pending:_fire(Enums.Event.NewVoxel, result)

	-- Cleanup only ever runs on Partial - that's the debris Shatter exists to produce. Extra
	-- is the untouched remainder of the target (just reconstructed as fewer, greedy-meshed
	-- parts) and is left in the world; callers that want it gone can :Cleanup() it themselves
	-- off Result.Voxels.Extra.
	local cleanupMethod = config.Cleanup
	if cleanupMethod then
		local pendingDestroy = 0
		local function track(voxel)
			pendingDestroy += 1
			voxel.Instance.Destroying:Once(function()
				pendingDestroy -= 1
				if pendingDestroy == 0 then
					pending:_fire(Enums.Event.Destroyed, result)
				end
			end)
		end
		for _, voxel in buckets.Partial do
			track(voxel)
		end
		for _, voxel in buckets.Partial do
			voxel:Cleanup(cleanupMethod, config.CleanupDuration)
		end
	end

	self._cleanup = cleanupMethod
end

-- `Shatter(Config)` when the controller has a Host (Target is implied); `Shatter(Target, Config)`
-- otherwise. Hitbox is optional - omit it to shatter the whole Target/Host directly.
function VoxelController:Shatter(a: Instance | ShatterConfig, b: ShatterConfig?)
	local target: Instance
	local config: ShatterConfig

	if typeof(a) == "table" then
		assert(self.Host, "Shatter() with no Target requires the controller to have a Host")
		target = self.Host
		config = a :: ShatterConfig
	else
		target = a :: Instance
		config = b or {}
	end

	local pending = PendingResult.new()

	if self.RuntimeType == Enums.RuntimeType.Timeline and not self._started then
		table.insert(self._queue, { target = target, config = config, pending = pending })
		return pending
	end

	self:_runShatter(target, config, pending)
	return pending
end

-- Flushes the Timeline queue in call order. No-op for Instant controllers (they never queue).
function VoxelController:Start()
	self._started = true
	local queue = self._queue
	self._queue = {}
	for _, job in queue do
		self:_runShatter(job.target, job.config, job.pending)
	end
end

function VoxelController:Destroy()
	self._queue = {}
end

return VoxelController
