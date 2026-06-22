-- Facet
-- _Patterns/Pool.luau
-- Plinko Labs
--
-- A tiny Part object pool VoxelController draws from when Config.ObjectPooling is true - reused
-- across Shatter calls instead of Instance.new/Destroy every voxel. Parked parts sit disabled
-- under workspace._Bin.Pool until reacquired. Internal - not part of the public API surface
-- (no @class tag, same as Octree.luau).

local stack: { Part } = {}

local function container(): Folder
	local bin = workspace:FindFirstChild("_Bin")
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = "_Bin"
		bin.Parent = workspace
	end
	local pool = bin:FindFirstChild("Pool")
	if not pool then
		pool = Instance.new("Folder")
		pool.Name = "Pool"
		pool.Parent = bin
	end
	return pool :: Folder
end

local function acquire(): Part
	local part = table.remove(stack)
	if part then
		return part
	end
	return Instance.new("Part")
end

local function release(part: Part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = container()
	table.insert(stack, part)
end

return {
	acquire = acquire,
	release = release,
}
