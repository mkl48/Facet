-- Facet
-- VoxelController/Workers/init.luau
-- Plinko Labs
--
-- Coordinates a small pool of Actors that run Voxelize.computeCells() in parallel - the
-- multithreaded path Relative controllers take when a Shatter call touches more than one
-- candidate part. Each job hands a worker plain data only (a Grid and, if there's a hitbox, a
-- Voxelize.PointHitbox) - never the BasePart itself - because Instance access isn't safe from
-- a desynchronized Actor. Instance creation always happens back on the calling thread once
-- every job's plain {CFrame, Size, Color, Material, Kind} result comes back.
--
-- RunContext (Server/Client) can only be written from Studio/Plugin capability, never from a
-- live game script - so the pool clones a pre-baked "Worker" (Server) or "WorkerClient" (Client)
-- template instead of mutating RunContext at runtime. Both templates are baked at sync/install
-- time (see default.project.json's $properties and scripts/build-installer.luau's inst() calls).
--
-- NOTE: this can't be exercised by `lune run` - headless Lune has no Actor/parallel Luau
-- support at all, so this module has only been verified by reading against the documented
-- Actor/SendMessage/BindToMessageParallel APIs, not by an actual Studio run. computeAsync()
-- falls back to running every job inline (no Actor) if the pool fails to build for any reason,
-- so a real engine surprise here degrades to "no speedup," not a broken Shatter call.

local RunService = game:GetService("RunService")
local Voxelize = require(script.Parent.Voxelize)

local POOL_SIZE = 4

--[=[
	@interface Job
	@within Workers
	.Grid Grid -- a part's already-built grid (Voxelize.buildGrid) - plain data, no Instance reference.
	.Hitbox PointHitbox? -- the classification hitbox, in the same Instance-free shape Voxelize.classifyPoint expects. nil means "no hitbox" - every cell classifies Partial.
	.GreedyMeshing boolean? -- Config.GreedyMeshing, read on the calling thread and carried across the Actor boundary as plain data (defaults true).
]=]
export type Job = { Grid: Voxelize.Grid, Hitbox: Voxelize.PointHitbox?, GreedyMeshing: boolean? }

--[=[
	@class Workers
	The Actor pool VoxelController dispatches through for multithreaded voxelization. Not part
	of the public Shatter API - VoxelController calls `Workers.computeAsync` itself whenever a
	Relative controller's Shatter call touches more than one part; nothing here needs calling
	directly from game code.
]=]
local Workers = {}

local pool: { Actor }? = nil
local poolFailed = false

local function runInline(job: Job): { Voxelize.MergedVoxel }
	local hitbox = job.Hitbox
	local classify = if hitbox
		then function(pos: Vector3)
			return Voxelize.classifyPoint(pos, hitbox)
		end
		else function()
			return "Partial"
		end
	return Voxelize.computeCells(job.Grid, classify, job.GreedyMeshing)
end

-- How long to wait for every worker in a freshly built pool to report Ready before giving up
-- and falling back to single-threaded voxelization. Each worker only needs to run its own
-- top-level script body once - if it hasn't managed that in 5 seconds something is genuinely
-- wrong (not just a slow frame), so this isn't tuned to be tight against normal startup time.
local POOL_READY_TIMEOUT = 5

local function buildPool(): { Actor }?
	local ok, result = pcall(function()
		-- RunContext can't be set from a live game script (Studio/Plugin-only capability) -
		-- so we ship two pre-baked templates instead of mutating one at runtime. See
		-- default.project.json / scripts/build-installer.luau for where each gets its RunContext.
		local templateName = if RunService:IsServer() then "Worker" else "WorkerClient"
		local template = (script :: Instance):FindFirstChild(templateName) :: Script?
		assert(template, `Facet Workers: missing "{templateName}" template`)
		local built = {}
		local readyEvents: { BindableEvent } = {}
		for i = 1, POOL_SIZE do
			local actor = Instance.new("Actor")
			actor.Name = "FacetWorker" .. i

			local worker = template:Clone()
			local ready = Instance.new("BindableEvent")
			ready.Name = "Ready"
			ready.Parent = worker

			worker.Enabled = true
			worker.Parent = actor
			actor.Parent = script

			built[i] = actor
			readyEvents[i] = ready
		end

		-- A newly parented Script doesn't start running synchronously - it begins on a later
		-- resumption, after this function has already returned to the caller. Block here until
		-- every worker has actually reached its BindToMessageParallel call (see Worker.server.luau),
		-- so the caller never dispatches a job to a worker that isn't listening yet.
		for _, ready in readyEvents do
			local fired = false
			local connection = ready.Event:Once(function()
				fired = true
			end)
			local deadline = os.clock() + POOL_READY_TIMEOUT
			while not fired and os.clock() < deadline do
				task.wait()
			end
			connection:Disconnect()
			ready:Destroy()
			assert(fired, "Facet Workers: a worker never signaled Ready in time")
		end

		return built
	end)
	if not ok then
		warn("[Facet] Worker pool failed to start, falling back to single-threaded voxelization: " .. tostring(result))
		return nil
	end
	return result
end

local function getPool(): { Actor }?
	if poolFailed then
		return nil
	end
	if not pool then
		pool = buildPool()
		poolFailed = pool == nil
	end
	return pool
end

--[=[
	@within Workers
	Runs Voxelize.computeCells() for every job in `jobs`, spread across the Actor pool, and
	returns the results in the same order `jobs` was given. Falls back to running every job
	serially on the calling thread (still correct, just not parallel) if the Actor pool isn't
	available.
]=]
function Workers.computeAsync(jobs: { Job }): { { Voxelize.MergedVoxel } }
	local actors = getPool()
	if not actors then
		local results = {}
		for i, job in jobs do
			results[i] = runInline(job)
		end
		return results
	end

	local results = {}
	local remaining = #jobs
	if remaining == 0 then
		return results
	end

	local done = Instance.new("BindableEvent")
	for i, job in jobs do
		local actor = actors[(i - 1) % #actors + 1]
		local reply = Instance.new("BindableEvent")
		reply.Event:Once(function(cells)
			results[i] = cells
			remaining -= 1
			reply:Destroy()
			if remaining == 0 then
				done:Fire()
			end
		end)
		actor:SendMessage("ComputeCells", reply, job.Grid, job.Hitbox, job.GreedyMeshing)
	end

	if remaining > 0 then
		done.Event:Wait()
	end
	done:Destroy()

	return results
end

return Workers
