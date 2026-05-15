--!strict
----------------------------------------------------------------------
-- ReservoirBarsGui
----------------------------------------------------------------------
-- Mounts the R/G/B energy bars at BottomRight (above SpellMenu),
-- wired to the local player's EnergyReservoirs. Updates whenever
-- any reservoir changes.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger               = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager     = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local ReservoirBarsBuilder = require(ReplicatedStorage.Shared.Hud.ReservoirBarsBuilder)
local PlayerSession        = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("ReservoirBarsGui")

local session = PlayerSession.get()
local bars = ReservoirBarsBuilder.build()

bars.gui.LayoutOrder = 1
HudLayoutManager:register("BottomRight", bars.gui)

-- Render initial state
bars:setEnergy(session.energyReservoirs:snapshot())

session.energyReservoirs.changed:Connect(function()
	bars:setEnergy(session.energyReservoirs:snapshot())
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.ReservoirBars = bars

log:info("Initialized")
