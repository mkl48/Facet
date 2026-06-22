-- Facet
-- _Classes/VoxelController/Workers/init.luau
-- Plinko Labs
--
-- Coordinates a small pool of Actors (built via _Patterns/Thread) that run
-- Voxelize.computeCells() in parallel - the multithreaded path Relative controllers take when a
-- Shatter call touches more than one candidate part. Each job hands a worker plain data only (a
-- Grid and, if there's a hitbox, a Voxelize.PointHitbox) - never the BasePart itself - because
-- Instance access isn't safe from a desynchronized Actor. Instance creation always happens back
-- on the calling thread once every job's plain {CFrame, Size, Color, Material, Kind} result
-- comes back.
--
-- RunContext (Server/Client) can only be written from Studio/Plugin capability, never from a
-- live game script - so the pool clones a pre-baked "WorkerServer" (Server) or "WorkerClient"
-- (Client) shell instead of mutating RunContext at runtime. Both are baked at sync/install time
-- (see default.project.json's $properties and scripts/build-installer.luau's inst() calls); the
-- actual worker logic both shells share lives in Worker.luau, a plain context-agnostic
-- ModuleScript.
--
-- NOTE: this can't be exercised by `lune run` - headless Lune has no Actor/parallel Luau
-- support at all, so this module has only been verified by reading against the documented
-- Actor/SendMessage/BindToMessageParallel APIs, not by an actual Studio run. computeAsync()
-- falls back to running every job inline (no Actor) if the pool fails to build for any reason,
-- so a real engine surprise here degrades to "no speedup," not a broken Shatter call.

local RunService = game:GetService("RunService")
local Voxelize = require(script.Parent.Voxelize)
local Thread = require(script.Parent.Parent.Parent._Patterns.Thread)

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

local pool: Thread.Thread? = nil
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

local function getPool(): Thread.Thread?
	if poolFailed then
		return nil
	end
	if not pool then
		local templateName = if RunService:IsServer() then "WorkerServer" else "WorkerClient"
		local template = (script :: Instance):FindFirstChild(templateName) :: Script?
		assert(template, `Facet Workers: missing "{templateName}" template`)
		pool = Thread.new(template, script, POOL_SIZE)
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
	local thread = getPool()
	if not thread then
		local results = {}
		for i, job in jobs do
			results[i] = runInline(job)
		end
		return results
	end

	local argsList = {}
	for i, job in jobs do
		argsList[i] = { job.Grid, job.Hitbox, job.GreedyMeshing }
	end
	return thread:Map("ComputeCells", argsList)
end

return Workers
