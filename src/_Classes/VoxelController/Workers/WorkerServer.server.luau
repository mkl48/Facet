-- Facet
-- _Classes/VoxelController/Workers/WorkerServer.server.luau
-- Plinko Labs
--
-- The Server-realm shell: two lines of real work, everything else lives in Worker.luau (a plain
-- ModuleScript, context-agnostic). RunContext = Server is baked onto this Script at install/sync
-- time (see scripts/build-installer.luau) - it can't be set from a live game script, which is the
-- only reason this shell exists separately from WorkerClient.client.luau instead of one script
-- detecting its own context at runtime.

local Worker = require(script.Parent.Worker)

local actor = script:GetActor()
assert(actor, "WorkerServer.server.luau must run inside an Actor")
Worker.bind(actor)

-- A freshly cloned/parented Script doesn't start running the instant Thread.new() sets
-- worker.Parent = actor - it begins on a later resumption, after the call that builds the pool
-- has already returned. Without this, the very first SendMessage to a brand new pool can arrive
-- before Worker.bind above has even run, gets silently dropped, and the caller hangs forever
-- waiting for a reply that never comes. Firing Ready here, right after binding, lets Thread.new
-- confirm every worker is actually listening before the pool is handed back.
local ready = script:FindFirstChild("Ready")
if ready then
	(ready :: BindableEvent):Fire()
end
