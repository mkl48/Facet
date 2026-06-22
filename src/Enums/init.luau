-- Facet
-- Enums/init.luau
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
	@prop Effects {Explode: "Explode", Anchored: "Anchored"}
	Keys into `ShatterConfig.Effects`. `Explode = {Radius: number}` pushes the voxel outward
	from the Shatter origin; `Anchored = boolean` sets the produced part's `Anchored` directly.
]=]

--[=[
	@within Enums
	@prop Cleanup {Rebuild: "Rebuild", Fade: "Fade", Destroy: "Destroy"}
	Passed as `ShatterConfig.Cleanup`, or to `Voxel:Cleanup` directly. `Destroy` is instant;
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

export type Effects = "Explode" | "Anchored"

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
