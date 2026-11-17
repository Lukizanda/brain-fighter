--!strict

----------------------------------------------------------------------
-- BotConstants
----------------------------------------------------------------------
-- Names and numbers of the Studio playtest bot (PlaytestBot). Numbers
-- marked "FightSim" are the same assumptions src/shared/Playtest/Sim/
-- FightSim.luau makes, so the real bot and the simulated one stand and
-- see alike. See wiki/design/ai-playtest.md.
--
-- Dev tooling: no game system requires this module.
----------------------------------------------------------------------

local BotConstants = {}

-- Workspace attributes the bot reads (its on-switch and its target arena).
BotConstants.BOT_ATTRIBUTE = "PlaytestBot"
BotConstants.ARENA_ATTRIBUTE = "PlaytestArena"
BotConstants.DEFAULT_ARENA = "IslandReview"

-- Names under the client scripts.
BotConstants.BOSS_NAME = "Boss"
BotConstants.TAP_CONTROLLER_NAME = "BlockTapController"
BotConstants.REQUEST_POP_NAME = "RequestPop"
BotConstants.CAST_CONTROLLER_NAME = "SpellCastController"
BotConstants.REQUEST_CAST_NAME = "RequestCast"
-- How long to wait for the two bindables a script creates at start.
BotConstants.BINDABLE_WAIT_SEC = 10

-- Portal action word the server expects (Lobby.Action).
BotConstants.JOIN_ACTION = "join"

-- Loop period.
BotConstants.TICK_SEC = 0.1

-- Rays start this far above the root part (FightSim EYE_HEIGHT).
BotConstants.EYE_HEIGHT = 7
-- A cast ray starts and ends this far above the root part (FightSim ROOT_HEIGHT).
BotConstants.ROOT_HEIGHT = 3
-- A ray that stops this close to a target counts as reaching it (FightSim).
BotConstants.SIGHT_TOLERANCE = 3

-- Walking. Humanoid:MoveTo gives up after 8 s, so a goal is re-issued
-- before that.
BotConstants.MOVE_REISSUE_SEC = 6
BotConstants.GOAL_CHANGE_STUDS = 2
BotConstants.GOAL_REACHED_STUDS = 3
-- A standing spot that has not been reached by now is picked again.
BotConstants.GOAL_STALE_SEC = 12
-- Island walkable radius around the boss's home spot (FightSim MAX_GOAL_RADIUS).
BotConstants.MAX_GOAL_RADIUS = 135

-- Lobby: walk this close to the portal, then send the join request, and
-- resend (the server's request cooldown is 1 s) until the arena takes us.
BotConstants.PORTAL_JOIN_RADIUS = 14
BotConstants.JOIN_RETRY_SEC = 2
-- A jump in position this big in one tick is a teleport: the entry pad
-- put the character on the island.
BotConstants.TELEPORT_JUMP_STUDS = 40

-- Word play (FightSim).
BotConstants.PLAN_LENGTH_TRIES = 3
BotConstants.REPLAN_SEC = 2
-- Consecutive refused pops before a word is given up.
BotConstants.MAX_POP_FAILS = 20
-- A refused cast waits this long before the persona is asked again.
BotConstants.CAST_RETRY_SEC = 1
BotConstants.COLORS = { "red", "green", "blue" }

return BotConstants
