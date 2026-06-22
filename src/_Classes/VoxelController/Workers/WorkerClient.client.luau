-- Facet
-- _Classes/VoxelController/Workers/WorkerClient.client.luau
-- Plinko Labs
--
-- The Client-realm shell - identical in spirit to WorkerServer.server.luau, just baked with
-- RunContext = Client instead of Server (see scripts/build-installer.luau). See Worker.luau for
-- the actual logic; see WorkerServer.server.luau for why two thin shells exist instead of one
-- context-aware script.

local Worker = require(script.Parent.Worker)

local actor = script:GetActor()
assert(actor, "WorkerClient.client.luau must run inside an Actor")
Worker.bind(actor)

local ready = script:FindFirstChild("Ready")
if ready then
	(ready :: BindableEvent):Fire()
end
