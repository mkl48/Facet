-- Facet
-- _Patterns/Thread.luau
-- Plinko Labs
--
-- Generic Actor-pool pattern: clones a context-baked Script/LocalScript template into `Size`
-- Actors, waits for every one of them to confirm it's actually bound and listening, then
-- dispatches named messages across the pool round-robin and collects replies in call order.
-- Not Facet-specific - anything that needs a small pool of Actors running the same worker
-- logic can use this instead of hand-rolling pool/Ready/SendMessage bookkeeping.
--
-- RunContext (Server/Client) can only be set on `template` from Studio/Plugin capability, never
-- from a live game script - this pattern doesn't fight that, it just clones whatever template
-- it's handed. Callers own picking the right pre-baked template for the calling realm.
--
-- NOTE: this can't be exercised by `lune run` - headless Lune has no Actor/parallel Luau support
-- at all, so this module has only been verified by reading against the documented
-- Actor/SendMessage/BindToMessageParallel APIs, not by an actual Studio run.

local DEFAULT_SIZE = 4

-- How long to wait for every worker in a freshly built pool to report Ready before giving up.
-- Each worker only needs to run its own top-level script body once - if it hasn't managed that
-- in 5 seconds something is genuinely wrong (not just a slow frame), so this isn't tuned to be
-- tight against normal startup time.
local DEFAULT_READY_TIMEOUT = 5

--[=[
	@class Thread
	A small pool of Actors all running a clone of the same template, dispatched to round-robin.
	Build one with [Thread.new]; nothing else here is meant to be called directly.
]=]
export type Thread = {
	Map: (self: Thread, message: string, argsList: { { any } }) -> { any },
	Destroy: (self: Thread) -> (),
}

local Thread = {}
Thread.__index = Thread

--[=[
	@within Thread
	Builds a pool of `size` Actors (default 4), each running a clone of `template` parented
	under `parent`. Blocks (up to `readyTimeout` seconds, default 5) until every worker fires its
	own "Ready" BindableEvent, since a freshly parented Script/LocalScript doesn't start running
	the instant it's cloned in - it resumes on a later tick, after this call would otherwise have
	already returned. Returns `nil` instead of throwing if any worker fails to start in time, so
	callers can fall back to running work inline rather than crashing.
]=]
function Thread.new(template: Script | LocalScript, parent: Instance, size: number?, readyTimeout: number?): Thread?
	local poolSize = size or DEFAULT_SIZE
	local ok, result = pcall(function()
		local actors: { Actor } = {}
		local readyEvents: { BindableEvent } = {}
		for i = 1, poolSize do
			local actor = Instance.new("Actor")
			actor.Name = template.Name .. i

			local worker = template:Clone()
			local ready = Instance.new("BindableEvent")
			ready.Name = "Ready"
			ready.Parent = worker

			worker.Enabled = true
			worker.Parent = actor
			actor.Parent = parent

			actors[i] = actor
			readyEvents[i] = ready
		end

		local timeout = readyTimeout or DEFAULT_READY_TIMEOUT
		for _, ready in readyEvents do
			local fired = false
			local connection = ready.Event:Once(function()
				fired = true
			end)
			local deadline = os.clock() + timeout
			while not fired and os.clock() < deadline do
				task.wait()
			end
			connection:Disconnect()
			ready:Destroy()
			assert(fired, "Thread: a worker never signaled Ready in time")
		end

		return actors
	end)
	if not ok then
		warn("[Facet] Thread pool failed to start: " .. tostring(result))
		return nil
	end

	return setmetatable({ _actors = result :: { Actor }, _next = 1 }, Thread) :: any
end

--[=[
	@within Thread
	Dispatches one `message` per entry in `argsList` across the pool round-robin and returns the
	single-value replies in the same order `argsList` was given (not the order replies actually
	arrive in). Each worker is expected to `SendMessage`-style reply by firing the `BindableEvent`
	it's handed as the first extra argument with exactly one value.
]=]
function Thread:Map(message: string, argsList: { { any } }): { any }
	local actors = (self :: any)._actors :: { Actor }
	local results = {}
	local remaining = #argsList
	if remaining == 0 then
		return results
	end

	local done = Instance.new("BindableEvent")
	for i, args in argsList do
		local actor = actors[(self :: any)._next]
		;(self :: any)._next = ((self :: any)._next % #actors) + 1
		local reply = Instance.new("BindableEvent")
		reply.Event:Once(function(value)
			results[i] = value
			remaining -= 1
			reply:Destroy()
			if remaining == 0 then
				done:Fire()
			end
		end)
		actor:SendMessage(message, reply, table.unpack(args))
	end

	if remaining > 0 then
		done.Event:Wait()
	end
	done:Destroy()

	return results
end

--[=[
	@within Thread
	Destroys every Actor in the pool. The pool isn't reusable after this.
]=]
function Thread:Destroy()
	for _, actor in (self :: any)._actors :: { Actor } do
		actor:Destroy()
	end
	(self :: any)._actors = {}
end

return Thread
