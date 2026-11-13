--!strict

----------------------------------------------------------------------
-- wordkit_gate_watcher
----------------------------------------------------------------------
-- WordKitWatcher against the REAL BreakableWallService. Walls are made at
-- runtime with the breakableWallFixture (real tag, real WallState
-- attribute, real boss-fireball events and regen); the pools and the
-- watcher are the test's own, in the test's own arenas.
--
--   - a wall with GateId = G breaks: its kit is untouched while it is broken;
--     when it re-seals (broken -> intact) the kit on KitGate = G is replaced
--     whole;
--   - a wall with another GateId re-sealing does not touch it;
--   - a wall in ANOTHER ARENA with the same GateId does not touch it, and a
--     kit in that other arena is left alone by this arena's wall;
--   - a round starting in the arena replaces the kit even though no wall
--     changed state (the half-eaten-kit-carries-over case);
--   - a disabled watcher re-rolls nothing.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)
local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)
local WordKitWatcher = require(ServerScriptService.Server.BlockSpawner.WordKitWatcher)

local TEST_ARENA = "TestKitGateArena"
local OTHER_ARENA = "TestKitGateOther"
local GATE = "TestKitGate"
local OTHER_GATE = "TestKitGateB"
local WALL_HEALTH = 2
local REGEN_SEC = 0.6
local RESEAL_TIMEOUT_SEC = 4
local RESEAL_POLL_SEC = 0.05
local CONSUMED = 2

type Ctx = {
	kit: wordKitFixture.Fixture?,
	walls: breakableWallFixture.Fixture?,
	watcher: WordKitWatcher.WordKitWatcher?,
	failure: string?,
}

return {
	name = "wordkit_gate_watcher",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA)
		ctx.walls = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local walls = ctx.walls :: breakableWallFixture.Fixture
		local length = wordKitFixture.KIT_WORD_LENGTH

		local pool = kit:pool({ arenaId = TEST_ARENA, boxes = { kit:kitBox({ kitGate = GATE }) } })
		local otherPool = kit:pool({ arenaId = OTHER_ARENA, boxes = { kit:kitBox({ kitGate = GATE }) } })
		pool:start()
		otherPool:start()
		local watcher = WordKitWatcher.new({ [TEST_ARENA] = pool, [OTHER_ARENA] = otherPool })
		watcher:start()
		ctx.watcher = watcher

		local function newWall(name: string, gate: string, arenaId: string?): BasePart
			local wall = walls:wall(name, { maxHealth = WALL_HEALTH, regenSec = REGEN_SEC, arenaId = arenaId })
			wall:SetAttribute(WordKitWatcher.GATE_ID_ATTRIBUTE, gate)
			return wall
		end

		local boss = walls:boss()
		local gateWall = newWall("GateWall", GATE)
		local otherGateWall = newWall("OtherGateWall", OTHER_GATE)
		local otherArenaWall = newWall("OtherArenaWall", GATE, OTHER_ARENA)
		walls:settle()

		-- Breaks the wall with boss fireballs; waitForReseal then lets its own regen timer close it.
		local function breakWall(wall: BasePart): boolean
			walls:fireballs(wall, boss, WALL_HEALTH)
			if walls:stateOf(wall) ~= C.State.Broken then
				ctx.failure = string.format("%s did not break (state %s)", wall.Name, tostring(walls:stateOf(wall)))
				return false
			end
			return true
		end
		local function waitForReseal(wall: BasePart): boolean
			local waited = 0
			while walls:stateOf(wall) ~= C.State.Intact and waited < RESEAL_TIMEOUT_SEC do
				task.wait(RESEAL_POLL_SEC)
				waited += RESEAL_POLL_SEC
			end
			walls:settle()
			if walls:stateOf(wall) ~= C.State.Intact then
				ctx.failure = string.format("%s never re-sealed", wall.Name)
				return false
			end
			return true
		end

		-- 1. The gate wall: kit untouched while broken, replaced whole on re-seal.
		local before = pool:getActiveBlocks()
		local otherBefore = otherPool:getActiveBlocks()
		before[1]:Destroy()
		before[2]:Destroy()
		if not breakWall(gateWall) then
			return
		end
		if kit:liveCount(before) ~= length - CONSUMED then
			ctx.failure = "the kit was touched while its wall was still broken"
			return
		end
		if not waitForReseal(gateWall) then
			return
		end
		if kit:liveCount(before) ~= 0 then
			ctx.failure = string.format("%d old letters survived the gate re-seal", kit:liveCount(before))
			return
		end
		local after = pool:getActiveBlocks()
		if #after ~= length or #kit:wordsMatching(after) == 0 then
			ctx.failure = string.format("after the re-seal the kit holds %d blocks (a curated word?) expected a fresh %d", #after, length)
			return
		end
		if kit:liveCount(otherBefore) ~= length then
			ctx.failure = "a wall in one arena re-rolled the kit of another"
			return
		end

		-- 2. Another GateId, and 3. the same GateId in another arena.
		if not breakWall(otherGateWall) or not waitForReseal(otherGateWall) then
			return
		end
		if kit:liveCount(after) ~= length then
			ctx.failure = string.format("re-sealing a wall of gate %s re-rolled the kit on gate %s", OTHER_GATE, GATE)
			return
		end
		if not breakWall(otherArenaWall) or not waitForReseal(otherArenaWall) then
			return
		end
		if kit:liveCount(after) ~= length then
			ctx.failure = string.format("a wall in %s with the same GateId re-rolled a kit in %s", OTHER_ARENA, TEST_ARENA)
			return
		end
		if kit:liveCount(otherBefore) ~= 0 then
			ctx.failure = "the other arena's own wall did not re-roll its kit"
			return
		end

		-- 4. A round start replaces a half-eaten kit although no wall changed.
		local halfEaten = pool:getActiveBlocks()
		halfEaten[1]:Destroy()
		halfEaten[2]:Destroy()
		local inOtherArena = otherPool:getActiveBlocks()
		walls:roundStarted(TEST_ARENA)
		if kit:liveCount(halfEaten) ~= 0 or #pool:getActiveBlocks() ~= length then
			ctx.failure = string.format(
				"round start left %d old letters and %d blocks, expected 0 and %d",
				kit:liveCount(halfEaten), #pool:getActiveBlocks(), length
			)
			return
		end
		if kit:liveCount(inOtherArena) ~= length then
			ctx.failure = "a round in one arena re-rolled the kit of another"
			return
		end

		-- 5. A disabled watcher re-rolls nothing.
		watcher:disable()
		local current = pool:getActiveBlocks()
		walls:roundStarted(TEST_ARENA)
		if not breakWall(gateWall) or not waitForReseal(gateWall) then
			return
		end
		if kit:liveCount(current) ~= length then
			ctx.failure = "a disabled watcher still re-rolled a kit"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "gate re-seal and round start replace the kit whole; other gates, other arenas and a disabled watcher do not"
	end,

	teardown = function(ctx: Ctx)
		if ctx.watcher then
			ctx.watcher:destroy()
		end
		if ctx.walls then
			ctx.walls:destroy()
		end
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
