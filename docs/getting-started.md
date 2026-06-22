---
sidebar_position: 2
---

# Getting started

## Install

```toml
# wally.toml
[dependencies]
Facet = "kr3ative/facet@0.1.0"
```

Or, with no toolchain at all, paste the bootstrap one-liner into the Studio command bar
(enable *Game Settings → Security → Allow HTTP Requests* first):

```lua
local h = game:GetService("HttpService")
loadstring(h:GetAsync("https://raw.githubusercontent.com/mkl48/Facet/master/dist/install.luau"))()
```

Either way you end up with a `Facet` module under `ReplicatedStorage`.

## Define a controller

```lua
local Facet = require(game.ReplicatedStorage.Facet)
local Enums = Facet.Enums

local Wall = Facet.Define({
    Type = Enums.ControllerType.Absolute,
    VoxelSize = 2,
    Host = workspace.Wall,
})
```

`Host` scopes every `Shatter` call on this controller to `workspace.Wall` without naming a
target each time. Skip it and pass the target explicitly per call instead:
`Controller:Shatter(workspace.Wall, config)`.

## Shatter it

```lua
Wall:Shatter({
    Hitbox = {
        Size = Vector3.new(4, 4, 4),
        CFrame = impactCFrame,
        HitboxType = Enums.HitboxType.Partial,
    },
    Cleanup = Enums.Cleanup.Fade,
}):Next(Enums.Event.NewVoxel):Then(function(result)
    print(#result.Voxels.Partial, "voxels produced")
end)
```

See [DefineConfig](/api/VoxelController#DefineConfig) and
[ShatterConfig](/api/VoxelController#ShatterConfig) for every option.

## Next

Head to [Hitboxes](./hitboxes) to see how detection actually picks parts.
