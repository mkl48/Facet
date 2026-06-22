-- Facet
-- Config.luau
-- Plinko Labs
--
-- Global, process-wide feature flags every VoxelController/Voxel reads directly - call
-- Facet.Configure to flip one and every controller picks it up on its next Shatter/Cleanup.
-- Multithreading/GreedyMeshing/ObjectPooling are all read on the calling thread, before any
-- Actor work starts - none of this table is ever shared INTO a desynchronized Actor as live
-- state. GreedyMeshing crosses that boundary as a plain field on the Job instead (see
-- VoxelController/Workers/init.luau) since requiring this module from inside an Actor would get
-- its own independent copy, not the one Facet.Configure just changed.

--[=[
	@class Config
	Global feature flags - set with [Facet.Configure]. Defaults match the documented behaviour
	the rest of Facet's docs assume.
]=]
export type Config = {
	ObjectPooling: boolean,
	Multithreading: boolean,
	GreedyMeshing: boolean,
}

local Config: Config = {
	--[=[
		@within Config
		@prop ObjectPooling boolean
		Default `false`. When `true`, produced voxel `Part`s are drawn from and returned to a
		small pool (internal `Pool.luau`) instead of `Instance.new`/`Destroy` every time - fewer
		allocations under heavy, repeated destruction, at the cost of pooled parts sitting
		(disabled, invisible) under `workspace._Bin.Pool` instead of actually being destroyed.
	]=]
	ObjectPooling = false,
	--[=[
		@within Config
		@prop Multithreading boolean
		Default `true`. When `true`, `Relative` controllers split multi-part `Shatter` calls
		across the `Workers` Actor pool. Set `false` to force every call to run serially on the
		calling thread instead - useful for debugging, or if the Actor pool isn't behaving in
		your game.
	]=]
	Multithreading = true,
	--[=[
		@within Config
		@prop GreedyMeshing boolean
		Default `true`. When `true`, cells produced outside a hitbox (`Result.Voxels.Extra`) are
		merged into the fewest boxes that cover them. Set `false` to emit one part per grid cell
		instead - more parts, but every cell individually addressable.
	]=]
	GreedyMeshing = true,
}

--[=[
	@within Config
	Merges `overrides` into the shared config table - call it once, anywhere, before or while
	using Facet; every controller reads the same table. Unknown keys error immediately instead
	of being silently ignored.
]=]
local function configure(overrides: { ObjectPooling: boolean?, Multithreading: boolean?, GreedyMeshing: boolean? })
	for key, value in overrides do
		assert((Config :: any)[key] ~= nil, `Facet.Configure: unknown key "{tostring(key)}"`);
		(Config :: any)[key] = value
	end
end

return {
	Config = Config,
	configure = configure,
}
