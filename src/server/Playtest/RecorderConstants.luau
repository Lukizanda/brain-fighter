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

-- Spores (FightSim's conventions): a spore pop is a `pop` with this zone and
-- a `boss_damage` with this spell name at this tier.
RecorderConstants.SPORE_ZONE = "Spore"
RecorderConstants.SPORE_SPELL = "Spore"
RecorderConstants.SPORE_DAMAGE_TIER = 1
-- The pop damage reaches the recorder twice (PlayerDamaged and the boss's
-- HealthChanged, in either order); the two are paired when they arrive
-- within this long of each other and their damage agrees within this many
-- health points.
RecorderConstants.ATTRIBUTION_WINDOW_SEC = 0.5
RecorderConstants.DAMAGE_MATCH_TOLERANCE = 1
-- Spores of one lob land in the same frame; those seen within this long
-- of the first make one `spore_lob`.
RecorderConstants.LOB_BATCH_SEC = 0.25
-- A spore removed within this long before its fuse time still counts as
-- having burst (clock and rounding slack); earlier it was popped or cleared.
RecorderConstants.BURST_SLACK_SEC = 0.25

RecorderConstants.OUTCOME_WIN = "win"
RecorderConstants.OUTCOME_TIMEOUT = "timeout"

return RecorderConstants
