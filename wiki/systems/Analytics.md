---
type: system
description: Phase 5.4 analytics (2026-09-22) — the onboarding funnel (joined → first_pop → first_memorize → first_cast → first_boss_damage → boss_kill) and the loop-health custom events (word_memorized, memorize_fizzle, spell_cast, round_played, blocks_popped, session_length), sent to Roblox AnalyticsService by one listening Script. Gameplay domains fire their own BindableEvents on the accept branch; AnalyticsReporter subscribes, OnboardingFunnel enforces once-and-in-order, AnalyticsSink budgets and pcalls every send. Funnel step and event count are published as Player attributes.
updated: 2026-09-22
---

# Analytics

The soft launch ([[design/build-plan]] Phase 5.4) exists to observe whether
retention is a wall, and with zero analytics that is unobservable —
[[design/persistence-progression]] § 4 pulled this into the release gate
for that reason. Built 2026-09-22 on Roblox's own `AnalyticsService`: no
infrastructure, and the dashboard is most useful *at* launch.

## What is measured

**Onboarding funnel** — mirrors the 5.4 cold-player milestone. Logged with
`LogOnboardingFunnelStepEvent`, once per player per server, strictly in
order:

| Step | Name | Trigger |
|---|---|---|
| 1 | `joined` | `PlayerAdded` |
| 2 | `first_pop` | `BlockConsumed` — a consume the server accepted |
| 3 | `first_memorize` | `WordMemorized` — the ledger credited a word |
| 4 | `first_cast` | `SpellCast` — the executor ran a cast |
| 5 | `first_boss_damage` | `PlayerDamaged` whose target rig carries the `Boss` tag |
| 6 | `boss_kill` | `BossDefeated(arenaId)`, for every roster member of that arena |

**Custom events** (`LogCustomEvent`) for the loop's health:

| Event | Value | Fields (1 / 2 / 3) | When |
|---|---|---|---|
| `word_memorized` | energy credited (sum over colours) | word length | per accepted word |
| `memorize_fizzle` | 1 | — | per fizzle (tiles spelled no word) |
| `spell_cast` | energy cost | colour / tier / spell name | per applied cast |
| `round_played` | 1 | mode name / outcome id / `won` `lost` `none` | per roster member at `RoundEnded` |
| `blocks_popped` | pops this server session | — | on leave |
| `session_length` | seconds | — | on leave |

Block pops are aggregated rather than sent one by one: forty blocks in a
minute would spend the server's whole send budget on the least
interesting signal. Boss attempts and clears, and duel results, fall out
of `round_played`'s mode and outcome fields — the outcome ids are
`GameModeConstants.RoundOutcome` ([[systems/GameMode]]).

## Ownership

| Thing | Owner | Lives in |
|---|---|---|
| Step numbers and names, event names, field keys, send budget, attribute names | `AnalyticsConstants` | `src/server/Analytics/AnalyticsConstants.luau` |
| Once-and-in-order per player | `OnboardingFunnel` (pure over an injected sink) | `src/server/Analytics/OnboardingFunnel.luau` |
| The only caller of `AnalyticsService`; budget, pcall, counts | `AnalyticsSink` (injectable backend) | `src/server/Analytics/AnalyticsSink.luau` |
| Subscribing to the domain events and driving the two above | `AnalyticsReporter` (Script) | `src/server/Analytics/AnalyticsReporter.server.luau` |
| Saying a pop / word / cast happened | the domain that accepted it | `BlockShoot/Events/BlockConsumed`, `Economy/Events/{WordMemorized,MemorizeFizzled}`, `SpellCast/Events/SpellCast` |

**No gameplay system knows analytics exists.** Each domain fires its own
server-side BindableEvent on the branch where the thing happened —
`BlockConsumed` after the ledger credit, `WordMemorized` after the verdict
said yes, `SpellCast` after `SpellExecutor.cast` — so the reporter can
never hear about a pop the server refused. The reporter listens to those
plus the events that already existed: `PlayerDamaged`
([[systems/Health]]), `BossDefeated` ([[systems/Boss]]), `RoundStarted` /
`RoundEnded` ([[systems/GameMode]]). Same seam pattern as those; the three
new events are the first server-side signals their domains have exposed.

## Rules that matter

- **Strictly in order.** Step N is logged only when N−1 was. Honest play
  guarantees the order (you cannot cast without memorizing, or memorize
  without popping); a gap can only come from a dev cheat, and a funnel with
  a fabricated middle step is worse than one with a hole. A gap is logged
  as a throttled info line and not filled. A co-op passenger who never
  damaged the boss therefore does not get `boss_kill` — the milestone is
  "contributed to a kill", which is the one a cold player is being
  measured against.
- **Once per player per server.** Roblox dedupes across servers on its
  side; the funnel forgets a player on leave.
- **A refused send leaves the step unreached**, so the next trigger
  retries instead of silently losing the row.
- **Budget.** Roblox allows 120 events per minute per server. `AnalyticsSink`
  runs a token bucket (`SEND_BURST` 60, `SEND_PER_SEC` 1.5 ≈ 90/min) and
  counts drops rather than queueing — late analytics is worse than none.
  Every send is pcall-wrapped; failures are counted and warned once per
  30 s per label.
- **Custom field keys** come from `Enum.AnalyticsCustomFieldKeys` when the
  enum exists, with the documented string names as fallback. Three fields
  per event, string values.

## Watching it without a dashboard

`AnalyticsReporter` writes two attributes on each Player:
`Analytics_FunnelStep` (highest step logged this server) and
`Analytics_Events` (custom events sent for that player). They replicate,
so the Properties panel on a Player in a playtest shows the funnel moving;
the suite reads them. `[Analytics] <name> → first_pop` lines mark each
step in the server log.

Whether Studio playtests reach the Roblox dashboard is **not verified** —
the docs page consulted did not say. Nothing here depends on it: the
sink's counts and the attributes are what the playtest checks, and the
dashboard is checked after the unlisted publish.

## Files

```
src/server/Analytics/
  AnalyticsConstants.luau      — Funnel steps + names, Event names, Field keys, budget, attribute names
  OnboardingFunnel.luau        — reach(player, step) / stepOf / forget
  AnalyticsSink.luau           — new(backend?, budget?) → onboardingStep / custom / counts; engineBackend()
  AnalyticsReporter.server.luau — the listener
src/server/BlockShoot/Events/BlockConsumed.model.json     — (player, letter, color, arenaId)
src/server/Economy/Events/WordMemorized.model.json        — (player, word, energyByColor)
src/server/Economy/Events/MemorizeFizzled.model.json      — (player)
src/server/SpellCast/Events/SpellCast.model.json          — (player, spellName, color, tier, cost, targetName?)
src/server/Boss/Scripts/BossSpawner.luau                  — exports BOSS_TAG (was a file-local literal)
src/shared/Tests/Suites/Analytics/
  onboarding_funnel_rules.luau · analytics_wires_domain_events.luau
```

## Verification

One playtest, 2026-09-22.

- **Suite** (`RunTests = Analytics`): 2/2. `onboarding_funnel_rules` pins
  once / in-order / gap-not-filled / refused-send-retries / per-player
  isolation against a recording sink. `analytics_wires_domain_events`
  fires the real `BlockConsumed`, `WordMemorized`, `MemorizeFizzled`,
  `SpellCast`, `PlayerDamaged` (throwaway `Boss`-tagged rig) and
  `BossDefeated` (throwaway NoOp session, roster only) and watched the
  real reporter take the harness player from step 1 to 6 and count three
  custom events.
- **Engine acknowledged every call.** The Studio console prints
  `AnalyticsService: LogOnboardingFunnelStepEvent event fired.` /
  `LogCustomEvent event fired.` for each send — six funnel steps and four
  custom events in the run, zero failures, zero budget drops. So the
  signatures are right and Studio does dispatch the calls; whether they
  land on the dashboard is still to be read after the unlisted publish.
- **Live accept branches**, probed by a server-side listener on the two
  new events while the client fired the real remotes: a real
  `ConsumeBlock` on the nearest lobby block produced
  `BlockConsumed(ZandaLuki, N, blue, Lobby)`; a dev T1 grant followed by a
  real `SpellCastServer("green", 1)` produced
  `SpellCast(ZandaLuki, Mend, green, T1, cost=5, target=nil)` and
  `Analytics_Events` went 3 → 4. The memorize branch was not driven live
  (needs a real word from popped letters); its one-line fire mirrors the
  other two and the suite covers the listener side.

## Not built

- **Progression events** (`LogProgressionEvent`) — nothing to progress
  through until Phase 5.5's personal bests.
- **Economy events** (`LogEconomyEvent`) — no currency; energy is
  per-round and already carried by `word_memorized` / `spell_cast`.
- **Per-round pop counts** — pops aggregate per server session; add a
  round-scoped counter if the dashboard needs pops-per-round.
- **A client-side funnel** (first HUD interaction, tutorial steps) —
  belongs to [[systems/Tutorial]] when it exists, and would relay through
  a validated remote, not log from the client.

## Cross-references

- Why it is in the gate → [[design/persistence-progression]] § 4, [[design/build-plan]] Phase 5.4
- The events it listens to → [[systems/Health]] (damage), [[systems/Boss]] (defeat), [[systems/GameMode]] (rounds, outcome ids)
- The accept branches it hangs off → [[systems/BlockShoot]], [[systems/SpellCastService]] § Validated memorize
- Test shape → [[concepts/MultiplayerTestPattern]]
