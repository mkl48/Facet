<div align="center">

<img width="200" height="200" alt="FacetLogoRB" src="FacetLogoRB.png" />

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
> `Enums` - is built and working end-to-end, with greedy meshing, an octree-backed spatial index
> over the candidate parts, and Actor-based multithreading for Relative controllers. All four
> `QueryType`s are wired up (`Box`/`Sphere`/`Region` through the octree + an exact shape test,
> `Raycast` straight through the engine - single closest hit, no multi-hit walk yet). The Actor
> pool (see [`src/VoxelController/Workers`](src/VoxelController/Workers)) is built against the
> documented `Actor`/`SendMessage`/`BindToMessageParallel` APIs but hasn't been run against a
> real Studio session yet - it falls back to single-threaded voxelization automatically if the
> pool fails to start, so a surprise there costs speed, not correctness, but treat it as
> unverified until someone profiles it in Studio.

## Features

- **Two controller types** - `Relative` (dynamic sizing toward a `RecommendedVoxelSize`,
  falling back toward `MinimumVoxelSize`) or `Absolute` (a fixed `VoxelSize`).
- **One verb, fully configurable** - `Controller:Shatter(Target?, Config)`. Omit `Hitbox`
  entirely to shatter the whole target; include it to scope detection, with `HitboxType`
  (`Whole` returns a part untouched, `Partial` voxelizes whatever's detected).
- **Indiscriminate destruction** - call `Controller:Shatter(Config)` with **no `Host` and no
  Target** - just a `Hitbox` - and it shatters whatever overlaps that region anywhere in the
  world (or `Hitbox.Scope`, if you want to restrict the search), with no single Target tying the
  call to one part.
- **Greedy meshing** - voxel cells produced outside the hitbox (`Result.Voxels.Extra`) are
  merged dimension-by-dimension into the fewest boxes that cover them, instead of one part per
  grid cell. Cells you're meant to see fragment (`Partial`, or a no-hitbox `Shatter`) stay one
  piece per cell.
- **Octree-backed spatial queries** - candidate parts are indexed in a broad-phase octree
  (`src/VoxelController/Octree.luau`) before the exact shape test runs, so detection doesn't
  depend on `CanQuery`/`CanCollide` or the part living in `workspace`.
- **Multithreaded slicing for Relative controllers** - when a `Shatter` call touches more than
  one part, each part's grid classification + greedy meshing runs on its own desynchronized
  Actor (`src/VoxelController/Workers`) instead of serially on the calling thread. `Absolute`
  controllers, and any call that only touches one part, skip the Actor round-trip entirely.
- **Four query types** - `Enums.QueryType.Box` / `Sphere` / `Region` / `Raycast`, set on
  `Hitbox.QueryType`.
- **Three-way result split** - `Result.Voxels.Whole` / `.Partial` / `.Extra`, so you always
  know what was isolated whole, what got sliced, and what was produced but fell outside the
  hitbox.
- **Composable cleanup** - `Cleanup = { Method = Enums.Cleanup.Rebuild / Fade / Destroy, Delay = number? }`,
  or pass your own `{ Method = function(voxel) ... end }`.
- **Eight Effects** - `Explode`, `Anchored`, `Chunk` (real structural collapse - welds everything
  a Shatter call produced, including `Extra`, into one unanchored rigid assembly that falls as a
  single piece once a building's support is cut away, then fractures into smaller chunks on a
  hard enough landing), `Slice` (splits debris either side of a plane apart), `Blackhole` /
  `Whitehole` (pull toward / launch away from a point), `Scatter`, and `Shrink` - see
  [docs/effects](https://mkl48.github.io/Facet/effects).
- **Richer voxels** - every produced `Voxel` carries `OriginalPosition`/`OriginalOrientation`
  (captured before any Effect moved it) and `Distance` from the Shatter origin, alongside
  `Instance`/`Kind`/`OriginalCFrame`.
- **Smoothed material** - plain `Plastic` voxels come out `SmoothPlastic` (it reads better once
  chopped into many small cubes); every other Material is left as-is.
- **Two runtime modes** - `Instant` controllers run every `Shatter` call immediately;
  `Timeline` controllers queue calls until you call `Controller:Start()`.
- **Global feature flags** - `Facet.Configure({ ObjectPooling, Multithreading, GreedyMeshing })`
  turns any of the three on/off process-wide, no per-controller wiring needed.
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
        [Enums.Effects.Anchored] = false, -- Explode alone doesn't unanchor - see Effects below
    },
    Cleanup = { Method = Enums.Cleanup.Fade, Delay = 1.2 },
}):Next(Enums.Event.NewVoxel):Then(function(result)
    print(#result.Voxels.Partial, "voxels produced")
end)
```

See [`examples/server.server.luau`](examples/server.server.luau) for a fuller example wired
to a RemoteEvent.

## Defining a controller

`Facet.Define(config)` builds a `VoxelController` and returns it - nothing runs until you call
`:Shatter()` on it. Two things decide how it sizes voxels:

```lua
-- Absolute: every voxel is exactly VoxelSize studs, regardless of part size.
local Wall = Facet.Define({
    Type = Enums.ControllerType.Absolute,
    VoxelSize = 2,
    Host = workspace.Wall,
})

-- Relative: sizes toward RecommendedVoxelSize, shrinking toward MinimumVoxelSize under load.
local Debris = Facet.Define({
    Type = Enums.ControllerType.Relative,
    RecommendedVoxelSize = 1.5,
    MinimumVoxelSize = 0.5,
})
```

`RuntimeType` (`Instant`, the default, or `Timeline`) decides *when* a `Shatter` call actually
runs - `Instant` controllers run it the moment you call it; `Timeline` controllers queue every
call until you run `Controller:Start()`, then flush them in order. Pair `Timeline` with a
cutscene, a countdown, or a server-authoritative "go" signal.

## Shattering

`Controller:Shatter(Target?, Config)` is the one verb. With a `Host` set, `Target` is implied
and you only pass `Config`:

```lua
Wall:Shatter({
    Hitbox = {
        Size = Vector3.new(4, 4, 4),
        CFrame = impactCFrame,
        QueryType = Enums.QueryType.Box,   -- Box | Sphere | Region | Raycast
        HitboxType = Enums.HitboxType.Partial, -- Partial slices; Whole isolates untouched
    },
    Effects = {
        [Enums.Effects.Explode] = { Radius = 12 },
        [Enums.Effects.Anchored] = false,
    },
    Cleanup = { Method = Enums.Cleanup.Fade, Delay = 1.2 },
})
```

See [docs/effects](https://mkl48.github.io/Facet/effects) for the full Effects reference -
`Explode`, `Anchored`, `Chunk` (real structural collapse - welds everything produced, including
`Extra`, into one unanchored assembly so a building falls as a single piece once you cut its
support out, fracturing into smaller chunks on a hard landing), `Slice`
(splits debris either side of a plane apart), `Blackhole`/`Whitehole` (pull toward/launch away
from a point), and `Scatter`/`Shrink`.

Omit `Hitbox` entirely and the whole target gets voxelized with no detection step. Every
produced part lands under `workspace._Bin.Voxels.<TargetName>` - grouped in a `Model` named
after the part it came from - instead of back into wherever the original part lived, so debris
never pollutes the rest of your place hierarchy.

### Indiscriminate destruction (no Target)

Skip `Host` and the `Target` argument entirely and `Shatter` runs against the `Hitbox` itself -
whatever overlaps that region gets shattered, regardless of which part it came from:

```lua
local Demolition = Facet.Define({ Type = Enums.ControllerType.Relative, RecommendedVoxelSize = 1 })

Demolition:Shatter({
    Hitbox = {
        Size = Vector3.new(24, 24, 24),
        CFrame = explosionCFrame,
        QueryType = Enums.QueryType.Sphere,
        Scope = workspace.City, -- optional - defaults to the whole workspace
    },
    Cleanup = { Method = Enums.Cleanup.Destroy },
})
```

A `Hitbox` is required here - there's no Target to fall back to detecting against. `Scope`
restricts the search to one instance's descendants; omit it to scan the whole `workspace`.
`Result.Instance` is `nil` for this form, since no single Target/Host exists.

### Reading the Result

`Shatter` returns a [`PendingResult`](https://mkl48.github.io/Facet/api/PendingResult) you
chain off of with `:Next(Event):Then(callback)`:

```lua
Wall:Shatter(config)
    :Next(Enums.Event.NewVoxel):Then(function(result)
        print(#result.Voxels.Partial, "voxels produced")
    end)
    :Next(Enums.Event.Destroyed):Then(function(result)
        print("every Partial voxel from this call is gone")
    end)
```

| `Result` field | Type | Fires on |
|---|---|---|
| `Voxels.Whole` | `{Voxel}` | `NewVoxel` - parts the hitbox isolated but never sliced (`HitboxType.Whole` only) |
| `Voxels.Partial` | `{Voxel}` | `NewVoxel` - the actual blast debris; the only bucket `Cleanup` ever touches |
| `Voxels.Extra` | `{Voxel}` | `NewVoxel` - produced but outside the hitbox, greedy-meshed into a handful of boxes, left alone |
| `Instance` | `Instance?` | always - the `Target`/`Host` this call ran against |

Each entry in every bucket is a [`Voxel`](https://mkl48.github.io/Facet/api/Voxel), not a bare
`BasePart` - alongside `Instance` and `Kind`, it carries `OriginalCFrame`/`OriginalPosition`/
`OriginalOrientation` (captured the instant it was created, before any Effect moved it) and
`Distance` (from the Shatter origin), plus `:Cleanup(method, duration?)` (run the same
Rebuild/Fade/Destroy/custom logic against just that one part) and, on `Whole` voxels only,
`:Shatter(config?)` to re-shatter that exact part with no hitbox needed.

## Public API cheat-sheet

```lua
Facet.Define(config: DefineConfig): VoxelController
Facet.Configure(overrides: { ObjectPooling: boolean?, Multithreading: boolean?, GreedyMeshing: boolean? }): ()
Facet.Enums: { ControllerType, RuntimeType, HitboxType, QueryType, Effects, Cleanup, Event }

VoxelController:Shatter(target: Instance?, config: ShatterConfig): PendingResult
-- target is also optional when config.Hitbox is set and the controller has no Host - see
-- "Indiscriminate destruction" above.
VoxelController:Start(): ()   -- flushes a Timeline controller's queue
VoxelController:Destroy(): () -- clears anything still queued

PendingResult:Next(event: Enums.Event): { Then: (callback: (Result) -> ()) -> PendingResult }

Voxel:Cleanup(method: Enums.Cleanup | (Voxel) -> (), duration: number?): ()
Voxel:Shatter(config: { Effects: {...}?, Size: number? }?): PendingResult -- Whole voxels only
```

Every type above (`DefineConfig`, `ShatterConfig`, `HitboxConfig`, `VoxelController`, `Result`,
`Voxel`, `PendingResult`, and every `Enums.*` union) is re-exported off the top-level `Facet`
module, so `export type X = Facet.X` works anywhere you need to annotate a variable without
reaching into a submodule.

## Development

```sh
rokit install      # Rojo, Wally, Lune
wally install
rojo serve
```

```sh
lune run scripts/build-installer   # regenerates dist/install.luau + dist/bootstrap.luau
```

Docs are built with [Moonwave](https://github.com/UpliftGames/moonwave) from the `--[=[ ]=]`
comment blocks in `src/` - see `moonwave.toml` for the sidebar order and home page config.

## License

MIT - see [LICENSE](LICENSE).
