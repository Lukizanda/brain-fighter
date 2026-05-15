---
type: system
description: Tutorial system — teaches the core Brain Fighter loop (shoot blocks → buffer word → memorize → cast spell) through guided in-world steps
status: planning
updated: 2026-05-16
---

# Tutorial System

## Goal

Guide a first-time player through the full Brain Fighter loop without UI overload:
1. Shoot a LetterBlock with the Spelling Staff
2. See the letter land in the buffer
3. Arrange / collect enough letters to spell a word
4. Memorize (validate + convert to energy)
5. Cast a spell at the dummy boss
6. See the boss take damage → win condition

## Design Questions (open)

- **Scripted vs freeform** — fully scripted linear sequence, or a sandbox with hint overlays that unlock as the player discovers each step organically?
- **Gating** — lock the arena door until each step is complete, or soft-guide with highlights + text?
- **Skip option** — returning players should be able to skip; gated behind "have you played before?" flag (DataStore).
- **Failure handling** — what happens if the player shoots the wrong block or the word fails the Dictionary check mid-tutorial?
- **Locale / copy** — all tutorial text lives in a single config table for easy translation.

## Systems the Tutorial Must Touch

| System | Interaction |
|---|---|
| LetterBlaster | Fire cooldown should be slowed or guided during tutorial |
| WordBuffer | Highlight specific tiles; prevent reordering until step unlocked |
| MindFullManager | Gate the Memorize button until a valid word is queued |
| MemorizeAction | Listen for success event to advance tutorial step |
| CastAction | Prompt player to pick a spell and fire |
| SpellExecutor | Confirm at least one `damage` effect lands on the dummy boss |
| BossAdapter | Use a dedicated tutorial dummy that can't die until the final step |

## Proposed Architecture

```
TutorialService (server)     — owns step state, fires RemoteEvent to client
TutorialController (client)  — listens for step events, drives UI overlays + highlights
TutorialConfig (shared)      — ordered step definitions (id, title, body, completionSignal)
```

- Step completion signals are **server-authoritative** (e.g., MemorizeAction fires `tutorialStepComplete("memorize")` on success).
- The client controller reacts to RemoteEvents — no client-side cheating of step advancement.
- Highlight/arrow overlays use a `TutorialOverlayBuilder` following the existing Builder + Config + LayoutManager pattern.

## Open Implementation Tasks

- [ ] Define TutorialConfig step table (step id, title, hint text, completion predicate, highlight target)
- [ ] TutorialService skeleton (step machine, RemoteEvent wires)
- [ ] TutorialController + TutorialOverlayBuilder (arrow, tooltip, dim overlay)
- [ ] Skip-tutorial DataStore flag
- [ ] Tutorial dummy boss variant (health floor = 1, no respawn during tutorial)
- [ ] Playtest: full first-time run without skipping
- [ ] Accessibility: screen-reader-friendly hint text, color-blind safe highlight colors

## Related Pages

- [[systems/LetterBlaster]]
- [[systems/WordBuffer]]
- [[systems/MindFullManager]]
- [[systems/MemorizeAction]]
- [[systems/CastAction]]
- [[systems/BossAdapter]]
- [[design/gameplay-loop]]
