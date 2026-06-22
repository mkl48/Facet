---
sidebar_position: 3
---

# Hitboxes

A `Shatter` call with no `Hitbox` voxelizes the whole target - no detection step at all.
Pass `Hitbox` to scope it:

```lua
Wall:Shatter({
    Hitbox = {
        Size = Vector3.new(4, 4, 4),
        CFrame = impactCFrame,
        QueryType = Enums.QueryType.Box,
        HitboxType = Enums.HitboxType.Partial,
    },
})
```

## How detection works

Every candidate part under the target gets indexed into a broad-phase octree built fresh for
that one call (`src/VoxelController/Octree.luau`). The octree narrows candidates down by
bounding sphere; an exact geometric test then runs on whatever it returns, picked by
`QueryType`:

| `QueryType` | Exact test | Notes |
|---|---|---|
| `Box` (default) | oriented box vs. part overlap | respects the hitbox's `CFrame` rotation |
| `Sphere` | distance from `CFrame.Position` vs. radius | `Size` is read as a radius |
| `Region` | axis-aligned bounding box overlap | ignores the hitbox's rotation |
| `Raycast` | a single `workspace:Raycast` along `ViewVector` | one hit only - see [Caveats](#caveats) |

Because detection runs through the octree instead of `workspace:GetPartBoundsInBox`, it
doesn't depend on the candidate's `CanQuery`/`CanCollide` or even on it living in `workspace`.

## HitboxType

`Partial` (the default) slices whatever the hitbox finds into a voxel grid, splitting the
result into `Partial` (inside the hitbox) and `Extra` (outside it, greedy-meshed). `Whole`
skips slicing entirely for parts the hitbox *fully* contains - those come back untouched in
`Result.Voxels.Whole`, each one still carrying a `:Shatter()` you can call later with no
hitbox needed.

If `Target` is a multi-part `Model`, only the parts the hitbox actually overlaps go through
detection at all - any other part of that same `Model` (say, the floors above a foundation cut)
never enters that step. Those parts still end up in `Result.Voxels.Extra`, unsliced but with
`Effects` applied, specifically so `Effects.Chunk` can weld them into the same falling assembly
as the slice itself - otherwise the building above the cut would just sit there inert, never
having been touched by anything. See [Effects](./effects) for `Chunk`.

## Caveats

`Raycast` casts once through the engine and only resolves the single closest hit along
`ViewVector` - there's no multi-hit walk through everything the ray passes through. If you
need every part along a ray, run your own `workspace:Raycast` loop and pass the resulting
parts through as a `Region`/`Box` hitbox per hit instead.

## Indiscriminate destruction (no Target)

Every example above scopes the hitbox to one target's descendants. Drop the `Target` argument
*and* leave the controller without a `Host`, and the hitbox becomes the only scope - `Shatter`
queries the engine directly (`workspace:GetPartBoundsInBox`/`GetPartBoundsInRadius`, or
`workspace:Raycast`) instead of narrowing a known candidate list through the octree:

```lua
local Demolition = Facet.Define({ Type = Enums.ControllerType.Relative, RecommendedVoxelSize = 1 })

Demolition:Shatter({
    Hitbox = {
        Size = Vector3.new(24, 24, 24),
        CFrame = explosionCFrame,
        QueryType = Enums.QueryType.Sphere,
        Scope = workspace.City, -- optional - defaults to the whole workspace
    },
})
```

A `Hitbox` is required for this form - omitting both `Target` and `Hitbox` leaves Shatter with
no scope at all and it errors. `Scope` (default the whole `workspace`) restricts the native
query to one instance's descendants, the same way a `Target` would for the scoped form above.
`Result.Instance` comes back `nil`, since no single Target/Host exists for this call.
