----------------------------------------------------------------------
-- BuffTrayGui
----------------------------------------------------------------------
-- Instantiates the BuffTray at the TopRight region.
--
-- Intentionally empty of content — no demo buffs, no adapter wiring.
-- When the buff system is ready, write an adapter that:
--   1. listens to wherever buffs come from (server RemoteEvent, child
--      "Buff" instances under the character, or an attribute map)
--   2. calls tray:addBuff / :updateBuff / :removeBuff
-- and give it a named seam to reach the tray through, the way
-- `client/DashApi` does for the dash button. The handle used to sit in a
-- global slot that nothing ever read.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffTrayBuilder = require(ReplicatedStorage.Shared.Hud.BuffTrayBuilder)
local BuffIconConfig = require(ReplicatedStorage.Shared.Hud.BuffIconConfig)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)

local log = Logger.new("BuffTray")

local tray = BuffTrayBuilder.build()
tray.gui.LayoutOrder = BuffIconConfig.LAYOUT_ORDER
HudLayoutManager:register("TopRight", tray.gui, HudGate.Policy.Always)

log:info("Initialized (empty tray, awaiting adapter wiring)")
