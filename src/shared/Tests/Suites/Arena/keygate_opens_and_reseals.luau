--!strict

----------------------------------------------------------------------
-- keygate_opens_and_reseals — popping a gate's key letters breaks that gate and no other; when it re-seals, fresh keys hang
----------------------------------------------------------------------
-- Through the real BreakableWallService (the game's, which watches the tag)
-- with walls from breakableWallFixture, a key kit in a pool of the test's
-- own, and a WordKitWatcher of the test's own over just that pool (the
-- game's watcher only knows the pools that existed at boot).
--   * the OpenGate event alone breaks the wall with that GateId in that
--     arena, and leaves a wall with another GateId and a wall with the same
--     GateId in another arena intact;
--   * end to end: the last key letter popped breaks the gate;
--   * the gate re-seals after its RegenSec and the kit is re-rolled whole.
-- A pop here is the block being destroyed, which is all the pool reads.
--
-- NOT covered: a real client's tap and its reach (see keyreach_range_check
-- for the server's half of that).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BreakableWallConstants = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)
local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)
local WordKitWatcher = require(ServerScriptService.Server.BlockSpawner.WordKitWatcher)

local openGateEvent = ServerScriptService.Server.Arena.Events.OpenGate :: BindableEvent

local ARENA_ID = "KeyGateArena"
local OTHER_ARENA = "KeyGateOtherArena"
local GATE = "KeyedGate"
local EVENT_GATE = "EventGate"
local OTHER_GATE = "UnkeyedGate"
local KEY_LENGTH = 3
local WALL_HEALTH = 30
local NEVER_REFILL_SEC = 600
local State = BreakableWallConstants.State

return {
	name = "keygate_opens_and_reseals",

	setup = function(ctx: any)
		ctx.walls = breakableWallFixture.new(ARENA_ID)
		ctx.kit = wordKitFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local walls = ctx.walls
		local kit = ctx.kit
		local regen = breakableWallFixture.GATE_REGEN_SEC
		local keyed = walls:wall("KeyedGate", { gateId = GATE, regenSec = regen, maxHealth = WALL_HEALTH })
		local eventWall = walls:wall("EventGate", { gateId = EVENT_GATE, regenSec = regen, maxHealth = WALL_HEALTH })
		local otherGate = walls:wall("OtherGate", { gateId = OTHER_GATE, regenSec = regen, maxHealth = WALL_HEALTH })
		local otherArena = walls:wall("OtherArenaGate", { gateId = EVENT_GATE, regenSec = regen, maxHealth = WALL_HEALTH, arenaId = OTHER_ARENA })
		walls:settle()

		-- The event alone.
		openGateEvent:Fire(ARENA_ID, EVENT_GATE)
		walls:settle()
		ctx.eventWallState = walls:stateOf(eventWall)
		ctx.otherGateState = walls:stateOf(otherGate)
		ctx.otherArenaState = walls:stateOf(otherArena)
		ctx.keyedBefore = walls:stateOf(keyed)
		-- A second request for an open gate is harmless.
		openGateEvent:Fire(ARENA_ID, EVENT_GATE)

		-- End to end.
		local pool = kit:pool({
			boxes = { kit:kitBox({ wordKit = KEY_LENGTH, kitGate = GATE, kitOpensGate = true }) },
			respawnDelay = NEVER_REFILL_SEC,
		})
		pool:start()
		local watcher = WordKitWatcher.new({ [ARENA_ID] = pool })
		ctx.watcher = watcher
		watcher:start()

		local keys = pool:getActiveBlocks()
		ctx.keyCount = #keys
		for index = 1, #keys - 1 do
			keys[index]:Destroy()
		end
		walls:settle()
		ctx.keyedWithOneLeft = walls:stateOf(keyed)
		if keys[#keys] then
			keys[#keys]:Destroy()
		end
		walls:settle()
		ctx.keyedAfter = walls:stateOf(keyed)
		ctx.keysWhileOpen = #pool:getActiveBlocks()

		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		walls:settle()
		ctx.keyedResealed = walls:stateOf(keyed)
		ctx.keysAfterReseal = #pool:getActiveBlocks()
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.done then
			return false, "the test did not finish"
		end
		if ctx.eventWallState ~= State.Broken then
			return false, "OpenGate did not break the wall with that GateId (state " .. tostring(ctx.eventWallState) .. ")"
		end
		if ctx.otherGateState ~= State.Intact or ctx.keyedBefore ~= State.Intact then
			return false, "OpenGate broke a wall with a different GateId"
		end
		if ctx.otherArenaState ~= State.Intact then
			return false, "OpenGate broke a wall with the same GateId in another arena"
		end
		if ctx.keyCount ~= KEY_LENGTH then
			return false, string.format("fixture: the key kit holds %s letters", tostring(ctx.keyCount))
		end
		if ctx.keyedWithOneLeft ~= State.Intact then
			return false, "the gate opened with a key letter still out"
		end
		if ctx.keyedAfter ~= State.Broken then
			return false, "popping the last key letter did not open the gate (state " .. tostring(ctx.keyedAfter) .. ")"
		end
		if ctx.keysWhileOpen ~= 0 then
			return false, "keys were hung again while the gate was still open"
		end
		if ctx.keyedResealed ~= State.Intact then
			return false, "the keyed gate did not re-seal"
		end
		if ctx.keysAfterReseal ~= KEY_LENGTH then
			return false, string.format("%s key letters after the re-seal, expected %d", tostring(ctx.keysAfterReseal), KEY_LENGTH)
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.watcher then
			ctx.watcher:destroy()
		end
		if ctx.kit then
			ctx.kit:destroy()
		end
		if ctx.walls then
			ctx.walls:destroy()
		end
	end,
}
