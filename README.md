<div align="center">

# Facet

**A comprehensive voxel destruction library for Roblox.**

<img src="https://img.shields.io/badge/Facet-v0.1.0-7aa2f7?style=for-the-badge&logoColor=white" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge&logoColor=white" alt="luau" />
<img src="https://img.shields.io/badge/License-MIT-9ece6a?style=for-the-badge" alt="license" />
<img src="https://img.shields.io/badge/Status-Early-e0af68?style=for-the-badge" alt="status" />

One verb - `Shatter` - with Hitbox detection, Effects, and Cleanup all as config on the same call.

</div>

---

Facet voxelizes Roblox parts on demand. You `Define` a `VoxelController` (Relative or
Absolute), point it at a `Host` (or pass a `Target` per call), and `Shatter` it - optionally
scoped to a hitbox, with explosion/anchoring effects and a cleanup strategy (rebuild, fade,
destroy, or your own function), and a `Result` you can chain off of with `:Next(Event):Then(cb)`.

> **Status: early.** The public API - `Define`, `Host`, `RuntimeType` (Instant/Timeline),
> `Shatter`'s `Hitbox`/`Effects`/`Cleanup` config, `Result.Voxels.Whole/Partial/Extra`, and the
> `Enums` - is built and working end-to-end, with greedy meshing and an octree-backed spatial
> index over the candidate parts. All four `QueryType`s are wired up (`Box`/`Sphere`/`Region`
> through the octree + an exact shape test, `Raycast` straight through the engine - single
> closest hit, no multi-hit walk yet). The one item still outstanding is **multithreaded
> slicing across Actors** for Relative controllers - see
> [`src/VoxelController/Voxelize.luau`](src/VoxelController/Voxelize.luau) for where that lands.

## Features

- **Two controller types** - `Relative` (dynamic sizing toward a `RecommendedVoxelSize`,
  falling back toward `MinimumVoxelSize`) or `Absolute` (a fixed `VoxelSize`).
- **One verb, fully configurable** - `Controller:Shatter(Target?, Config)`. Omit `Hitbox`
  entirely to shatter the whole target; include it to scope detection, with `HitboxType`
  (`Whole` returns a part untouched, `Partial` voxelizes whatever's detected).
- **Greedy meshing** - voxel cells produced outside the hitbox (`Result.Voxels.Extra`) are
  merged dimension-by-dimension into the fewest boxes that cover them, instead of one part per
  grid cell. Cells you're meant to see fragment (`Partial`, or a no-hitbox `Shatter`) stay one
  piece per cell.
- **Octree-backed spatial queries** - candidate parts are indexed in a broad-phase octree
  (`src/VoxelController/Octree.luau`) before the exact shape test runs, so detection doesn't
  depend on `CanQuery`/`CanCollide` or the part living in `workspace`.
- **Four query types** - `Enums.QueryType.Box` / `Sphere` / `Region` / `Raycast`, set on
  `Hitbox.QueryType`.
- **Three-way result split** - `Result.Voxels.Whole` / `.Partial` / `.Extra`, so you always
  know what was isolated whole, what got sliced, and what was produced but fell outside the
  hitbox.
- **Composable cleanup** - `Enums.Cleanup.Rebuild` / `Fade` / `Destroy`, or pass your own
  `function(voxel) ... end`.
- **Two runtime modes** - `Instant` controllers run every `Shatter` call immediately;
  `Timeline` controllers queue calls until you call `Controller:Start()`.
- **Two ways to install** - Wally for a Rojo workflow, or a single paste-into-the-command-bar
  installer with no toolchain at all.

## Installation

### Wally

```toml
# wally.toml
[dependencies]
Facet = "kr3ative/facet@0.1.0"
```

```sh
wally install
```

### Command-bar install (no toolchain)

**Bootstrap (recommended)** - paste this one snippet into the Studio command bar; it fetches
and runs the installer over HTTP (enable *Game Settings → Security → Allow HTTP Requests*):

```lua
local h = game:GetService("HttpService")
loadstring(h:GetAsync("https://raw.githubusercontent.com/mkl48/Facet/master/dist/install.luau"))()
```

([`dist/bootstrap.luau`](dist/bootstrap.luau) is the same with error handling + a
no-`loadstring` fallback.) Or, offline, paste the whole [`dist/install.luau`](dist/install.luau)
directly. Either way it recreates the whole `Facet` tree under `ReplicatedStorage`.

Regenerate it from source any time with:

```sh
lune run scripts/build-installer
```

## Quick start

```lua
local Facet = require(game.ReplicatedStorage.Facet)
local Enums = Facet.Enums

local Wall = Facet.Define({
    Type = Enums.ControllerType.Absolute,
    VoxelSize = 2,
    Host = workspace.Wall,
})

Wall:Shatter({
    Hitbox = {
        Size = Vector3.new(4, 4, 4),
        CFrame = impactCFrame,
        HitboxType = Enums.HitboxType.Partial,
    },
    Effects = {
        [Enums.Effects.Explode] = { Radius = 12 },
    },
    Cleanup = Enums.Cleanup.Fade,
}):Next(Enums.Event.NewVoxel):Then(function(result)
    print(#result.Voxels.Partial, "voxels produced")
end)
```

See [`examples/server.server.luau`](examples/server.server.luau) for a fuller example wired
to a RemoteEvent.

## License

MIT - see [LICENSE](LICENSE).
