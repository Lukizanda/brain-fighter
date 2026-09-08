--!strict

----------------------------------------------------------------------
-- HudGate tests
----------------------------------------------------------------------
-- Self-contained — exposes `M.run()` which throws on any assertion
-- failure and prints `[Hud.__tests] all scenarios passed` on success.
--
-- **Client only.** `HudGate` resolves `Players.LocalPlayer` at require
-- time, so requiring this module on the server errors before the first
-- scenario runs.
--
-- These scenarios cover one thing: the ownership rule recorded in
-- `wiki/concepts/HudGate.md` § "Owners never write the gated property".
-- The gate learns owner intent by watching the property it also writes,
-- and Roblox does not fire a changed signal for a write that does not
-- change the value. So an owner that writes the gated property while the
-- gate is closed loses its `true` -> `false` transition, the gate keeps
-- `ownerWants = true`, and the next arena entry reveals an element whose
-- owner believes it is hidden. That is F4 — the death overlay appearing
-- to a living player on arena entry.
--
-- `ownerWants` is a local inside the gate, so every assertion reads it
-- through the only observable it has: open the gate and look at the
-- gated property. `Enabled == false` after entering the arena is
-- `ownerWants == false`.
--
-- Signals here are deferred, so each step settles before it is asserted.
--
-- Usage (on a client VM):
--   require(ReplicatedStorage.Shared.Hud.__tests).run()
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)

local M = {}

local player = Players.LocalPlayer

-- Deferred property-changed signals land at the end of the frame, and
-- the gate's re-suppression is itself a write that fires another. Two
-- frames is enough for a write to be observed and answered.
local function settle()
	task.wait()
	task.wait()
end

local function setState(state: string)
	player:SetAttribute(Arena.STATE_ATTRIBUTE, state)
end

-- A ScreenGui parented to PlayerGui, like the six scripts that own one.
-- Named so a leaked instance is obvious in the explorer.
local function makeGui(enabled: boolean): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HudGateTestGui"
	gui.ResetOnSpawn = false
	gui.Enabled = enabled
	gui.Parent = player:WaitForChild("PlayerGui")

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Visible = false
	overlay.Parent = gui

	return gui, overlay
end

function M.run(): boolean
	local savedState = player:GetAttribute(Arena.STATE_ATTRIBUTE)

	-- 1. The F4 reproduction. A non-compliant owner writes the gated
	--    property itself: `true` on death, `false` on respawn, both while
	--    standing in the lobby. The `false` write is a no-op on an
	--    already-false property, so no signal fires and the gate never
	--    hears the retraction.
	--
	--    This asserts the *broken* outcome on purpose. It is the reason
	--    the rule exists, and there is no gate-side repair: the write the
	--    gate would need to see is a write Roblox never reports. If a
	--    future change makes this assertion fail because the gate learned
	--    to see it, delete the scenario — do not weaken it.
	do
		setState(Arena.PlayerState.InLobby)
		local gui = makeGui(false)
		HudGate.bindScreenGui(gui, HudGate.Policy.ArenaOnly)
		settle()

		gui.Enabled = true -- owner "show" in the lobby
		settle()
		assert(gui.Enabled == false, "F4 repro: the closed gate must re-suppress an owner's true write")

		gui.Enabled = false -- owner "hide" — already false, fires nothing
		settle()

		setState(Arena.PlayerState.InArena)
		settle()
		assert(
			gui.Enabled == true,
			"F4 repro: an owner that writes the gated property is expected to leak on arena entry; "
				.. "if this now passes as hidden, the gate changed and this scenario is obsolete"
		)

		gui:Destroy()
	end

	-- 2. The shipped DeathScreenGui shape. The owner never touches
	--    `Enabled` — it leaves the ScreenGui enabled and toggles a child
	--    overlay's `Visible`, the split GameStateGui and ScoreboardGui
	--    already use. Dying in the lobby and respawning must leave nothing
	--    on screen when the arena opens the gate.
	do
		setState(Arena.PlayerState.InLobby)
		local gui, overlay = makeGui(true)
		HudGate.bindScreenGui(gui, HudGate.Policy.ArenaOnly)
		settle()
		assert(gui.Enabled == false, "compliant owner: the gate suppresses the ScreenGui in the lobby")

		overlay.Visible = true -- died in the lobby
		settle()
		assert(gui.Enabled == false, "compliant owner: an overlay toggle must not open the gate")

		overlay.Visible = false -- respawned
		settle()

		setState(Arena.PlayerState.InArena)
		settle()
		assert(gui.Enabled == true, "compliant owner: the gate restores the ScreenGui in the arena")
		assert(overlay.Visible == false, "compliant owner: no overlay is drawn to a living player on arena entry")

		-- ...and the overlay still works once the player actually dies there.
		overlay.Visible = true
		settle()
		assert(gui.Enabled and overlay.Visible, "compliant owner: dying in the arena must show the overlay")

		gui:Destroy()
	end

	-- 3. The same sequence as scenario 1, with the owner obeying the rule:
	--    it drives the child and leaves the gated property alone. The gate
	--    ends with `ownerWants` still false, read through the property
	--    after the gate opens.
	do
		setState(Arena.PlayerState.InLobby)
		local gui, overlay = makeGui(false)
		HudGate.bindScreenGui(gui, HudGate.Policy.ArenaOnly)
		settle()

		overlay.Visible = true
		settle()
		overlay.Visible = false
		settle()

		setState(Arena.PlayerState.InArena)
		settle()
		assert(gui.Enabled == false, "ownerWants must end false: the owner never asked for the ScreenGui")

		gui:Destroy()
	end

	-- 4. `Always` is never suppressed, and `nil` state degrades to visible
	--    rather than hidden (§ "Nil means visible").
	do
		setState(Arena.PlayerState.InLobby)
		local always = makeGui(true)
		HudGate.bindScreenGui(always, HudGate.Policy.Always)
		local arenaOnly = makeGui(true)
		HudGate.bindScreenGui(arenaOnly, HudGate.Policy.ArenaOnly)
		settle()
		assert(always.Enabled == true, "Always is visible in the lobby")
		assert(arenaOnly.Enabled == false, "ArenaOnly is hidden in the lobby")

		player:SetAttribute(Arena.STATE_ATTRIBUTE, nil)
		settle()
		assert(arenaOnly.Enabled == true, "nil state degrades to visible, never hidden")

		always:Destroy()
		arenaOnly:Destroy()
	end

	player:SetAttribute(Arena.STATE_ATTRIBUTE, savedState)
	settle()

	print("[Hud.__tests] all scenarios passed")
	return true
end

return M
