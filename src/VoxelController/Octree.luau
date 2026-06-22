-- Facet
-- VoxelController/Octree.luau
-- Plinko Labs
--
-- Self-contained spatial index over a controller's candidate parts. Unlike
-- workspace:GetPartBoundsInBox, it doesn't depend on CanQuery/CanCollide or the part actually
-- living in workspace - anything inserted is queryable. Broad-phase only: Query() returns every
-- part whose containing leaf could overlap a query sphere; callers run the exact geometric test
-- (see VoxelController's _intersectsBox/_intersectsSphere/_intersectsRegion) on the result.
-- Rebuilt per-Shatter from the controller's resolved candidates rather than kept permanently in
-- sync with the DataModel - candidate sets are already small relative to a whole game, and
-- rebuilding sidesteps having to track every candidate's live position.

export type Node = {
	Center: Vector3,
	HalfSize: number,
	Parts: { BasePart },
	Children: { Node }?,
}

local MAX_PARTS_PER_NODE = 8
local MIN_HALF_SIZE = 2

local Octree = {}
Octree.__index = Octree

function Octree.new(center: Vector3, halfSize: number)
	return setmetatable({
		_root = { Center = center, HalfSize = halfSize, Parts = {}, Children = nil } :: Node,
	}, Octree)
end

local function octantIndex(center: Vector3, point: Vector3): number
	local index = 0
	if point.X >= center.X then
		index += 1
	end
	if point.Y >= center.Y then
		index += 2
	end
	if point.Z >= center.Z then
		index += 4
	end
	return index + 1
end

local function octantOffset(index: number): Vector3
	index -= 1
	local x = if bit32.band(index, 1) ~= 0 then 1 else -1
	local y = if bit32.band(index, 2) ~= 0 then 1 else -1
	local z = if bit32.band(index, 4) ~= 0 then 1 else -1
	return Vector3.new(x, y, z)
end

local function split(node: Node)
	local children = {}
	local childHalf = node.HalfSize / 2
	for i = 1, 8 do
		local offset = octantOffset(i) * (childHalf / 2)
		children[i] = { Center = node.Center + offset, HalfSize = childHalf, Parts = {}, Children = nil } :: Node
	end
	node.Children = children
	local parts = node.Parts
	node.Parts = {}
	for _, part in parts do
		local idx = octantIndex(node.Center, part.Position)
		table.insert((children[idx] :: Node).Parts, part)
	end
end

local function insert(node: Node, part: BasePart)
	if node.Children then
		local idx = octantIndex(node.Center, part.Position)
		insert(node.Children[idx], part)
		return
	end
	table.insert(node.Parts, part)
	if #node.Parts > MAX_PARTS_PER_NODE and node.HalfSize > MIN_HALF_SIZE then
		split(node)
	end
end

function Octree:Insert(part: BasePart)
	insert(self._root, part)
end

local function nodeIntersectsSphere(node: Node, center: Vector3, radius: number): boolean
	local diff = node.Center - center
	local nodeRadius = node.HalfSize * 1.7320508 -- sqrt(3): radius of the node's bounding sphere
	return diff.Magnitude <= nodeRadius + radius
end

local function query(node: Node, center: Vector3, radius: number, results: { BasePart })
	if not nodeIntersectsSphere(node, center, radius) then
		return
	end
	if node.Children then
		for _, child in node.Children do
			query(child, center, radius, results)
		end
		return
	end
	for _, part in node.Parts do
		table.insert(results, part)
	end
end

-- Broad-phase: every part whose leaf could overlap a sphere of `radius` around `center`. Not
-- an exact test on its own - callers narrow the result with a precise shape check.
function Octree:Query(center: Vector3, radius: number): { BasePart }
	local results = {}
	query(self._root, center, radius, results)
	return results
end

-- Builds a fresh tree sized to fit every given part, then inserts them all.
function Octree.fromParts(parts: { BasePart })
	local minP: Vector3? = nil
	local maxP: Vector3? = nil
	for _, part in parts do
		local pos = part.Position
		if not minP then
			minP, maxP = pos, pos
		else
			minP = Vector3.new(math.min((minP :: Vector3).X, pos.X), math.min((minP :: Vector3).Y, pos.Y), math.min((minP :: Vector3).Z, pos.Z))
			maxP = Vector3.new(math.max((maxP :: Vector3).X, pos.X), math.max((maxP :: Vector3).Y, pos.Y), math.max((maxP :: Vector3).Z, pos.Z))
		end
	end
	minP = minP or Vector3.zero
	maxP = maxP or Vector3.zero

	local center = ((minP :: Vector3) + (maxP :: Vector3)) / 2
	local halfSize = math.max(((maxP :: Vector3) - (minP :: Vector3)).Magnitude / 2, 4)

	local octree = Octree.new(center, halfSize)
	for _, part in parts do
		octree:Insert(part)
	end
	return octree
end

return Octree
