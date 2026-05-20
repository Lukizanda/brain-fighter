--!strict
----------------------------------------------------------------------
-- DevDebug — keyboard shortcuts for feature playtesting.
-- Remove before shipping.
--
--   [  append next letter of TEST_WORD cycling (default: "CATALOG")
--   ]  trigger memorize action
--   \  clear the buffer
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local PlayerSession  = require(script.Parent.PlayerSession)
local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)
local Dictionary     = require(ReplicatedStorage.Shared.Dictionary)

local log = Logger.new("DevDebug")

local TEST_WORD = "CATALOG"
local letterIdx = 1

local session = PlayerSession.get()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftBracket then
		local letter = string.sub(TEST_WORD, letterIdx, letterIdx)
		letterIdx = (letterIdx % #TEST_WORD) + 1
		session.wordBuffer:append(letter, "blue")
		local word = session.wordBuffer:asWord()
		log:info(string.format("append '%s' → '%s'  valid=%s", letter, word, tostring(Dictionary.isWord(word))))

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
	end
end)

log:info("ready — [=letter  ]=memorize  \\=clear  (cycling: " .. TEST_WORD .. ")")
