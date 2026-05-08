# Loadout System — Design & Plan

**Status:** Design locked, implementation not started (2026-04-23)

## Overview

This is a hero-shooter-style team game. Every player builds their own "hero" per spawn by picking weapons and a special ability from the respawn area. Loadouts are freely swappable mid-round by returning to the respawn room — there is no pre-round lobby menu.

### Slots

| Slot | Count per player | Source | Constraints |
|---|---|---|---|
| Primary | 1 | Any Normal weapon pickup | Must differ from Secondary |
| Secondary | 1 | Any Normal weapon pickup | Must differ from Primary |
| Special | 0 or 1 | Special pickup in respawn area | **Only one per team is active** |

### Match types

Teams only: 1v1, 2v2, 3v3, 4v4, 5v5. FFA is explicitly out of scope.

## Key design decisions (from 2026-04-23 discussion)

1. **Melee folds into Normal.** A sword is a Normal weapon; a player can equip two melees (one in each Normal slot) if they want — no separate Melee slot.
2. **Loadout changes happen in the respawn room**, not a menu. Players spawn with nothing (or a default?) and physically pick up weapons + special from pedestals.
3. **Specials are claimed first-come first-serve within a team.** Only one team member can hold the team's special at a time.
4. **Specials persist through death.** The holder retains their special across respawns until they *voluntarily* unequip it in the respawn room (placing it back on the pedestal so a teammate can pick it up).
5. **Tab cycles between Normal slots (Primary ↔ Secondary).** Special has its own activation key: `Q`.
6. **Cooldown is per-special**, modifiable by items / in-game rules we add later.
7. **Stretch goal**: dual-melee combo — if both Normal slots hold melee weapons, cycle is disabled and a double-slash attack fires with combined damage.

## Data model changes

### Tool template attributes

Retire the `WeaponSlot = "Primary" / "Secondary" / "Melee"` attribute. Replace with:

- `WeaponCategory` — `"Normal"` or `"Special"`. Drives slot eligibility at pickup time.
- `SpecialId` — string, **Special only**. Stable identifier (e.g. `"Shield"`, `"Beam"`, `"SwarmMissiles"`) used by the Loadout service and the team-uniqueness check.
- Other per-special attributes as needed (cooldown seconds, charge count, etc.) — deferred to the Special implementation phase.

Existing weapons to re-tag:
- `Sword`, `BlasterMk2`, `LaserBlaster`, `AutoRifle`, `Blaster` → `WeaponCategory = "Normal"` (and drop `WeaponSlot`)

### Player loadout state (server)

New `LoadoutService` on the server. For each player:

```luau
type Loadout = {
    primary: string?,   -- Tool template name or nil
    secondary: string?,
    special: string?,   -- SpecialId or nil
}
```

### Team state (server)

New `SpecialClaimService` (or folded into LoadoutService). Per team:

```luau
type TeamSpecials = {
    [specialId: string]: Player?,  -- which player currently holds it, nil = available
}
```

One entry per known Special. Only one non-nil value per specialId per team at any time.

## New systems

### LoadoutService (server)

Responsibilities:
- Track per-player loadout.
- Accept requests from the pickup system: "player X wants to pick up weapon Y".
- Validate the request and apply the change, or reject with a reason:
  - Normal weapon into occupied P1 → swap (drop old into respawn pedestal)
  - Normal weapon duplicate (already in P2 when picked up for P1) → reject with reason "already equipped"
  - Special into full special slot by same player → reject (unequip first)
  - Special into empty special slot for a player on a team that already has that special claimed → reject with reason "team already has this special"
- On player death: retain loadout. Respawn with current loadout contents.
- On player disconnect: release their special claim back to the team pool.
- On `unequipSpecial` request (respawn-zone interaction): clear the special slot and release the claim.

### SpecialPickupService (server-side; could be part of LoadoutService)

- Watches the respawn-zone pedestals (or pedestals have a server script tagged).
- On a player's touch / interact: forward to LoadoutService.
- Renders pedestal state: show special as `available` (glowing pedestal) or `claimed` (dimmed, tag shows teammate name holding it).

### WeaponPickupController (client, reuse existing)

- Current weapon spawner already handles pickup for weapons. Extend to call the new LoadoutService RPC instead of just equipping the tool directly.

### SpecialRuntime (server + client)

- One module per Special (`src/shared/Specials/<SpecialId>.luau`) implementing a common interface:

```luau
export type SpecialModule = {
    specialId: string,
    cooldownSeconds: number,
    onEquip: (player: Player) -> (),
    onUnequip: (player: Player) -> (),
    onActivate: (player: Player, context: ActivationContext) -> (),  -- primary fire
    onSecondaryInput: ((player: Player, input: InputObject) -> ())?, -- e.g. shield expand/contract
    onUpdate: ((dt: number) -> ())?,                                 -- per-frame for sustained effects
}
```

- Server-side logic (damage, physics impulses, etc.) lives in the module's server half.
- Client-side input + visual feedback lives in the client half, mirroring the existing Weapon architecture.

## UI changes

Current Rolodex shows **one** active weapon card at a time, cycles via Tab. For the new design, options:

- **Option A — three cards always visible.** P1, P2, Special stacked or arranged. Active Normal highlighted. Special always shown with cooldown state. Biggest visual change but clearest hero-shooter feel.
- **Option B — keep the single active-Normal card, add a small dedicated Special indicator.** Tab cycles P1↔P2 as today; Special sits beside/below it with cooldown overlay. Minimal disruption to the current Rolodex work.

**Recommendation: Option B for phase 4**, iterate to A later if the information density doesn't feel right in playtest.

New visuals required either way:
- Empty-slot state (before a weapon is picked up)
- Cooldown overlay / ring on the Special indicator
- "Double-slash ready" state when dual-melee is active (stretch)

## Specials

Scope for the first pass:

### Shield
- Activatable shield that blocks incoming damage in a forward cone.
- Can be expanded/contracted in discrete steps while held.
- When expanded, applies a physical impulse force to hostile characters that intersect the shield edge.
- **Inputs:** primary key activates/deactivates; hold-primary or scroll/secondary input adjusts expansion.
- **Cooldown:** on deactivation, cooldown applies before re-activation.

### Beam
- Fires a sustained high-damage beam for N seconds.
- Damage-per-tick model (existing hit rate / damage replication primitives should cover this).
- **Inputs:** tap to fire the full duration (not held).
- **Cooldown:** starts when the beam ends.

### Swarm Missiles
- Fires M missiles that seek the nearest hostile characters.
- Each missile does X damage on hit.
- **Inputs:** tap to launch the full salvo.
- **Cooldown:** fixed seconds.

## Stretch goal — dual-melee combo

If both Normal slots hold weapons with `WeaponCategory = "Normal"` AND both are identified as melee (to be defined — probably by the presence of `meleeDamage` attribute or a new `WeaponSubcategory = "Melee"`):

- Weapon cycling (Tab) is disabled.
- A new combined attack fires on primary-fire that plays a "double slash" animation and applies `meleeDamage_primary + meleeDamage_secondary` in a single swing.
- Other melee properties (reach, hitbox, cooldown) averaged or summed — decide during implementation.

Do not block the main feature on this. Build after specials are stable.

## Phased implementation plan

### Phase 1 — data model
- Introduce `WeaponCategory` attribute on the Tool templates.
- Migrate existing weapons to `WeaponCategory = "Normal"`.
- No behavior change yet; existing gameplay continues to work with the old `WeaponSlot` ignored.
- Drop `WeaponSlot` usage from the codebase (Rolodex sort, etc.) — weapons now sort by pickup order in the player's Backpack instead.

### Phase 2 — server LoadoutService + loadout-aware pickup
- Server state: per-player loadout, per-team special claims.
- RPC surface: `requestEquip`, `requestUnequip`, `queryLoadout`.
- Wire the existing weapon pickup flow through LoadoutService. Enforce the "no duplicate Normal" and "one Special per team" rules.
- Returns the *reason* for rejection so UI can display feedback ("your team already has Shield").

### Phase 3 — respawn zone

Split into 3A / 3B / 3C so the backend logic ships independently of the scene work.

#### Phase 3A — pure server logic (2026-04-23, done)
- Normal 2-slot cap in LoadoutService. Oldest-picked Normal is evicted (destroyed) when a 3rd Normal lands. Per-player pickup-order list tracked; AncestryChanged prunes the list on drop.
- `LoadoutRequestDrop` RemoteEvent at `ReplicatedStorage.Shared.Loadout.Remotes.LoadoutRequestDrop`. Client fires (no args) → server destroys the currently-equipped Tool if it has `WeaponCategory`. Claim release + pickup-order cleanup ride the existing AncestryChanged handlers, so the drop handler is a one-liner.

#### Phase 3B — scene contract (user-placed parts + server services)

**Components the user places in Workspace:**

- BaseParts tagged `RespawnZone` (CollectionService) — define the boundary of each team's respawn area. Usually transparent, non-colliding, sized to cover the respawn room.
  - Attribute `Team: string` — matches `player.Team.Name`. If teams aren't wired yet, leave the zone team-neutral and the service treats it as "anyone's respawn room".
- BaseParts named `RespawnPedestal` — pedestal markers inside a RespawnZone. Pattern mirrors the existing `WeaponSpawner` convention.
  - Attribute `WeaponName: string` — template folder name under `ReplicatedStorage.Shared.Weapon.Templates`.
  - Attribute `Team: string?` — optional; should match the enclosing zone's team. Used so team-scoped specials know which respawn room they belong to.
  - Attribute `SpawnerMesh: string?` — optional pedestal mesh name (reuses the existing SpawnerMesh pool).
  - Attribute `RespawnAfterClaim: boolean?` — default true. If true, the pedestal regenerates its weapon a short delay after pickup (delay = a service-level constant for now). Set to false for pedestals that should only spawn at round start.

The existing one-shot `WeaponSpawner` markers can continue to coexist for any arena-world spawns the user wants to keep, or can be retired once the respawn-zone flow takes over.

**Server services I'll build in 3B (not yet):**

- `RespawnZoneService` (module + init script)
  - `isPlayerInZone(player: Player, team: string?): boolean`
  - `getPlayersInZone(team: string?): { Player }`
  - Signals: `playerEnteredZone(player, team)`, `playerExitedZone(player, team)`
  - Impl: `Touched` / `TouchEnded` on each tagged RespawnZone part, with a per-player presence set. Cheaper than Region3 polling and accurate enough for zone-gated interactions.
- `RespawnPedestalManager` (server script)
  - On server start: scans for `RespawnPedestal` markers, spawns weapons.
  - On pickup: detects claim via the LoadoutService hook (or parallel ChildAdded on the spawned Tool's parent change), starts a respawn timer per pedestal.
  - On respawn timer: re-clones the weapon onto the pedestal — BUT for specials, consults LoadoutService team claims; if the team already holds that special, the pedestal stays empty (matches the design-doc "claimed pedestals render empty" rule).
  - Reuses the existing `Spawner.Meshes` pedestal-mesh pool.

**Interaction surfaces already available for the user to wire into (from 3A):**
- `ReplicatedStorage.Shared.Loadout.Remotes.LoadoutRequestDrop:FireServer()` — client drops the currently-equipped Tool.

#### Phase 3C — drop/swap UX (after 3B scene lands)
- Client-side zone gate: only allow `LoadoutRequestDrop` to fire when the player is inside their team's RespawnZone (validated both client-side for input gating and server-side for trust).
- Pedestal affordances: hover highlight, interact prompt, visual state for "claimed by teammate" (dimmed + teammate tag).
- Per-weapon swap UX: how exactly does the player pick which of their P1/P2 to drop? Candidates TBD once the zone feel is live.

### Phase 4 — HUD update (Option B, see UI section)
- Extend the current Rolodex to include a dedicated Special indicator with cooldown state.
- Show empty-slot placeholders when P1 / P2 / Special is empty.
- Hook into LoadoutService's state events.

### Phase 5 — Shield special
- Server module for damage blocking + impulse.
- Client activation, expand/contract input, visual part.
- Full SpecialRuntime contract validated against this first implementation.

### Phase 6 — Specials polish
- Cooldown integration in the HUD.
- Team "someone picked up your special" feedback.
- Pedestal visual states (available / claimed / cooldown).

### Phase 7 — Beam special
- Reuse the SpecialRuntime interface.
- Tick damage via existing shot-validation primitives.

### Phase 8 — Swarm Missiles special
- Homing projectile system is new; may need its own small module for missile tracking.

### Phase 9 — Stretch: dual-melee combo
- Define what qualifies as a melee (attribute-driven).
- Disable cycle, enable combined attack.
- Combined animation + damage.

## Resolved during design (2026-04-23)

- **Default loadout at first spawn:** empty. Players pick everything up from the respawn-zone pedestals before going into battle.
- **Drop on death:** no drop. Players retain their loadout across deaths and respawns. The only way to remove a weapon or special from a slot is voluntary — the player drops it themselves in the respawn room.
- **Pedestal visuals while claimed:**
  - Special pedestals show empty when claimed. No tooltip for the teammate holding it (simplest first pass; revisit if confusion arises in playtest).
  - Normal weapon pedestals either respawn the weapon model back onto the pedestal or leave a persistent claimable instance. Exact mechanism TBD in phase 3.
- **Special activation key:** `Q`.

## Still open for implementation

- **How "melee" is identified** for the dual-melee stretch (attribute vs tag) — decide in phase 9.
- **Weapon management controls (new):** players need a way to voluntarily drop a weapon or swap P1 ↔ P2 ordering while in the respawn room. No specific interaction chosen yet. Candidates to explore in phase 3:
  - Walk onto a "drop slot" trigger in the respawn zone to eject whatever's in P1 / P2 / Special.
  - A hotkey that drops the currently-active Normal weapon (safe because you have to be in the respawn zone to usefully do it).
  - A simple menu triggered in the respawn zone that shows P1 / P2 / Special and lets you drop / reorder.
  Pick one (or design a blend) when phase 3 starts. This is a first-class concern, not a nice-to-have — players can't build a hero they want without it.
