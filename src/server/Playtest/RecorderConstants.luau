--!strict

----------------------------------------------------------------------
-- RecorderConstants
----------------------------------------------------------------------
-- Names and numbers of the playtest recorder (PlaytestRecorder). The
-- attribute names are shared with the client bot (BotConstants).
--
-- Dev tooling: no game system requires this module.
----------------------------------------------------------------------

local RecorderConstants = {}

-- Workspace attributes: the bot's on-switch, its arena, and the count of
-- finished fights the recorder publishes.
RecorderConstants.BOT_ATTRIBUTE = "PlaytestBot"
RecorderConstants.ARENA_ATTRIBUTE = "PlaytestArena"
RecorderConstants.FIGHTS_DONE_ATTRIBUTE = "PlaytestFightsDone"
RecorderConstants.DEFAULT_ARENA = "IslandReview"

-- Where reports go: workspace.PlaytestReport.Fight_<n> (a StringValue).
RecorderConstants.REPORT_FOLDER = "PlaytestReport"
RecorderConstants.REPORT_PREFIX = "Fight_"

-- The boss model's tag and its state-machine attribute (BossSpawner,
-- BossController).
RecorderConstants.BOSS_TAG = "Boss"
RecorderConstants.BOSS_STATE_ATTRIBUTE = "CurrentState"

RecorderConstants.SAMPLE_EVERY_SEC = 1
-- PlaytestMetrics indexes damage by tier 1..3; a higher tier counts as 3.
RecorderConstants.MAX_DAMAGE_TIER = 3

RecorderConstants.OUTCOME_WIN = "win"
RecorderConstants.OUTCOME_TIMEOUT = "timeout"

return RecorderConstants
