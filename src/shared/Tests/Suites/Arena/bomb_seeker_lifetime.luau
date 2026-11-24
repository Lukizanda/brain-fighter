--!strict

----------------------------------------------------------------------
-- bomb_seeker_lifetime — a seeker hovers over the ground while it flies and bursts where it is when its lifetime ends; a player outside the burst radius is not hurt
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock. A floor slab lies
-- under the boss; the player is parked bombFixture.FAR_STUDS away, so no seeker
-- comes near.
--   Hover     a few steps after the hatch, with the seekers flying, the first
--             seeker is bombHoverHeight over the floor;
--   Early     just before the first seeker's lifetime nothing has burst;
--   Expiry    past it the oldest seeker has burst (BombBurst, 0 hit: the player
--             is outside the radius) and the others are still flying;
--   Rest      the younger seekers burst when their own lifetime ends, one
--             BombBurst each, and then the Model is gone; the player's health is
--             untouched.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local EARLY_MARGIN_SEC = 0.1
local HOVER_AFTER_STEPS = 5
local HOVER_TOLERANCE = 0.05

return {
	name = "bomb_seeker_lifetime",

	setup = function(ctx: any)
		bombFixture.record(ctx)
	end,

	run = function(ctx: any)
		if not bombFixture.begin(ctx) then
			return
		end
		local player: Player = ctx.player
		local bombs = ctx.bombs
		local clock = ctx.clock
		local root: BasePart = ctx.root
		local lifetime: number = ctx.spec.bombSeekerLifetimeSec
		ctx.floorTop = bombFixture.addFloor(ctx)

		local farAt = root.Position + Vector3.new(0, 0, bombFixture.FAR_STUDS)
		local playerHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not bombFixture.placePlayer(player, farAt) or not playerHumanoid then
			return
		end
		ctx.placed = true
		playerHumanoid.Health = playerHumanoid.MaxHealth

		local model = bombFixture.lobAndLand(bombs, clock, root.Position, bombFixture.rootOf(player))
		if not model then
			return
		end
		ctx.thrown = true
		local letterCount = #bombFixture.letters(model)
		ctx.letterCount = letterCount
		bombFixture.hatchAll(bombs, clock, model)

		-- Fly a few steps: the hover height.
		for _ = 1, HOVER_AFTER_STEPS do
			bombFixture.advance(bombs, clock, bombFixture.STEP_SEC)
		end
		local part = bombFixture.seeker(model, 1)
		ctx.hoverY = if part then part.Position.Y else nil

		-- Seeker 1 hatched at BombHatchAt, so it lives until that plus the lifetime.
		local firstHatch = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE) :: number
		local untilFirstBurst = firstHatch + lifetime - clock.now
		bombFixture.jump(bombs, clock, untilFirstBurst - EARLY_MARGIN_SEC)
		ctx.earlyBursts = #ctx.bursts
		bombFixture.jump(bombs, clock, EARLY_MARGIN_SEC * 2)
		task.wait(bombFixture.SETTLE_SEC)
		ctx.firstBursts = #ctx.bursts
		ctx.liveAfterFirst = bombs:liveCount()
		ctx.firstHit = if ctx.bursts[1] then ctx.bursts[1].hitCount else nil

		-- The rest.
		bombFixture.jump(bombs, clock, letterCount * bombFixture.STAGGER_SEC)
		task.wait(bombFixture.SETTLE_SEC)
		ctx.modelGone = model.Parent == nil
		ctx.health = playerHumanoid.Health
		ctx.maxHealth = playerHumanoid.MaxHealth
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.bombs then
			return false, "BossBombs.new returned nil, or the arena build failed"
		end
		if not ctx.placed or not ctx.thrown then
			return false, "the player was not placed, or no puzzle landed"
		end
		local expectedY = ctx.floorTop + ctx.spec.bombHoverHeight
		if ctx.hoverY == nil or math.abs(ctx.hoverY - expectedY) > HOVER_TOLERANCE then
			return false, string.format("seeker 1 flew at y=%s, expected %.2f (%s over the floor)", tostring(ctx.hoverY), expectedY, tostring(ctx.spec.bombHoverHeight))
		end
		if ctx.earlyBursts ~= 0 then
			return false, "a seeker burst before its lifetime ended"
		end
		if ctx.firstBursts ~= 1 or ctx.liveAfterFirst ~= ctx.letterCount - 1 then
			return false, string.format("at the first expiry %d bursts and %d seekers left (expected 1 and %d)", ctx.firstBursts, ctx.liveAfterFirst, ctx.letterCount - 1)
		end
		if ctx.firstHit ~= 0 then
			return false, "a burst 400 studs from the player reported " .. tostring(ctx.firstHit) .. " hit"
		end
		if #ctx.bursts ~= ctx.letterCount then
			return false, string.format("%d bursts, expected %d", #ctx.bursts, ctx.letterCount)
		end
		if not ctx.modelGone then
			return false, "the Model outlived its last seeker"
		end
		if ctx.health < ctx.maxHealth - 0.01 or #ctx.damage ~= 0 then
			return false, "a player outside every burst radius was hurt"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.finish(ctx)
	end,
}
