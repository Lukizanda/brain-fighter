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
local AttributeBarBuilder   = require(ReplicatedStorage.Shared.Hud.AttributeBarBuilder)
local MemorizeButtonBuilder = require(ReplicatedStorage.Shared.Hud.MemorizeButtonBuilder)
local Dictionary            = require(ReplicatedStorage.Shared.Dictionary)
local VfxConfig             = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local PlayerSession         = require(script.Parent.Parent.PlayerSession)
local EconomyReport         = require(script.Parent.Parent.EconomyReport)

local log = Logger.new("GameplayHudGui")

-- BottomCenter stacking order (higher LO = lower on screen with VerticalAlignment.Bottom)
local LAYOUT = {
	TILES  = 2,   -- BufferDisplay  (letter tiles, topmost)
	HEALTH = 3,   -- Health bar
	ABSORB = 1,   -- MemorizeButton (closest to thumb zone)
}

local HEALTH_COLOR    = Color3.fromRGB(80,  200,  80)
local HEALTH_WARNING  = Color3.fromRGB(220, 180,  40)
local HEALTH_CRITICAL = Color3.fromRGB(210,  60,  60)

-- Matches SpellMenuGui's fizzle: same asset, same pitch drop, so a
-- refused cast sounds identical wherever it was triggered from.
local FIZZLE_PLAYBACK_SPEED = 0.55

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId       = VfxConfig.SFX.fizzle
fizzleSound.Volume        = 1
fizzleSound.PlaybackSpeed = FIZZLE_PLAYBACK_SPEED
fizzleSound.Parent        = SoundService

local session = PlayerSession.get()

local display = BufferDisplayBuilder.build({
	onReorder = function(fromIdx: number, toIdx: number)
		session.wordBuffer:reorder(fromIdx, toIdx)
	end,
	onRemove = function(idx: number)
		session.wordBuffer:remove(idx)
	end,
})
local healthBar = AttributeBarBuilder.build({
	name          = "Health",
	color         = HEALTH_COLOR,
	warningColor  = HEALTH_WARNING,
	criticalColor = HEALTH_CRITICAL,
})
local btn = MemorizeButtonBuilder.build()

display.gui.LayoutOrder  = LAYOUT.TILES
healthBar.gui.LayoutOrder = LAYOUT.HEALTH
btn.gui.LayoutOrder      = LAYOUT.ABSORB

HudLayoutManager:register("BottomCenter", display.gui)
HudLayoutManager:register("BottomCenter", healthBar.gui)
HudLayoutManager:register("BottomCenter", btn.gui)

-- Health adapter: subscribe Humanoid properties → bar, torn down on respawn
local player = Players.LocalPlayer
local healthConnections: { RBXScriptConnection } = {}

local function detachHealth()
	for _, c in healthConnections do c:Disconnect() end
	table.clear(healthConnections)
end

local function attachHealth(character: Model)
	detachHealth()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local function push() healthBar:setValue(humanoid.Health, humanoid.MaxHealth) end
	table.insert(healthConnections, humanoid:GetPropertyChangedSignal("Health"):Connect(push))
	table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(push))
	push()
end

if player.Character then
	attachHealth(player.Character)
end
player.CharacterAdded:Connect(attachHealth)

local function onBufferChanged()
	local tiles = session.wordBuffer:tiles()
	display:setTiles(tiles)
	local size = session.wordBuffer:size()
	-- isSpellable, not isWord: the buffer may hold wildcard tiles, so
	-- "D*G" has to glow as valid on the strength of DOG existing.
	local isValid = size > 0 and Dictionary.isSpellable(session.wordBuffer:asWord())
	display:setValidWordGlow(isValid)
	display:setSparkle(isValid)
	btn:setValidWord(isValid)
	btn:setEnabled(size > 0)
end
onBufferChanged()

session.wordBuffer.changed:Connect(onBufferChanged)

btn.activated:Connect(function()
	local result = EconomyReport.memorize(session)
	btn:flashResult(result.ok)
	if result.ok then
		log:info("Memorized:", result.word)
	else
		fizzleSound:Play()
		log:info("Memorize fizzle:", result.reason)
	end
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.BufferDisplay  = display
_G.PlayerHud.MemorizeButton = btn
_G.PlayerHud.AttributeStack = healthBar.gui

log:info("Initialized")
