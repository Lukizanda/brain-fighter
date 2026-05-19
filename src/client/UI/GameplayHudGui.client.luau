--!strict
----------------------------------------------------------------------
-- GameplayHudGui
----------------------------------------------------------------------
-- Mounts BufferDisplay (tile row) and MemorizeButton directly into
-- BottomCenter. BottomCenter's UIListLayout (VerticalAlignment.Bottom,
-- higher LO = lower on screen) controls the stacking:
--   LO=1  letter tiles   (top of cluster)
--   LO=2  health bar     (registered by PlayerHud/init.client.luau)
--   LO=3  ABSORB button  (closest to screen edge / thumb zone)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Logger                = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager      = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local BufferDisplayBuilder  = require(ReplicatedStorage.Shared.Hud.BufferDisplayBuilder)
local MemorizeButtonBuilder = require(ReplicatedStorage.Shared.Hud.MemorizeButtonBuilder)
local MemorizeAction        = require(ReplicatedStorage.Shared.MemorizeAction)
local Dictionary            = require(ReplicatedStorage.Shared.Dictionary)
local PlayerSession         = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("GameplayHudGui")

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID
fizzleSound.Volume = 1
fizzleSound.Parent = SoundService

local session = PlayerSession.get()

local display = BufferDisplayBuilder.build({
	onReorder = function(fromIdx: number, toIdx: number)
		session.wordBuffer:reorder(fromIdx, toIdx)
	end,
	onRemove = function(idx: number)
		session.wordBuffer:remove(idx)
	end,
})
local btn = MemorizeButtonBuilder.build()

-- LO=1 → tiles at top; LO=3 → ABSORB at bottom. Health bar (LO=2) is
-- registered between them by PlayerHud/init.client.luau.
display.gui.LayoutOrder = 1
btn.gui.LayoutOrder = 3

HudLayoutManager:register("BottomCenter", display.gui)
HudLayoutManager:register("BottomCenter", btn.gui)

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
_G.PlayerHud.BufferDisplay = display
_G.PlayerHud.MemorizeButton = btn

log:info("Initialized")
