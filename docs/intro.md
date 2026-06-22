---
sidebar_position: 1
---

# Introduction

Facet is a voxel destruction library for Roblox. It is one verb, fully configurable:

```lua
local Facet = require(game.ReplicatedStorage.Facet)
local Enums = Facet.Enums

local Wall = Facet.Define({
    Type = Enums.ControllerType.Absolute,
    VoxelSize = 2,
    Host = workspace.Wall,
})

Wall:Shatter({
    Hitbox = { Size = Vector3.new(4, 4, 4), CFrame = impactCFrame },
    Effects = { [Enums.Effects.Explode] = { Radius = 12 } },
    Cleanup = Enums.Cleanup.Fade,
})
```

`Define` builds a `VoxelController` - `Relative` (dynamic sizing toward a
`RecommendedVoxelSize`) or `Absolute` (a fixed `VoxelSize`). `Shatter` is the only thing you
call on it: hitbox detection, explosion/anchoring effects, and cleanup are all just config on
the same call, and every call hands back a `Result` you can chain off of with
`:Next(Event):Then(callback)`.

Under the hood, candidate parts are indexed in a per-call octree, classified against the
hitbox with an exact shape test (`Box`/`Sphere`/`Region`/`Raycast`), sliced into a grid, and
anything produced outside the hitbox is greedy-meshed back down into a handful of boxes
instead of staying one part per cell.

## Where to go next

- [Getting started](./getting-started) - install Facet and run your first Shatter
- [Hitboxes](./hitboxes) - the four query types, indiscriminate destruction, and how detection works
- [Effects](./effects) - Explode, Unstable, Slice, Blackhole, Whitehole, Scatter, Shrink, and why debris sometimes doesn't move
- [Cleanup](./cleanup) - Rebuild, Fade, Destroy, and writing your own
- [Configuration](./configuration) - turn object pooling, multithreading, and greedy meshing on/off

The full API reference lives under the **API** tab.
