---
type: system
description: Tutorial system — teaches the core Brain Fighter loop (shoot blocks → buffer word → memorize → cast spell) through guided in-world steps
status: planning
updated: 2026-07-15
---

# Tutorial System

## Goal

Guide a first-time player through the full Brain Fighter loop without UI overload:

1. Equip the Spelling Staff
2. Shoot a LetterBlock
3. Collect enough letters to spell a word
4. Memorize (validate + convert to energy)
5. Cast a spell at the dummy boss
6. See the boss take damage → tutorial complete

## Architecture Overview

```
TutorialService (server)        — owns step state, DataStore flag, RemoteEvents
                                  Listens to BlockShoot.blockConsumed,
                                  Boss Humanoid.HealthChanged, and client claims.
TutorialController (client)     — listens for TutorialStepChanged events,
                                  drives the overlay (tooltip + arrow + dim).
TutorialOverlayBuilder (shared) — Builder + Config: constructs the overlay GUI,
                                  resolves highlight targets, animates show/hide.
TutorialOverlayConfig (shared)  — visual constants (colors, easing, tooltip sizes).
TutorialConfig (shared)         — ordered step table — id, title, hint, completion
                                  signal name, highlight target.
TutorialConstants (shared)      — IDs, DataStore key prefix, magic numbers.
```

**Step state is server-authoritative.** The client never decides which step is current — it only sends "event occurred" claims (`memorize_success`, `cast_success`) which the server consumes as inputs to the step machine. Block consumption and boss damage are detected server-side without client involvement.

## Design Decisions

| Question | Decision | Rationale |
|---|---|---|
| Scripted vs freeform | **Scripted linear sequence**, 6 steps. | Educational target — first-time players need a predictable path. Freeform hint overlays risk dead-ends and timing failures. |
| Gating | **Soft-guide** (highlights + text). No locked arena door. | The natural gates already in the loop (Memorize disabled on empty buffer, fizzle on invalid word, can't cast without energy) are enough. Hard gates would frustrate kids. |
| Skip option | **DataStore-backed `TutorialCompleted` boolean** + persistent in-overlay Skip button. | Returning players bypass automatically; first-time players can opt out at any step. |
| Failure handling | **Silent retry.** Invalid memorize / no-target cast / mis-color spell don't fail the tutorial — hint stays visible, player retries. | Punishing mistakes during a tutorial is a anti-pattern. The Skip button is the escape hatch. |
| Locale / copy | All text lives in `TutorialConfig.STEPS[i].hintText`. | Single translation surface; designers can edit copy without touching code. |
| Tutorial dummy boss | **Reuse the live [[systems/Boss]] rig** (no separate dummy variant). Advance on first damage, not death. | Simpler; avoids forking the boss. The tutorial completes the moment any spell lands a damage event on the boss, well before the boss could die. (Originally planned against BossAdapter, deleted in commit `6610291`; retarget to the Boss `Humanoid`/health signal.) |

## Systems the Tutorial Touches

| System | Interaction | Modification needed? |
|---|---|---|
| LetterBlaster | None — tutorial just guides where to point. | No |
| BlockShoot (shared) | Add `blockConsumed: RBXScriptSignal` exposed from the shared module; fired by BlockShootService after successful destroy. | **Yes** — small addition |
| WordBuffer | Tutorial counts ConsumeBlock events server-side (≥3 → advance from `fill_buffer`); doesn't need WordBuffer state directly since WordBuffer lives on the client. | No |
| MemorizeAction | Client fires `memorize_success` claim after `tryMemorize` returns `ok=true`. Server trusts the claim (no independent validation in MVP). | No (claim from `GameplayHudGui` call site) |
| CastAction | Client fires `cast_success` claim after `tapReservoir`/`castSpecific` returns `ok=true`. | No (claim from `SpellMenuGui` call site) |
| SpellExecutor | Untouched — damage happens via existing path. | No |
| [[systems/Boss]] | TutorialService connects to the boss health-changed signal to detect the first-damage event. | No |
| HUD (existing builders) | Builders already expose their root `gui` Frame and are registered in `_G.PlayerHud.*`. TutorialController reads `_G.PlayerHud.MemorizeButton.gui` etc. to position tooltips. | No |

## TutorialConfig — Step Table

`src/shared/Tutorial/TutorialConfig.luau`:

```lua
--!strict
export type HighlightKind = "ui" | "world" | "none"
export type HighlightTarget = {
    kind: HighlightKind,
    id: string, -- resolved by TutorialController (see Resolution table)
}

export type StepDef = {
    id: string,
    title: string,
    hintText: string,
    completionSignal: string, -- canonical event name TutorialService waits for
    highlightTarget: HighlightTarget,
    showContinueButton: boolean, -- shows an explicit "Continue" button when true
}

local TutorialConfig = {}

TutorialConfig.STEPS = {
    {
        id = "welcome",
        title = "Welcome to Brain Fighter",
        hintText = "You're a wizard who casts spells by spelling words. Tap Continue to begin.",
        completionSignal = "welcome_dismissed",
        highlightTarget = { kind = "none", id = "" },
        showContinueButton = true,
    },
    {
        id = "shoot_block",
        title = "Shoot a Letter",
        hintText = "Aim at any glowing block and tap to fire. The letter lands in your buffer.",
        completionSignal = "block_consumed",
        highlightTarget = { kind = "world", id = "nearest_letter_block" },
        showContinueButton = false,
    },
    {
        id = "fill_buffer",
        title = "Collect a Few More",
        hintText = "Shoot two more blocks. You'll need at least three letters to spell something useful.",
        completionSignal = "three_blocks_consumed",
        highlightTarget = { kind = "ui", id = "BufferDisplay" },
        showContinueButton = false,
    },
    {
        id = "memorize_word",
        title = "Spell a Word",
        hintText = "Drag the tiles to spell a real word, then tap Memorize. Your letters become spell energy.",
        completionSignal = "memorize_success",
        highlightTarget = { kind = "ui", id = "MemorizeButton" },
        showContinueButton = false,
    },
    {
        id = "cast_spell",
        title = "Cast a Spell",
        hintText = "Tap any glowing spell on the right to fire it at the boss.",
        completionSignal = "boss_damaged",
        highlightTarget = { kind = "ui", id = "SpellMenu" },
        showContinueButton = false,
    },
    {
        id = "victory",
        title = "You're a Wizard",
        hintText = "That's the whole loop. Keep blasting blocks, spell bigger words, and bring the boss down.",
        completionSignal = "victory_dismissed",
        highlightTarget = { kind = "none", id = "" },
        showContinueButton = true,
    },
}

TutorialConfig.HIGHLIGHT_RESOLUTION = {
    -- UI ids: looked up via _G.PlayerHud.<id>.gui
    BufferDisplay = "_G.PlayerHud.BufferDisplay.gui",
    MemorizeButton = "_G.PlayerHud.MemorizeButton.gui",
    SpellMenu = "_G.PlayerHud.SpellMenu.gui",
    -- World ids: documented for TutorialController.resolveWorldTarget
    nearest_letter_block = "CollectionService:GetTagged(LetterBlocks.TAG) → nearest to character",
    boss = "workspace.Boss.PrimaryPart",
}

return TutorialConfig
```

Six steps total. The two `_dismissed` steps (`welcome`, `victory`) use an explicit Continue button. The four gameplay steps complete on real-world events.

## TutorialService — Server State Machine

`src/server/Tutorial/TutorialService.server.luau`:

**States** (one per player):

```
not_loaded → step:welcome → step:shoot_block → step:fill_buffer
           → step:memorize_word → step:cast_spell → step:victory → complete
```

Plus a meta-state: `skipped` (jumps directly to `complete`, sets DataStore flag).

**Per-player session state:**

```lua
type Session = {
    player: Player,
    stepIndex: number,           -- 1..#TutorialConfig.STEPS
    blocksConsumed: number,      -- counter for fill_buffer transition
    bossHealthAtStart: number,   -- captured when cast_spell step begins
    connections: { RBXScriptConnection }, -- per-session cleanup
    completed: boolean,
}
```

**RemoteEvents** (under `ReplicatedStorage.Shared.Tutorial.Remotes`, defined via a `Remotes.model.json`):

| Name | Direction | Payload | Purpose |
|---|---|---|---|
| `TutorialStepChanged` | Server → Client | `{ stepId: string, hintText: string, title: string, highlightTarget: {kind, id}, showContinueButton: boolean, isFinal: boolean }` | Server pushes the next step's render data. Also fires on initial load and on `complete` (with `isFinal=true` to teardown overlay). |
| `TutorialClientEvent` | Client → Server | `{ event: string }` | Client emits claims: `welcome_dismissed`, `memorize_success`, `cast_success`, `victory_dismissed`. |
| `TutorialSkipRequested` | Client → Server | `()` | Skip button. Server flips DataStore + transitions to `complete`. |

**Server-side native signal hooks** (no client claim required):

- `BlockShoot.blockConsumed:Connect(function(player, block) ... end)` — increments `blocksConsumed` for that player's session. Drives `shoot_block` → `fill_buffer` (after 1 block) and `fill_buffer` → `memorize_word` (after 3).
- `boss.Humanoid:GetPropertyChangedSignal("Health")` — when `step:cast_spell` is active and health drops below `bossHealthAtStart`, transition to `step:victory`. (Subscribed when the step begins, disconnected when it ends.)

**Player lifecycle:**

```lua
Players.PlayerAdded:Connect(function(player)
    local completed = readTutorialFlag(player) -- DataStore GetAsync
    if completed then
        return -- no tutorial; player has played before
    end
    startSession(player)
end)

Players.PlayerRemoving:Connect(function(player)
    teardownSession(player) -- disconnect all per-session connections
end)
```

**Transition rules:**

- Each step's `completionSignal` is matched against either a native server event (block_consumed, three_blocks_consumed, boss_damaged) or a client claim (welcome_dismissed, memorize_success, victory_dismissed).
- On match → increment `stepIndex`, fire `TutorialStepChanged` with new step's data, set up any step-specific hooks (e.g., when entering `cast_spell`, capture boss HP and connect HealthChanged).
- On reaching `complete` → `SetAsync(TutorialCompleted_<UserId>, true)`, fire `TutorialStepChanged` with `isFinal = true`, teardown connections.

**Idempotency:** Client claims that don't match the current step are logged and dropped. Prevents replays / mis-clicks from advancing prematurely.

**Cleanup:** `TutorialService:disable(player)` disconnects per-player connections without clearing the DataStore flag. `TutorialService:destroy()` tears down all sessions plus the module-level `Players.PlayerAdded` connection.

## TutorialController + TutorialOverlayBuilder — Client

### Overlay structure

A single full-screen ScreenGui at `DisplayOrder = HudConstants.OVERLAY_DISPLAY_ORDER` (20, already > HUD's 10). This is **its own ScreenGui**, NOT registered into `HudLayoutManager` regions, because:

- Tutorial needs a dim layer covering everything (including HUD).
- Region-based layout doesn't fit screen-spanning overlays.
- HudConstants already reserves `OVERLAY_DISPLAY_ORDER = 20` for exactly this use.

### Layers (z-order, bottom to top)

1. **Dim layer** — full-screen Frame, `BackgroundColor3 = #000000`, `BackgroundTransparency = 0.55` (config). Doesn't punch a hole; instead the highlighted target gets a glowing border outline drawn on top.
2. **Highlight outline** — for `kind="ui"`: a Frame matching the target's `AbsolutePosition`/`AbsoluteSize` with a `UIStroke` (4px, accent color, `Transparency = 0` tween-pulsed). Repositions via `RunService.RenderStepped` while visible (cheap — one frame, recomputed each step).
3. **Tooltip panel** — `TutorialOverlayConfig.TOOLTIP_WIDTH = 320`, dark BG, contains:
   - Title (`TextLabel`, large)
   - HintText (`TextLabel`, wrapped, medium)
   - "Continue" `TextButton` (visible iff `showContinueButton`)
   - Step indicator (`"Step 3 of 6"`, small)
4. **Arrow** — a triangle ImageLabel pointing from the tooltip toward the highlight target. Positioned by `TutorialOverlayBuilder._placeArrow(tooltipFrame, targetFrame)` using the vector between centers; rotated to face the target.
5. **Skip button** — persistent top-right, separate from the per-step tooltip. Fires `TutorialSkipRequested`.

### Builder + Config + LayoutManager pattern fit

Following the same shape as `MemorizeButtonBuilder` / `SpellMenuBuilder`:

```lua
-- src/shared/Hud/TutorialOverlayBuilder.luau
export type Handle = {
    gui: ScreenGui,
    skipRequested: RBXScriptSignal,
    continueRequested: RBXScriptSignal,
    showStep: (self: Handle, step: StepDef, resolvedTarget: GuiObject? | BasePart?) -> (),
    hide: (self: Handle) -> (),
    disable: (self: Handle) -> (), -- reversible: hide overlay, keep GUI parented
    destroy: (self: Handle) -> (), -- permanent: disconnect, destroy GUI
}

function TutorialOverlayBuilder.build(): Handle
```

- `TutorialOverlayConfig.luau` holds: `DIM_TRANSPARENCY`, `TOOLTIP_WIDTH`, `TOOLTIP_HEIGHT_MAX`, `TOOLTIP_BG`, `OUTLINE_COLOR`, `OUTLINE_THICKNESS`, `ARROW_ASSET_ID`, `PULSE_TWEEN_INFO`, `FADE_TWEEN_INFO`, fonts, text sizes.
- Builder constructs all GUI elements once. `showStep` repositions/repopulates them rather than re-creating. Cheap step transitions.

### TutorialController

`src/client/UI/TutorialController.client.luau`:

```lua
local overlay = TutorialOverlayBuilder.build()

local function resolveTarget(target: HighlightTarget): GuiObject? | BasePart?
    if target.kind == "none" then return nil end
    if target.kind == "ui" then
        local hud = _G.PlayerHud
        if not hud then return nil end -- HUD not initialized yet; retry next step
        local handle = hud[target.id]
        return handle and handle.gui or nil
    end
    if target.kind == "world" then
        if target.id == "nearest_letter_block" then
            return findNearestTaggedBlock()
        elseif target.id == "boss" then
            local boss = workspace:FindFirstChild("Boss")
            return boss and boss.PrimaryPart or nil
        end
    end
    return nil
end

Remotes.TutorialStepChanged.OnClientEvent:Connect(function(payload)
    if payload.isFinal then
        overlay:hide()
        return
    end
    local target = resolveTarget(payload.highlightTarget)
    overlay:showStep(payload, target)
end)

overlay.skipRequested:Connect(function()
    Remotes.TutorialSkipRequested:FireServer()
end)

overlay.continueRequested:Connect(function()
    Remotes.TutorialClientEvent:FireServer({ event = currentStep.id .. "_dismissed" })
end)
```

### Wiring client claims into existing call sites

Two small touch-ups to existing client HUD scripts:

- `src/client/UI/GameplayHudGui.client.luau` — after `MemorizeAction.tryMemorize` returns `ok=true`, fire `Remotes.TutorialClientEvent:FireServer({ event = "memorize_success" })`.
- `src/client/UI/SpellMenuGui.client.luau` — after `CastAction.tapReservoir` returns `ok=true`, fire `Remotes.TutorialClientEvent:FireServer({ event = "cast_success" })`.

Both fires are unconditional — TutorialService drops claims that don't match the current step, so this works whether or not the tutorial is active for that player.

### Cleanup contract

- `overlay:disable()` — hide the overlay (set ScreenGui.Enabled = false), keep state. Reversible.
- `overlay:destroy()` — disconnect all `RunService.RenderStepped`, tween cancels, destroy ScreenGui, destroy BindableEvents. Called on player leaving or `complete` step.

## Skip-Tutorial Flow

**DataStore:**

- DataStore name: `"BrainFighterTutorial"` (constant in `TutorialConstants.luau`).
- Key per player: `"completed_" .. tostring(player.UserId)`.
- Value: `true` (presence-based; absent / false means "show tutorial").

**On Players.PlayerAdded (server):**

```lua
local ok, completed = pcall(function()
    return tutorialStore:GetAsync(keyFor(player)) == true
end)
if not ok then
    -- DataStore unavailable; default to NOT showing the tutorial to avoid
    -- forcing returning players through it again. Log + move on.
    log:warn("DataStore unavailable for " .. player.Name .. "; skipping tutorial")
    return
end
if completed then
    return -- player has played before
end
startSession(player)
```

**Persisting completion:**

- On reaching `step:victory` → user dismisses → `SetAsync(true)` + transition to `complete`.
- On `TutorialSkipRequested` → `SetAsync(true)` + transition to `complete` immediately.
- Wrap `SetAsync` in `pcall`; on failure, log and continue (don't crash the session).

**Why RemoteEvent (not RemoteFunction):** No synchronous return value needed. The server's response to a skip is to push a new `TutorialStepChanged` event with `isFinal=true`, which the client already handles. RemoteEvent keeps the channel unidirectional + symmetric with `TutorialClientEvent`.

## File Layout

```
src/
  server/
    Tutorial/
      TutorialService.server.luau   — step machine, DataStore, RemoteEvent wires
      Remotes.model.json            — Folder + three RemoteEvents
  shared/
    Tutorial/
      TutorialConfig.luau           — STEPS table, types
      TutorialConstants.luau        — DataStore name, key prefix, magic numbers
    Hud/
      TutorialOverlayBuilder.luau   — overlay GUI construction
      TutorialOverlayConfig.luau    — colors, sizes, tweens
    BlockShoot/
      init.luau                     — (modify) export blockConsumed BindableEvent
  client/
    UI/
      TutorialController.client.luau — overlay driver, claim emitter, target resolver
      GameplayHudGui.client.luau    — (modify) fire memorize_success claim
      SpellMenuGui.client.luau      — (modify) fire cast_success claim
```

## Updated Task List

Ordered for implementation. Tasks within a phase are roughly parallelizable; phases are sequential.

### Phase A — Foundations (no behavior change yet)

- [ ] `src/shared/Tutorial/TutorialConstants.luau` — DataStore name `"BrainFighterTutorial"`, key prefix, idle-timeout seconds, completion-flag value.
- [ ] `src/shared/Tutorial/TutorialConfig.luau` — STEPS table (6 entries) + `HighlightTarget`/`StepDef` types per spec above.
- [ ] `src/server/Tutorial/Remotes.model.json` — Folder containing `TutorialStepChanged`, `TutorialClientEvent`, `TutorialSkipRequested` (all `RemoteEvent`).
- [ ] Modify `src/shared/BlockShoot/init.luau` — expose `BlockShoot.blockConsumed` (BindableEvent.Event). Modify `src/server/BlockShoot/BlockShootService.server.luau` to fire it after successful `block:Destroy()` with `(player, block)` payload.

### Phase B — Overlay UI

- [ ] `src/shared/Hud/TutorialOverlayConfig.luau` — visual constants (dim transparency, tooltip width, outline color, tween infos, fonts).
- [ ] `src/shared/Hud/TutorialOverlayBuilder.luau` — `build()`/`Handle` per spec: dim layer, outline tracker, tooltip panel, arrow, skip button, continue button. `showStep`, `hide`, `disable`, `destroy`. Type annotations on all signatures.

### Phase C — Server state machine

- [ ] `src/server/Tutorial/TutorialService.server.luau` — per-player Session table, DataStore GetAsync on PlayerAdded, step transitions driven by:
  - `BlockShoot.blockConsumed` (server-native) for `shoot_block` + `fill_buffer`
  - `boss.Humanoid:GetPropertyChangedSignal("Health")` (subscribed when entering `cast_spell`) for `cast_spell` → `victory`
  - `TutorialClientEvent` claims (`welcome_dismissed`, `memorize_success`, `cast_success`, `victory_dismissed`)
  - `TutorialSkipRequested` jumps to `complete`
  - On `complete`: `pcall(SetAsync)` of completion flag; fire `TutorialStepChanged` with `isFinal=true`; teardown.
  - `:disable(player)` + `:destroy()` methods.

### Phase D — Client wiring

- [ ] `src/client/UI/TutorialController.client.luau` — listens to `TutorialStepChanged`, resolves highlight targets (via `_G.PlayerHud.*` + workspace lookups), drives the overlay. Emits skip + continue claims. `:disable()`/`:destroy()`.
- [ ] Modify `src/client/UI/GameplayHudGui.client.luau` — on `MemorizeAction.tryMemorize` ok, `FireServer({event="memorize_success"})`.
- [ ] Modify `src/client/UI/SpellMenuGui.client.luau` — on `CastAction.tapReservoir` ok, `FireServer({event="cast_success"})`.

### Phase E — Validation

- [ ] MCP playtest: fresh player join → full 6-step path → confirm DataStore flag set → leave + rejoin → tutorial skipped.
- [ ] MCP playtest: fresh player join → tap Skip at step 2 → confirm flag set + overlay torn down → rejoin → skipped.
- [ ] MCP playtest: confirm idempotency — fire `memorize_success` claim while on `shoot_block`; server logs + drops.
- [ ] Accessibility audit: color-blind safe outline color (avoid pure green/red); confirm hint text is screen-reader friendly (no glyph-only icons).
- [ ] Wiki ingest: update `wiki/index.md` Tutorial entry status `planning` → `built`, append `wiki/log.md` entry, bump `updated:` on this page.

## Related Pages

- [[systems/LetterBlaster]]
- [[systems/BlockShoot]]
- [[systems/WordBuffer]]
- [[systems/MindFullManager]]
- [[systems/MemorizeAction]]
- [[systems/CastAction]]
- [[systems/SpellExecutor]]
- [[systems/Boss]]
- [[systems/HUD]]
- [[concepts/BuilderConfigLayout]]
- [[concepts/SingleOwnership]]
- [[design/gameplay-loop]]
- [[design/build-plan]]
