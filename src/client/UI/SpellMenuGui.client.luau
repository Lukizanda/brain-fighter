--!strict
----------------------------------------------------------------------
-- SpellMenuGui
----------------------------------------------------------------------
-- Mounts the three-color spell panel at BottomRight. On tap, calls
-- CastAction.tapReservoir with the local character as caster.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager  = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local SpellMenuBuilder  = require(ReplicatedStorage.Shared.Hud.SpellMenuBuilder)
local CastAction        = require(ReplicatedStorage.Shared.CastAction)
local PlayerSession     = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("SpellMenuGui")

local player = Players.LocalPlayer
local session = PlayerSession.get()
local menu = SpellMenuBuilder.build()

HudLayoutManager:register("BottomRight", menu.gui)

-- Render initial state
menu:setReservoirs(session.energyReservoirs:snapshot())

session.energyReservoirs.changed:Connect(function()
	menu:setReservoirs(session.energyReservoirs:snapshot())
end)

menu.castRequested:Connect(function(color: string)
	local character = player.Character
	if not character then
		log:warn("cast requested but no character")
		return
	end
	local result = CastAction.tapReservoir(
		color :: CastAction.Color,
		session.energyReservoirs,
		character,
		nil
	)
	if result.ok then
		log:info(string.format("Cast: %s", result.cast and result.cast.name or "?"))
	else
		log:info(string.format("Cast fizzle: %s", result.reason or "?"))
	end
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.SpellMenu = menu

log:info("Initialized")
