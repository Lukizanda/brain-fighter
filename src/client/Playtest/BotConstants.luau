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
-- That jump only counts when it starts this close to the pad: the teleport
-- from the lobby into the ready room is a jump too, and is not an arrival.
BotConstants.PAD_NEAR_STUDS = 20
-- The pad may not have streamed in when the bot reaches the ready room. Only
-- after this long without one is the arena taken to have no ready room.
BotConstants.PAD_WAIT_SEC = 10

-- Word play (FightSim).
BotConstants.PLAN_LENGTH_TRIES = 3
BotConstants.REPLAN_SEC = 2
-- Consecutive refused pops before a word is given up.
BotConstants.MAX_POP_FAILS = 20
-- A refused cast waits this long before the persona is asked again.
BotConstants.CAST_RETRY_SEC = 1
BotConstants.COLORS = { "red", "green", "blue" }

-- Spores (FightSim "Spores and ward letters are popped on sight"). Each
-- spore is popped with chance max(reactChance, stealTow) / SPORE_CHANCE_DIVISOR
-- + SPORE_CHANCE_BASE, rolled once, and not before the persona's
-- reactDelaySec after it was first seen (later spores of one lob a tap
-- apart).
BotConstants.SPORE_CHANCE_DIVISOR = 2
BotConstants.SPORE_CHANCE_BASE = 0.5

-- Scramble bombs (FightSim's bomb block; wiki/design/scramble-bomb.md). The
-- notice chance and unscramble seconds per letter are the simulator's, read
-- from PlaytestPersonas. The taps go through BombTapController's Studio-only
-- `RequestBombTap` bindable (Invoke(bomb: Model, tileIndex: number) -> boolean),
-- so a bot tap passes the client's own checks; it drops a tap within 0.25 s
-- of the last. It is waited for this long without blocking the bot; if it
-- never appears bombs are skipped.
BotConstants.BOMB_TAP_CONTROLLER_NAME = "BombTapController"
BotConstants.REQUEST_BOMB_TAP_NAME = "RequestBombTap"
BotConstants.BOMB_BINDABLE_WAIT_SEC = 10
-- The two-phase puzzle (FightSim `tune.bomb.hatch`; the same numbers, copied,
-- so keep the two together). A resting puzzle is walked to and stood at this
-- share of the CENTRE reach from the centre (FightSim SPORE_STAND_SHARE).
BotConstants.PUZZLE_STAND_SHARE = 0.8
-- Hurt this soon after a seeker vanished on its own = it burst on the bot
-- (the bot cannot see a burst; this is how a persona that missed the puzzle
-- engages its seekers).
BotConstants.SEEKER_HURT_WINDOW_SEC = 1

return BotConstants
