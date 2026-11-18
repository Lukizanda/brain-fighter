--!strict

----------------------------------------------------------------------
-- keykit_pool_announces — a key kit holds a key word with a short reach, and popping its last letter is announced once, with its gate
----------------------------------------------------------------------
-- MODULE LEVEL: BlockSpawner pools on wordKitFixture, nothing else.
--   * a kit with `kitOpensGate` rolls a 3-letter key word, every letter
--     stamped with the volume's `popReach`;
--   * popping letters one by one announces nothing until the last, then
--     announces the kit's gate exactly once;
--   * re-rolling the kit for its gate (what a re-seal does) hangs a fresh
--     word and announces nothing;
--   * an ordinary gated kit announces nothing when emptied;
--   * `kitOpensGate` without a gate is ignored: the volume is an ordinary kit;
--   * a listener that was stopped hears nothing.
-- A pop here is the block being destroyed, which is all the pool reads.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local WordKits = require(ReplicatedStorage.Shared.BlockSpawner.WordKits)
local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local ARENA_ID = "KeyKitPool"
local KEY_LENGTH = 3
local ORDINARY_LENGTH = 5
local GATE = "KeyGate"
local OTHER_GATE = "PlainGate"
local REACH_STUDS = 40
local NEVER_REFILL_SEC = 600
-- The pool hears of a removed block on a deferred signal.
local SETTLE_SEC = 0.1

local function popAll(blocks: { Model }, exceptLast: boolean)
	local last = if exceptLast then #blocks - 1 else #blocks
	for index = 1, last do
		blocks[index]:Destroy()
	end
	task.wait(SETTLE_SEC)
end

return {
	name = "keykit_pool_announces",

	setup = function(ctx: any)
		ctx.kit = wordKitFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local kit = ctx.kit

		-- The key kit.
		local pool = kit:pool({
			boxes = { kit:kitBox({ wordKit = KEY_LENGTH, kitGate = GATE, kitOpensGate = true, popReach = REACH_STUDS }) },
			respawnDelay = NEVER_REFILL_SEC,
		})
		local heard: { string } = {}
		pool:onGateKitEmptied(function(gate: string)
			table.insert(heard, gate)
		end)
		local stoppedHeard = 0
		local stop = pool:onGateKitEmptied(function()
			stoppedHeard += 1
		end)
		stop()
		pool:start()

		local blocks = pool:getActiveBlocks()
		ctx.keyCount = #blocks
		ctx.allReach = true
		local letters: { string } = {}
		for _, block in blocks do
			if BlockShoot.reachOf(block) ~= REACH_STUDS then
				ctx.allReach = false
			end
			table.insert(letters, kit:letterOf(block))
		end
		table.sort(letters)
		local sorted = table.concat(letters)
		ctx.isKeyWord = false
		for _, word in WordKits.keyWords(KEY_LENGTH) do
			local chars = string.split(word, "")
			table.sort(chars)
			if table.concat(chars) == sorted then
				ctx.isKeyWord = true
			end
		end
		if #blocks ~= KEY_LENGTH then
			return
		end

		popAll(blocks, true)
		ctx.heardBeforeLast = #heard
		blocks[#blocks]:Destroy()
		task.wait(SETTLE_SEC)
		ctx.heardAfterLast = #heard
		ctx.heardGate = heard[1]

		ctx.rerolled = pool:rerollKitsForGate(GATE)
		task.wait(SETTLE_SEC)
		ctx.countAfterReroll = #pool:getActiveBlocks()
		ctx.heardAfterReroll = #heard
		ctx.stoppedHeard = stoppedHeard

		-- An ordinary gated kit, and a key flag with no gate.
		local plain = kit:pool({
			boxes = { kit:kitBox({ wordKit = ORDINARY_LENGTH, kitGate = OTHER_GATE }) },
			respawnDelay = NEVER_REFILL_SEC,
		})
		local plainHeard = 0
		plain:onGateKitEmptied(function()
			plainHeard += 1
		end)
		plain:start()
		popAll(plain:getActiveBlocks(), false)
		ctx.plainHeard = plainHeard

		local gateless = kit:pool({
			boxes = { kit:kitBox({ wordKit = ORDINARY_LENGTH, kitOpensGate = true }) },
			respawnDelay = NEVER_REFILL_SEC,
		})
		local gatelessHeard = 0
		gateless:onGateKitEmptied(function()
			gatelessHeard += 1
		end)
		gateless:start()
		ctx.gatelessCount = #gateless:getActiveBlocks()
		popAll(gateless:getActiveBlocks(), false)
		ctx.gatelessHeard = gatelessHeard
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if ctx.keyCount ~= KEY_LENGTH then
			return false, string.format("the key kit holds %s letters, expected %d", tostring(ctx.keyCount), KEY_LENGTH)
		end
		if not ctx.isKeyWord then
			return false, "the key kit's letters are not one of the key words"
		end
		if not ctx.allReach then
			return false, "a key letter does not carry the volume's pop reach"
		end
		if not ctx.done then
			return false, "the test did not finish"
		end
		if ctx.heardBeforeLast ~= 0 then
			return false, "the kit was announced before its last letter was popped"
		end
		if ctx.heardAfterLast ~= 1 or ctx.heardGate ~= GATE then
			return false, string.format("emptying the kit announced %s time(s) for gate %s", tostring(ctx.heardAfterLast), tostring(ctx.heardGate))
		end
		if ctx.rerolled ~= 1 or ctx.countAfterReroll ~= KEY_LENGTH then
			return false, "a re-roll for the gate did not hang a fresh key word"
		end
		if ctx.heardAfterReroll ~= 1 then
			return false, "a re-roll was announced as the kit being popped"
		end
		if ctx.stoppedHeard ~= 0 then
			return false, "a stopped listener was still called"
		end
		if ctx.plainHeard ~= 0 then
			return false, "an ordinary gated kit was announced as a key kit"
		end
		if ctx.gatelessCount ~= ORDINARY_LENGTH or ctx.gatelessHeard ~= 0 then
			return false, "KitOpensGate without a gate did not fall back to an ordinary kit"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
