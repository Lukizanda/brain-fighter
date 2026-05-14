--!strict
----------------------------------------------------------------------
-- MemorizeButtonGui
----------------------------------------------------------------------
-- Mounts the Memorize button at BottomCenter below the BufferDisplay.
-- On click, calls MemorizeAction.tryMemorize and flashes the result.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger                 = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager       = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local MemorizeButtonBuilder  = require(ReplicatedStorage.Shared.Hud.MemorizeButtonBuilder)
local MemorizeAction         = require(ReplicatedStorage.Shared.MemorizeAction)
local PlayerSession          = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("MemorizeButtonGui")

local session = PlayerSession.get()
local btn = MemorizeButtonBuilder.build()

HudLayoutManager:register("BottomCenter", btn.gui)

-- Sync enabled state to buffer size
local function syncEnabled()
	btn:setEnabled(session.wordBuffer:size() > 0)
end
syncEnabled()

session.wordBuffer.changed:Connect(syncEnabled)

-- Handle button press
btn.activated:Connect(function()
	local result = MemorizeAction.tryMemorize(session.wordBuffer, session.energyReservoirs)
	btn:flashResult(result.ok)
	if result.ok then
		log:info("Memorized:", result.word)
	else
		log:info("Memorize fizzle:", result.reason)
	end
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.MemorizeButton = btn

log:info("Initialized")
