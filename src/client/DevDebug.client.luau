--!strict
----------------------------------------------------------------------
-- DevDebug — keyboard shortcuts for feature playtesting.
-- Remove before shipping.
--
--   [  append next letter of TEST_WORD cycling (default: "CATALOG")
--   ]  trigger memorize action
--   \  clear the buffer
--   1  fill all reservoirs to T1 threshold (5)
--   2  fill all reservoirs to T2 threshold (10)
--   3  fill all reservoirs to T3 threshold (20)
--   4  fill all reservoirs to T4 threshold (40)
--   M  toggle mobile-input override (forces InputCategorizer to "Touch"
--       so touch-only HUD widgets like the dash button appear on desktop)
--   ;  toggle boss phase label visibility
--
-- Automation hook (no keyboard):
--   workspace:SetAttribute("DevFillMana", <1-4>)  — same as pressing 1-4
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local PlayerSession     = require(script.Parent.PlayerSession)
local EconomyReport     = require(script.Parent.EconomyReport)
local Dictionary        = require(ReplicatedStorage.Shared.Dictionary)
local InputCategorizer  = require(ReplicatedStorage.Shared.Core.InputCategorizer)

local log = Logger.new("DevDebug")

local TEST_WORD = "CATALOG"
local TEST_COLORS = { "red", "green", "blue" }
local TIER_ENERGY = { 5, 10, 20, 40 }
local letterIdx = 1

local session = PlayerSession.get()

local function fillReservoirsToAmount(amount: number)
	for _, color in TEST_COLORS do
		local current = session.energyReservoirs:get(color)
		if current > amount then
			session.energyReservoirs:drain(color, current - amount)
		elseif current < amount then
			session.energyReservoirs:add(color, amount - current)
		end
	end
end

----------------------------------------------------------------------
-- Automation hook
----------------------------------------------------------------------
-- The 1-4 mana binds below are unreachable from tool-driven playtests:
-- those keys are permanently bound to CoreGui hotbar actions and Studio's
-- VirtualInput refuses to deliver them (it still refuses after the
-- Backpack CoreGui is disabled). Driving the reservoirs directly from an
-- injected script doesn't work either — injected code gets its own module
-- instances, so it would fill a different PlayerSession than the HUD reads.
--
-- An attribute crosses both boundaries, because attributes are DataModel
-- state rather than per-VM Luau state. Same pattern the test autorunner
-- already uses with workspace:SetAttribute("RunTests", ...).
--
-- Self-clearing on purpose: RunTests has to be nil'd by hand and silently
-- re-fires on the next playtest if you forget. This one can't accumulate
-- that way.
local DEV_FILL_MANA_ATTR = "DevFillMana"

local function onDevFillMana()
	local tier = workspace:GetAttribute(DEV_FILL_MANA_ATTR)
	if tier == nil then return end

	if typeof(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > #TIER_ENERGY then
		log:warn(string.format("%s = %s ignored — want an integer 1-%d",
			DEV_FILL_MANA_ATTR, tostring(tier), #TIER_ENERGY))
	else
		fillReservoirsToAmount(TIER_ENERGY[tier])
		log:info(string.format("%s -> reservoirs set to T%d (%d each)",
			DEV_FILL_MANA_ATTR, tier, TIER_ENERGY[tier]))
	end

	workspace:SetAttribute(DEV_FILL_MANA_ATTR, nil)
end

workspace:GetAttributeChangedSignal(DEV_FILL_MANA_ATTR):Connect(onDevFillMana)
-- Honour an attribute that was already set before this script loaded.
onDevFillMana()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- NOTE: these letters are conjured, not taken from a block, so the
	-- server's EnergyLedger never saw them arrive. Memorizing them will
	-- always log a coverage failure ("claimed 1 x A/red, holds 0"). That
	-- is the dev path being a dev path, NOT a shadow-mode finding —
	-- discount any would-reject line that follows a `[` press before
	-- reading the log as evidence about real players.
	if input.KeyCode == Enum.KeyCode.LeftBracket then
		local letter = string.sub(TEST_WORD, letterIdx, letterIdx)
		letterIdx = (letterIdx % #TEST_WORD) + 1
		local color = TEST_COLORS[math.random(1, #TEST_COLORS)]
		session.wordBuffer:append(letter, color)
		local word = session.wordBuffer:asWord()
		log:info(string.format("append '%s' [%s] → '%s'  valid=%s", letter, color, word, tostring(Dictionary.isSpellable(word))))

	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		local result = EconomyReport.memorize(session)
		letterIdx = 1
		if result.ok then
			log:info("memorize ok word=" .. tostring(result.word))
		else
			log:info("memorize fail reason=" .. tostring(result.reason))
		end

	elseif input.KeyCode == Enum.KeyCode.BackSlash then
		session.wordBuffer:clear()
		letterIdx = 1
		log:info("buffer cleared")

	elseif input.KeyCode == Enum.KeyCode.One then
		fillReservoirsToAmount(TIER_ENERGY[1])
		log:info(string.format("reservoirs set to T1 (%d each)", TIER_ENERGY[1]))
	elseif input.KeyCode == Enum.KeyCode.Two then
		fillReservoirsToAmount(TIER_ENERGY[2])
		log:info(string.format("reservoirs set to T2 (%d each)", TIER_ENERGY[2]))
	elseif input.KeyCode == Enum.KeyCode.Three then
		fillReservoirsToAmount(TIER_ENERGY[3])
		log:info(string.format("reservoirs set to T3 (%d each)", TIER_ENERGY[3]))
	elseif input.KeyCode == Enum.KeyCode.Four then
		fillReservoirsToAmount(TIER_ENERGY[4])
		log:info(string.format("reservoirs set to T4 (%d each)", TIER_ENERGY[4]))

	elseif input.KeyCode == Enum.KeyCode.M then
		if InputCategorizer._debugOverride then
			InputCategorizer.clearDebugOverride()
			log:info("mobile override OFF — real input restored")
		else
			InputCategorizer.setDebugOverride(InputCategorizer.InputCategory.Touch)
			log:info("mobile override ON — InputCategorizer now reports Touch")
		end
	end
end)

log:info("ready — [=letter  ]=memorize  \\=clear  1-4=fill mana T1-T4  M=mobile-toggle  ;=phase-label  (cycling: " .. TEST_WORD .. ")")
