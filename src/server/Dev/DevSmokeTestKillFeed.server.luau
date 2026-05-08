----------------------------------------------------------------------
-- DevSmokeTestKillFeed
----------------------------------------------------------------------
-- Dev helper: fires three synthetic KillFeed events at the first
-- character spawn so the client UI can be visually verified without
-- staging real combat. Gated by GameConfig.DEV_SMOKE_KILLFEED.
--
-- Exercises all three render branches in src/client/UI/KillFeedGui:
--   1. Normal kill        — killerId != victimId, both nonzero
--   2. Self-elim          — killerId == victimId
--   3. Environment kill   — killerId == 0
--
-- Real Player.UserIds are passed for the local player so team-color
-- lookup resolves; the "killer" in branch 1 uses an unused UserId so
-- it harmlessly falls back to the neutral colour.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("DevSmokeTestKillFeed")

if not GameConfig.DEV_SMOKE_KILLFEED then
	return
end

local INTER_EVENT_DELAY = 0.4 -- seconds between fires
local START_DELAY = 12 -- seconds after first character spawn before firing (sized to clear the round countdown so smoke captures land inside the entry-lifetime window)
local LOOP_INTERVAL = 10 -- seconds between repeat fires; lets MCP screen captures land mid-cycle without timing the entry-lifetime window precisely

local killFeedRemote = ReplicatedStorage.Shared.GameMode.Remotes.KillFeed

local started = false

local function fireOnce(player: Player)
	local lpId = player.UserId
	local fakeKillerId = lpId + 1 -- not a real player; resolves to neutral colour, that's expected

	-- Branch 1 — normal kill: someone else fragged the local player.
	killFeedRemote:FireAllClients({
		killerId = fakeKillerId,
		killerName = "EnemyBot",
		victimId = lpId,
		victimName = player.Name,
		weaponName = "Rifle",
	})
	task.wait(INTER_EVENT_DELAY)

	-- Branch 2 — self-elim: local player killed themselves.
	killFeedRemote:FireAllClients({
		killerId = lpId,
		killerName = player.Name,
		victimId = lpId,
		victimName = player.Name,
		weaponName = "Rifle",
	})
	task.wait(INTER_EVENT_DELAY)

	-- Branch 3 — environment kill: fall damage, death zone, etc.
	killFeedRemote:FireAllClients({
		killerId = 0,
		killerName = "Environment",
		victimId = lpId,
		victimName = player.Name,
		weaponName = "Fall",
	})
end

local function runSmokeLoop(player: Player)
	if started then
		return
	end
	started = true

	task.wait(START_DELAY)
	log:info("Starting smoke-fire loop")

	while player.Parent do
		fireOnce(player)
		task.wait(LOOP_INTERVAL)
	end
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(runSmokeLoop, player)
		return
	end
	player.CharacterAdded:Once(function()
		task.spawn(runSmokeLoop, player)
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

log:info("Initialized — armed for first character spawn")
