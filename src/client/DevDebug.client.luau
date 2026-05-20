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
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local PlayerSession  = require(script.Parent.PlayerSession)
local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)
local Dictionary     = require(ReplicatedStorage.Shared.Dictionary)

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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftBracket then
		local letter = string.sub(TEST_WORD, letterIdx, letterIdx)
		letterIdx = (letterIdx % #TEST_WORD) + 1
		local color = TEST_COLORS[math.random(1, #TEST_COLORS)]
		session.wordBuffer:append(letter, color)
		local word = session.wordBuffer:asWord()
		log:info(string.format("append '%s' [%s] → '%s'  valid=%s", letter, color, word, tostring(Dictionary.isWord(word))))

	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		local result = MemorizeAction.tryMemorize(session.wordBuffer, session.energyReservoirs)
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
	end
end)

log:info("ready — [=letter  ]=memorize  \\=clear  1-4=fill mana T1-T4  (cycling: " .. TEST_WORD .. ")")
