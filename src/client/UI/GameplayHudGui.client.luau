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
local MemorizeAction        = require(ReplicatedStorage.Shared.MemorizeAction)
local Dictionary            = require(ReplicatedStorage.Shared.Dictionary)
local PlayerSession         = require(script.Parent.Parent.PlayerSession)

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
	local isValid = size > 0 and Dictionary.isWord(session.wordBuffer:asWord())
	display:setValidWordGlow(isValid)
	display:setSparkle(isValid)
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
_G.PlayerHud.BufferDisplay  = display
_G.PlayerHud.MemorizeButton = btn
_G.PlayerHud.AttributeStack = healthBar.gui

log:info("Initialized")
