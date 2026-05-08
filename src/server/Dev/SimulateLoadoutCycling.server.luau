----------------------------------------------------------------------
-- SimulateLoadoutCycling
----------------------------------------------------------------------
-- Server-side dev driver: places 2 Normal weapons in the first
-- player's Backpack (real server-side parenting → real Backpack.
-- ChildAdded → real LoadoutService.onToolAdded → real registerNormal
-- chain), then drives a Tab-cycle equivalent via humanoid:EquipTool
-- a fixed number of times. Reads workspace.LoadoutDiag for the
-- server-side trace and writes a deterministic summary to
-- workspace.LoadoutCycleSimResult.
--
-- Why server-side: MCP execute_luau runs in client/plugin context.
-- Setting `clone.Parent = lp.Backpack` from a client script is a
-- local-only edit that the server never sees, so the loadout flow
-- can't be reproduced from MCP alone. This script runs in the real
-- server VM and exercises the full chain.
--
-- Gated by GameConfig.DEV_SIMULATE_LOADOUT_CYCLING (default off).
-- Enable, sync via Rojo, start playtest, read the result attribute.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SimulateLoadoutCycling")

if not GameConfig.DEV_SIMULATE_LOADOUT_CYCLING then
	return
end

local START_DELAY = 12 -- seconds after first character spawn (clears countdown)
local CYCLE_COUNT = 6
local CYCLE_DELAY = 0.5 -- seconds between equips
local TOOL_NAMES = { "Rifle", "Pistol" }
-- Third Normal template used by the eviction-order phase. Picked up
-- AFTER cycling to verify the pickup-order invariant: the cap-overflow
-- eviction must target the FIRST-placed tool (TOOL_NAMES[1] = "Rifle").
--
-- This phase was added during the NIM-2 audit (2026-05-06) to test
-- whether the WeaponRolodex client-side AncestryChanged race
-- (`feedback_ancestrychanged_race.md`) also fires on the server. It
-- doesn't — server-side AncestryChanged for Humanoid:EquipTool emits a
-- single event with the settled parent, with no nil intermediate. The
-- probe is retained as a regression tripwire in case engine semantics
-- ever change: a future engine update that introduced a nil-parent
-- intermediate would corrupt the pickup-order list to [2nd, 1st] and
-- the 2nd-placed ("Pistol") would be evicted instead of the oldest.
local EVICTION_PROBE_TOOL = "LaserPistol"

local function setResult(line: string)
	local cur = Workspace:GetAttribute("LoadoutCycleSimResult") or ""
	if typeof(cur) ~= "string" then cur = "" end
	if #cur > 3000 then cur = cur:sub(-2000) end
	Workspace:SetAttribute("LoadoutCycleSimResult", cur .. line .. "\n")
end

local started = false

local function run(player: Player)
	if started then return end
	started = true

	task.wait(START_DELAY)
	setResult(string.format("=== sim start for %s ===", player.Name))

	-- Reset the LoadoutService diag attribute so the trace below is fresh.
	Workspace:SetAttribute("LoadoutDiag", "")

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not backpack or not humanoid then
		setResult("ABORT: no backpack or humanoid")
		return
	end

	-- Clear existing tools
	for _, t in backpack:GetChildren() do if t:IsA("Tool") then t:Destroy() end end
	for _, t in character:GetChildren() do if t:IsA("Tool") then t:Destroy() end end
	task.wait(0.3)

	-- Place 2 weapons (server-side parent assignment fires real ChildAdded)
	local templates = ReplicatedStorage.Shared.Weapon.Templates
	local placed: { Tool } = {}
	for _, name in TOOL_NAMES do
		local tmpl = templates:FindFirstChild(name)
		if not tmpl then
			setResult(string.format("ABORT: template %s missing", name))
			return
		end
		local clone = tmpl:Clone()
		clone.Parent = backpack
		table.insert(placed, clone)
	end
	task.wait(1.0) -- let LoadoutService's task.deferred onToolAdded settle

	setResult(string.format("placed %d tools | backpack=%d char=%d",
		#placed, #backpack:GetChildren(),
		character and #character:GetChildren() or -1))

	-- Equip the first one to start
	humanoid:EquipTool(placed[1])
	task.wait(CYCLE_DELAY)

	-- Cycle: alternate between tools via EquipTool. This is what
	-- WeaponRolodex.cycleNext does after a Tab press.
	for i = 1, CYCLE_COUNT do
		local equipped = character:FindFirstChildOfClass("Tool")
		local nextTool: Tool? = nil
		for _, t in placed do
			if t.Parent and t ~= equipped then
				nextTool = t
				break
			end
		end
		if not nextTool then
			setResult(string.format("Cycle %d ABORT: no next tool — placed[1]=%s placed[2]=%s",
				i,
				placed[1].Parent and placed[1].Parent.Name or "DESTROYED",
				placed[2].Parent and placed[2].Parent.Name or "DESTROYED"))
			return
		end
		humanoid:EquipTool(nextTool)
		task.wait(CYCLE_DELAY)

		local survivors = 0
		for _, t in placed do if t.Parent then survivors += 1 end end
		setResult(string.format("Cycle %d → %s | survivors=%d", i, nextTool.Name, survivors))
		if survivors < 2 then
			setResult(string.format("  ⚠ BUG: lost a tool. placed[1].Parent=%s placed[2].Parent=%s",
				placed[1].Parent and placed[1].Parent.Name or "DESTROYED",
				placed[2].Parent and placed[2].Parent.Name or "DESTROYED"))
			return
		end
	end

	setResult(string.format("=== sim done: all %d tools survived %d cycles ===", #placed, CYCLE_COUNT))

	-- ------------------------------------------------------------------
	-- Eviction-order probe — see EVICTION_PROBE_TOOL comment. After
	-- cycling, pick up a 3rd Normal (cap is 2) and assert
	-- LoadoutService evicts the FIRST-placed tool (oldest). A
	-- regression here would surface an engine change that introduced a
	-- nil-parent intermediate to server-side AncestryChanged.
	-- ------------------------------------------------------------------
	setResult("=== eviction-order probe ===")

	local probeTpl = templates:FindFirstChild(EVICTION_PROBE_TOOL)
	if not probeTpl then
		setResult(string.format("ABORT probe: template %s missing", EVICTION_PROBE_TOOL))
		return
	end

	-- Unequip first so the probe placement doesn't touch the equipped slot.
	humanoid:UnequipTools()
	task.wait(0.3)

	local probe = probeTpl:Clone()
	probe.Parent = backpack
	task.wait(1.0) -- let registerNormal's task.defer chain settle

	local oldest = placed[1]
	local secondPlaced = placed[2]
	local oldestAlive = oldest.Parent ~= nil
	local secondAlive = secondPlaced.Parent ~= nil
	local probeAlive = probe.Parent ~= nil

	if probeAlive and (not oldestAlive) and secondAlive then
		setResult(string.format("OK: pickup-order preserved — evicted %s (oldest), %s + %s alive",
			TOOL_NAMES[1], TOOL_NAMES[2], EVICTION_PROBE_TOOL))
	elseif probeAlive and oldestAlive and (not secondAlive) then
		setResult(string.format("⚠ BUG: pickup-order corrupted — evicted %s (2nd-placed); should have evicted %s (oldest)",
			TOOL_NAMES[2], TOOL_NAMES[1]))
	else
		setResult(string.format("INDETERMINATE: oldest=%s second=%s probe=%s",
			oldestAlive and "alive" or "DESTROYED",
			secondAlive and "alive" or "DESTROYED",
			probeAlive and "alive" or "DESTROYED"))
	end
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(run, player)
		return
	end
	player.CharacterAdded:Once(function()
		task.spawn(run, player)
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end

log:info("Initialized — armed for first character spawn")
