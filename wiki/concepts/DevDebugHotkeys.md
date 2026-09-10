---
type: concept
description: Keyboard hotkeys available in DevDebug.client.luau for playtesting word buffer, energy reservoirs, and mobile-input simulation.
updated: 2026-09-10
---

# Dev Debug Hotkeys

`src/client/DevDebug.client.luau` — active in Studio playtests only (dev-only LocalScript, not shipped).

## Hotkeys

| Key | Action |
|-----|--------|
| `[` | Append next letter of "CATALOG" (cycles) with a random tile color (red / green / blue) to the word buffer, **and credit it to the server's `EnergyLedger` as held** |
| `]` | Trigger memorize action on the current buffer; resets the cycling letter index. Validates against those held letters, so it earns real server-side energy |
| `\` | Clear the word buffer and reset the letter index |
| `1` | Fill all energy reservoirs to T1 (5 energy) **and grant the server ledger the same tier** |
| `2` | Same, T2 (10 energy) |
| `3` | Same, T3 (20 energy) |
| `4` | Same, T4 (40 energy) |
| `M` | Toggle mobile-input override — forces `InputCategorizer` to report "Touch" so the touch HUD can be tested on desktop |
| `;` | Toggle boss phase label visibility — hidden by default in gameplay; press to reveal/hide during playtesting |

## Notes

- `[` / `]` / `\` were originally F1–F3 but moved to avoid conflicts with Studio's built-in F-key shortcuts (commit `e7555ae`).
- Mana tier keys 1–4 were added in commit `b3fbb6c` to speed up spell-casting tests without grinding word buffer fills.
- `M` is the primary way to develop and verify mobile-only HUD widgets (e.g. DASH button, vertical spell column) without a physical device.
- **So does the `[` / `]` word cheat, and it gets the better fix.** A conjured
  letter never popped a block, so the ledger never held it and the `]` memorize
  failed coverage — `claimed 2 x A/blue, holds 0`. Harmless while `ENFORCE` was
  false; under enforcement the memorize credits the client's reservoirs and
  nothing on the server, so the dev word banks energy no cast can spend. Fixed
  2026-09-10: `[` fires `Shared.Economy.Remotes.DevCreditLetter` and
  `EconomyService` calls `EnergyLedger.creditBlock` — the same call the accepting
  branch of `BlockShootService` makes. The `]` then goes through the **real**
  memorize remote, coverage check and energy split, so only the letter's origin
  is faked and not its worth. Prefer this shape over a direct grant whenever a
  dev path has to cross the client/server line.
- **A rejection after a `[` press is a finding again.** The old advice was to
  discount any `would reject` line following `[`, because the dev path produced
  one every time. That is no longer true, and the note is retired rather than
  softened — advice to ignore a class of log line outlives the reason for it.
- **The mana cheat has two halves, and one of them is on the server.** Filling
  the reservoirs was the whole cheat until `EconomyConstants.ENFORCE` went true
  (2026-09-08, refactor chunk 6). After that the client would spend conjured
  energy happily and `SpellCastService` would refuse the cast against a ledger
  that had never seen a memorize — `red cast costs 5, ledger has 0`. The cast
  looked fine locally and simply never landed, which reads as "spells are
  broken" rather than "the cheat is stale". Fixed 2026-09-10: `fillToTier` also
  fires `Shared.Economy.Remotes.DevGrantEnergy`, and `EconomyService` sets the
  ledger ceiling via `EnergyLedger.devSetCeiling`. The wire carries the **tier**,
  not an amount, so the server stays the one deciding what a tier is worth.
- **The grant remote is Studio-only.** `EconomyService` gates the handler on
  `RunService:IsStudio()`, which is false on a Roblox server — a remote that
  hands out energy may not be one config flag away from being live. The ready
  log says which way it resolved.
- **Remove before shipping** — none of these bindings should reach production.
- `;` is listed here for discoverability, but the `Enum.KeyCode.Semicolon` binding and the phase-label toggle it drives both live in `src/client/UI/BossHudGui.client.luau`, not in `DevDebug.client.luau` — this file only prints it in the ready-log hint. A stale in-code comment in `BossHudGui.client.luau` said "toggle with P"; fixed to `;` in refactor chunk 0 (2026-09-08).
