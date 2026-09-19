--!strict

----------------------------------------------------------------------
-- RoundOutcomeCopy
----------------------------------------------------------------------
-- What a finished round is called on screen. The server sends an outcome
-- id (`GameModeConstants.RoundOutcome`) on the PostRound payload; the
-- round-over card and the timer strip both turn it into words here, so a
-- boss kill reads "BOSS DEFEATED" on both rather than "No winner" on one
-- and "Round Over" on the other.
--
-- A single module rather than a table in each Config because two surfaces
-- share the vocabulary, and copy that drifts between them is the kind of
-- bug a screenshot finds and a log never does.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local RoundOutcome = GameModeConstants.RoundOutcome

local RoundOutcomeCopy = {}

-- What the card says when the payload carries no outcome (an older
-- server, or a mode that returned none).
RoundOutcomeCopy.DEFAULT_TITLE = "ROUND OVER"
RoundOutcomeCopy.DEFAULT_NO_WINNER = "No winner"
RoundOutcomeCopy.WINNER_PREFIX = "Winner: "

local TITLES: { [string]: string } = {
	[RoundOutcome.BossDefeated] = "BOSS DEFEATED",
	[RoundOutcome.BossSurvived] = "TIME'S UP",
	[RoundOutcome.ScoreLimit] = "DUEL OVER",
	[RoundOutcome.Forfeit] = "OPPONENT LEFT",
	[RoundOutcome.TimeUp] = "TIME'S UP",
	[RoundOutcome.Draw] = "TIME'S UP",
	[RoundOutcome.Abandoned] = "ROUND OVER",
}

-- The winner line when nobody is credited. A co-op objective has no
-- winner by design, so "No winner" would be the wrong word for it.
local NO_WINNER: { [string]: string } = {
	[RoundOutcome.BossDefeated] = "The boss is down",
	[RoundOutcome.BossSurvived] = "The boss survives",
	[RoundOutcome.Draw] = "Draw",
	[RoundOutcome.Abandoned] = "Everyone left",
}

RoundOutcomeCopy.TITLES = TITLES
RoundOutcomeCopy.NO_WINNER = NO_WINNER

function RoundOutcomeCopy.titleFor(outcome: string?): string
	return (outcome and TITLES[outcome]) or RoundOutcomeCopy.DEFAULT_TITLE
end

function RoundOutcomeCopy.winnerLineFor(outcome: string?, winnerName: string?): string
	if winnerName then
		return RoundOutcomeCopy.WINNER_PREFIX .. winnerName
	end
	return (outcome and NO_WINNER[outcome]) or RoundOutcomeCopy.DEFAULT_NO_WINNER
end

return RoundOutcomeCopy
