--!strict
----------------------------------------------------------------------
-- GameplayHudGui
----------------------------------------------------------------------
-- Mounts BufferDisplay (tile row) and MemorizeButton in a shared
-- vertical-stack container at BottomCenter, avoiding the overlap that
-- results from two independent register() calls into the same region.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Logger                = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager      = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local BufferDisplayBuilder  = require(ReplicatedStorage.Shared.Hud.BufferDisplayBuilder)
local MemorizeButtonBuilder = require(ReplicatedStorage.Shared.Hud.MemorizeButtonBuilder)
local MemorizeAction        = require(ReplicatedStorage.Shared.MemorizeAction)
local PlayerSession         = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("GameplayHudGui")

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID
fizzleSound.Volume = 1
fizzleSound.Parent = SoundService

local session = PlayerSession.get()

local container = Instance.new("Frame")
container.Name = "GameplayHud"
container.Size = UDim2.new(0, 400, 0, 0)
container.AutomaticSize = Enum.AutomaticSize.Y
container.BackgroundTransparency = 1

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = container

local display = BufferDisplayBuilder.build({
	onReorder = function(fromIdx: number, toIdx: number)
		session.wordBuffer:reorder(fromIdx, toIdx)
	end,
	onRemove = function(idx: number)
		session.wordBuffer:remove(idx)
	end,
})
local btn = MemorizeButtonBuilder.build()

display.gui.LayoutOrder = 1
btn.gui.LayoutOrder = 2

display.gui.Parent = container
btn.gui.Parent = container

HudLayoutManager:register("BottomCenter", container)

local function onBufferChanged()
	local tiles = session.wordBuffer:tiles()
	display:setTiles(tiles)
	btn:setEnabled(session.wordBuffer:size() > 0)
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
