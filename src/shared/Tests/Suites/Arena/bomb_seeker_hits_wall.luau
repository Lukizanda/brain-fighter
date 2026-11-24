--!strict

----------------------------------------------------------------------
-- bomb_seeker_hits_wall — a seeker bursts on world geometry in its path, so a player behind cover is not hurt by it (a burst only hurts inside its radius); players and other seekers do not stop it
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock and dt. The puzzle is
-- lobbed at the boss's own position and lands there (a bare arena: the target's
-- own ground). A wall (a big anchored, collidable slab) stands WALL_Z studs
-- from it across the line to the player, who is parked, anchored, 60 studs
-- behind the wall.
--   Wall      the timer runs out, every seeker bursts (BombBurst) before passing
--             the wall, and the player behind it is unhurt (each burst is more
--             than the burst radius from them);
--   Passes    with the wall removed the same throw reaches the player (a burst
--             that hurts them), which shows the wall is what stopped it.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local WALL_Z = 25
local WALL_SIZE = Vector3.new(400, 400, 2)
local PLAYER_BEHIND_STUDS = 60
local REGEN_SLACK = 3

-- A puzzle is landed, hatched and flown until it is gone.
local function flyAll(ctx: any, model: Model): boolean
	local bombs = ctx.bombs
	bombFixture.hatchAll(bombs, ctx.clock, model)
	return bombFixture.runUntil(bombs, ctx.clock, bombFixture.STEP_SEC, function()
		return model.Parent == nil
	end)
end

return {
	name = "bomb_seeker_hits_wall",

	setup = function(ctx: any)
		bombFixture.record(ctx)
	end,

	run = function(ctx: any)
		if not bombFixture.begin(ctx) then
			return
		end
		local player: Player = ctx.player
		local bombs = ctx.bombs
		local root: BasePart = ctx.root

		local wall = Instance.new("Part")
		wall.Name = "BombTestWall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.Size = WALL_SIZE
		wall.Position = root.Position + Vector3.new(0, 0, WALL_Z)
		wall.Parent = ctx.hf.container

		local playerAt = root.Position + Vector3.new(0, 0, WALL_Z + PLAYER_BEHIND_STUDS)
		local playerHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not bombFixture.placePlayer(player, playerAt) or not playerHumanoid then
			return
		end
		ctx.placed = true
		playerHumanoid.Health = playerHumanoid.MaxHealth

		-- Behind the wall.
		local model = bombFixture.lobAndLand(bombs, ctx.clock, root.Position, nil)
		if not model then
			return
		end
		ctx.thrown = true
		ctx.letterCount = #bombFixture.letters(model)
		ctx.wallStopped = flyAll(ctx, model)
		task.wait(bombFixture.SETTLE_SEC)
		ctx.burstsBehind = #ctx.bursts
		ctx.brokenBehind = #ctx.broken
		ctx.hitsBehind = 0
		for _, burst in ctx.bursts do
			ctx.hitsBehind += burst.hitCount
		end
		ctx.lossBehind = playerHumanoid.MaxHealth - playerHumanoid.Health

		-- Without the wall.
		wall:Destroy()
		playerHumanoid.Health = playerHumanoid.MaxHealth
		local second = bombFixture.lobAndLand(bombs, ctx.clock, root.Position, nil)
		if not second then
			return
		end
		ctx.openStopped = flyAll(ctx, second)
		task.wait(bombFixture.SETTLE_SEC)
		ctx.lossOpen = playerHumanoid.MaxHealth - playerHumanoid.Health
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
		if not ctx.wallStopped then
			return false, "the seekers did not all end at the wall"
		end
		if ctx.burstsBehind ~= ctx.letterCount then
			return false, string.format("%d bursts at the wall, expected %d", ctx.burstsBehind, ctx.letterCount)
		end
		if ctx.hitsBehind ~= 0 or ctx.lossBehind > 0.01 then
			return false, "a player behind the wall was hurt by bursts on it"
		end
		if ctx.brokenBehind ~= 1 then
			return false, "BombBroken fired " .. ctx.brokenBehind .. " times for one hatched puzzle"
		end
		if not ctx.openStopped then
			return false, "the control puzzle (no wall) never ended"
		end
		if ctx.lossOpen < ctx.spec.bombBurstDamage - REGEN_SLACK then
			return false, string.format("with the wall gone the player lost %.2f, expected a burst of %s", ctx.lossOpen, tostring(ctx.spec.bombBurstDamage))
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.finish(ctx)
	end,
}
