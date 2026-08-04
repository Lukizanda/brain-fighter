---
type: design
description: Audit of which systems run gameplay code on both VMs, and the staged plan to replace the accidental client-side prediction in the Skills pipeline with an explicit authority / prediction / presentation split.
updated: 2026-08-04
---

# Client/Server Boundary

Written 2026-08-04, immediately after commit `a7d4638` ("draw player-facing effects where players can see them"). That commit was the fourth consecutive fix for the same class of bug — a player-facing effect raised on a VM no player can perceive. The user's question at the end of that session was *"are we trying to work around the problem?"*, and the honest answer was: partly, yes. This page is the root-cause pass.

`a7d4638` and its guardrails are **not** to be reverted. Everything it added is either correct-and-permanent (the server-side refusals, `VfxBroadcast`, attribute-driven status visuals) or correct-but-symptomatic (`drawnLocallyBy`, the `RunService:IsServer()` branch in `SkillVisuals`). This page distinguishes the two and plans the removal of the second group only.

## The finding

**The caster's client runs the entire spell simulation, and then the server runs it again.**

- `src/client/UI/SpellMenuGui.client.luau:17` requires `CastAction`
- `src/shared/CastAction/init.luau:112` — `drainAndCast` calls `SpellExecutor.cast` on the caster's client
- the same client fires `SpellCastServer`, so `src/server/SpellCastService.server.luau:102,120` calls `SpellExecutor.cast` again on the server
- both land in `SkillDelivery.deliver` (`src/shared/SpellExecutor/init.luau:91`), which is a single shared module with no notion of which run it is

Both VMs spawn projectiles, run swept-ray hit detection, apply damage, and write freeze/shield state. It works because `Humanoid.Health` writes on a client are local-only and get corrected by replication. So this is, in effect, **client-side prediction with authoritative re-simulation** — a legitimate architecture. The problem is that it was never designed as one:

- there is no prediction layer and no reconciliation step;
- nothing marks which run is which, so every guard has to re-derive it from `RunService:IsServer()` or from "is the source a player character";
- the two runs simulate **different Part instances** against **different physics timelines**, and nothing checks that they agreed.

The VFX bugs were the visible symptom. The duplication is the cause.

## Audit — which systems run on both VMs

Evidence is from `require` graph traversal plus per-file guard inspection, not from assumption.

| System | Client VM | Server VM | Intentional? | Evidence |
|---|---|---|---|---|
| `CastAction` | ✅ runs | ❌ | ⚠️ by omission | `SpellMenuGui.client.luau:17`; no server consumer. Owns the drain — so the economy is client-only. |
| `SpellExecutor` | ✅ runs | ✅ runs | ❌ **no** | `CastAction/init.luau:112` (client) and `SpellCastService.server.luau:102,120` (server) |
| `SkillDelivery` | ✅ runs | ✅ runs | ❌ **no** | `SpellExecutor/init.luau:91`. Also entered server-only from `server/Boss/Scripts/BossStates.luau:29`. |
| ↳ `instant` handler | ✅ | ✅ | ❌ no | no VM guard |
| ↳ `projectile` handler | ✅ | ✅ | ❌ no | three `IsServer()` guards (`:419`, `:529`, `:556`, the last with an `else` arm at `:583`) patching the duplication |
| ↳ `aoe` handler | ✅ | ✅ | ❌ no | `drawnLocallyBy` passed at `:812` for exactly this reason |
| ↳ `world_spawn` handler | early-returns | ✅ | ✅ **yes** | guarded at `SkillDelivery.luau:855` — the one handler that already has an explicit mode |
| `SkillEffects` | ✅ runs | ✅ runs | ❌ **no** | `damage` writes `h.Health` at `:138,:140`; `heal` at `:150`; `freeze` writes `WalkSpeed`/`_freezeState`/`_frozen` at `:175,:84` — none VM-guarded |
| ↳ `applyDamage` path | ❌ nil | ✅ | ✅ yes | `SkillEffects.luau:42` — server-only require, boss attacks only |
| `SkillBuffs` | ✅ runs | ✅ runs | ❌ **no** | `grantShield` read-modify-writes `_shield` at `:228`; client write never replicates upward |
| `SkillVisuals` | ✅ draws | ✅ broadcasts | ⚠️ workaround | `IsServer()` branches at `:87,:123,:143,:218` — correct today, exists only because callers run on both |
| `SkillInterrupt` | ✅ | ✅ | ❌ no | reached from `SkillEffects` freeze/purge |
| **BlockShoot** | ✅ | ✅ | ✅ **yes — correct** | `src/shared/BlockShoot/init.luau:23-38` is two pure read-only helpers (`findLetterBlock`, `readBlock`). Zero state writes. Textbook shared module. |
| **LetterBlaster** | ✅ only | ❌ | ✅ yes | `StarterPack/Spelling Staff/Scripts/SpellingStaff.client.luau:6`; fires `ConsumeBlock` at `LetterBlaster/init.luau:119`. Server owns the destroy. Correct request/authority split. |
| **BlockSpawner** | ❌ | ✅ only | ✅ yes | required only by `server/BlockSpawner/BlockSpawnerService.server.luau:8` |
| `LetterBlocks` | ✅ | ✅ | ✅ yes | tag + attribute names only |
| `WordBuffer`, `EnergyReservoirs`, `MindFullManager`, `MemorizeAction`, `EnergyEconomy`, `Dictionary` | ✅ only | ❌ | ⚠️ known hole | all via `client/PlayerSession.luau:14-16`. The server has no reservoir — this is the client-trusted affordability gap already tracked in [[systems/SpellCastService]] § Trust model. |
| `Health` / `applyDamage` / `DeathHandler` | ❌ | ✅ only | ✅ yes | `ServerScriptService` |
| `Boss` | ❌ | ✅ only | ✅ yes | `server/Boss/*` |
| `Vfx` (`VfxConfig`, `spawnEffect`, `StatusVisuals`) | ✅ draws | refuses | ✅ yes | `spawnEffect` refuses server-side by design |

**Verdict: the duplication is confined to one chain — `CastAction → SpellExecutor → SkillDelivery → SkillEffects/SkillBuffs/SkillVisuals`.** Everything else the audit touched is either correctly server-only, correctly client-only, or a genuinely pure shared module. The suspected offenders (BlockShoot, LetterBlaster, BlockSpawner) all came back clean — BlockShoot in particular is the model the Skills chain should be measured against: shared code that reads and never writes.

## What the duplication actually costs

Four concrete failure modes, each traceable to "two simulations, no marker".

**1. Two projectiles, two hit detections, one truth.** `SkillDelivery.luau:556` makes the server's Part invisible and broadcasts a cosmetic; the client branch at `:583` keeps its own Part and *also* runs the swept-ray gameplay loop from `:600` onward. The two Parts are independent rigid bodies on independent timelines. They can disagree about what was hit — and when they do, the client's version is what the player *watched*, while the server's is what *happened*. The shield bug in `a6b94b3` (a shot visibly continuing 4.7 studs past the block point) is exactly this disagreement, and the fix — hand network ownership to the server, hide the server Part, broadcast a cosmetic — patched the visual symptom rather than the divergence.

**2. Prediction results drive authoritative economy decisions.** `CastAction.drainAndCast:113` refunds the cost when the executor returns `ok = false`. That executor run is the *predicted* one. `world_spawn` has to fake a success to avoid a spurious refund — `SkillDelivery.luau:846`: *"The client branch returns ok so CastAction doesn't refund a cast that the server is about to honour."* Every future server-only handler will need the same lie.

**3. `drawnLocallyBy` is a per-call parameter for something that is a property of the run.** ✅ *Resolved in Stage 2.* `casterUserIdFrom` (`SkillDelivery.luau:112`) inferred "did a client already draw this?" from "is the source a player character" — a proxy that happened to hold, and that breaks the moment an NPC casts a player spell, or a player spell is triggered server-side (a trap, a scripted event, a tutorial). It was threaded by hand through `:374`, `:812`, and every `SkillVisuals` entry point. It is now `ctx.predictedBy`, one field set once at the entry point from fact rather than inference.

**4. `_freezeState` vs `_frozen` can drift.** `_freezeState` (`SkillEffects.luau:62`) is per-VM gameplay bookkeeping; `_frozen` (`:84`) is the replicated render signal. Both VMs write both. They agree today only because the same code writes both in the same order; anything that writes the attribute directly desyncs them silently. Already flagged in [[systems/SkillPipeline]].

## Two candidate architectures

### Option A — server-only delivery, separate client presentation

`SkillDelivery` and `SkillEffects` run **only** on the server. The client's cast path stops at "validate, drain, fire the remote, play local cast feedback". Everything world-facing arrives back as `VfxBroadcast` one-shots or replicated attributes.

- **Removes:** `drawnLocallyBy` entirely; `casterUserIdFrom`; the `IsServer()` branches in `SkillVisuals` (it becomes client-draw + a thin server-side broadcast shim); the invisible-server-shot / cosmetic-client-shot split (there is only ever one Part and one cosmetic); the `world_spawn` fake-success; the `_freezeState` divergence (one VM owns it).
- **Costs:** the caster sees their own projectile one round-trip late.
- **Why that cost is small *for the current roster*:** Brain Fighter has no hitscan today. Every offensive spell is a travelling projectile or a windup AoE — `aoe` has an explicit `windupSec`. A 30–100 ms delay on an object that takes 0.5–1.5 s to reach its target is inside the noise. **This premise is time-limited — see "Zero-travel skills" below.**
- **Real cost:** the refund-on-failure contract has to change. See below.

### Option B — keep the shared module, pass `mode: "authoritative" | "predicted"`

`DeliveryCtx` gains a `mode` field, set once at each entry point. Handlers branch on `ctx.mode` instead of `RunService:IsServer()`. `drawnLocallyBy` becomes a derived read of `ctx.mode == "predicted"`.

- **Removes:** the ad-hoc `casterUserIdFrom` inference; the ambiguity about which run a guard is protecting.
- **Does not remove:** the two-simulation divergence, the refund coupling, or the duplicated hit detection. It labels the problem accurately instead of solving it.
- **Cost:** small. Mostly mechanical.

## Recommendation

**Adopt A as the destination. Implement B first, as the scaffold that makes A safe.**

These are not competing architectures — B is the refactoring step that turns A from a risky rewrite into a sequence of small deletions. Once every handler branches on an explicit `ctx.mode`, moving a handler to server-only is a one-line change (delete the `predicted` branch) that is individually testable and individually revertable. Attempting A directly means changing the entry points, the handlers, the visual routing and the refund contract in one commit, against a system whose failure mode is "looks 80% right in a playtest".

Concretely, the destination:

| Layer | Runs on | Owns |
|---|---|---|
| **Authority** | server only | hit detection, damage, `_shield`/`_frozen`/buff writes, collidable Parts, freeze bookkeeping |
| **Prediction** | caster's client, explicitly marked | local cast feedback only — muzzle burst, cast SFX, HUD drain. Never touches another entity's state. |
| **Presentation** | every client | effects derived from replicated attributes and `VfxBroadcast` one-shots. Never a gameplay input. |

The rule that falls out, and the one worth pinning: **prediction may only write to things the predicting client already owns.** Its own HUD, its own camera, its own cosmetics. The moment a predicted run writes another entity's `Health`, `WalkSpeed`, or `_shield`, it is a second simulation, not a prediction.

### The refund contract has to change

This is the one genuine design change A forces, and it is a simplification. Today: drain → predict → refund if the prediction refused. Under A the client never sees the executor's verdict.

Replace it with **validate-before-drain**. Every `ok = false` reason the pipeline can currently produce is statically knowable from `(spec, target)` before anything runs:

- `"damage requires Humanoid target"` (`SkillEffects.luau:122`)
- `"heal requires a Humanoid"` (`:148`)
- `"shield requires a Humanoid"` / `"requires a positive amount"` (`:236,:238`)
- `"buff requires a buffKind"` (`:252`)
- `"unknown delivery kind"` (`SkillDelivery.luau:946`)

None depends on simulation outcome. `SpellRegistry.needsEnemyTarget` already encodes most of the target rule and `SpellCastService.server.luau:97` already uses it. So `drainAndCast`'s refund path becomes a pure precondition check that runs *before* the drain, and the refund branch — plus `world_spawn`'s fake success — both delete. Fewer moving parts than today, not more.

## Zero-travel skills (hitscan)

Added 2026-08-04, after the user flagged that hitscan spells are likely later. This is the one input that could have invalidated the recommendation, so it is worth being precise about what it does and does not change.

**What breaks.** Option A's cost — "the caster sees their own effect one round trip late" — is negligible for a fireball that flies for 1.2 s and unacceptable for a hitscan bolt that resolves instantly. With zero travel time, the entire perceived responsiveness of the spell *is* the round trip. Click → 60 ms of nothing → tracer is read as input lag in a way no projectile ever is.

**What doesn't break: the architecture.** Authority / prediction / presentation is exactly the split a hitscan skill needs; it just needs the prediction layer to actually exist, which today it doesn't. The rule generalises cleanly:

> The shorter a skill's time-to-effect, the more of its feel depends on predicted presentation. A projectile can afford to have none. Hitscan cannot.

So hitscan does not argue for keeping the dual simulation — it argues for finishing the job, because the dual simulation is precisely what makes a *correct* prediction layer impossible to write.

**The contract for a future `hitscan` delivery kind:**

| Layer | Does | Must not |
|---|---|---|
| Prediction (caster's client) | raycast locally **for a Vector3 only**; draw tracer muzzle→endpoint, muzzle flash, cast SFX, speculative impact spark | resolve a victim, call `SkillEffects`, write any state, emit a damage number |
| Authority (server) | raycast authoritatively, apply damage, broadcast the real impact to everyone except `predictedBy` | assume the client's endpoint is true |
| Presentation (all clients) | draw the broadcast impact | feed anything back into gameplay |

**Why no reconciliation is needed.** A mispredicted tracer is a cosmetic with a ~100 ms lifetime. It expires before a correction could arrive, and the authoritative impact lands on its own. There is nothing to roll back because prediction never wrote anything — which is the whole point of the "prediction may only write what the predicting client already owns" rule. A mispredicted *hit marker* would be worse (it lies to the player about damage), so hit markers and damage numbers are authoritative-only, driven by the server's broadcast.

**Consequences for this plan:**

1. **Stage 6 is promoted from optional to required**, and is the prerequisite for shipping any hitscan skill. It is no longer "add this if Stage 4 feels bad" — it is the prediction layer, and hitscan is unshippable without it.
2. **Its interface has to carry a predicted endpoint**, not just "play a muzzle flash". Designing it as flash-and-SFX-only would mean rewriting it when hitscan lands.
3. `aoe` with `windupSec = 0`, and any future instant-damage spell, sit in the same bucket. The trigger is *time-to-effect*, not the literal word "hitscan".

## Migration path

Each stage leaves the game shippable and is independently revertable. Stages 1–2 are safe to land before the soft launch; 3–5 are post-launch.

**Stage 1 — Name the two runs.** Add `mode: "authoritative" | "predicted"` to `SkillTypes.DeliveryCtx`. Set it once: `SpellExecutor.cast` gains a `mode` argument; `CastAction` passes `"predicted"`, `SpellCastService` and `BossStates` pass `"authoritative"`. No behaviour change — every existing `RunService:IsServer()` guard stays exactly as it is. Ship this alone and verify nothing moved.
*Done when:* the Skills + SpellExecutor + CastAction suites pass unchanged, and a playtest looks identical.

**Stage 2 — Replace the inference with a fact.** ✅ **Done 2026-08-04.** `casterUserIdFrom` is deleted. `DeliveryCtx` carries `predictedBy: number?`, set at the entry point: `SpellCastService` supplies `player.UserId` because it *knows* — this handler only runs because that client fired the relay, and `SpellMenuGui.client.luau:136` only relays a cast its own predicted run already accepted. Boss and NPC fire leave it nil. `SpellExecutor.cast`'s 4th argument became a `RunContext` table (`{ mode, predictedBy }`) rather than a second positional, because the two fields constrain each other — only an authoritative run can have been predicted by someone.

*Two corrections to this stage as planned:*

- **`SkillVisuals` does not take `mode`, and its `IsServer()` branch stays until Stage 4.** The plan assumed every caller has a run context. It doesn't: `WorldVfxController.client.luau:40` (drawing a received broadcast) and `CosmeticProjectile.luau:200,245,279,302` (drawing its own impacts) are pure presentation, already on a client, and have no delivery ctx to speak of. Forcing `mode` on them would invent a fake one. `SkillVisuals` keeps `drawnLocallyBy` as its parameter name — at that layer "a client already drew this" *is* the accurate description — and delivery handlers feed it from `ctx.predictedBy`. This is a real seam between the delivery and presentation domains, not an oversight to clean up.
- **One wire key was renamed after all.** `VfxBroadcast`'s payloads are unchanged as planned, but the separate `ProjectileVfxEvent` payload had a field named `casterUserId` that no longer means the caster's UserId — it means "who already drew this". Renamed to `predictedBy` in `SkillDelivery.luau:548` and `ProjectileVfxController.client.luau:52`. Safe because Roblox ships client and server from one place file, so there is no version skew.

*Verified* — Skills suite 4/4, SpellExecutor 11/11, plus a live client-side wire check: a player cast broadcast `predictedBy = <that player's UserId>`, the boss's own 30-projectile Volley in the same playtest broadcast `predictedBy = nil`, and the retired `casterUserId` key was absent from every payload. Both branches of the discrimination exercised on a client, across the wire.

*Still outstanding:* the two-client visual confirmation (one burst for the caster, one for the observer). The wire check proves the right UserId is on the payload and that `ProjectileVfxController` tests the right field, which is the part that could regress silently; seeing it with two players is cheap and worth doing at the next friends checkpoint.

**Stage 3 — Make effects authoritative-only.** `SkillEffects` and `SkillBuffs` early-return on `mode == "predicted"`. Damage, heal, freeze, shield and buff stop running twice. The caster loses the local pre-flash of a frozen rig; `_frozen` now arrives from replication (~one round trip). If that reads badly in playtest, the fix is a *presentation* one — `FreezeVfxController` gets an optimistic local hint — not a return to double simulation.
*Done when:* `SkillEffects.isFrozen` is false on the client and true on the server for the same cast, and the ice shards still appear.

**Stage 4 — Make delivery authoritative-only.** `projectile` and `aoe` early-return on `predicted`, as `world_spawn` already does. The client-side Part, its swept ray, and its parallel hit detection all delete. The invisible-server-shot split collapses: there is one Part, it is the server's, it is authoritative, and every client draws its own cosmetic from the broadcast — including the caster. The three `IsServer()` guards in the projectile handler (`:419`, `:529`, `:556`) and the four in `SkillVisuals` all delete with it.
*Done when:* a two-client playtest shows one projectile per cast on both screens, hitting the same target, with the shield block landing on the bubble surface. This is the stage that must be measured, not eyeballed.

**Stage 5 — Validate before drain.** ✅ **Done 2026-08-04, and moved ahead of Stage 3** — see the ordering note below. `SkillEffects.canApply` and `SkillDelivery.canDeliver` are pure precondition predicates mirroring each handler's guards; `SpellExecutor.canCast` composes them; `CastAction.drainAndCast` checks before it drains. `cast_refund_on_failure` is replaced by `cast_rejected_before_drain`, which watches `EnergyReservoirs.changed` and asserts **zero** fires — the old suite compared before/after totals and so could not tell "never drained" from "drained then refunded".

One subtlety worth keeping: `canDeliver` validates `onImpact` effects **only** for `instant` and `world_spawn`, because those apply them against `ctx.target` synchronously. `projectile` and `aoe` resolve their effect targets at impact, so pre-checking their effects against `ctx.target` would refuse a Fireball aimed at a patch of ground, which is legal. A splash that lands on nobody stays a miss, not a refusal.

The refund path is not deleted outright as originally planned — it survives as a guarded backstop that warns. It should be unreachable (`canCast` just approved the cast); if it ever fires, a precondition has drifted from the handler it mirrors, and a silent refund would hide that indefinitely.

*Done:* Skills suite 4/4 including the new one. `canCast` verified directly against the live registry — targeted spells refused with their real reasons when target is nil, self-fallback (Mend) and placement (Stone Wall) still allowed with no target.

> **Ordering correction.** Stage 5 must precede Stage 3, which the original sequence had backwards. Stage 3 makes a predicted run's effects a no-op returning `ok = true`; `CastAction`'s refund read exactly that return value, so doing 3 first would have silently eaten a player's mana on every cast that could not resolve. Discovered while implementing, not by playtest — the failure is invisible in a single-player Studio session because the cast still *looks* refused.

**Stage 6 — The prediction layer.** **Required, not optional** (see "Zero-travel skills"). Stage 4 deletes the client branch that currently raises the caster's muzzle flash and cast SFX (`SkillDelivery.luau:588`), so without this the caster's own cast goes quiet until the broadcast arrives — a regression that needs no playtest to predict. Build a deliberate, minimal prediction layer: on cast, the caster's client immediately plays muzzle flash, cast SFX and HUD drain, marked `predicted`, writing nothing but its own cosmetics. Give it a predicted-endpoint parameter from the start so a future `hitscan` skill can draw a tracer through it without a redesign. This is the *only* prediction the design sanctions, and it is additive on top of a clean boundary rather than a shortcut through it.

## Risks

- **Stage 4 is the one that can regress feel.** Everything before it is invisible to players; Stage 4 changes what the caster sees on the frame they cast. It should land with a friends-playtest checkpoint, not a solo Studio session. Mitigation: Stage 6 exists precisely as the escape hatch, and it is additive.
- **Server load.** Today half the projectile simulation cost is paid by the caster's machine. Moving it all server-side concentrates it — Boss Volley fires 30 projectiles at once (`SkillDelivery.luau:134` comment). The frame-level `_hittablesCache` already exists for this and is unaffected, but a Volley + several player casts is now a single-VM cost. Measure before and after Stage 4; the mitigation if needed is throttling the swept-ray to every other frame, which is a tuning change, not an architectural one.
- **Verification is easy to fake.** Every stage's done-condition after Stage 1 requires a *client-rendered* observation. A clean server log has accompanied all four of the shipped VFX bugs. Two clients, or a client-side count, or nothing.
- **`_freezeState` on a client mid-migration.** Between Stages 1 and 3 the client still holds freeze bookkeeping. Don't add anything that reads `SkillEffects.isFrozen` client-side during that window.
- **Scope creep into the affordability hole.** The client-trusted economy is a *different* problem with a *different* decided answer — the energy-ceiling ledger ([[design/build-plan]] Phase 5.4). This work does not fix it and must not try to; a server-authoritative economy was explicitly rejected. The two are compatible: the ledger prices casts at the remote boundary, which is unchanged by anything here.

## What survives untouched

Explicitly not in scope for removal, at any stage:

- attribute-driven status visuals (`_shield`, `_frozen`) — the correct replication channel for state a client must render
- `VfxBroadcast` as the server→client one-shot effect channel
- the server-side refusals in `spawnEffect` and `FreezeVfx.start` — these get *more* correct as delivery moves server-side, not less
- gameplay-authoritative server-owned objects (the Stone Wall slab in `SkillVisuals.spawnBarrier:200`)
- `BlockShoot` as a shared module, and the `LetterBlaster` → `ConsumeBlock` → server-destroy request/authority split

## See also

- [[concepts/ClientServerPredictionParity]] — the parity rule this design makes structural instead of aspirational
- [[decisions/HybridMeleeHitDetection]] — the project's existing "client detects, server validates" precedent (2026-04-17)
- [[systems/SkillPipeline]] · [[systems/VisualEffects]] · [[systems/SpellCastService]]
- `CLAUDE.md` § "Player-Facing Output (VFX / SFX)" — the Roblox replication table this all sits on
