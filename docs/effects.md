---
sidebar_position: 4
---

# Effects

`ShatterConfig.Effects` is a table keyed by `Enums.Effects`, applied to every voxel `Shatter`
produces (`Partial` *and* `Extra`) right after it's created, before `Cleanup` ever runs. You can
combine multiple keys in one call - they run in the order Luau happens to iterate the table,
each one only touching the properties it cares about.

```lua
Wall:Shatter({
    Hitbox = { Size = Vector3.new(4, 4, 4), CFrame = impactCFrame },
    Effects = {
        [Enums.Effects.Explode] = { Radius = 12 },
        [Enums.Effects.Anchored] = false,
    },
})
```

## Why debris sometimes doesn't move

A produced voxel starts out with the **same `Anchored` value the part you shattered had**. If
that part was `Anchored = true` (the normal case for a static wall or building), every voxel
comes out anchored too - and an anchored part ignores `AssemblyLinearVelocity` entirely, so
`Explode`/`Whitehole`/`Scatter` silently do nothing until something unanchors the part. Every
Effect below that gives a voxel velocity sets `Anchored = false` on it for you, **except**
`Explode` itself (it only sets velocity - pair it with `Anchored = false` explicitly, or use
`Chunk`/`Whitehole`/`Scatter` instead, which unanchor on their own).

## Reference

### `Explode = { Radius: number }`

Pushes the voxel directly away from the Shatter origin (the hitbox center, or the explicit point
for indiscriminate destruction) at `Radius` studs/sec. Does **not** unanchor the part - pair it
with `Anchored = false` or `Chunk = true`.

### `Anchored = boolean`

Sets the produced part's `Anchored` directly, overriding whatever the original part's `Anchored`
was. `Chunk` unanchors on its own regardless of this key, so combining the two only matters if
you want `Anchored = true` to win and keep the assembly frozen in place.

### `Chunk = boolean | { BreakSpeed: number?, BreakRadius: number? }`

```lua
Effects = { [Enums.Effects.Chunk] = true }
-- or, tuned:
Effects = { [Enums.Effects.Chunk] = { BreakSpeed = 30, BreakRadius = 6 } }
```

This is the one to reach for when you want an actual structural collapse, not just debris flying
everywhere. Every voxel one Shatter call produced (`Partial` *and* `Extra`) gets welded together
into a single unanchored rigid assembly - one piece, physically - instead of every tiny voxel
tumbling apart on its own. Cut the bottom floor out of a building with `Chunk = true` and the
remaining `Extra` geometry above it has nothing left holding it up: it falls and lands **as one
piece**, the way an actual building section would.

It doesn't stay one rigid lump forever, though - when the assembly's relative impact speed
against whatever it lands on reaches `BreakSpeed` studs/sec (default `40`), the weld at that
contact point breaks, detaching that voxel *and* every other still-welded voxel within
`BreakRadius` studs of it (default `4`) - so a hard enough landing fractures the assembly into a
handful of smaller chunks, while a soft landing leaves it intact. Detached chunks keep listening
for their own hard impacts, so a chunk that breaks off and then slams into something else can
fracture further.

Combine it with `Explode`/`Slice` for a more dramatic initial kick before gravity takes over -
just expect the welded pieces to settle into one shared velocity almost immediately, since
they're rigidly connected.

### `Slice = { Normal: Vector3?, Speed: number? }`

Splits voxels into two groups by which side of a plane (through the Shatter origin, facing
`Normal`, default `Vector3.new(0, 1, 0)`) they landed on, then pushes each group apart along
`Normal` at `Speed` studs/sec (default `8`) - one half goes `+Normal`, the other `-Normal`.
Unanchors automatically.

```lua
-- a horizontal cut: the top half launches up, the bottom half launches down
Effects = { [Enums.Effects.Slice] = { Normal = Vector3.new(0, 1, 0), Speed = 14 } }
```

### `Blackhole = { Position: Vector3?, Duration: number? }`

Tweens the voxel into `Position` (default the Shatter origin) while shrinking it to nothing over
`Duration` seconds (default `1`), then destroys it (or releases it back to the `Pool` if
`ObjectPooling` is on). Unanchors and disables `CanCollide` so nothing blocks its path inward.

### `Whitehole = { Position: Vector3?, Speed: number? }`

The mirror of `Blackhole` without the despawn: launches the voxel directly away from `Position`
(default the Shatter origin) at `Speed` studs/sec (default `16`). Unanchors automatically. Reads
like `Explode`, but takes a fixed launch speed instead of scaling with a radius, and an explicit
point instead of always using the Shatter origin.

### `Scatter = { Speed: number? }`

Launches the voxel in a random direction at `Speed` studs/sec (default `10`) - useful for messy,
non-directional debris where `Explode`'s radial-from-origin pattern looks too uniform. Unanchors
automatically.

### `Shrink = { Duration: number? }`

Tweens the voxel's `Size` down to nothing over `Duration` seconds (default `0.6`), then destroys
(or releases) it. Doesn't touch position/velocity/`Anchored` - combine it with another Effect
above if you also want it moving while it shrinks.

## A raw `Velocity`

The plain string key `"Velocity"` (not an `Enums.Effects` member) sets
`AssemblyLinearVelocity` to whatever `Vector3` you give it directly, with no unanchoring and no
origin math - an escape hatch for when none of the named Effects above fit:

```lua
Effects = { Velocity = Vector3.new(0, 20, 0) }
```
