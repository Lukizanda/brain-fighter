---
type: design
description: Canonical core loop — aim, shoot letter blocks, spell words in a 12-slot buffer, cast color-typed spells that drain per-color energy reservoirs to defeat the level monster
updated: 2026-08-12
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
5. **Memorize** — the explicit commit button (icon-only, e.g. ✨) validates the buffered word against the dictionary. **Valid** → the word's energy transmutes into the matching per-color reservoirs and the buffer clears. **Invalid** → the button shakes, the buffer flashes red, and the buffer is **cleared anyway** — the letters are consumed, so a bad commit costs the collected tiles and the player must re-collect. *No spell fires from this action* — committing and casting are now separate. (Revised from an earlier "preserve on invalid" rule; see Memorize section below.)
6. **Energy** — on a valid Memorize, `word_energy = Σ letter_values × length_multiplier`. Mixed-color words are allowed; energy is **split value-weighted by tile color** — each tile contributes its own `letter_value × length_multiplier` to *its* color's reservoir. Sum across colors equals whole-word energy. All blocks are colored. Energy persists across words, so the player can Memorize multiple words to stockpile before casting.
7. **Cast** — the player spends energy by **pressing and holding** a color reservoir. The charge starts at T1 (so a quick tap is a Firebolt) and climbs through the tiers that colour can afford — Firebolt T1·5 at 0 s, Fireball T2·10 at 0.25 s, Inferno T3·20 at 0.75 s, Volley T4·40 at 1.75 s — stopping dead at the affordability ceiling. Release over the panel fires the tier you reached; release outside cancels. Casting drains *exactly the tier cost*, not the whole bar, and **nothing is drained until release**, so a cancelled hold costs nothing. See [[systems/ChargeCast]].
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
- **Casting drains exactly the tier cost; cap at 60 (3×T3).** *Why:* full-drain casting would punish the player for accidentally chaining big words. Exact-cost drain rewards efficiency without punishing surplus. The 60 cap (≈ one T4 cast plus change) blocks indefinite stockpiling that would trivialize encounters and keeps the player casting frequently rather than hoarding for one nuke. (Originally 160 = 2×T3-of-80; lowered alongside the tier-cost rebalance.)
- **Word power = Scrabble letter values × length multiplier.** *Why:* Scrabble values are a known-good distribution that already rewards rare letters; pinning the formula to that gives us free intuition ("Z is worth more than E"). The length multiplier is what turns short common words into kindling and long words into the climactic payoff — `LIGHTNING` should feel meaningfully bigger than `FIRE`, not just slightly bigger.

### Targeting

- **`targetingMode: "auto" | "placement"` per spell.** *Why:* most spells (damage at a single monster, self-heal, single-target debuff) have an obvious target and forcing a manual aim step on every cast is friction. But wall-style and AOE spells *need* placement — auto-targeting Stone Wall would be nonsensical. A per-spell flag keeps the rule simple and the spell roster expressive without inventing categories.

### Memorize & Cast — two distinct surfaces

Word commit and spell cast are decoupled (revised 2026-05-13, supersedes an earlier single-button drag-cast design). Two actions, two surfaces.

#### Memorize (commit button)

An icon-only button next to the buffer converts the buffered word into mana.

- **Valid word** → energy transmutes into the matching color reservoirs (value-weighted by tile color per the formula). Buffer clears. The letters visibly flow into the bars as feedback.
- **Invalid word** → the button shakes, the buffer flashes red, and the buffer is **cleared** — the letters are consumed regardless (`MemorizeAction` `init.luau:76`). A soft fizzle sound communicates the failure. *(Revised 2026-05/06 from the original "letters preserved for typo correction" rule: consuming on a bad commit makes Memorize a real decision with stakes rather than a free retry. If playtest shows it's too punishing for young players, this is a one-line revert in `MemorizeAction`.)*
- The button is **icon-only** (sparkle / swirl glyph). No text label → no localization burden, and the action is taught in tutorial copy ("tap to absorb the word into mana") rather than baked into the button itself.

*Why:* the prior design coupled word commit with spell fire — every commit forced a cast decision. Decoupling them turns stockpiling into a real strategy (commit several words first, then choose when and what to cast) and removes the awkward "what color does an empty Cast tap default to?" question.

#### Cast (reservoir-driven)

Each color's reservoir is the cast surface for that color. **Press it, hold to climb the tiers, release to fire what you reached.** Full system page: [[systems/ChargeCast]] (Phase 5.8, 2026-08-12).

- **Press a reservoir** → the charge starts at T1 immediately, so a quick tap is a Firebolt.
- **Keep holding** → the charge climbs through the tiers, priced in seconds by how much *more* mana each one costs than a tap: T2 at 1 s, T3 at 3 s, T4 at 7 s (`MANA_FLOW_PER_SEC = 5`). T4 reads as a commitment for free, because it costs 8× a Firebolt.
- **It stops dead at what you can afford.** The panel pulses and the character orb strains rather than growing. You cannot charge into a fizzle.
- **Release over the panel** = fire that tier. **Release outside it** = cancel; no energy spent.
- **Nothing is drained until release.** The reserve band eaten out of the top of the fill, and the numeral counting down beside it, are a *promise*. Cancelling snaps both back — there is no refund because nothing was taken.
- **The commitment is visible to everyone.** An orb over the caster's head grows with the tier and pops on release, so "he's been holding red for a second and a half" is a tactical read. Same deliberate leak as the collect stream in [[design/tap-to-pop]].
- **Placement-mode spells** still need their second aim step; the marker treatment described below moves onto the panel rather than a menu entry, and is not built yet.

*Why:* anchoring the cast on the color reservoir makes color explicit by virtue of which bar you touched, so there's no arbitrary tap-default rule. Making the *tier* a duration rather than a menu selection is what gives "save big, fire small" a home that costs one gesture: the choice is how long you commit, and the cost of overcommitting is a real one, because the hold is time an opponent can see and act on.

> **Superseded 2026-08-12 — the drag-from-reservoir tier menu.** Kept because the reasoning is still the reason the cast lives on the reservoir at all.
>
> - **Tap a reservoir** = fire the highest currently-affordable tier. Default fast-path; one touch, predictable.
> - **Drag from a reservoir** = a vertical menu opens alongside it, listing **all currently-affordable tiers of that color** (red: Firebolt T1·5, Fireball T2·10, Inferno T3·20, Volley T4·40). Affordable tiers bright; tiers above current energy greyed/locked. Release on a tier to fire it.
> - **Release outside the menu** = cancel; no energy spent.
> - The menu opens **toward the screen interior** (reservoirs live on the right edge → menu opens left), so the player's finger doesn't occlude the choices.
> - **Placement-mode spells are visually marked** in the menu — a crosshair glyph (⌖) at the right edge of the entry, plus a **dashed outline** (auto-target entries use a solid outline). Two layered cues: the glyph identifies the targeting mode; the dashed outline signals "this entry has a second step after release." First-time use of any placement spell triggers a one-shot tutorial flash.
>
> *Why it was replaced:* it was never built, and by the time it came up for building the objection was that it costs a mode. A menu that opens over the arena hides the arena, and the tier decision then happens with the fight paused behind a panel — in a game whose other two verbs (pop, memorize) are single taps. Hold-to-charge asks the same question with no surface at all, works identically on mouse and touch, and turns the decision into something an opponent can read. What is genuinely lost is the *legend*: the menu named every tier and its price, and a hold does not. The tier rings, the reserve band and the numeral on the panel are what replace that, and they are weaker at teaching a first-time player which spell is which. The panel took a second bite out of this when it became a circle and the spell name came off it — but the name did not vanish, it moved onto the charge orb, where it pops in on each tier crossing and an opponent can read it too. That closes the *mid-charge* half of the gap. The half still open is teaching a new player the roster **before** they press, which no charge-time cue can do and which belongs to [[systems/Tutorial]]. See [[systems/ChargeCast]] § The name label.

### Spawner

- **Constrained-random with soft heuristics + escape hatches, not a hard "always spellable" guarantee.** *Why:* a hard guarantee is brittle (what counts as "spellable" depends on what's already in the buffer, what tier the player is going for, etc.) and expensive to compute. Soft bias + "if stuck, spawn extras" + "player can reroll" covers the same failure mode with much less code. Don't over-engineer this up front.
- **Shot blocks vanish, spawner replenishes; blocks float and require player movement.** *Why:* movement-gated letter pickup is what couples the TPS template's locomotion to the spelling layer — without it, the player roots and the game becomes a typing test with no shooter texture.
- **~24 blocks floating at once in a moderate arena, framed as density-per-area in code.** *Why:* 8 blocks per color is just enough for a 5-letter same-color word to be findable without the search dominating; 24 total keeps the arena legible rather than soup. Storing as `BLOCKS_PER_100_SQ_STUDS` (≈ 0.4) means the number tracks level size automatically — no per-level hand-tuning of an absolute count.
- **Letter selection within a color is Scrabble-frequency-weighted, independent of color weighting.** *Why:* English vowels and common consonants (E, A, I, O, N, R, T, L, S, U) carry most words; an even letter distribution would over-represent rare letters and make the pool feel unspellable. Frequency-weighting also makes Q/Z/J/X feel like treasure moments — exactly because they're worth more energy AND rarer to spawn.
- **Color weighting defaults to 33/33/33, but is per-level configurable via `colorWeights`.** *Why:* equal-weight is the right neutral for tutorialization and most encounters. The per-level override is what unlocks future encounter design (a boss balanced around scarce green = "no easy healing, plan offensively") and costs nothing to plumb now vs adding it later as a refactor. **No adaptive spawning** based on player state — it erodes player agency and is over-engineering for first prototype.

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
| T1 | 5 | 5 |
| T2 | 10 | 10 |
| T3 | 20 | 20 |
| T4 | 40 | 40 |

Bar cap per color: **60** (3×T3). Energy above the cap is discarded. (Rebalanced 2026-05/06 from the original 10/30/80/75 + cap 160 — the lower numbers keep casts frequent rather than encouraging hoarding. Code is pinned: `SpellRegistry.TIER_COSTS = { 5, 10, 20, 40 }`, `EnergyReservoirs.CAP_PER_COLOR = 60`.)

T4 exists for red only (Volley). Other colors top out at T3.

### Spell roster (prototype)

| Color | Tier | Spell | Effect (prototype) | Delivery | Targeting |
|---|---|---|---|---|---|
| Red | T1 | Firebolt | ~5% boss HP damage | projectile | `auto` |
| Red | T2 | Fireball | ~20% boss HP damage | projectile | `auto` |
| Red | T3 | Inferno | ~50% boss HP damage | instant | `auto` |
| Red | T4 | Volley | 3 × flat-12 damage projectiles | projectile | `auto` |
| Green | T1 | Mend | ~15% self-heal | instant | `auto` |
| Green | T2 | Stone Wall | 6 s solid barrier, blocks everything | world_spawn | `placement` |
| Green | T3 | Sanctuary | Full heal + 40 absorb | instant | self |
| Blue | T1 | Frost Nip | 3 s freeze + 5% damage on target | instant | `auto` |
| Blue | T2 | Shield | 40 damage absorbed on self, no expiry | instant | self |
| Blue | T3 | Stasis | 5 s freeze + 2× damage amp | instant | `auto` |

Numbers are starting points for first-prototype tuning, not final balance.

All ten are implemented as of Phase 5.2 (2026-08-03). Two notes where the shipped behavior differs from the original sketch:

- **The shield is an absorb pool, not a timed bubble** — 40 damage soaked, with *no* expiry; it lasts until damage eats it or you die. Sanctuary's pool is the same size, so its T3 premium over Shield is the full heal rather than a bigger bubble.
- **Self-cast spells are marked in the registry** (`selfTarget`), not inferred from colour. Mend, Shield and Sanctuary are self-resolving and never need an enemy in range; the table's `targeting` column reads "self" for those.

**Stone Wall has no placement reticle yet** — it currently drops 12 studs ahead of where the caster is facing. The ⌖ marker and second aim step described under Targeting are still outstanding (Phase 5.3).

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

## Playtest verification

All major design decisions are now resolved (see the resolved-decisions sections above). What remains is **tuning** — every concrete number in this doc is an educated starting point, and the first playable prototype is what tells us whether the curve feels right. The list below names the levers most likely to need adjustment.

- **Energy curve.** `Σ letter_values × length_multiplier` produces (CAT, FIRE, FLAME, LIGHTNING, EARTHQUAKES) → (5, 7, 15, 42, 81). Are short words rewarding enough to not feel wasteful? Are long words rewarding enough to justify the build-up time? Does `CHARACTERIZE`=84 trivialize a boss in one cast, or is that the desired payoff moment?
- **Spell tier thresholds (10 / 30 / 80).** Is T1 reachable within ~10 sec of combat starting? Does T3 feel earned rather than constantly out of reach? If players are firing T1 spam exclusively, T1's cost may be too low (or its payoff too high).
- **Spawn density (~24 blocks, ~8 per color).** Is the player ever starved for >5 sec between word attempts (too few)? Does the arena read as "block soup" (too many)? Tune via the `BLOCKS_PER_100_SQ_STUDS` constant.
- **Color weighting.** Default 33/33/33. Per-level designers may want to lean specific colors scarce for encounter shape; the first signal will come when monster designs are concrete.
- **Mind Full pacing.** With a 12-slot buffer, how often does the player actually hit the cap? If it's a rare emergency, the cap is well-placed; if "destroy a letter to keep shooting" becomes a constant mode, the cap is too low or the Memorize gesture isn't being used enough.
- **Spawner reroll trigger.** How often do players manually reroll vs how often does the spawner's soft heuristic save them automatically? Heavy manual rerolls might mean the heuristic is too loose.

## References

- [`./gameplay-loop.excalidraw`](./gameplay-loop.excalidraw) — sibling visual diagram of the loop.
- [`./hud.mockup.html`](./hud.mockup.html) — sibling HUD mockup showing buffer, color reservoirs, and tier picker (in progress).
- [[design/ArtDirection]] — visual rules the HUD and block visuals must respect.
- [[systems/HUD]] — current code-driven HUD system; the buffer + reservoir bars will land as new builders here.
- [[systems/Weapon]] — the shooter side of the loop; the "shoot a letter block" path reuses this pipeline.
- [[concepts/BuilderConfigLayout]] — HUD architecture pattern the buffer/reservoir UI will follow.
- [[concepts/SingleOwnership]] — only one system writes the energy reservoirs and only one writes the buffer.
