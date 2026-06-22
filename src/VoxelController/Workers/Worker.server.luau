-- Facet
-- VoxelController/Workers/Worker.server.luau
-- Plinko Labs
--
-- Cloned into a fresh Actor by Workers.computeAsync() and run with RunContext forced to match
-- whichever realm called Shatter (it's parented under ReplicatedStorage, where a Legacy-context
-- Script would never run on its own). Binds in parallel: BindToMessageParallel hands this
-- function its own desynchronized thread per message, so jobs for different Actors genuinely
-- run at the same time. Touches no Instance except the `reply` BindableEvent it's handed, and
-- only after resynchronizing - everything in between is Voxelize, which is pure.
--
-- script.Parent is the Actor (e.g. FacetWorker1) Workers.computeAsync() parents this under, so
-- Voxelize lives three levels up: Worker -> Actor -> Workers -> VoxelController.

local Voxelize = require(script.Parent.Parent.Parent.Voxelize)

local actor = script:GetActor()
assert(actor, "Worker.server.luau must run inside an Actor")

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
