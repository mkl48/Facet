-- Facet
-- _Core/Enums.luau
-- Plinko Labs

--[=[
	@class Enums
	Every string-enum Facet's config and Result objects use. Each one is also re-exported as a
	type off the top-level `Facet` module (`Facet.ControllerType`, `Facet.RuntimeType`, etc.), so
	you don't need to reach into `Facet.Enums` just to annotate a variable.
]=]
local Enums = {}

--[=[
	@within Enums
	@prop ControllerType {Relative: "Relative", Absolute: "Absolute"}
	Passed as `DefineConfig.Type`. `Relative` sizes dynamically toward `RecommendedVoxelSize`
	and splits multi-part Shatter calls across the Workers Actor pool; `Absolute` uses a fixed
	`VoxelSize` and never threads.
]=]

--[=[
	@within Enums
	@prop RuntimeType {Instant: "Instant", Timeline: "Timeline"}
	Passed as `DefineConfig.RuntimeType`. `Instant` (default) runs every `Shatter` call the
	moment it's called; `Timeline` queues calls until `Controller:Start()` flushes them in order.
]=]

--[=[
	@within Enums
	@prop HitboxType {Whole: "Whole", Partial: "Partial"}
	Passed as `HitboxConfig.HitboxType`. `Partial` (default) slices whatever the hitbox finds;
	`Whole` returns parts the hitbox fully contains untouched, with no slicing.
]=]

--[=[
	@within Enums
	@prop QueryType {Raycast: "Raycast", Box: "Box", Sphere: "Sphere", Region: "Region"}
	Passed as `HitboxConfig.QueryType`. Mirrors Roblox's own spatial query kinds. `Box`/`Region`
	run through the Octree + an exact box/AABB test, `Sphere` through the Octree + a distance
	test, and `Raycast` casts directly through the engine (single closest hit - see the README's
	Raycast caveat).
]=]

--[=[
	@within Enums
	@prop Effects {Explode: "Explode", Anchored: "Anchored", Chunk: "Chunk", Slice: "Slice", Blackhole: "Blackhole", Whitehole: "Whitehole", Scatter: "Scatter", Shrink: "Shrink"}
	Keys into `ShatterConfig.Effects`. See [docs/effects](https://mkl48.github.io/Facet/effects) for
	the full config shape each one reads:

	- `Explode = {Radius: number}` - pushes the voxel outward from the Shatter origin.
	- `Anchored = boolean` - sets the produced part's `Anchored` directly.
	- `Chunk = boolean | {BreakSpeed: number?, BreakRadius: number?}` - welds every voxel a
	  Shatter call produced (Partial *and* Extra) into one unanchored rigid assembly, so the
	  remainder of a building falls as a single piece once its support is cut away, instead of
	  every voxel tumbling apart individually. A weld breaks - detaching that piece and everything
	  within `BreakRadius` studs of it (default `4`) - the moment its relative impact speed against
	  whatever it hit reaches `BreakSpeed` studs/sec (default `40`), so the assembly fractures into
	  smaller chunks on a hard enough landing instead of staying one rigid lump forever.
	- `Slice = {Normal: Vector3?, Speed: number?}` - splits voxels either side of a plane (through
	  the Shatter origin, facing `Normal`) apart along that normal at `Speed` studs/sec.
	- `Blackhole = {Position: Vector3?, Duration: number?}` - tweens the voxel into `Position`
	  while shrinking it to nothing, then destroys/releases it.
	- `Whitehole = {Position: Vector3?, Speed: number?}` - launches the voxel directly away from
	  `Position` at `Speed` studs/sec (like `Explode`, but a fixed point and speed instead of a
	  radius).
	- `Scatter = {Speed: number?}` - launches the voxel in a random direction at `Speed` studs/sec.
	- `Shrink = {Duration: number?}` - tweens the voxel's `Size` down to nothing over `Duration`
	  seconds, then destroys/releases it.
]=]

--[=[
	@within Enums
	@prop Cleanup {Rebuild: "Rebuild", Fade: "Fade", Destroy: "Destroy"}
	Passed as `ShatterConfig.Cleanup.Method`, or to `Voxel:Cleanup` directly. `Destroy` is instant;
	`Fade` tweens `Transparency` to 1 then destroys; `Rebuild` tweens the voxel's `CFrame` back
	to `OriginalCFrame` and never destroys it.
]=]

--[=[
	@within Enums
	@prop Event {NewVoxel: "NewVoxel", Destroyed: "Destroyed"}
	Passed to `PendingResult:Next`. `NewVoxel` fires once, right after voxelization/Effects;
	`Destroyed` fires once every `Partial` voxel from that call has actually been destroyed by
	Cleanup (never fires if `Cleanup` was `Rebuild` or unset).
]=]

export type ControllerType = "Relative" | "Absolute"

export type RuntimeType = "Instant" | "Timeline"

export type HitboxType = "Whole" | "Partial"

-- mirrors Roblox's own spatial query kinds. All four are wired up in VoxelController: Box and
-- Region run through the Octree + an exact box/AABB test, Sphere through the Octree + a
-- distance test, and Raycast casts directly (single closest hit - see README).
export type QueryType = "Raycast" | "Box" | "Sphere" | "Region"

export type Effects = "Explode" | "Anchored" | "Chunk" | "Slice" | "Blackhole" | "Whitehole" | "Scatter" | "Shrink"

export type Cleanup = "Rebuild" | "Fade" | "Destroy"

export type Event = "NewVoxel" | "Destroyed"

Enums.ControllerType = {
	Relative = "Relative",
	Absolute = "Absolute",
}

Enums.RuntimeType = {
	Instant = "Instant",
	Timeline = "Timeline",
}

Enums.HitboxType = {
	Whole = "Whole",
	Partial = "Partial",
}

Enums.QueryType = {
	Raycast = "Raycast",
	Box = "Box",
	Sphere = "Sphere",
	Region = "Region",
}

Enums.Effects = {
	Explode = "Explode",
	Anchored = "Anchored",
	Chunk = "Chunk",
	Slice = "Slice",
	Blackhole = "Blackhole",
	Whitehole = "Whitehole",
	Scatter = "Scatter",
	Shrink = "Shrink",
}

Enums.Cleanup = {
	Rebuild = "Rebuild",
	Fade = "Fade",
	Destroy = "Destroy",
}

Enums.Event = {
	NewVoxel = "NewVoxel",
	Destroyed = "Destroyed",
}

return Enums
