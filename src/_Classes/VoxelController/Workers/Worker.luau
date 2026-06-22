-- Facet
-- _Classes/VoxelController/Workers/Worker.luau
-- Plinko Labs
--
-- The actual worker logic - a plain ModuleScript, context-agnostic. Whether it ends up running
-- on the server or the client is entirely down to which RunContext-baked shell (WorkerServer or
-- WorkerClient, in this same folder) requires and calls it; this module itself never checks or
-- cares which realm it's on. Touches no Instance except the `reply` BindableEvent it's handed,
-- and only after resynchronizing - everything in between is Voxelize, which is pure.

local Voxelize = require(script.Parent.Parent.Voxelize)

--[=[
	@class Worker
	The voxelization job handler every pool Actor binds. Not part of the public API - see
	[Workers].
]=]
local Worker = {}

--[=[
	@within Worker
	Binds `actor` to handle "ComputeCells" messages in parallel - `BindToMessageParallel` hands
	this its own desynchronized thread per message, so jobs for different Actors genuinely run
	at the same time.
]=]
function Worker.bind(actor: Actor)
	actor:BindToMessageParallel("ComputeCells", function(reply: BindableEvent, grid: Voxelize.Grid, hitbox: Voxelize.PointHitbox?, greedyMeshing: boolean?)
		local classify = if hitbox
			then function(pos: Vector3)
				return Voxelize.classifyPoint(pos, hitbox)
			end
			else function()
				return "Partial"
			end

		local cells = Voxelize.computeCells(grid, classify, greedyMeshing)

		task.synchronize()
		reply:Fire(cells)
	end)
end

return Worker
