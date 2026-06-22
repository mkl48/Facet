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
-- fragment ("Partial"/no-hitbox) stay one piece per cell. Relative controllers split the
-- per-part grid classification + greedy meshing across an Actor pool when a call touches more
-- than one part - see Workers/init.luau and _voxelizeBatch below.

local Enums = require(script.Parent.Enums)
local PendingResult = require(script.PendingResult)
local VoxelModule = require(script.Voxel)
local Voxelize = require(script.Voxelize)
local Octree = require(script.Octree)
local Workers = require(script.Workers)
local ConfigModule = require(script.Parent.Config)
local Pool = require(script.Parent.Pool)

local Config = ConfigModule.Config

local Voxel = VoxelModule.new
local applyEffects = VoxelModule.applyEffects

-- Every Chunk assembly's pieces share this CollisionGroup, set non-collidable with itself, so
-- welded siblings (which touch at shared grid faces) don't fight each other for contact space -
-- without it, the physics solver treats those touching unanchored parts as overlapping and fires
-- a huge separating impulse the instant they're created, which spikes AssemblyLinearVelocity past
-- BreakSpeed and shreds the assembly into shrapnel before gravity ever gets to make it fall as one
-- piece. CanTouch stays true (set in _emitCells) so impact detection against the world still works.
local CHUNK_COLLISION_GROUP = "Facet_Chunk"
local chunkCollisionGroupReady = false
local function ensureChunkCollisionGroup()
	if chunkCollisionGroupReady then
		return
	end
	local PhysicsService = game:GetService("PhysicsService")
	if not PhysicsService:IsCollisionGroupRegistered(CHUNK_COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(CHUNK_COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(CHUNK_COLLISION_GROUP, CHUNK_COLLISION_GROUP, false)
	chunkCollisionGroupReady = true
end

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

--[=[
	@interface HitboxConfig
	@within VoxelController
	.Size Vector3? -- box/region extents, in studs, centered on `CFrame`. Ignored by `Raycast`.
	.CFrame CFrame? -- where the hitbox sits in the world. Defaults to `CFrame.new()` (the origin) if omitted.
	.ViewVector Vector3? -- cast direction for `QueryType.Raycast` only; ignored by every other QueryType.
	.Color Color3? -- cosmetic only - tints a visualized hitbox if you render one yourself. Facet never draws it for you.
	.QueryType Enums.QueryType? -- `Box` (default) | `Sphere` | `Region` | `Raycast`. Picks which exact-shape test runs after the octree broad phase.
	.HitboxType Enums.HitboxType? -- `Partial` (default, voxelizes whatever's detected) | `Whole` (returns fully-contained parts untouched, no slicing).
	.Shape Enum.PartType? -- reserved for a future visualized-hitbox helper; not read by Shatter today.
	.Copy Instance? -- reserved for a future "clone the hitbox as a real part" helper; not read by Shatter today.
	.Scope Instance? -- only read when `Shatter` is called with no Target and no Host (indiscriminate destruction) - restricts the workspace-wide query to this instance's descendants. Defaults to the whole `workspace`. Ignored otherwise (a Target/Host already scopes the search).
]=]
export type HitboxConfig = {
	Size: Vector3?,
	CFrame: CFrame?,
	ViewVector: Vector3?,
	Color: Color3?,
	QueryType: Enums.QueryType?,
	HitboxType: Enums.HitboxType?,
	Shape: Enum.PartType?,
	Copy: Instance?,
	Scope: Instance?,
}

--[=[
	@interface CleanupConfig
	@within VoxelController
	.Method (Enums.Cleanup | (Voxel) -> ())? -- `Rebuild` | `Fade` | `Destroy`, or your own `function(voxel) ... end`. Only ever runs against `Result.Voxels.Partial`.
	.Delay number? -- seconds the Cleanup tween takes (`Fade`/`Rebuild` only - `Destroy` is instant). Defaults to 0.5 for Fade, 0.6 for Rebuild.
]=]
export type CleanupConfig = {
	Method: (Enums.Cleanup | ((any) -> ()))?,
	Delay: number?,
}

--[=[
	@interface ShatterConfig
	@within VoxelController
	.Hitbox HitboxConfig? -- scopes detection to a region of the target. Omit entirely to voxelize the whole target.
	.Effects {[string]: any}? -- keyed by `Enums.Effects` - see [Enums.Effects] for the full list and each one's config shape.
	.Cleanup CleanupConfig? -- `{ Method = Enums.Cleanup.X, Delay = number? }`, or your own `{ Method = function(voxel) ... end }`.
]=]
export type ShatterConfig = {
	Hitbox: HitboxConfig?,
	Effects: { [string]: any }?,
	Cleanup: CleanupConfig?,
}

--[=[
	@interface DefineConfig
	@within VoxelController
	.Type Enums.ControllerType -- `Relative` (dynamic sizing, requires `RecommendedVoxelSize`) or `Absolute` (fixed `VoxelSize`). Required.
	.RuntimeType Enums.RuntimeType? -- `Instant` (default, runs every Shatter immediately) or `Timeline` (queues calls until `:Start()`).
	.Host Instance? -- scopes every Shatter call on this controller to one instance without naming a Target each time.
	.MinimumVoxelSize number? -- Relative only. Floor `Shatter` will shrink voxels to under load. Defaults to `RecommendedVoxelSize` (no shrink) if omitted.
	.RecommendedVoxelSize number? -- Relative only. Target voxel size the controller sizes toward. Required for `Relative`.
	.Drivers {VoxelizationMethod: string?}? -- reserved for swapping the slicing backend; not read by Shatter today.
	.VoxelSize number? -- Absolute only. The fixed cube size every voxel is sliced to. Required for `Absolute`.
]=]
export type DefineConfig = {
	Type: Enums.ControllerType,
	RuntimeType: Enums.RuntimeType?,
	Host: Instance?,
	MinimumVoxelSize: number?,
	RecommendedVoxelSize: number?,
	Drivers: { VoxelizationMethod: string? }?,
	VoxelSize: number?,
}

--[=[
	@class VoxelController
	Returned by [Facet.Define]. Owns one Shatter pipeline: resolve candidate parts, optionally
	classify them against a [HitboxConfig], voxelize, apply Effects, run Cleanup, and fire a
	[Result] through the [PendingResult] chain. Typed explicitly (never `any`) so every field
	and method below has real Intellisense.
]=]
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

-- The no-Target/no-Host path ("indiscriminate destruction"): there's no candidate list to
-- narrow with our own Octree, so the hitbox itself queries the engine's native spatial index
-- directly (workspace:GetPartBoundsInBox/Radius, or :Raycast) over `hitbox.Scope` (default the
-- whole workspace) instead. Those calls already do an exact overlap test, not just broad-phase.
function VoxelController:_queryWorkspace(hitbox: HitboxConfig): { BasePart }
	local queryType = hitbox.QueryType or Enums.QueryType.Box
	local size = hitbox.Size or Vector3.new(4, 4, 4)
	local cframe = hitbox.CFrame or CFrame.new()
	local scope = hitbox.Scope

	if queryType == Enums.QueryType.Raycast then
		local direction = hitbox.ViewVector or cframe.LookVector
		local length = if size.Z > 0 then size.Z else math.max(direction.Magnitude, 1)
		direction = if direction.Magnitude > 1e-3 then direction.Unit * length else cframe.LookVector * length

		local params = RaycastParams.new()
		if scope then
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { scope }
		end
		local result = workspace:Raycast(cframe.Position, direction, params)
		if result and result.Instance and result.Instance:IsA("BasePart") then
			return { result.Instance :: BasePart }
		end
		return {}
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { scope or workspace }

	if queryType == Enums.QueryType.Sphere then
		return workspace:GetPartBoundsInRadius(cframe.Position, size.X / 2, overlap)
	end

	local box = if queryType == Enums.QueryType.Region then CFrame.new(cframe.Position) else cframe
	return workspace:GetPartBoundsInBox(box, size, overlap)
end

-- Reads `part` once (Size/CFrame/Color/Material - the only Instance access in this whole
-- pipeline) and lays out its grid, packaged with a plain (HitboxConfig-shaped but Instance-free)
-- hitbox alongside it. The result is what a Workers job actually carries across the Actor
-- boundary - see Workers/init.luau.
function VoxelController:_buildJob(part: BasePart, config: ShatterConfig, hitbox: HitboxConfig?): Workers.Job
	local voxelSize = (config :: any).Size or self:_voxelSizeFor(part)
	local grid = Voxelize.buildGrid(part, voxelSize)
	local pointHitbox = if hitbox then { Size = hitbox.Size, CFrame = hitbox.CFrame, QueryType = hitbox.QueryType } else nil
	return { Grid = grid, Hitbox = pointHitbox, GreedyMeshing = Config.GreedyMeshing }
end

-- Turns an already-computed cell list (Voxelize.computeCells' output, from either the inline
-- path or a Workers job) into real Parts, parented under workspace._Bin.Voxels.<part.Name> and
-- wrapped as Voxels. The only place Instance.new ever runs in the whole Shatter pipeline.
function VoxelController:_emitCells(part: BasePart, config: ShatterConfig, origin: Vector3?, cells: { Voxelize.MergedVoxel }): { [string]: { VoxelModule.Voxel } }
	local parent = voxelGroupFor(part.Name)
	local wasAnchored = part.Anchored
	local produced: { [string]: { VoxelModule.Voxel } } = { Whole = {}, Partial = {}, Extra = {} }

	for _, data in cells do
		local instance = if Config.ObjectPooling then Pool.acquire() else Instance.new("Part")
		instance.Size = data.Size
		instance.CFrame = data.CFrame
		instance.Color = data.Color
		instance.Material = data.Material
		instance.Transparency = 0
		instance.Anchored = wasAnchored
		instance.CanCollide = true
		instance.CanQuery = true
		instance.CanTouch = true
		instance.Parent = parent

		applyEffects(instance, config.Effects, origin or part.Position)
		table.insert(produced[data.Kind], Voxel(instance, data.Kind, self, origin))
	end

	part:Destroy()
	return produced
end

-- Effects.Chunk: welds every voxel one whole Shatter call produced - across every candidate part
-- the call touched, not just one - into a single unanchored rigid assembly (a star topology -
-- every piece welded straight to the first piece, `root`) instead of the per-voxel unanchor
-- every other Effect does, so the remainder of a multi-part target (e.g. a Model built from
-- several Parts) falls and lands as one piece, rather than each original part's slice becoming
-- its own disconnected chunk. A weld breaks - detaching that piece and everything within
-- BreakRadius of it - the moment its relative impact speed reaches BreakSpeed, so a hard enough
-- landing fractures the assembly into smaller chunks instead of staying one rigid lump forever.
function VoxelController:_makeChunk(partial: { VoxelModule.Voxel }, extra: { VoxelModule.Voxel }, chunkConfig: any)
	local settings = if type(chunkConfig) == "table" then chunkConfig else {}
	local breakSpeed = settings.BreakSpeed or 40
	local breakRadius = settings.BreakRadius or 4

	local pieces: { BasePart } = {}
	for _, voxel in partial do
		table.insert(pieces, voxel.Instance)
	end
	for _, voxel in extra do
		table.insert(pieces, voxel.Instance)
	end
	ensureChunkCollisionGroup()
	for _, piece in pieces do
		piece.Anchored = false
		piece.CollisionGroup = CHUNK_COLLISION_GROUP
	end
	if #pieces < 2 then
		return
	end

	local root = pieces[1]
	local welds: { [BasePart]: WeldConstraint } = {}
	for i = 2, #pieces do
		local piece = pieces[i]
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = piece
		weld.Parent = piece
		welds[piece] = weld
	end

	local connections: { RBXScriptConnection } = {}
	local remaining = #pieces - 1

	local function detachNear(position: Vector3)
		for piece, weld in welds do
			if (piece.Position - position).Magnitude <= breakRadius then
				weld:Destroy()
				welds[piece] = nil
				remaining -= 1
			end
		end
		if remaining <= 0 then
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end

	local lastCheck: { [BasePart]: number } = {}
	for _, piece in pieces do
		table.insert(
			connections,
			piece.Touched:Connect(function(other: BasePart)
				local now = os.clock()
				if (lastCheck[piece] or 0) + 0.1 > now then
					return
				end
				lastCheck[piece] = now
				local otherVelocity = if other:IsA("BasePart") then other.AssemblyLinearVelocity else Vector3.zero
				local relativeSpeed = (piece.AssemblyLinearVelocity - otherVelocity).Magnitude
				if relativeSpeed >= breakSpeed then
					detachNear(piece.Position)
				end
			end)
		)
	end
end

-- The single-part path: builds the job and computes its cells inline, on the calling thread.
-- Used by Absolute controllers and by Relative controllers when there's only one part to slice
-- (an Actor round-trip isn't worth it for one part - see _runShatter for the batched path).
function VoxelController:_voxelizePart(part: BasePart, config: ShatterConfig, origin: Vector3?, hitbox: HitboxConfig?)
	local job = self:_buildJob(part, config, hitbox)
	local classify = if hitbox
		then function(pos: Vector3)
			return Voxelize.classifyPoint(pos, job.Hitbox :: Voxelize.PointHitbox)
		end
		else function()
			return "Partial"
		end
	local cells = Voxelize.computeCells(job.Grid, classify, job.GreedyMeshing)
	return self:_emitCells(part, config, origin, cells)
end

-- Relative controllers split voxelization for more than one part across the Workers Actor pool
-- (see Workers/init.luau) - each part's grid classification + greedy meshing runs on its own
-- desynchronized thread, then every result comes back here to actually create Parts. Absolute
-- controllers, and any Relative call that only touches one part, skip the Actor round-trip
-- entirely via _voxelizePart above.
function VoxelController:_voxelizeBatch(parts: { BasePart }, config: ShatterConfig, origin: Vector3?, hitbox: HitboxConfig?): { [string]: { VoxelModule.Voxel } }
	if #parts == 0 then
		return { Whole = {}, Partial = {}, Extra = {} }
	end
	if self.Type ~= Enums.ControllerType.Relative or #parts == 1 or not Config.Multithreading then
		local combined: { [string]: { VoxelModule.Voxel } } = { Whole = {}, Partial = {}, Extra = {} }
		for _, part in parts do
			local produced = self:_voxelizePart(part, config, origin, hitbox)
			table.move(produced.Partial, 1, #produced.Partial, #combined.Partial + 1, combined.Partial)
			table.move(produced.Extra, 1, #produced.Extra, #combined.Extra + 1, combined.Extra)
		end
		return combined
	end

	local jobs: { Workers.Job } = {}
	for i, part in parts do
		jobs[i] = self:_buildJob(part, config, hitbox)
	end
	local results = Workers.computeAsync(jobs)

	local combined: { [string]: { VoxelModule.Voxel } } = { Whole = {}, Partial = {}, Extra = {} }
	for i, part in parts do
		local produced = self:_emitCells(part, config, origin, results[i])
		table.move(produced.Partial, 1, #produced.Partial, #combined.Partial + 1, combined.Partial)
		table.move(produced.Extra, 1, #produced.Extra, #combined.Extra + 1, combined.Extra)
	end
	return combined
end

-- Splits `overlapping` into Whole (fully contained, HitboxType.Whole only) vs toSlice, then
-- voxelizes toSlice. Shared by both the Target/Host path (overlapping comes from _queryHitbox,
-- narrowed to the target's own descendants) and the unmounted path (overlapping comes from
-- _queryWorkspace, narrowed only by hitbox.Scope) below.
function VoxelController:_classifyAndSlice(overlapping: { BasePart }, hitbox: HitboxConfig, config: ShatterConfig, origin: Vector3): ({ VoxelModule.Voxel }, { [string]: { VoxelModule.Voxel } })
	local hitboxType = hitbox.HitboxType or Enums.HitboxType.Partial
	local whole: { VoxelModule.Voxel } = {}
	local toSlice: { BasePart } = {}
	for _, part in overlapping do
		if hitboxType == Enums.HitboxType.Whole and self:_isFullyContained(part, hitbox) then
			table.insert(whole, Voxel(part, Enums.HitboxType.Whole, self, origin))
		else
			table.insert(toSlice, part)
		end
	end
	local produced = self:_voxelizeBatch(toSlice, config, origin, hitbox)
	return whole, produced
end

function VoxelController:_runShatter(target: Instance?, config: ShatterConfig, pending: PendingResult.PendingResult)
	local buckets: { Whole: { VoxelModule.Voxel }, Partial: { VoxelModule.Voxel }, Extra: { VoxelModule.Voxel } } =
		{ Whole = {}, Partial = {}, Extra = {} }
	local hitbox = config.Hitbox

	if not target then
		-- Indiscriminate destruction: no Target/Host means the hitbox itself is the only scope,
		-- queried directly against the engine (see _queryWorkspace) instead of against a
		-- specific instance's descendants.
		assert(hitbox, "Shatter() with no Target and no Host requires a Hitbox (indiscriminate destruction)")
		local cframe = hitbox.CFrame or CFrame.new()
		local overlapping = self:_queryWorkspace(hitbox)
		local whole, produced = self:_classifyAndSlice(overlapping, hitbox, config, cframe.Position)
		table.move(whole, 1, #whole, #buckets.Whole + 1, buckets.Whole)
		table.move(produced.Partial, 1, #produced.Partial, #buckets.Partial + 1, buckets.Partial)
		table.move(produced.Extra, 1, #produced.Extra, #buckets.Extra + 1, buckets.Extra)
	elseif not hitbox then
		local candidates = self:_resolveCandidateParts(target)
		local produced = self:_voxelizeBatch(candidates, config, nil, nil)
		table.move(produced.Partial, 1, #produced.Partial, #buckets.Partial + 1, buckets.Partial)
	else
		local candidates = self:_resolveCandidateParts(target)
		local cframe = hitbox.CFrame or CFrame.new()
		local overlapping = self:_queryHitbox(hitbox, candidates)
		local whole, produced = self:_classifyAndSlice(overlapping, hitbox, config, cframe.Position)
		table.move(whole, 1, #whole, #buckets.Whole + 1, buckets.Whole)
		table.move(produced.Partial, 1, #produced.Partial, #buckets.Partial + 1, buckets.Partial)
		table.move(produced.Extra, 1, #produced.Extra, #buckets.Extra + 1, buckets.Extra)
	end

	-- Welds the whole call's output together, across every candidate part it touched - has to
	-- run after every part's voxels exist, not per-part, so a multi-part target (a Model built
	-- from several Parts) collapses as one assembly instead of each part's slice becoming its
	-- own disconnected chunk.
	local chunkConfig = config.Effects and config.Effects[Enums.Effects.Chunk]
	if chunkConfig then
		self:_makeChunk(buckets.Partial, buckets.Extra, chunkConfig)
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
	local cleanupMethod = config.Cleanup and config.Cleanup.Method
	if cleanupMethod then
		local delay = config.Cleanup and config.Cleanup.Delay
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
			voxel:Cleanup(cleanupMethod, delay)
		end
	end

	self._cleanup = cleanupMethod
end

--[=[
	@within VoxelController
	@method Shatter
	@param a Instance | ShatterConfig -- a Target when the controller has no Host, otherwise the ShatterConfig directly.
	@param b ShatterConfig? -- the config, when `a` was a Target.
	@return PendingResult -- chain off it with `:Next(Enums.Event.X):Then(callback)`.

	`Shatter(Config)` when the controller has a [Host], Target is implied. `Shatter(Target, Config)`
	otherwise. `Hitbox` is optional in either form - omit it to shatter the whole Target/Host
	directly with no detection step.

	A third form: `Shatter(Config)` with **no Host and a `Hitbox`** runs indiscriminate
	destruction - there's no single Target, so the hitbox queries `hitbox.Scope` (default the
	whole `workspace`) directly and shatters whatever it finds, regardless of which part it came
	from. `Result.Instance` is `nil` for this form, since no one Target/Host exists.
]=]
function VoxelController:Shatter(a: Instance | ShatterConfig, b: ShatterConfig?): PendingResult.PendingResult
	local target: Instance?
	local config: ShatterConfig

	if typeof(a) == "table" then
		config = a :: ShatterConfig
		if self.Host then
			target = self.Host
		else
			assert(config.Hitbox, "Shatter() with no Target and no Host requires a Hitbox (indiscriminate destruction)")
			target = nil
		end
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

--[=[
	@within VoxelController
	@method Start
	Flushes the `Timeline` queue in call order. No-op for `Instant` controllers - they never queue,
	every `:Shatter()` call already ran by the time it returns.
]=]
function VoxelController:Start()
	self._started = true
	local queue = self._queue
	self._queue = {}
	for _, job in queue do
		self:_runShatter(job.target, job.config, job.pending)
	end
end

--[=[
	@within VoxelController
	@method Destroy
	Clears any queued `Timeline` jobs that haven't run yet. Doesn't touch parts already produced
	by past `:Shatter()` calls - those live on independently under `workspace._Bin.Voxels`.
]=]
function VoxelController:Destroy()
	self._queue = {}
end

return VoxelController
