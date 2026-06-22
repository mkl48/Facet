---
sidebar_position: 5
---

# Cleanup

`Cleanup` only ever runs against `Result.Voxels.Partial` - the actual blast debris a `Shatter`
call produced. `Result.Voxels.Extra` (the untouched remainder, reconstructed as fewer
greedy-meshed parts) is left in the world; clean it up yourself if you want it gone.

```lua
Wall:Shatter({
    Hitbox = { Size = Vector3.new(4, 4, 4), CFrame = impactCFrame },
    Cleanup = {
        Method = Enums.Cleanup.Fade,
        Delay = 1.2, -- seconds; defaults to 0.5 for Fade, 0.6 for Rebuild
    },
})
```

`Cleanup` is always a table: `{ Method: Enums.Cleanup | function, Delay: number? }`. `Method` is
the only required field - omit `Delay` to take the strategy's own default.

## Strategies

- **`Enums.Cleanup.Destroy`** - instant. Ignores `Delay`.
- **`Enums.Cleanup.Fade`** - tweens `Transparency` to `1` over `Delay` seconds
  (default `0.5`), then destroys (or, with `ObjectPooling` on, releases) the part.
- **`Enums.Cleanup.Rebuild`** - anchors the voxel and tweens its `CFrame` back to
  `OriginalCFrame` over `Delay` seconds (default `0.6`), reassembling the target in
  place instead of destroying anything.
- **a function** - `Cleanup = { Method = function(voxel) ... end }` runs your own logic against
  each `Partial` voxel instead. `voxel` is a full [`Voxel`](/api/Voxel), so you still get
  `voxel.Instance`, `voxel.OriginalCFrame`/`OriginalPosition`/`OriginalOrientation`, `voxel.Kind`,
  and `voxel.Distance`. `Delay` is ignored - read whatever you need straight off the function's
  closure instead.

## Rebuild/Fade doing nothing visible? Check Anchored

`Rebuild` and `Fade` only animate whatever a voxel's *current* `CFrame`/`Transparency` already
is - they don't make debris move on their own. A produced voxel inherits the original part's
`Anchored` state by default (see [Effects](./effects)), so if the part you shattered was
`Anchored = true` (a typical static wall/building), every voxel comes out anchored too: nothing
has a velocity to move with, the debris sits exactly where it was sliced, and `Rebuild`'s tween
(which targets that same unmoved position) looks like a no-op. This is the single most common
"Cleanup looks broken" report - it's actually an Effects gap, not a Cleanup one.

Fix it by setting `Effects.Anchored = false` (lets the slice fall/fly under whatever velocity you
gave it) or, for an actual structural collapse, `Effects.Unstable = true` - see
[Effects](./effects) for the full breakdown.

## Per-voxel cleanup

Every [`Voxel`](/api/Voxel) - in any bucket, not just `Partial` - exposes the same logic
directly. The direct method keeps the simpler two-argument shape (no `Cleanup` table needed,
since there's no second voxel bucket to apply it to):

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

This only fires for `Destroy`/`Fade` (anything that calls `Instance:Destroy()`, including the
`Blackhole`/`Shrink` Effects, which destroy on their own timer independent of `Cleanup`);
`Rebuild` never destroys the part, so a call with only `Rebuild` set never fires `Destroyed`.
