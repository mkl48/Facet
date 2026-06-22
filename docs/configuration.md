---
sidebar_position: 6
---

# Configuration

`Facet.Configure` flips process-wide feature flags - call it once, anywhere, and every
controller picks up the change on its next `Shatter`/`Cleanup` call:

```lua
local Facet = require(game.ReplicatedStorage.Facet)

Facet.Configure({
    ObjectPooling = true,
    Multithreading = false,
    GreedyMeshing = true,
})
```

| Flag | Default | What it does |
|---|---|---|
| `ObjectPooling` | `false` | Produced voxel `Part`s are drawn from and returned to a small pool instead of `Instance.new`/`Destroy` every time. Fewer allocations under heavy, repeated destruction - pooled parts sit disabled under `workspace._Bin.Pool` instead of actually being destroyed. |
| `Multithreading` | `true` | `Relative` controllers split multi-part `Shatter` calls across the `Workers` Actor pool. Set `false` to force every call serial on the calling thread - useful for debugging, or if the Actor pool isn't cooperating in your game. |
| `GreedyMeshing` | `true` | Cells produced outside a hitbox (`Result.Voxels.Extra`) get merged into the fewest boxes that cover them. Set `false` to emit one part per grid cell instead. |

Passing an unrecognized key throws immediately, rather than silently doing nothing.

## Notes on ObjectPooling

Pooling only ever recycles plain `Part` instances Facet itself created - it never pools the
original target/host part you're shattering. A pooled part is reset (`Anchored`/`CanCollide`/
`CanQuery`/`CanTouch` disabled, parented under `workspace._Bin.Pool`) when released, and
restored when reacquired. If you never enable it, Facet behaves exactly as before -
`Instance.new`/`Destroy` per voxel.
