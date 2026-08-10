---
type: system
description: Server relay for client-initiated spell casts. Applies effects server-side because client Humanoid.Health writes don't replicate for server-owned rigs. Hardened in 5.4 — except affordability, which is blocked on client-side energy state.
updated: 2026-08-03
---

# SpellCastService

Server handler for the `SpellCastServer` remote. The client executes a spell locally for VFX and energy drain, then fires this remote so the server actually applies the damage / freeze / shield.

It exists because a client-side `Humanoid.Health` write does not replicate to the server for a server-owned character — the boss and NPCs would visibly take damage on the caster's screen and nowhere else.

## Files

- `src/server/SpellCastService.server.luau` — the handler.
- `src/server/SpellCast/SpellCastConstants.luau` — trust thresholds.
- `src/server/SpellCast/SpellCastValidation.luau` — `resolveSpec` / `checkCaster` / `checkTarget`, split out so the Hardening suite can drive them without a live remote fire.
- `src/shared/SpellCast/Remotes/SpellCastServer.model.json` — the RemoteEvent.
- `src/server/Utility/RateLimiter.luau` — shared per-key token bucket (also used by [[systems/BlockShoot]]).

## Payload

`(color: string, tier: number, target: Model?)`.

`target` is legitimately `nil` for self-buffs and placement spells (Phase 5.2). A self-buff has to land on the server because `applyDamage` reads the shield pool there; Stone Wall has to spawn there because a client-side Part can't block the server-owned boss. `SpellRegistry.needsEnemyTarget(spec)` decides which spells may omit it — never branch on colour, since blue Shield is a self-buff while the rest of blue demands an enemy.

## Trust model

Hardened in Phase 5.4. Checks run cheapest-first; every failure drops the request and logs, and nothing throws, so a malformed payload can never take the handler down for other players.

| # | Check | Rejects |
|---|---|---|
| 1 | `RateLimiter:consume(player)` | Cast loops (flood guard — **not** a price check, see below) |
| 2 | `resolveSpec(color, tier)` | Non-string colours, non-number / NaN / fractional / out-of-range tiers, and roster gaps |
| 3 | `checkCaster(player.Character)` | Casters that aren't a living Model in the workspace |
| 4 | `checkTarget(target, caster)` | Non-Model targets, targets outside the world, targets beyond `MAX_TARGET_DISTANCE_STUDS` |
| 5 | Target liveness | Dropped **silently** — a target dying mid-flight is ordinary play, not an exploit |

Check 2 closes a latent crash as well as an exploit. `SpellRegistry.getSpell` accepts any tier in 1–4, but only red defines a T4, so `green/4` returned `nil` and the old handler then errored indexing it — killing that invocation. `resolveSpec` nil-checks the lookup rather than trusting the tier range.

### Tuning

`MAX_TARGET_DISTANCE_STUDS` = 150 + 50. The 150 mirrors `AUTO_TARGET_RANGE_STUDS` in `client/UI/SpellMenuGui` — the range the client's auto-targeter will lock within. The 50 absorbs drift: both caster and target keep moving during the client→server hop, so a target locked at exactly the client's limit can be measurably further away by the time the server reads it.

> **Duplicated constant.** The 150 is copied, not shared — a server Script cannot require a LocalScript, so the two must be changed together. Hoisting it into [[systems/SpellRegistry]] so both sides read one number is the right fix; it was left out of 5.4 because that phase ran parallel to a session that owned the client UI files.

### Blocked: server-side affordability

**The server still takes the client's word that the caster could afford the spell.** This is the one item of the 5.4 brief that was not delivered, and it is an architecture decision rather than an oversight.

Energy state lives entirely client-side. `EnergyReservoirs` is instantiated in exactly one place — `src/client/PlayerSession.luau` — and the server holds no reservoir, no word buffer, and no memorize history. Nothing in `src/server/` references [[systems/EnergyReservoirs]], [[systems/WordBuffer]], [[systems/EnergyEconomy]] or [[systems/MemorizeAction]]. There is no server-side number to compare a cast cost against.

The rate limit is a flood guard standing in for the missing price check. Its floor is derived from what the economy physically permits — energy only enters a reservoir by memorizing a word, every letter in that word costs one popped block, and the input gates pops at `BlockTapConfig.COOLDOWN` — taking the most generous possible reading of one block per cast so it can never reject real play. It stops a remote loop dead; it does not stop a client casting T4 Volley with an empty red bar.

Two ways forward were put up:

1. **Energy-ceiling ledger (cheap, sound, approximate).** The server already sees every `ConsumeBlock`, and each block carries `Block.Letter` / `Block.Color`. It can therefore track an *upper bound* on the energy each player could possibly have earned, and reject casts whose running cost exceeds it. One-sided by construction, so it never rejects legitimate play, and it needs no change to [[systems/EnergyReservoirs]] or [[systems/SpellRegistry]]. It would not catch a client that under-spends, only one that spends energy it never earned — which is the exploit that matters.
2. **Server-authoritative economy (correct, expensive).** Mirror the whole memorize chain server-side: LetterBlock → WordBuffer → Dictionary → EnergyEconomy → EnergyReservoirs, with the client HUD reading replicated state. This is the real fix and roughly the shape [[design/persistence-progression]] will want anyway, since a server that can't price a cast also can't be trusted to record a personal best.

> **Decided 2026-08-03: option 1, the energy-ceiling ledger.** Tracked as its own item in [[design/build-plan]] Phase 5.4.

### Ledger design (not yet built)

Credit on every *accepted* `ConsumeBlock`, debit on every *accepted* cast. Both hooks sit in files this pass already owns, so it needs no new cross-system coupling beyond one shared server module.

The bound per consumed block is its best possible contribution: `EnergyEconomy.letterValue(letter) × 3`, where 3 is the top length multiplier (`LENGTH_MULTIPLIER_EPIC`, 9+ letters) — a block can never be worth more than being part of the longest-multiplier word. Contribution flows to the block's own colour, since [[systems/EnergyEconomy]] splits value-weighted per tile. A [[systems/Wildcard]] block credits `MAX_LETTER_VALUE × 3` to *all three* colours, because its energy spreads across all of them and the ceiling must be an upper bound for each independently.

Two refinements keep the bound tight rather than useless:

- Clamp each colour's running ceiling at `EnergyReservoirs.CAP_PER_COLOR` (60). Overflow above the cap is discarded by the real reservoir, so a player can never be holding more than that regardless of how much they've earned.
- Debit `spec.cost` from the cast's colour on every accepted cast, so the ceiling tracks earned-minus-spent rather than lifetime-earned.

Both are sound in the same direction: they can only ever lower the ceiling toward the true value, and the check is `ceiling[colour] >= spec.cost`, so a too-high ceiling merely fails to catch an exploit while a too-low one would reject real play. Whatever the suite asserts, it should assert that asymmetry explicitly.

## See also

- [[systems/SpellRegistry]] — the roster `resolveSpec` validates against.
- [[systems/SpellExecutor]] — applies the effects once the payload is trusted.
- [[systems/BlockShoot]] — the other client→server gameplay remote, hardened in the same pass.
- [[systems/EnergyReservoirs]] — the client-side state that blocks affordability.
- [[systems/Tests]] — § Hardening covers both remotes.
- [[design/build-plan]] — Phase 5.4.
