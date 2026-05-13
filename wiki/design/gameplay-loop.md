---
type: design
description: Canonical core loop — aim, shoot letter blocks, spell words in a 12-slot buffer, cast color-typed spells that drain per-color energy reservoirs to defeat the level monster
updated: 2026-05-13
---

# Gameplay Loop

## Elevator pitch

Brain Fighter is a third-person shooter where combat *is* spelling. The player is a wizard whose spells are loaded by shooting floating letter blocks scattered around the level; shot letters land in a small word buffer, the player drags them into a real word, and pressing Cast spends per-color energy to fire a spell at the level's monster. Block color decides which spell type charges — red feeds damage, green feeds healing/walls, blue feeds utility — so what you *can* cast is shaped by what's currently flying around the arena. The TPS-template foundation (aiming, hit detection, movement) is in service of a literacy mechanic: precision aim and vocabulary are the same skill.

## Core loop

The full cycle, as drawn in [`./gameplay-loop.excalidraw`](./gameplay-loop.excalidraw):

1. **Aim** — player tracks a floating letter block with the TPS reticle.
2. **Shoot** — a successful hit despawns the block; the spawner queues a replacement.
3. **Buffer** — the shot letter appends to the 12-slot word buffer. Each tile remembers the **color** of the block it came from.
4. **Arrange** — player drags buffer tiles into the order they want and double-clicks/taps to destroy unwanted letters. The buffer is the only place words are constructed.
5. **Memorize** — the explicit commit button (icon-only, e.g. ✨) validates the buffered word against the dictionary. **Valid** → the word's energy transmutes into the matching per-color reservoirs and the buffer clears. **Invalid** → the button shakes, the buffer flashes red, and the letters are preserved so the player can correct typos without retyping. *No spell fires from this action* — committing and casting are now separate.
6. **Energy** — on a valid Memorize, `word_energy = Σ letter_values × length_multiplier`. Mixed-color words are allowed; energy is **split value-weighted by tile color** — each tile contributes its own `letter_value × length_multiplier` to *its* color's reservoir. Sum across colors equals whole-word energy. All blocks are colored. Energy persists across words, so the player can Memorize multiple words to stockpile before casting.
7. **Cast** — the player spends energy by interacting with a color reservoir directly. **Tap** a reservoir = fire that color's highest currently-affordable tier. **Drag from** a reservoir = a vertical menu opens, listing **all currently-affordable tiers of that color** (Spark T1·10 / Fireball T2·30 / Inferno T3·80 for red), with locked tiers greyed; release on the desired tier to fire it. Release outside = cancel. Casting drains *exactly the tier cost*, not the whole bar.
8. **Spell** — the spell config's `targetingMode` decides what happens next: `auto` fires at the monster (or self, for buffs); `placement` hands the player an aimed reticle for the spell's footprint.
9. **Effect** — the spell resolves against the monster (damage, debuff) or the player (heal, shield) or the world (wall, AOE).
10. **Loop** — buffer drains on Memorize; player re-engages floating blocks. Level ends when the monster's HP hits zero.

Pacing tension — slow spelling vs urgent combat — is the central design risk and the loop is built around it. The 12-slot cap and the rearrange/destroy UX are both biased toward "the player is mostly *curating*, occasionally *firing*"; if playtest shows that tips into "hoard letters then nuke," that's a tuning lever, not a bug to mask.

## Resolved design decisions

### Buffer & input

- **12 slots, append-on-shot, drag-to-reorder, double-click/tap to destroy, explicit Cast.** *Why:* 12 covers any word a curated K-12 dictionary realistically contains while still bounding hoarding. Direct tile manipulation is more tactile and kid-legible than a "backspace" verb; double-tap-to-destroy reads as "I don't want this" without teaching a new vocabulary.
- **Buffer-full blocks shooting.** *Why:* diegetic — the wizard's mind is at capacity. The player must destroy a letter or cast a spell to free room. Failed shots need clear feedback (fizzle, greyed crosshair, "mind full" indicator) so the input rejection is legible and not mistaken for input lag.
- **Touch/mouse first, minimal keyboard.** *Why:* Roblox audience skews mobile. Keyboard exists only for the unavoidable hotkeys (Cast, possibly color/tier pick). Anything that *requires* a key combo is broken on phone.

### Spell typing & roster

- **Block color determines spell type. Spell element is derived from blocks used, NOT word theme.** *Why:* spelling "ROCK" with red blocks is a damage spell, not an earth spell — because "ROCK" with green blocks is a heal. This keeps the system orthogonal: letters are a typing-puzzle layer, color is the spell-school layer, and they don't fight. Word theme is flavor, not mechanics.
- **Three colors at launch — Red=Damage, Green=Healing/Walls, Blue=Utility.** *Why:* a three-school roster is the smallest set that can express the offense/defense/control rock-paper-scissors monsters can be designed around. More colors can be added later if they earn their place; starting wider risks each school feeling thin.
- **Three tiers per color, gated by per-color energy thresholds.** *Why:* tiering gives the player a tangible "is this worth casting now or saving for the big one?" decision every cast, which is the choice the loop is built around. One tier per color would flatten that to "press button when bar full."

### Spell economy

- **Per-color persistent reservoirs.** *Why:* one shared energy pool would erase the meaning of color; one tier-locked reservoir per color forces the player to actually engage with whichever colors the spawner is offering. Persistence (vs. per-word reset) is what lets short words contribute — `CAT` is worthless on its own, but five `CAT`s is a T2 cast.
- **Casting drains exactly the tier cost; cap at 160 (2×T3).** *Why:* full-drain casting would punish the player for accidentally chaining big words. Exact-cost drain rewards efficiency without punishing surplus. The 160 cap absorbs overshoot from one huge word (`EARTHQUAKES`=81, `CHARACTERIZE`=84) but blocks indefinite stockpiling that would trivialize encounters.
- **Word power = Scrabble letter values × length multiplier.** *Why:* Scrabble values are a known-good distribution that already rewards rare letters; pinning the formula to that gives us free intuition ("Z is worth more than E"). The length multiplier is what turns short common words into kindling and long words into the climactic payoff — `LIGHTNING` should feel meaningfully bigger than `FIRE`, not just slightly bigger.

### Targeting

- **`targetingMode: "auto" | "placement"` per spell.** *Why:* most spells (damage at a single monster, self-heal, single-target debuff) have an obvious target and forcing a manual aim step on every cast is friction. But wall-style and AOE spells *need* placement — auto-targeting Stone Wall would be nonsensical. A per-spell flag keeps the rule simple and the spell roster expressive without inventing categories.

### Memorize & Cast — two distinct surfaces

Word commit and spell cast are decoupled (revised 2026-05-13, supersedes an earlier single-button drag-cast design). Two actions, two surfaces.

#### Memorize (commit button)

An icon-only button next to the buffer converts the buffered word into mana.

- **Valid word** → energy transmutes into the matching color reservoirs (value-weighted by tile color per the formula). Buffer clears. The letters visibly flow into the bars as feedback.
- **Invalid word** → the button shakes, the buffer flashes red, but **letters are preserved** so the player can correct typos without starting over. A soft fizzle sound communicates the failure without punishing it.
- The button is **icon-only** (sparkle / swirl glyph). No text label → no localization burden, and the action is taught in tutorial copy ("tap to absorb the word into mana") rather than baked into the button itself.

*Why:* the prior design coupled word commit with spell fire — every commit forced a cast decision. Decoupling them turns stockpiling into a real strategy (commit several words first, then choose when and what to cast) and removes the awkward "what color does an empty Cast tap default to?" question.

#### Cast (reservoir-driven)

Each color's reservoir is the cast surface for that color.

- **Tap a reservoir** = fire the highest currently-affordable tier of that color. Default fast-path; one touch, predictable.
- **Drag from a reservoir** = a vertical menu opens alongside it, listing **all currently-affordable tiers of that color** (e.g. red: Spark T1·10, Fireball T2·30, Inferno T3·80). Affordable tiers are bright; tiers above the current energy are greyed/locked. Release on a tier to fire that spell.
- **Release outside the menu** = cancel; no energy spent.
- The menu opens **toward the screen interior** (reservoirs live on the right edge → menu opens to the left), so the player's finger doesn't occlude the choices.

*Why:* anchoring the cast on the color reservoir resolves two problems with the prior single-button drag-cast — (1) color is now explicit by virtue of which bar you touched, so there's no arbitrary tap-default rule, and (2) the menu has room to show all three tiers of that one color rather than compressing into one entry per color, which gives the "save big, fire small" decision a natural home.

### Spawner

- **Constrained-random with soft heuristics + escape hatches, not a hard "always spellable" guarantee.** *Why:* a hard guarantee is brittle (what counts as "spellable" depends on what's already in the buffer, what tier the player is going for, etc.) and expensive to compute. Soft bias + "if stuck, spawn extras" + "player can reroll" covers the same failure mode with much less code. Don't over-engineer this up front.
- **Shot blocks vanish, spawner replenishes; blocks float and require player movement.** *Why:* movement-gated letter pickup is what couples the TPS template's locomotion to the spelling layer — without it, the player roots and the game becomes a typing test with no shooter texture.

### Dictionary

- **Local Luau ModuleScript hashtable, ~10–30k curated entries.** *Why:* the reason to curate is *not* memory (Roblox handles 5–8 MB fine) — it's age-appropriateness (Scrabble lists contain obscure/offensive 2–3 letter words) and game feel (you want "FLAME" to feel earned, not "QAT"). Local + hashtable gives O(1) lookup with zero network dependency. Possible future direction: tier the dictionary by level to scaffold a learning curve.

### Win condition

- **One monster per level; defeat it with charged spells.** *Why:* a single boss focuses the loop. Multi-enemy encounters can be added later, but the first version needs the player to *care* about each cast — and that requires a target that visibly responds to power.

## Tuning numbers

### Letter values (Scrabble)

| Value | Letters |
|---|---|
| 1 | A E I O U L N S T R |
| 2 | D G |
| 3 | B C M P |
| 4 | F H V W Y |
| 5 | K |
| 8 | J X |
| 10 | Q Z |

### Length multipliers

| Word length | Multiplier |
|---|---|
| ≤ 4 | 1× |
| 5–6 | 1.5× |
| 7–8 | 2× |
| 9+ | 3× |

### Spell tier thresholds

| Tier | Energy required to cast | Drain on cast |
|---|---|---|
| T1 | 10 | 10 |
| T2 | 30 | 30 |
| T3 | 80 | 80 |

Bar cap per color: **160** (2×T3). Energy above the cap is discarded.

### Spell roster (prototype)

| Color | Tier | Spell | Effect (prototype) | Targeting |
|---|---|---|---|---|
| Red | T1 | Spark | ~5% boss HP damage | `auto` |
| Red | T2 | Fireball | ~20% boss HP damage | `auto` |
| Red | T3 | Inferno | ~50% boss HP damage | `auto` |
| Green | T1 | Mend | ~15% self-heal | `auto` |
| Green | T2 | Stone Wall | ~6 s wall, player-placed | `placement` |
| Green | T3 | Sanctuary | Full heal + buff | `auto` |
| Blue | T1 | Frost Nip | 1 s freeze on target | `auto` |
| Blue | T2 | Shield | ~5 s damage absorb on self | `auto` |
| Blue | T3 | Stasis | 5 s freeze + damage amp | `auto` |

Numbers are starting points for first-prototype tuning, not final balance.

## Worked examples

Spot-check the formula end-to-end. `Σ letter_values × length_multiplier`, rounded to integer.

| Word | Letter sum | Length | Multiplier | Energy | Tier reached on this cast |
|---|---|---|---|---|---|
| CAT | 3+1+1 = 5 | 3 | 1× | **5** | — (below T1) |
| FIRE | 4+1+1+1 = 7 | 4 | 1× | **7** | — (below T1) |
| ROCK | 1+1+3+5 = 10 | 4 | 1× | **10** | T1 |
| FLAME | 4+1+1+3+1 = 10 | 5 | 1.5× | **15** | T1 |
| DRAGON | 2+1+1+2+1+1 = 8 | 6 | 1.5× | **12** | T1 |
| FROZEN | 4+1+1+10+1+1 = 18 | 6 | 1.5× | **27** | T1 |
| FIREBALL | 4+1+1+1+3+1+1+1 = 13 | 8 | 2× | **26** | T1 |
| LIGHTNING | 1+1+2+4+1+1+1+1+2 = 14 | 9 | 3× | **42** | T2 |
| EARTHQUAKES | 1+1+1+1+4+10+1+1+5+1+1 = 27 | 11 | 3× | **81** | T3 |
| CHARACTERIZE | 3+4+1+1+1+3+1+1+1+1+10+1 = 28 | 12 | 3× | **84** | T3 |

If anything in this table drifts from what code returns at runtime, the code has a bug — these are pinned.

### Color-split worked examples

Mixed-color words split energy value-weighted, not count-weighted. Each tile contributes its own `letter_value × length_multiplier` to its color's reservoir.

| Word | Tiles (color) | Per-color letter sums | Length × | Per-color energy | Total |
|---|---|---|---|---|---|
| FLAME | F-L-M = red, A-E = green | Red 8, Green 2 | 5 → 1.5× | Red **12**, Green **3** | **15** |
| FROZEN | F-R-Z = red, O-E-N = blue | Red 15, Blue 3 | 6 → 1.5× | Red **22**, Blue **5** | **27** (rounding: 22.5→22) |
| ROCK | R-O = red, C-K = blue | Red 2, Blue 8 | 4 → 1× | Red **2**, Blue **8** | **10** |

The Red+Blue Z-padding-exploit ("stuff a Z into red, pad with cheap blue letters for a 50/50 split") is structurally impossible — the Z's 10 points only ever feed the color of the Z's tile.

## Open design questions

These are the next decisions to make, before or during prototype. Each is paired with the trade-off the prototype is meant to surface.

- **Spawn density.** How many blocks float at once? Too few and the player is starved between casts; too many and the level reads as visual noise and the spawner's color bias matters less. This depends on level size and is best tuned against a real arena.
- **Color distribution in spawner.** Equal-weight R/G/B, or weighted (e.g. 50/25/25)? Equal is neutral; weighted lets monster designs lean on scarce colors ("this fight is hard because green is rare and you need walls"). Weighting needs the monster system to be in place to be meaningful — premature otherwise.

We'll have evidence on all three after the first playable prototype puts a real player in a real arena with real monsters. Premature locking is worse than the cost of revisiting.

## References

- [`./gameplay-loop.excalidraw`](./gameplay-loop.excalidraw) — sibling visual diagram of the loop.
- [`./hud.mockup.html`](./hud.mockup.html) — sibling HUD mockup showing buffer, color reservoirs, and tier picker (in progress).
- [[design/ArtDirection]] — visual rules the HUD and block visuals must respect.
- [[systems/HUD]] — current code-driven HUD system; the buffer + reservoir bars will land as new builders here.
- [[systems/Weapon]] — the shooter side of the loop; the "shoot a letter block" path reuses this pipeline.
- [[concepts/BuilderConfigLayout]] — HUD architecture pattern the buffer/reservoir UI will follow.
- [[concepts/SingleOwnership]] — only one system writes the energy reservoirs and only one writes the buffer.
