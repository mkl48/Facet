-- Facet
-- Enums/init.luau
-- Plinko Labs

local Enums = {}

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
