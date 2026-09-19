--!strict

----------------------------------------------------------------------
-- duel_win_condition — Phase 6 stage 6, the rules of a duel
----------------------------------------------------------------------
-- PvPDuel's win condition and time-out leader are pure functions of a
-- score table, so they are checked here against hand-built tables with
-- two fake duellists. Nothing here needs a second client: the round loop,
-- the score tracker and the kill routing are exercised elsewhere, and
-- what this pins down is the *rules* — kill limit, forfeit, abandonment,
-- leader and draw — and the outcome id each one reports.
--
-- Also asserts the config shape the queue relies on: exactly two seats,
-- PvP on, and the tunables falling back to their constants when the
-- Workspace attributes are unset.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local PvPDuel = require(ReplicatedStorage.Shared.GameMode.Modes.PvPDuel)

local RoundOutcome = GameModeConstants.RoundOutcome

local TEST_ARENA = "Stage6TestRules"

type Entry = { kills: number, deaths: number, assists: number }

local function entry(kills: number): Entry
	return { kills = kills, deaths = 0, assists = 0 }
end

-- Enough of a Player for the mode: it reads `UserId` and nothing else.
local function fakeDuellist(userId: number): any
	return { UserId = userId, Name = "Duellist" .. userId }
end

return {
	name = "duel_win_condition",

	verify = function(_ctx): (boolean, string?)
		local failures: { string } = {}
		local function expect(label: string, ok: boolean)
			if not ok then
				table.insert(failures, label)
			end
		end

		local a = fakeDuellist(1001)
		local b = fakeDuellist(1002)

		local config = PvPDuel.getConfig()
		local limit = config.scoreLimit

		-- Config shape the queue and the PvP gate depend on.
		expect("minPlayers is not DUEL_PLAYERS", config.minPlayers == GameModeConstants.DUEL_PLAYERS)
		expect("maxPlayers is not DUEL_PLAYERS", config.maxPlayers == GameModeConstants.DUEL_PLAYERS)
		expect("allowsPvP is not true", config.allowsPvP == true)
		expect("countdownSec missing", config.countdownSec == GameModeConstants.DUEL_COUNTDOWN_SEC)
		if workspace:GetAttribute(GameModeConstants.DUEL_KILL_LIMIT_ATTRIBUTE) == nil then
			expect("kill limit did not fall back to DUEL_KILL_LIMIT", limit == GameModeConstants.DUEL_KILL_LIMIT)
		end
		if workspace:GetAttribute(GameModeConstants.DUEL_TIME_LIMIT_ATTRIBUTE) == nil then
			expect("time limit did not fall back to DUEL_TIME_LIMIT_MIN minutes",
				config.timeLimit == GameModeConstants.DUEL_TIME_LIMIT_MIN * GameModeConstants.SECONDS_PER_MINUTE)
		end

		PvPDuel.onRoundStart(TEST_ARENA)

		-- A fresh duel is not over.
		local ended = PvPDuel.checkWinCondition({ [a] = entry(0), [b] = entry(0) } :: any, TEST_ARENA)
		expect("a fresh duel ended on its first tick", ended == false)

		-- One kill short is not over either.
		ended = PvPDuel.checkWinCondition({ [a] = entry(limit - 1), [b] = entry(limit - 1) } :: any, TEST_ARENA)
		expect("a duel one kill short of the limit ended", ended == false)

		-- Reaching the limit ends it for that player.
		local endedAtLimit, winner, outcome =
			PvPDuel.checkWinCondition({ [a] = entry(limit), [b] = entry(limit - 1) } :: any, TEST_ARENA)
		expect("hitting the kill limit did not end the round", endedAtLimit == true)
		expect("the kill-limit winner is not the player who hit it", winner == a.UserId)
		expect("kill-limit outcome is not ScoreLimit: " .. tostring(outcome), outcome == RoundOutcome.ScoreLimit)

		-- One duellist left: the survivor is credited.
		local endedAlone, survivor, forfeit = PvPDuel.checkWinCondition({ [b] = entry(0) } :: any, TEST_ARENA)
		expect("a duel with one player did not end", endedAlone == true)
		expect("the survivor was not credited", survivor == b.UserId)
		expect("forfeit outcome is not Forfeit: " .. tostring(forfeit), forfeit == RoundOutcome.Forfeit)

		-- Nobody left: over, nobody credited.
		local endedEmpty, nobody, abandoned = PvPDuel.checkWinCondition({} :: any, TEST_ARENA)
		expect("an emptied duel did not end", endedEmpty == true)
		expect("an emptied duel credited someone", nobody == nil)
		expect("abandoned outcome is not Abandoned: " .. tostring(abandoned), abandoned == RoundOutcome.Abandoned)

		-- Clock runs out: the kill leader wins…
		local leader, timeUp = PvPDuel.getRoundLeader({ [a] = entry(1), [b] = entry(2) } :: any, TEST_ARENA)
		expect("time-out leader is not the player with more kills", leader == b.UserId)
		expect("time-out outcome is not TimeUp: " .. tostring(timeUp), timeUp == RoundOutcome.TimeUp)

		-- …and level kills is a draw, including at zero.
		local tied, draw = PvPDuel.getRoundLeader({ [a] = entry(2), [b] = entry(2) } :: any, TEST_ARENA)
		expect("a tie credited a leader", tied == nil)
		expect("tie outcome is not Draw: " .. tostring(draw), draw == RoundOutcome.Draw)
		local zeroLeader, zeroDraw = PvPDuel.getRoundLeader({ [a] = entry(0), [b] = entry(0) } :: any, TEST_ARENA)
		expect("a killless duel credited a leader", zeroLeader == nil)
		expect("killless outcome is not Draw", zeroDraw == RoundOutcome.Draw)

		PvPDuel.onRoundEnd(TEST_ARENA)

		if #failures > 0 then
			return false, table.concat(failures, "; ")
		end
		return true, nil
	end,
}
