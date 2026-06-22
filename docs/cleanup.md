---
sidebar_position: 4
---

# Cleanup

`Cleanup` only ever runs against `Result.Voxels.Partial` - the actual blast debris a `Shatter`
call produced. `Result.Voxels.Extra` (the untouched remainder, reconstructed as fewer
greedy-meshed parts) is left in the world; clean it up yourself if you want it gone.

```lua
Wall:Shatter({
    Hitbox = { Size = Vector3.new(4, 4, 4), CFrame = impactCFrame },
    Cleanup = Enums.Cleanup.Fade,
    CleanupDuration = 1.2, -- seconds; defaults to 0.5 for Fade, 0.6 for Rebuild
})
```

## Strategies

- **`Enums.Cleanup.Destroy`** - instant. Ignores `CleanupDuration`.
- **`Enums.Cleanup.Fade`** - tweens `Transparency` to `1` over `CleanupDuration` seconds
  (default `0.5`), then destroys the part.
- **`Enums.Cleanup.Rebuild`** - anchors the voxel and tweens its `CFrame` back to
  `OriginalCFrame` over `CleanupDuration` seconds (default `0.6`), reassembling the target in
  place instead of destroying anything.
- **a function** - `Cleanup = function(voxel) ... end` runs your own logic against each
  `Partial` voxel instead. `voxel` is a full [`Voxel`](/api/Voxel), so you still get
  `voxel.Instance`, `voxel.OriginalCFrame`, and `voxel.Kind`.

## Per-voxel cleanup

Every [`Voxel`](/api/Voxel) - in any bucket, not just `Partial` - exposes the same logic
directly:

```lua
for _, voxel in result.Voxels.Extra do
    voxel:Cleanup(Enums.Cleanup.Fade, 2)
end
```

## Knowing when it's done

`Controller:Shatter(...)` fires `Enums.Event.Destroyed` once every `Partial` voxel from that
call has actually been destroyed (not just had `Cleanup` *started* on it):

```lua
Wall:Shatter(config):Next(Enums.Event.Destroyed):Then(function(result)
    print("debris is fully gone")
end)
```

This only fires for `Destroy`/`Fade` (anything that calls `Instance:Destroy()`); `Rebuild`
never destroys the part, so a call with only `Rebuild` set never fires `Destroyed`.
