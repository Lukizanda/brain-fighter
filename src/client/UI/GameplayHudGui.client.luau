--!strict
----------------------------------------------------------------------
-- GameplayHudGui  (BottomCenter coordinator)
----------------------------------------------------------------------
-- Single source of truth for BottomCenter stacking order.
-- Edit LAYOUT here to reorder the three elements.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Logger                = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager      = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local BufferDisplayBuilder  = require(ReplicatedStorage.Shared.Hud.BufferDisplayBuilder)
local MemorizeButtonBuilder = require(ReplicatedStorage.Shared.Hud.MemorizeButtonBuilder)
local MemorizeAction        = require(ReplicatedStorage.Shared.MemorizeAction)
local Dictionary            = require(ReplicatedStorage.Shared.Dictionary)
local PlayerSession         = require(script.Parent.Parent.PlayerSession)
local PlayerHud             = require(script.Parent.Parent.PlayerHud)

local log = Logger.new("GameplayHudGui")

-- BottomCenter stacking order (higher LO = lower on screen with VerticalAlignment.Bottom)
local LAYOUT = {
	TILES  = 2,   -- BufferDisplay  (letter tiles, topmost)
	HEALTH = 3,   -- PlayerAttributeStack
	ABSORB = 1,   -- MemorizeButton (closest to thumb zone)
}

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID
fizzleSound.Volume = 1
fizzleSound.Parent = SoundService

local session = PlayerSession.get()

local display     = BufferDisplayBuilder.build({
	onReorder = function(fromIdx: number, toIdx: number)
		session.wordBuffer:reorder(fromIdx, toIdx)
	end,
	onRemove = function(idx: number)
		session.wordBuffer:remove(idx)
	end,
})
local healthStack = PlayerHud.build()
local btn         = MemorizeButtonBuilder.build()

display.gui.LayoutOrder = LAYOUT.TILES
healthStack.LayoutOrder = LAYOUT.HEALTH
btn.gui.LayoutOrder     = LAYOUT.ABSORB

HudLayoutManager:register("BottomCenter", display.gui)
HudLayoutManager:register("BottomCenter", healthStack)
HudLayoutManager:register("BottomCenter", btn.gui)

-- CharacterAdded wiring (moved from PlayerHud/init.client.luau)
local player = Players.LocalPlayer
if player.Character then
	PlayerHud.attachAdapters(player.Character)
end
player.CharacterAdded:Connect(PlayerHud.attachAdapters)

local function onBufferChanged()
	local tiles = session.wordBuffer:tiles()
	display:setTiles(tiles)
	local size = session.wordBuffer:size()
	local isValid = size > 0 and Dictionary.isWord(session.wordBuffer:asWord())
	display:setValidWordGlow(isValid)
	btn:setValidWord(isValid)
	btn:setEnabled(size > 0)
end
onBufferChanged()

session.wordBuffer.changed:Connect(onBufferChanged)

btn.activated:Connect(function()
	local result = MemorizeAction.tryMemorize(session.wordBuffer, session.energyReservoirs)
	btn:flashResult(result.ok)
	if result.ok then
		log:info("Memorized:", result.word)
	else
		fizzleSound:Play()
		log:info("Memorize fizzle:", result.reason)
	end
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.BufferDisplay   = display
_G.PlayerHud.MemorizeButton  = btn
_G.PlayerHud.AttributeStack  = healthStack

log:info("Initialized")
