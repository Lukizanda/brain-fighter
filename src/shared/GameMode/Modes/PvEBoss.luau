--!strict

----------------------------------------------------------------------
-- PvEBoss
----------------------------------------------------------------------
-- Co-op boss fight: the arena's round starts when somebody takes the PvE
-- portal, ends when the boss dies or the clock runs out, and the roster
-- goes back to the hub. Phase 6 stage 5 — see `wiki/design/lobby.md`
-- § Stage 5 detail for the five decisions this file is the product of.
--
-- Behaviour:
--   - `minPlayers` is the global MIN_PLAYERS (1): a lone player never
--     waits. Anyone taking the portal while the round is Active drops in.
--   - A short `countdownSec`, so a group taking the portal together lands
--     together. A finite `timeLimit` is the fail state: players keep
--     respawning, there is no wipe rule, and on timeout the round ends
--     with no winner.
--   - The objective is not a player kill and is not modelled as one. The
--     Boss domain fires `BossDefeated(arenaId)` from its Died handler;
--     this module remembers which arenas' bosses fell and answers the win
--     check from that. One mode table serves every session running it,
--     which is why the callbacks carry the arena id.
--   - An empty score table — the roster left mid-round — also ends the
--     round, closing the stage-4a trap ("a session left empty stays
--     Active") in the one place stage 4a said it belonged.
--   - `getRoundLeader` returns nil: co-op has no leader. The outcome ids
--     (`BossDefeated` / `BossSurvived` / `Abandoned`) ride the PostRound
--     payload so the round-over card can say what happened. `onPlayerKill`
--     returns 0: PvP is off, so a player death here is the boss's or the
--     environment's, and neither scores.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local RoundOutcome = GameModeConstants.RoundOutcome

-- Server-fired BindableEvent beside the Boss RemoteEvents. Inaudible to
-- clients, which is fine — they already get the phase-0 sentinel.
local bossDefeatedEvent = ReplicatedStorage.Shared.Boss.BossEvents.BossDefeated :: BindableEvent

-- Kills never end a co-op round; only the objective or the clock does.
local NO_SCORE_LIMIT = math.huge

local PvEBoss = {}

PvEBoss.name = "PvE Boss"

-- Arenas whose boss has died since their round started. Cleared on round
-- start so a defeat recorded outside a round (there should be none — the
-- boss is torn down on RoundEnded) cannot end the next one on its first
-- tick.
local defeated: { [string]: true } = {}

bossDefeatedEvent.Event:Connect(function(arenaId: string)
	defeated[arenaId] = true
end)

function PvEBoss.getConfig()
	return {
		scoreLimit = NO_SCORE_LIMIT,
		timeLimit = GameModeConstants.PVE_ROUND_TIME_LIMIT_SEC,
		countdownSec = GameModeConstants.PVE_COUNTDOWN_SEC,
		respawnTime = GameModeConstants.RESPAWN_TIME,
		-- The shipped arena's pad tag: the PvE arena *is* the Default slot
		-- (stage 5 decision 1). `SpawnTags.PvEArena` is for a second slot.
		spawnTag = Arena.SpawnTags.Default,
		runsRounds = true,
		allowsPvP = false,
	}
end

function PvEBoss.onPlayerJoin(player: Player)
	player.Neutral = true
end

function PvEBoss.onPlayerKill(_killer: Player?, _victim: Player, _cause: string): number
	return 0
end

function PvEBoss.checkWinCondition(scores: { [Player]: any }, arenaId: string): (boolean, number?, string?)
	if defeated[arenaId] then
		return true, nil, RoundOutcome.BossDefeated
	end
	-- Nobody left to fight: the tracker's membership follows the roster
	-- exactly, so an empty table means an empty arena.
	if next(scores) == nil then
		return true, nil, RoundOutcome.Abandoned
	end
	return false, nil, nil
end

-- The clock ran out: co-op has no leader, and the boss is still up.
function PvEBoss.getRoundLeader(_scores: { [Player]: any }, _arenaId: string): (number?, string?)
	return nil, RoundOutcome.BossSurvived
end

function PvEBoss.onRoundStart(arenaId: string)
	defeated[arenaId] = nil
end

function PvEBoss.onRoundEnd(arenaId: string)
	defeated[arenaId] = nil
end

return PvEBoss
