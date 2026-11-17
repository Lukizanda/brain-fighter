--!strict

----------------------------------------------------------------------
-- spore_lob_lands_marked — a lob puts sporeCount marked blocks near the target after the flight, outside the pool's counts
----------------------------------------------------------------------
-- MODULE LEVEL: BossSpores on a stand-in boss, ticked by hand, with a pool of
-- the test's own (one quota volume, so the field is one block). A lob at a
-- point:
--   * lands nothing during the flight, then sporeCount blocks, after about
--     the flight time (and a second lob is refused while one is in the air);
--   * each is within sporeLandRadius of the point (horizontal), carries the
--     spore mark (Block.Spore) and a fuse time in server-time seconds in the
--     future, is a Common-table letter in red or blue, and is a block of the
--     pool's arena (so ConsumeBlock would accept it);
--   * none of them is in the pool's field: the target count and the active
--     blocks are unchanged;
--   * BlockShoot.isSpore sees the mark on them and not on a field block;
--   * destroying the object removes them, and a lob still in the air then
--     lands nothing.
--
-- NOT covered: the throw and landing cues (a client view is needed).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local SporeConstants = require(ReplicatedStorage.Shared.BlockSpawner.SporeConstants)
local BossSpores = require(ServerScriptService.Server.Boss.Scripts.BossSpores)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local sporeFixture = require(ReplicatedStorage.Shared.Tests.Helpers.sporeFixture)

local ARENA_ID = "SporeLob"
local ZONE_OFFSET = Vector3.new(0, 0, 40)
local TARGET_OFFSET = Vector3.new(60, 0, 0)
local NEVER_REFILL_SEC = 600
-- tick() runs every POLL_SEC, so the landing may be a poll late but never early.
local FLIGHT_EARLY_SLACK_SEC = 0.02
local FLIGHT_LATE_SLACK_SEC = 0.5
local RADIUS_EPSILON_STUDS = 0.01
local MID_FLIGHT_SEC = 0.1
local AFTER_DESTROY_WAIT_SEC = 0.6

local function horizontal(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

return {
	name = "spore_lob_lands_marked",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		local zoneAt = root.Position + ZONE_OFFSET
		local pool = hf:pool({ hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local fieldBlock = hf:blockAt(pool, zoneAt)
		local spec = sporeFixture.spec()
		local spores = BossSpores.new(boss, humanoid, root, spec)
		if not spores then
			return
		end
		ctx.built = true
		ctx.spec = spec
		ctx.fieldIsNotSpore = fieldBlock ~= nil and not BlockShoot.isSpore(fieldBlock)
		local targetCountBefore = pool:getTargetCount()
		local activeBefore = #pool:getActiveBlocks()

		local target = root.Position + TARGET_OFFSET
		local landed = false
		ctx.began = spores:beginLob(target, function() landed = true end)
		ctx.refusedSecondLob = spores:beginLob(target, function() end) == false
		task.wait(MID_FLIGHT_SEC)
		spores:tick()
		ctx.noneInFlight = #pool:getSpores() == 0 and not landed

		local started = os.clock()
		while not landed and os.clock() - started < sporeFixture.FLIGHT_SEC + FLIGHT_LATE_SLACK_SEC do
			task.wait(sporeFixture.POLL_SEC)
			spores:tick()
		end
		ctx.landed = landed
		ctx.flightSec = os.clock() - started + MID_FLIGHT_SEC

		local blocks = pool:getSpores()
		ctx.count = #blocks
		ctx.liveCount = spores:liveCount()
		local now = workspace:GetServerTimeNow()
		local common = LetterTables.members(LetterTables.COMMON)
		ctx.nearest = true
		ctx.marked = true
		ctx.letters = true
		ctx.colors = true
		ctx.fuses = true
		ctx.inArena = true
		ctx.notInField = true
		local field = pool:getActiveBlocks()
		for _, block in blocks do
			if horizontal(block:GetPivot().Position, target) > spec.sporeLandRadius + RADIUS_EPSILON_STUDS then
				ctx.nearest = false
			end
			if not BlockShoot.isSpore(block) then
				ctx.marked = false
			end
			local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
			local color = block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
			if not table.find(common, letter) then
				ctx.letters = false
			end
			if color ~= "red" and color ~= "blue" then
				ctx.colors = false
			end
			local expiresAt = block:GetAttribute(SporeConstants.EXPIRES_ATTRIBUTE)
			if type(expiresAt) ~= "number" or expiresAt <= now or expiresAt > now + spec.sporeFuseSec then
				ctx.fuses = false
			end
			if Arena.idOf(block) ~= ARENA_ID then
				ctx.inArena = false
			end
			if table.find(field, block) then
				ctx.notInField = false
			end
		end
		ctx.targetCountSame = pool:getTargetCount() == targetCountBefore
		ctx.activeSame = #field == activeBefore

		-- Destroying clears them, and a lob in the air lands nothing after.
		spores:destroy()
		ctx.clearedByDestroy = #pool:getSpores() == 0
		local second = BossSpores.new(boss, humanoid, root, spec)
		if second then
			second:beginLob(target, function() end)
			second:destroy()
			task.wait(AFTER_DESTROY_WAIT_SEC)
			second:tick()
			ctx.noLandingAfterDestroy = #pool:getSpores() == 0
			ctx.secondDone = true
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "BossSpores.new returned nil for a spore-configured type"
		end
		if not ctx.fieldIsNotSpore then
			return false, "fixture: the field block is missing or reads as a spore"
		end
		if not ctx.began then
			return false, "beginLob refused a first lob"
		end
		if not ctx.refusedSecondLob then
			return false, "a second lob was accepted while one was in the air"
		end
		if not ctx.noneInFlight then
			return false, "spores existed before the flight was over"
		end
		if not ctx.landed then
			return false, "the lob never landed"
		end
		if ctx.flightSec < ctx.spec.sporeFlightSec - FLIGHT_EARLY_SLACK_SEC then
			return false, string.format("landed after %.2fs, before the %.2fs flight", ctx.flightSec, ctx.spec.sporeFlightSec)
		end
		if ctx.count ~= ctx.spec.sporeCount or ctx.liveCount ~= ctx.spec.sporeCount then
			return false, string.format("%d spores in the pool, %d tracked, expected %d", ctx.count, ctx.liveCount, ctx.spec.sporeCount)
		end
		if not ctx.nearest then
			return false, "a spore landed farther than sporeLandRadius from the target"
		end
		if not ctx.marked then
			return false, "a spore is missing the Block.Spore mark"
		end
		if not ctx.letters then
			return false, "a spore's letter is not in the Common table"
		end
		if not ctx.colors then
			return false, "a spore is not red or blue"
		end
		if not ctx.fuses then
			return false, "a spore's published fuse time is missing, past, or longer than the fuse"
		end
		if not ctx.inArena then
			return false, "a spore does not carry the pool's arena id (ConsumeBlock would refuse it)"
		end
		if not ctx.notInField or not ctx.targetCountSame or not ctx.activeSame then
			return false, "a spore is in the pool's field or changed its counts"
		end
		if not ctx.clearedByDestroy then
			return false, "destroying the BossSpores object left spores in the world"
		end
		if not ctx.secondDone or not ctx.noLandingAfterDestroy then
			return false, "a lob in the air landed spores after its object was destroyed"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
