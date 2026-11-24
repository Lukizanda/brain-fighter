--!strict

----------------------------------------------------------------------
-- bomb_dead_body_no_wall — a player's body in a seeker's path is not a wall, dead or alive: the seeker flies through it instead of bursting
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock and dt. The player's
-- (collidable) root is parked 60 studs away along +Z, in the seekers' path. To
-- stand for a dead character, whose body Hittables no longer lists, the root
-- is renamed so neither Hittables nor the follow check can see it: the
-- character is still the player's but no longer "alive" to the game. The
-- seekers fly on along their heading, through the body, and are all still
-- flying well past it: no burst, no BombBurst.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local ROOT_NAME = "HumanoidRootPart"
local HIDDEN_ROOT_NAME = "RootHiddenByTest"
local BODY_OFFSET = Vector3.new(0, 0, 60)
-- Fly this far past the body, in studs, with every seeker still in the air.
local PAST_BODY_STUDS = 15
local MAX_STEPS = 200

return {
	name = "bomb_dead_body_no_wall",

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
		local bodyAt = root.Position + BODY_OFFSET
		if not bombFixture.placePlayer(player, bodyAt) then
			return
		end
		ctx.placed = true
		local body = bombFixture.rootOf(player)
		if body == nil then
			return
		end
		ctx.body = body
		body.CanCollide = true

		local model = bombFixture.lobAndLand(bombs, clock, root.Position, nil)
		if not model then
			return
		end
		ctx.thrown = true
		ctx.letterCount = #bombFixture.letters(model)
		bombFixture.hatchAll(bombs, clock, model)

		-- Nobody alive to chase: a heading along +Z, through the body.
		body.Name = HIDDEN_ROOT_NAME
		task.wait(bombFixture.POLL_SEC)
		ctx.passed = false
		for _ = 1, MAX_STEPS do
			bombFixture.advance(bombs, clock, bombFixture.STEP_SEC)
			if #ctx.bursts > 0 or model.Parent == nil then
				break
			end
			local furthest = 0
			for index = 1, ctx.letterCount do
				local part = bombFixture.seeker(model, index)
				if part ~= nil then
					furthest = math.max(furthest, part.Position.Z - root.Position.Z)
				end
			end
			if furthest > BODY_OFFSET.Z + PAST_BODY_STUDS then
				ctx.passed = true
				break
			end
		end
		ctx.stillFlying = bombs:liveCount()
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
		if #ctx.bursts ~= 0 then
			return false, "a seeker burst on a player's body (or on something else) in its path"
		end
		if not ctx.passed then
			return false, "the seekers never got past the body"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.body then
			ctx.body.Name = ROOT_NAME
		end
		bombFixture.finish(ctx)
	end,
}
