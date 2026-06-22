-- Facet - a comprehensive voxel destruction library for Roblox.
--
-- One entry point on both realms: require(ReplicatedStorage.Facet). Define() builds a
-- VoxelController - Relative (dynamic sizing, multithreaded, hitbox-driven) or Absolute
-- (fixed voxel size) - and that controller's :Shatter() is the one verb everything else
-- (Hitbox detection, Effects, Cleanup, Result chaining) hangs off of.
--
-- See VoxelController/init.luau for the Shatter pipeline and Enums/init.luau for every
-- enum referenced in configs below.

local VoxelController = require(script.VoxelController)
local Enums = require(script.Enums)

local Facet = {}

Facet.Enums = Enums

export type DefineConfig = VoxelController.DefineConfig
export type ShatterConfig = VoxelController.ShatterConfig
export type HitboxConfig = VoxelController.HitboxConfig
export type VoxelController = VoxelController.VoxelController

--[=[
	@within Facet
	Creates a VoxelController. `Type` picks Relative (dynamic sizing via
	RecommendedVoxelSize/MinimumVoxelSize, multithreaded, swappable Drivers) or Absolute
	(fixed VoxelSize). Pass `Host` to scope every Shatter call on the controller to one
	instance without naming a Target each time.
]=]
function Facet.Define(config: DefineConfig): VoxelController
	return VoxelController.new(config)
end

return Facet
