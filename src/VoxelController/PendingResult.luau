-- Facet
-- VoxelController/PendingResult.luau
-- Plinko Labs
--
-- The chain object Shatter returns: Controller:Shatter(...):Next(Enums.Event.X):Then(cb).
-- Listeners registered before the matching event fires run immediately when it does;
-- listeners registered after a past event has already fired never run for that firing
-- (each PendingResult only lives for one Shatter call).

local Enums = require(script.Parent.Parent.Enums)

export type Result = {
	Voxels: { Whole: { any }, Partial: { any }, Extra: { any } },
	Instance: Instance?,
	CollisionPoint: Vector3?,
	SurfaceNormal: Vector3?,
}

export type PendingResult = {
	Next: (self: PendingResult, event: Enums.Event) -> { Then: (self: any, callback: (Result) -> ()) -> PendingResult },
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
