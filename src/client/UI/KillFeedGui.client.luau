----------------------------------------------------------------------
-- KillFeedGui
----------------------------------------------------------------------
-- Top-right HUD strip showing recent kills:
--    Player1 [Rifle] Player2
-- Listens to the GameMode KillFeed RemoteEvent and forwards entries to
-- the builder, along with the local player's userId for name styling.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local KillFeedBuilder = require(ReplicatedStorage.Shared.Hud.KillFeedBuilder)

local log = Logger.new("KillFeedGui")

local localPlayer = Players.LocalPlayer
local killFeedRemote = ReplicatedStorage.Shared.GameMode.Remotes.KillFeed

local handle = KillFeedBuilder.build()
HudLayoutManager:register("TopRight", handle.container, HudGate.Policy.ArenaOnly)

killFeedRemote.OnClientEvent:Connect(function(entryData)
	handle:addEntry(entryData, localPlayer.UserId)
end)

log:info("Initialized")
