---
type: design
description: Persistence & progression strategy — mastery-first progression, ProfileStore-backed PlayerData, analytics in the 5.4 release gate, implementation as Phase 5.5
updated: 2026-07-27
---

# Persistence & Progression

Decided 2026-07-27 in a dedicated design session, spun off from the release-readiness discussion that set the Phase 5.4 soft-launch bar. Companion to [[design/build-plan]] (Phase 5.4 analytics item + Phase 5.5) and [[design/gameplay-loop]] (the stats this page persists all fall out of the core loop).

**Context:** the game currently has zero persistence — no DataStores, no analytics, nothing survives a session. That is deliberate for the soft launch: persistence does **not** gate Phase 5.4. This page defines what comes immediately after, plus the one exception pulled forward (analytics).

## Decisions

### 1. Progression philosophy: mastery-first

The game stays fully open — no content is gated behind session-to-session unlocks. Retention comes from self-improvement: personal bests, cumulative stats, and (later) leaderboards.

**Rationale:** Brain Fighter's core loop is already a skill loop (spell better words → more energy → bigger casts). Spell tiers are gated by in-run energy (5/10/20/40), which is the game's own difficulty curve; retro-gating spells behind meta unlocks would distort SpellRegistry/EnergyEconomy balance and remove the "full toolkit from minute one" feel. Meta unlocks were considered and **rejected** for the first wave.

### 2. What persists (first wave, Phase 5.5)

| Category | Contents | Notes |
|---|---|---|
| **Settings** | Input prefs, UI options | Cheap, expected by players |
| **Word stats & personal bests** | Total words memorized, highest-value word (word + energy), longest word, best boss clear time, boss kills, total sessions | All derivable from existing MemorizeAction / CastAction / Boss events — no gameplay changes needed |
| **Cosmetics inventory** | `owned` + `equipped` slots | **Schema reserved only** — no cosmetic content ships in 5.5. When content arrives (later phase), cosmetics are earned via mastery milestones only (e.g. first boss kill, 100 words, a 7+ letter word). No Robux monetization. |

**Deliberately excluded from the first wave:** run history & daily streaks (revisit once analytics shows session patterns), spell/tier unlocks (rejected per philosophy), purchasable anything.

### 3. DataStore architecture: ProfileStore behind a PlayerData module

- **ProfileStore** (loleris — successor to ProfileService) for session locking. Even though the game is effectively single-player today, session locking makes duplication/data-loss bugs a non-issue and costs nothing extra.
- Wrapped in a single server-side **`PlayerData`** module — the only file in the codebase allowed to touch ProfileStore or DataStores directly ([[concepts/SingleOwnership]] applied to persistence). Gameplay systems write through its API; they never see the profile object.
- **Schema versioning** from day one: `schemaVersion` field + reconcile-against-defaults template on load, so adding fields later is a non-event.
- Client reads its own data via replication from PlayerData (remote/attribute), never via DataStore APIs.

Sketch of the v1 profile template:

```lua
{
  schemaVersion = 1,
  settings = {},
  stats = {
    totalWords = 0,
    bestWord = { word = "", energy = 0 },
    longestWord = "",
    bestBossClearTime = nil,
    bossKills = 0,
    totalSessions = 0,
  },
  cosmetics = { owned = {}, equipped = {} },  -- reserved, empty until cosmetics content ships
}
```

### 4. Analytics: pulled INTO the Phase 5.4 release gate

The one change to the soft-launch bar from this session. The soft launch exists to observe whether retention is a wall — with zero analytics that's unobservable. Roblox's built-in `AnalyticsService` needs no infrastructure and is most valuable *at* launch:

- **Onboarding funnel** mirroring the 5.4 cold-player milestone: join → first shoot → first memorize → first cast → first boss damage → boss kill.
- **Custom events** for the loop's health: words memorized (with energy value), spells cast (by color/tier), fizzles, boss attempts/clears, session length.

Recorded as a new item in the Phase 5.4 table in [[design/build-plan]].

### 5. Build plan placement: Phase 5.5

Persistence & progression is **Phase 5.5**, the first post-launch phase — see [[design/build-plan]]. Scope: PlayerData module (ProfileStore), settings + stats persistence, cosmetics schema reservation, and a minimal "personal bests" surface in the HUD. Leaderboards (OrderedDataStore) are explicitly a candidate follow-on, not in 5.5.

## Open questions (for Phase 5.5 kickoff or later)

- **Leaderboards:** global OrderedDataStore boards (best word energy, fastest boss clear) — natural extension of mastery-first, but wait for soft-launch analytics to confirm which stats players care about.
- **Streaks / run history:** revisit once session-pattern data exists.
- **PB surface in HUD:** where personal bests show up (end-of-run summary vs. persistent menu page) — design pass at 5.5 kickoff.
- **Cosmetics content phase:** which slots (staff skin first?), milestone list, and pipeline — its own phase after 5.5.
