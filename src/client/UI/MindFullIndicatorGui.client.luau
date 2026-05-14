--!strict
----------------------------------------------------------------------
-- MindFullIndicatorGui
----------------------------------------------------------------------
-- Shows the MindFull warning banner when the player's WordBuffer is
-- full (shooting is blocked). Wires MindFullManager signals →
-- MindFullIndicatorBuilder → HudLayoutManager("TopCenter").
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger                  = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager        = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local MindFullIndicatorBuilder = require(ReplicatedStorage.Shared.Hud.MindFullIndicatorBuilder)
local PlayerSession           = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("MindFullIndicatorGui")

local session = PlayerSession.get()
local indicator = MindFullIndicatorBuilder.build()

HudLayoutManager:register("TopCenter", indicator.gui)

-- Sync to current state immediately
indicator:setActive(session.mindFullManager:isMindFull())

session.mindFullManager.mindFull:Connect(function()
	log:info("mind full — showing indicator")
	indicator:setActive(true)
end)

session.mindFullManager.mindFreed:Connect(function()
	log:info("mind freed — hiding indicator")
	indicator:setActive(false)
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.MindFullIndicator = indicator
