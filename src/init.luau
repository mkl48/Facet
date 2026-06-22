-- Facet - a comprehensive voxel destruction library for Roblox.
--
-- One entry point on both realms: require(ReplicatedStorage.Facet). Define() builds a
-- VoxelController - Relative (dynamic sizing, multithreaded, hitbox-driven) or Absolute
-- (fixed voxel size) - and that controller's :Shatter() is the one verb everything else
-- (Hitbox detection, Effects, Cleanup, Result chaining) hangs off of.
--
-- See VoxelController/init.luau for the Shatter pipeline and Enums/init.luau for every
-- enum referenced in configs below.

--[=[
	@class Facet
]=]

local VoxelController = require(script.VoxelController)
local PendingResult = require(script.VoxelController.PendingResult)
local Enums = require(script.Enums)

local Facet = {}

Facet.Enums = Enums

-- Config tables - everything a Define()/Shatter() call accepts. See VoxelController for the
-- @interface doc blocks on each of these.
export type DefineConfig = VoxelController.DefineConfig
export type ShatterConfig = VoxelController.ShatterConfig
export type HitboxConfig = VoxelController.HitboxConfig

-- The objects a Define()/Shatter() call hands back.
export type VoxelController = VoxelController.VoxelController
export type PendingResult = PendingResult.PendingResult
export type Result = PendingResult.Result
export type Voxel = PendingResult.Voxel

-- Enum-backed string unions, re-exported so callers can annotate their own variables
-- (`local kind: Facet.HitboxType`) without reaching into `Facet.Enums` for the type.
export type ControllerType = Enums.ControllerType
export type RuntimeType = Enums.RuntimeType
export type HitboxType = Enums.HitboxType
export type QueryType = Enums.QueryType
export type EffectsType = Enums.Effects
export type CleanupType = Enums.Cleanup
export type EventType = Enums.Event

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
