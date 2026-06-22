-- Facet
-- VoxelController/Voxelize.luau
-- Plinko Labs
--
-- Slices one BasePart into an axis-aligned grid of same-size cubes at the part's own
-- orientation, then (optionally) greedy-meshes runs of identically-classified cells into
-- larger boxes - the standard "merge dimension by dimension" technique used by voxel engines
-- (merge along X into runs, merge matching runs along Y into rectangles, merge matching
-- rectangles along Z into boxes).
--
-- Every function below this point is pure: Grid/HitboxConfig/Vector3/CFrame are plain data, and
-- nothing here ever touches a live Instance. That's deliberate - it's what lets
-- VoxelController/Workers run computeCells() on a desynchronized Actor (see Workers/init.luau).
-- Only `buildGrid` reads a BasePart, and only once, on the calling (synchronized) thread, before
-- any of this runs.

export type VoxelData = {
	CFrame: CFrame,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
}

export type MergedVoxel = VoxelData & { Kind: string }

export type Grid = {
	CountX: number,
	CountY: number,
	CountZ: number,
	StepX: number,
	StepY: number,
	StepZ: number,
	Origin: CFrame,
	Color: Color3,
	Material: Enum.Material,
}

-- Picks the actual cube size for a part given the controller's sizing rule.
local function resolveVoxelSize(part: BasePart, sizing: { Absolute: number? }): number
	if sizing.Absolute then
		return sizing.Absolute
	end
	error("Voxelize.slice requires a resolved size; pass Relative sizing through resolveRelativeSize first", 2)
end

-- Relative controllers want a size close to RecommendedVoxelSize, falling back toward
-- MinimumVoxelSize when the part is too small to fit even one recommended-size voxel.
local function resolveRelativeSize(part: BasePart, recommended: number, minimum: number): number
	local smallestDimension = math.min(part.Size.X, part.Size.Y, part.Size.Z)
	if smallestDimension >= recommended then
		return recommended
	end
	return math.max(minimum, smallestDimension)
end

-- Produced voxels never keep a part's exact Material - plain Plastic in particular reads as
-- rough/blocky once it's chopped into many small cubes, so it's smoothed to SmoothPlastic.
-- Every other Material is left alone (Wood, Metal, etc. should still look like themselves).
local function voxelMaterial(material: Enum.Material): Enum.Material
	if material == Enum.Material.Plastic then
		return Enum.Material.SmoothPlastic
	end
	return material
end

-- Lays out the grid of cells `part` will be sliced into at `voxelSize`, without producing any
-- voxels yet - callers classify cells against this grid before deciding what to merge/emit.
local function buildGrid(part: BasePart, voxelSize: number): Grid
	local size = part.Size
	local countX = math.max(1, math.floor(size.X / voxelSize + 0.5))
	local countY = math.max(1, math.floor(size.Y / voxelSize + 0.5))
	local countZ = math.max(1, math.floor(size.Z / voxelSize + 0.5))

	return {
		CountX = countX,
		CountY = countY,
		CountZ = countZ,
		StepX = size.X / countX,
		StepY = size.Y / countY,
		StepZ = size.Z / countZ,
		Origin = part.CFrame * CFrame.new(-size.X / 2, -size.Y / 2, -size.Z / 2),
		Color = part.Color,
		Material = voxelMaterial(part.Material),
	}
end

-- World-space position of cell (x, y, z)'s center, 0-indexed.
local function cellPosition(grid: Grid, x: number, y: number, z: number): Vector3
	return (grid.Origin * CFrame.new((x + 0.5) * grid.StepX, (y + 0.5) * grid.StepY, (z + 0.5) * grid.StepZ)).Position
end

-- Slices `part` into a flat grid of individual cubes of `voxelSize`, every one its own
-- VoxelData - no merging. Used where callers need one piece per cell (e.g. the debris the
-- player is meant to see fragment, as opposed to off-hitbox cells greedyMesh collapses).
local function slice(part: BasePart, voxelSize: number): { VoxelData }
	local grid = buildGrid(part, voxelSize)
	local voxels: { VoxelData } = {}
	for x = 0, grid.CountX - 1 do
		for y = 0, grid.CountY - 1 do
			for z = 0, grid.CountZ - 1 do
				table.insert(voxels, {
					CFrame = grid.Origin * CFrame.new((x + 0.5) * grid.StepX, (y + 0.5) * grid.StepY, (z + 0.5) * grid.StepZ),
					Size = Vector3.new(grid.StepX, grid.StepY, grid.StepZ),
					Color = grid.Color,
					Material = grid.Material,
				})
			end
		end
	end
	return voxels
end

-- Greedy meshing: `classify(worldPosition)` labels every cell (or returns nil to drop it
-- entirely - not produced at all). Cells sharing a label are merged first into X-runs, then
-- matching X-runs are merged along Y into rectangles, then matching rectangles are merged
-- along Z into boxes. The result is a handful of MergedVoxel boxes instead of one per cell
-- wherever a label is uniform across a region.
local function greedyMesh(grid: Grid, classify: (Vector3) -> string?): { MergedVoxel }
	local kindAt: { [number]: { [number]: { [number]: string? } } } = {}
	for x = 0, grid.CountX - 1 do
		kindAt[x] = {}
		for y = 0, grid.CountY - 1 do
			kindAt[x][y] = {}
			for z = 0, grid.CountZ - 1 do
				kindAt[x][y][z] = classify(cellPosition(grid, x, y, z))
			end
		end
	end

	type Run = { X0: number, X1: number, Kind: string }
	local runsByYZ: { [number]: { [number]: { Run } } } = {}
	for y = 0, grid.CountY - 1 do
		runsByYZ[y] = {}
		for z = 0, grid.CountZ - 1 do
			local list: { Run } = {}
			local x = 0
			while x < grid.CountX do
				local kind = kindAt[x][y][z]
				if kind then
					local x1 = x
					while x1 + 1 < grid.CountX and kindAt[x1 + 1][y][z] == kind do
						x1 += 1
					end
					table.insert(list, { X0 = x, X1 = x1, Kind = kind })
					x = x1 + 1
				else
					x += 1
				end
			end
			runsByYZ[y][z] = list
		end
	end

	type Rect = { X0: number, X1: number, Y0: number, Y1: number, Kind: string }
	local rectsByZ: { [number]: { Rect } } = {}
	for z = 0, grid.CountZ - 1 do
		local usedAt: { [number]: { [number]: boolean } } = {}
		for y = 0, grid.CountY - 1 do
			usedAt[y] = {}
		end

		local list: { Rect } = {}
		for y = 0, grid.CountY - 1 do
			for i, run in runsByYZ[y][z] do
				if not usedAt[y][i] then
					local y1 = y
					local nextY = y + 1
					while nextY < grid.CountY do
						local matchIndex: number? = nil
						for j, otherRun in runsByYZ[nextY][z] do
							if otherRun.X0 == run.X0 and otherRun.X1 == run.X1 and otherRun.Kind == run.Kind and not usedAt[nextY][j] then
								matchIndex = j
								break
							end
						end
						if not matchIndex then
							break
						end
						usedAt[nextY][matchIndex] = true
						y1 = nextY
						nextY += 1
					end
					table.insert(list, { X0 = run.X0, X1 = run.X1, Y0 = y, Y1 = y1, Kind = run.Kind })
				end
			end
		end
		rectsByZ[z] = list
	end

	type Box = { X0: number, X1: number, Y0: number, Y1: number, Z0: number, Z1: number, Kind: string }
	local boxes: { Box } = {}
	local usedRect: { [number]: { [number]: boolean } } = {}
	for z = 0, grid.CountZ - 1 do
		usedRect[z] = {}
	end

	for z = 0, grid.CountZ - 1 do
		for i, rect in rectsByZ[z] do
			if not usedRect[z][i] then
				local z1 = z
				local nextZ = z + 1
				while nextZ < grid.CountZ do
					local matchIndex: number? = nil
					for j, otherRect in rectsByZ[nextZ] do
						if
							not usedRect[nextZ][j]
							and otherRect.X0 == rect.X0
							and otherRect.X1 == rect.X1
							and otherRect.Y0 == rect.Y0
							and otherRect.Y1 == rect.Y1
							and otherRect.Kind == rect.Kind
						then
							matchIndex = j
							break
						end
					end
					if not matchIndex then
						break
					end
					usedRect[nextZ][matchIndex] = true
					z1 = nextZ
					nextZ += 1
				end
				table.insert(boxes, { X0 = rect.X0, X1 = rect.X1, Y0 = rect.Y0, Y1 = rect.Y1, Z0 = z, Z1 = z1, Kind = rect.Kind })
			end
		end
	end

	local merged: { MergedVoxel } = {}
	for _, box in boxes do
		local sizeX = (box.X1 - box.X0 + 1) * grid.StepX
		local sizeY = (box.Y1 - box.Y0 + 1) * grid.StepY
		local sizeZ = (box.Z1 - box.Z0 + 1) * grid.StepZ
		local centerLocal = Vector3.new(
			(box.X0 + box.X1 + 1) / 2 * grid.StepX,
			(box.Y0 + box.Y1 + 1) / 2 * grid.StepY,
			(box.Z0 + box.Z1 + 1) / 2 * grid.StepZ
		)
		table.insert(merged, {
			CFrame = grid.Origin * CFrame.new(centerLocal),
			Size = Vector3.new(sizeX, sizeY, sizeZ),
			Color = grid.Color,
			Material = grid.Material,
			Kind = box.Kind,
		})
	end

	return merged
end

-- The same shape VoxelController.HitboxConfig uses, kept local to avoid requiring
-- VoxelController/init.luau from here (that module already requires this one).
export type PointHitbox = {
	Size: Vector3?,
	CFrame: CFrame?,
	QueryType: string?,
}

-- Classifies one world-space point as "Partial" (inside the hitbox) or "Extra" (outside it).
-- Pure - no Instance access - so it's safe to call from a desynchronized Actor.
local function classifyPoint(point: Vector3, hitbox: PointHitbox): string
	local size = hitbox.Size or Vector3.new(4, 4, 4)
	local cframe = hitbox.CFrame or CFrame.new()
	local queryType = hitbox.QueryType or "Box"

	if queryType == "Sphere" then
		return if (point - cframe.Position).Magnitude <= size.X / 2 then "Partial" else "Extra"
	end

	local relative = if queryType == "Region" then point - cframe.Position else cframe:PointToObjectSpace(point)
	local half = size / 2
	local inside = math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
	return if inside then "Partial" else "Extra"
end

-- The full per-part voxelization computation: greedy-mesh every "Extra"-classified cell into
-- the fewest boxes that cover it, and emit every other cell as its own piece. This is what
-- VoxelController._voxelizePart turns into real Instances - either inline on the calling
-- thread, or via VoxelController/Workers on a desynchronized Actor, since this function itself
-- never touches an Instance. `greedyMeshing` (defaults true) is Config.GreedyMeshing, threaded
-- through as a plain argument rather than read from Config directly so this stays callable from
-- a desynchronized Actor with no shared state - pass `false` to emit one part per cell instead
-- of merging "Extra" cells into boxes.
local function computeCells(grid: Grid, classify: (Vector3) -> string?, greedyMeshing: boolean?): { MergedVoxel }
	local mesh = if greedyMeshing == nil then true else greedyMeshing
	local out: { MergedVoxel } = {}

	if mesh then
		local merged = greedyMesh(grid, function(pos)
			return if classify(pos) == "Extra" then "Extra" else nil
		end)
		for _, data in merged do
			table.insert(out, data)
		end
	end

	for x = 0, grid.CountX - 1 do
		for y = 0, grid.CountY - 1 do
			for z = 0, grid.CountZ - 1 do
				local pos = cellPosition(grid, x, y, z)
				local kind = classify(pos) or "Partial"
				if kind ~= "Extra" or not mesh then
					table.insert(out, {
						CFrame = grid.Origin * CFrame.new((x + 0.5) * grid.StepX, (y + 0.5) * grid.StepY, (z + 0.5) * grid.StepZ),
						Size = Vector3.new(grid.StepX, grid.StepY, grid.StepZ),
						Color = grid.Color,
						Material = grid.Material,
						Kind = kind,
					})
				end
			end
		end
	end

	return out
end

return {
	slice = slice,
	resolveVoxelSize = resolveVoxelSize,
	resolveRelativeSize = resolveRelativeSize,
	buildGrid = buildGrid,
	cellPosition = cellPosition,
	greedyMesh = greedyMesh,
	classifyPoint = classifyPoint,
	computeCells = computeCells,
}
