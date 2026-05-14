--!strict
----------------------------------------------------------------------
-- BufferDisplayGui
----------------------------------------------------------------------
-- Mounts the letter-tile row at BottomCenter, wired to the local
-- player's WordBuffer. Updates on every buffer mutation.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger               = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager     = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local BufferDisplayBuilder = require(ReplicatedStorage.Shared.Hud.BufferDisplayBuilder)
local PlayerSession        = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("BufferDisplayGui")

local session = PlayerSession.get()
local display = BufferDisplayBuilder.build()

HudLayoutManager:register("BottomCenter", display.gui)

-- Render initial state
display:setTiles(session.wordBuffer:tiles())

session.wordBuffer.changed:Connect(function()
	display:setTiles(session.wordBuffer:tiles())
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.BufferDisplay = display

log:info("Initialized")
