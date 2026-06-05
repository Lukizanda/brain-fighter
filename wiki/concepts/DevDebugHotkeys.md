---
type: concept
description: Keyboard hotkeys available in DevDebug.client.luau for playtesting word buffer, energy reservoirs, and mobile-input simulation.
updated: 2026-06-05
---

# Dev Debug Hotkeys

`src/client/DevDebug.client.luau` — active in Studio playtests only (dev-only LocalScript, not shipped).

## Hotkeys

| Key | Action |
|-----|--------|
| `[` | Append next letter of "CATALOG" (cycles) with a random tile color (red / green / blue) to the word buffer |
| `]` | Trigger memorize action on the current buffer; resets the cycling letter index |
| `\` | Clear the word buffer and reset the letter index |
| `1` | Fill all energy reservoirs to T1 (5 energy) |
| `2` | Fill all energy reservoirs to T2 (10 energy) |
| `3` | Fill all energy reservoirs to T3 (20 energy) |
| `4` | Fill all energy reservoirs to T4 (40 energy) |
| `M` | Toggle mobile-input override — forces `InputCategorizer` to report "Touch" so the touch HUD can be tested on desktop |

## Notes

- `[` / `]` / `\` were originally F1–F3 but moved to avoid conflicts with Studio's built-in F-key shortcuts (commit `e7555ae`).
- Mana tier keys 1–4 were added in commit `b3fbb6c` to speed up spell-casting tests without grinding word buffer fills.
- `M` is the primary way to develop and verify mobile-only HUD widgets (e.g. DASH button, vertical spell column) without a physical device.
- **Remove before shipping** — none of these bindings should reach production.
