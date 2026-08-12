---
type: system
description: Server relay for client-initiated spell casts. Applies effects server-side because client Humanoid.Health writes don't replicate for server-owned rigs. Hardened in 5.4 — except affordability, which is blocked on client-side energy state.
updated: 2026-08-12
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

### Not checked: hold duration (2026-08-12)

[[systems/ChargeCast]] made the tier a function of how long the player held a colour panel. **The server does not and cannot verify that hold.** There is no server-side clock on the gesture; the `ChargeState` remote it does receive is a cosmetic broadcast (see below) that carries no timing guarantee, and adding one would mean timestamping a client-owned input across the wire.

This is stated rather than fixed because it is not a hole. Hold-to-charge changed **which** tier the client picks, not **whether** the server prices it: the cast relay is byte-identical to before, check 2 still resolves the spec, and the ledger still debits `spec.cost`. A client that claims to have charged instantly buys itself *speed*, not mana — it still pays 40 for a T4 Volley, and if it never earned that 40 the affordability check refuses it exactly as it would a tapped one.

What a lying client does gain is the ability to skip the 1.75 s windup, which is a PvP *tell* rather than a cost — an opponent watching for the charge orb would not see it coming. Closing that needs the same thing everything else here needs: a server that owns the gesture, not just the outcome. Filed with the authoritative-economy work below rather than as its own item.

The `ChargeState` remote itself lives in `server/SpellCast/ChargeStateService.server.luau`, deliberately **not** in this handler. Different remote, different lifecycle, different posture: a cast changes health and mana and gets the five checks above; a charge state writes two character attributes and gets a well-formedness check plus its own rate budget. Folding a cosmetic broadcast into the handler that debits the energy ledger would put the two on one rate limit and one rejection path for no reason.

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
3. **Validated memorize (added 2026-08-10).** Server tracks the letters each player has consumed and validates the word they claim to have memorized, crediting exact energy. Sits between the two above — see § Validated memorize below.

> **Decided 2026-08-03: option 1, the energy-ceiling ledger.** Tracked as its own item in [[design/build-plan]] Phase 5.4.
>
> **Superseded 2026-08-10: option 3, validated memorize.** The ledger's bound was worked against the real constants and found to saturate at `CAP_PER_COLOR` within ~8 s of sustained shooting, which is ≥ every cost in the roster — so it would have passed essentially every cast an actively-shooting client made. The ledger design below is kept as the record of what was rejected and why.

### Why the ledger was rejected

Not a tuning failure — an informational one, and the distinction is the whole argument.

The bound credits each consumed block `letterValue × 3`, where 3 is `LENGTH_MULTIPLIER_EPIC`. That is the *smallest sound* multiplier: a player genuinely can spell a 9+ letter word, so any lower figure would start rejecting legitimate play, which is the one thing the design is not allowed to do. The ledger is therefore already as tight as it can be given what it knows.

Worked against source constants — `LetterBlasterConfig.COOLDOWN` 0.25 s, Scrabble-weighted mean letter value ≈1.9, uniform 33/33/33 colour split — the ceiling accrues at roughly **7.6 per colour per second**, reaching `TIER_COSTS[4]` (40) in about five seconds and pinning at the 60 cap by eight. Against a real economy where a colour's energy accrues over tens of seconds of successful spelling, the ceiling is effectively always full.

So it catches a client that casts *without* shooting — a cast-spam bot, which `RateLimiter` already largely handles — and misses the cheat anyone would actually write: shoot blocks normally, producing traffic indistinguishable from real play, and never memorize a word. Spelling, the entire premise of the game, becomes optional while every spell stays available.

The reframe that produced option 3: the useful question is not *how do we bound energy*, but **does the server ever learn that a word was spelled?** The ledger's answer is no, and everything weak about it follows from that.

### Validated memorize (built 2026-08-10, shadow mode)

Landed as `server/Economy/` — `EnergyLedger` (state + verdicts, keyed by UserId so the suite can drive it without a `Players` entry), `EconomyConstants` (the `ENFORCE` flag), `EconomyService` (the `ReportMemorize` remote + lifecycle). Credit hooks the accepting branch of `BlockShootService`; the price check and debit sit in `SpellCastService` before the target checks. Client side, every memorize goes through `client/EconomyReport` so the wire format lives in one place and a new call site cannot silently skip the report.

`MemorizeAction.scoreTiles` was extracted for this: client and server price a word with the same code, because two implementations of "what is this word worth" would drift and the server's copy is only useful while it agrees on every legitimate play.

**Verified 2026-08-10**: suite `Economy/ledger_prices_a_cast` 1/1 (12 scenarios — including *shooting alone earns nothing*, which is the assertion the rejected ledger would have failed), and a live wire check firing `ReportMemorize` from the Client VM produced `[EconomyService] would reject memorize from ZandaLuki — claimed 1 x A/red, holds 0` with nothing refused.

**Owed:** the happy path end-to-end — tap real blocks, memorize, see the credit — has not been driven, because it needs actual tapping rather than injected Luau. The wire is proven; the credit path is proven only by the suite.

**Reading the shadow log:** `DevDebug`'s `[` hotkey conjures letters into the buffer without consuming a block, so every dev memorize logs a coverage failure. Those are not findings. Discount any would-reject line following a `[` press.

#### Design

The server keeps, per player, a **multiset of the letters consumed since that player's last memorize** — 26 letters × 3 colours, so 78 integers and no meaningful memory cost. A new remote carries the word on memorize. The server checks it against [[systems/Dictionary]], checks the letters are covered by the held set, and credits the **exact** `EnergyEconomy.splitByColor` value. `spec.cost` is debited from the cast's colour on every accepted cast, exactly as the ledger specified.

**Memorize clears the entire held set, not just the word's letters.** This mirrors `MemorizeAction.tryMemorize`, which drains the whole buffer — there is no such thing as memorizing a sub-word — and it handles double-tap-discard without a second remote: discarded letters are cleared on the same event the client cleared them. Whenever discards leave the server's set a superset of the client's real buffer, that is the safe direction, and it re-syncs on every memorize.

Two problems from the ledger design disappear rather than getting solved. `MAX_LETTER_VALUE` is not needed, because credit is exact rather than bounded — which is fortunate, since no such constant exists in `src/`. And [[systems/Wildcard]] needs no special case at the credit site: the claimed word carries resolved letters, held stars cover any letter during the coverage check, and `Dictionary.resolve` does the same work it does client-side.

**Residual gap — banking.** A client bypassing the mind-full gate could shoot far past the 12-slot buffer cap between memorizes and claim the best word among the accumulated letters. Deliberately **not** closed with a hard cap on held-set size: a player who discards aggressively could plausibly shoot well past 12 between memorizes, and a cap that is ever wrong rejects real play. Log the high-water mark and tighten later against evidence.

**False-reject path — largely closed by Phase 5.7 stage 4.** The client appends a letter to its buffer locally and *then* fires `ConsumeBlock`, so a server-side refusal on rate or range would leave the client holding a letter the server never credited, and a memorize using it would not validate. Phase 5.7 stage 4 (2026-08-10) closed this while solving the PvP block race: `reject()` now fires the client-minted request id back on `ConsumeBlock`, and `BlockTapController.onRejected` rolls the letter out via `WordBuffer:removeLastMatching`. Client buffer and server held-set therefore stay in sync by construction, and this design inherits that for free.

The residue is narrow: if the reply is lost or arrives after `PENDING_TTL_SEC`, the pending entry is swept without a rollback and the divergence returns for that one letter. Narrow enough to measure rather than design around — which is what shadow mode is for.

**Rollout: shadow mode first.** Compute the verdict, log it, reject nothing. Confirm the false-positive count is actually zero across the friends playtest, then flip to enforce. That makes "is the coverage check generous enough" a measurement rather than a judgement call — the same mistake the rate limiter's generous floor was standing in for.

**Why this and not the ledger, in one line:** it is roughly twice the work, it closes the cheat the ledger misses, and none of it is throwaway if the project later goes to option 2 — the memorize remote and the server-side `Dictionary` / `EnergyEconomy` wiring are exactly what a full authoritative economy needs. It also hands [[design/persistence-progression]] the word itself, which two of Phase 5.5's headline stats (longest word, highest-value word) require and which the ledger could never have provided.

### Ledger design (rejected 2026-08-10 — kept as the record)

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
