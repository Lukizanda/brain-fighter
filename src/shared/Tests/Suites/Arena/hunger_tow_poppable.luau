--!strict

----------------------------------------------------------------------
-- hunger_tow_poppable — a letter in tow is still a normal poppable block
----------------------------------------------------------------------
-- MODULE LEVEL: a block is put in tow through BossHunger on a stand-in boss
-- and carried a known distance. The block starts just OUT of the server's
-- pop range of the boss (BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS) and
-- is carried inside it. Then, with a stand-in character at the boss's place,
-- the real BlockShoot validators say what a tap would hear:
--   * the block is still tagged, in the workspace and stamped with its arena;
--   * the range check passes, because it reads the block's CURRENT position
--     (before the tow it would have failed);
--   * the position the pool publishes for clients matches the model's;
--   * a pool re-roll (rerollAll) leaves a block in tow alone (same instance,
--     same place) and the pool's count is unchanged.
-- Finally the pop: destroyed, it is no longer in tow.
--
-- NOT covered: the remote itself (rate limit, raycast) and what a client
-- draws; the client animator's follow of the published position is checked in
-- a live play session, not here.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local TowConstants = require(ReplicatedStorage.Shared.BlockSpawner.TowConstants)
local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local BlockShootConstants = require(ServerScriptService.Server.BlockShoot.BlockShootConstants)
local BlockShootValidation = require(ServerScriptService.Server.BlockShoot.BlockShootValidation)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerPop"
local INTERVAL_SEC = 1
local PULL_SPEED = 80
local REACH_STUDS = 1
-- Starts this far beyond the pop range; one 1 s tow tick carries it
-- PULL_SPEED studs, which puts it PULL_SPEED - BEYOND_RANGE_STUDS inside.
local BEYOND_RANGE_STUDS = 30
local NEVER_REFILL_SEC = 600
local POSITION_TOLERANCE_STUDS = 0.01

local function characterAt(position: Vector3): Model
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Position = position
	root.Parent = character
	return character
end

return {
	name = "hunger_tow_poppable",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		local startOffset = Vector3.new(BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS + BEYOND_RANGE_STUDS, 0, 0)
		local zoneAt = root.Position + startOffset
		local pool = hf:pool({ hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, startOffset.X + 1, 0, PULL_SPEED, REACH_STUDS
		))
		local block = hf:blockAt(pool, zoneAt)
		if not hunger or not block then
			return
		end
		ctx.fixtureOk = true
		-- The block sits anywhere within the zone, not exactly at its centre.
		local startAt = block:GetPivot().Position
		local character = characterAt(root.Position)
		ctx.character = character
		-- Before the tow: the tap would be out of range.
		ctx.rangeBefore = BlockShootValidation.checkRange(character, block)

		hunger:tick(INTERVAL_SEC) -- begins the tow
		hunger:tick(INTERVAL_SEC) -- one carry of PULL_SPEED studs
		ctx.inTow = pool:isTowed(block) and CollectionService:HasTag(block, TowConstants.TAG)
		ctx.moved = (block:GetPivot().Position - startAt).Magnitude

		local checked, _ = BlockShootValidation.checkBlock(block)
		ctx.checkBlock = checked == block
		ctx.arenaOk = (BlockShootValidation.checkArena(ARENA_ID, block))
		ctx.stamp = block:GetAttribute(Arena.ID_ATTRIBUTE) == ARENA_ID
		ctx.stillBlockTag = CollectionService:HasTag(block, LetterBlocks.TAG)
		ctx.rangeAfter = BlockShootValidation.checkRange(character, block)
		local published = block:GetAttribute(TowConstants.POSITION_ATTRIBUTE)
		ctx.published = typeof(published) == "Vector3"
			and (published - block:GetPivot().Position).Magnitude < POSITION_TOLERANCE_STUDS

		-- A re-roll of the pool does not touch it.
		local countBefore = #pool:getActiveBlocks()
		local positionBefore = block:GetPivot().Position
		pool:rerollAll()
		task.wait()
		ctx.rerollKept = block.Parent ~= nil and pool:isTowed(block)
			and (block:GetPivot().Position - positionBefore).Magnitude < POSITION_TOLERANCE_STUDS
			and #pool:getActiveBlocks() == countBefore

		-- The pop.
		block:Destroy()
		ctx.notTowedAfterPop = not pool:isTowed(block)
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.fixtureOk then
			return false, "fixture: no hunger object or no block at the zone"
		end
		if ctx.rangeBefore then
			return false, "fixture: the block was already inside pop range before the tow"
		end
		if not ctx.inTow then
			return false, "the block was not in tow (or lacked the tow tag)"
		end
		if math.abs(ctx.moved - PULL_SPEED) > POSITION_TOLERANCE_STUDS then
			return false, string.format("the block moved %s studs, expected %d", tostring(ctx.moved), PULL_SPEED)
		end
		if not ctx.checkBlock or not ctx.stillBlockTag then
			return false, "the block in tow no longer passes the block check (tag or workspace)"
		end
		if not ctx.arenaOk or not ctx.stamp then
			return false, "the block in tow lost its arena stamp"
		end
		if not ctx.rangeAfter then
			return false, "the range check did not use the block's current position"
		end
		if not ctx.published then
			return false, "the published tow position does not match the model"
		end
		if not ctx.rerollKept then
			return false, "rerollAll moved, removed or recounted a block in tow"
		end
		if not ctx.notTowedAfterPop then
			return false, "a popped block is still counted as in tow"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.character then
			ctx.character:Destroy()
		end
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
