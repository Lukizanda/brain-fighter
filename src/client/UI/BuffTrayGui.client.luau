----------------------------------------------------------------------
-- BuffTrayGui
----------------------------------------------------------------------
-- Instantiates the BuffTray at the TopRight region. The tray handle
-- is exposed on `_G.PlayerHud.BuffTray` so a future BuffAdapter (once
-- the gameplay buff system exists) can push active buffs into it
-- without this script needing to change.
--
-- Intentionally empty of content — no demo buffs, no adapter wiring.
-- When the buff system is ready, write an adapter that:
--   1. listens to wherever buffs come from (server RemoteEvent, child
--      "Buff" instances under the character, or an attribute map)
--   2. calls tray:addBuff / :updateBuff / :removeBuff
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffTrayBuilder = require(ReplicatedStorage.Shared.Hud.BuffTrayBuilder)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BuffTray")

local tray = BuffTrayBuilder.build()
HudLayoutManager:register("TopRight", tray.gui)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.BuffTray = tray

log:info("Initialized (empty tray, awaiting adapter wiring)")
