-- Facet
-- VoxelController/PendingResult.luau
-- Plinko Labs
--
-- The chain object Shatter returns: Controller:Shatter(...):Next(Enums.Event.X):Then(cb).
-- Listeners registered before the matching event fires run immediately when it does;
-- listeners registered after a past event has already fired never run for that firing
-- (each PendingResult only lives for one Shatter call).

local Enums = require(script.Parent.Parent.Enums)
local VoxelModule = require(script.Parent.Voxel)

export type Voxel = VoxelModule.Voxel

--[=[
	@interface Result
	@within PendingResult
	.Voxels {Whole: {Voxel}, Partial: {Voxel}, Extra: {Voxel}} -- every produced [Voxel], split three ways. `Whole`: isolated but never sliced (HitboxType.Whole only). `Partial`: the actual debris - sliced, and the only bucket Cleanup ever runs against. `Extra`: produced but outside the hitbox - greedy-meshed into a handful of boxes and left alone unless you Cleanup it yourself.
	.Instance Instance? -- the Target/Host this Shatter call ran against. `nil` for indiscriminate destruction (no Target, no Host - just a Hitbox).
	.CollisionPoint Vector3? -- reserved for a future raycast-driven Shatter helper; not populated today.
	.SurfaceNormal Vector3? -- reserved for a future raycast-driven Shatter helper; not populated today.
]=]
export type Result = {
	Voxels: { Whole: { Voxel }, Partial: { Voxel }, Extra: { Voxel } },
	Instance: Instance?,
	CollisionPoint: Vector3?,
	SurfaceNormal: Vector3?,
}

export type Then = { Then: (self: Then, callback: (Result) -> ()) -> PendingResult }

--[=[
	@class PendingResult
	The chain object every `Controller:Shatter(...)` call returns:
	`Controller:Shatter(...):Next(Enums.Event.X):Then(callback)`. Listeners registered before the
	matching event fires run immediately when it does; listeners registered after a past event
	has already fired never run for that firing - each PendingResult only lives for one Shatter
	call.
]=]
export type PendingResult = {
	--[=[
		@within PendingResult
		@method Next
		@param event Enums.Event -- `NewVoxel` (fires once, right after voxelization/Effects) or `Destroyed` (fires once every `Partial` voxel from this call has been destroyed by Cleanup).
		@return {Then: (callback: (Result) -> ()) -> PendingResult}
	]=]
	Next: (self: PendingResult, event: Enums.Event) -> Then,
	_fire: (self: PendingResult, event: Enums.Event, result: Result) -> (),
}

local PendingResult = {}
PendingResult.__index = PendingResult

function PendingResult.new(): PendingResult
	return setmetatable({ _listeners = {} }, PendingResult) :: any
end

function PendingResult:Next(event)
	local handle = {}
	function handle.Then(_, callback)
		table.insert(self._listeners, { event = event, callback = callback })
		return self
	end
	return handle
end

function PendingResult:_fire(event, result)
	for _, listener in self._listeners do
		if listener.event == event then
			task.spawn(listener.callback, result)
		end
	end
end

return PendingResult
