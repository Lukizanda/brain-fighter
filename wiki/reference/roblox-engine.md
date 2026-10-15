---
type: reference
description: Roblox engine behaviour as tested here — Emit() doesn't replicate, os.clock is per-VM, Studio fps is paced, third-party images don't load
updated: 2026-10-15
---

# Roblox engine

**Verified against:** Roblox Studio, 2026-04 to 2026-09 (dates per section). **Official docs:** https://create.roblox.com/docs/reference/engine

## Server-side particles don't reach players

`ParticleEmitter:Emit()` called on the server isn't replicated. Property writes (`Enabled = true`), `Sound:Play()` on workspace parts and new Parts are. A server-spawned effect therefore looks about 80% right in a playtest. The full table and the project rule are in [`docs/agents/vfx-sfx.md`](../../docs/agents/vfx-sfx.md), and the history is in [[design/client-server-boundary]].

## `os.clock()` is per-VM

`os.clock()` restarts at 0 in each process, so a client's and the server's values differ by however far apart the two VMs started. On 2026-04-20, a single-VM test passed while a real two-client run rejected every melee swing as "claim is stale (27s old)". Use `workspace:GetServerTimeNow()` on both sides for any timestamp that crosses the wire.

The general lesson: a test that runs every participant in one VM can't catch what the boundary adds (clock drift, serialization, replication, filtering). Contracts that cross client and server need a multi-client Studio test, which is user-driven ([[reference/studio-mcp]] § Only the Edit window).

## Studio fps is paced; measure render cost with counts

Unfocused Studio paces rendering to about 15 fps, so **fps-based A/B tests measure nothing**. The tell: `Stats.FrameRateManager.RenderAverage` reads *exactly* 66.668 ms (1/15 s) while `RenderThreadAverage` reads about 2.4 ms. A duration landing exactly on 1/N seconds is a pacing target, not a measurement. (Verified 2026-08-20.)

Use per-frame **counts**, which pacing, quality level and window focus don't affect:
- `Stats.RenderBreakdown` → children `Opaque`, `Transparent`, `UI`, `Decal`, `Particles`, `Sky`. `:GetValueString()` returns `"7598 tris, 121 draws"`.
- `Stats.FrameRateManager` → `Batches`, `Indices`, `MaterialChanges`, `AverageQualityLevel`, `RenderThreadAverage`, `PrepareAverage`, `PerformAverage`, `AveragePresent`.
- Pin quality with `settings():GetService("RenderSettings").QualityLevel = Enum.QualityLevel.Level21`. It defaults to `Automatic`, which collapses to about 1.8 under pacing. **Restore `Automatic` afterwards:** it's a persistent Studio setting, not a per-place one.

`RenderThreadAverage` is a running average, and its spread between repeated runs is often as large as the effect being measured. Quote the counts, not the timing, unless the difference clearly exceeds the noise.

For screen-space size questions, use `Camera:WorldToViewportPoint` on two world points a known distance apart rather than doing FOV arithmetic by hand.

Freshly created SurfaceGuis render blank for a second or two, so a capture taken right after `Instance.new` shows bare parts. Re-capture before concluding anything is broken.

## Third-party Creator Store images don't load

Images uploaded by other creators **don't load** in the BrainFighter universe (universeId 10138129057), even when `search_asset` reports `isFree: true`. On 2026-08-08, all 16 free fire and smoke flipbook decals from the top search results failed. Only assets in the **universe inventory** work: `17703243127` (8x8 fire flipbook) is the one usable fire texture.

Before building on a new texture id:
- Probe with an `ImageLabel` in a `SurfaceGui` and read `IsLoaded` after a few seconds. This is the only reliable check.
- If you use `ContentProvider:PreloadAsync`, pass the **callback** form. The plain call returns without error regardless and tells you nothing.
- Include a known-good control in the batch: **`rbxasset://textures/particles/sparkles_main.dds`** ships with the engine and can't fail for inventory reasons. Don't use `1913819781`: it's the Roblox shirt template, and five `VfxTemplates` emitters were once textured with it by mistake.
- `IsLoaded` answers *did the bytes arrive*, not *is this the right image*. Render the texture large on a dark `Frame` and look at it.
- When nothing you own fits, author the texture and upload it to the universe.

Details: [[systems/VisualEffects]] § "VfxTemplates and the third-party texture trap".
