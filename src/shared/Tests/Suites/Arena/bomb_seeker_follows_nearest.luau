--!strict

----------------------------------------------------------------------
-- bomb_seeker_follows_nearest — at the hatch the seekers follow the nearest living player of the arena to the puzzle; when that player is gone they follow the nearest living one, and with nobody they keep their heading
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock and dt. The puzzle
-- lands on the boss's own position (a bare arena) with the player 80 studs
-- away along +Z.
--   Rest      while the puzzle rests BombTargetUserId is 0;
--   Hatch     at the hatch the seeker follows the harness player (the only,
--             hence nearest, living player) and BombTargetUserId is their UserId;
--   Nobody    when the player has no living root the seeker follows nobody
--             (BombTargetUserId 0) and keeps flying along its last heading; when
--             the root is back it chases again.
--
-- NOT covered: choosing between two players by distance (the harness has one).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local ROOT_NAME = "HumanoidRootPart"
local PLAYER_OFFSET = Vector3.new(0, 0, 80)
local STEP_SEC = 0.1
local HIDDEN_ROOT_NAME = "RootHiddenByTest"
local HEADING_TOLERANCE = 0.01

return {
	name = "bomb_seeker_follows_nearest",

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
		local playerAt = root.Position + PLAYER_OFFSET
		if not bombFixture.placePlayer(player, playerAt) then
			return
		end
		ctx.placed = true

		local model = bombFixture.lobAndLand(bombs, clock, root.Position, bombFixture.rootOf(player))
		if not model then
			return
		end
		ctx.thrown = true
		ctx.restAttr = model:GetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE)

		-- The hatch: the first seeker follows the nearest living player.
		bombFixture.expire(bombs, clock, model)
		bombFixture.advance(bombs, clock, STEP_SEC)
		ctx.targetFollows = bombs:followOf(model, 1) == player
		ctx.targetAttr = model:GetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE)

		-- Nobody: the player's root disappears for a moment (Hittables and the
		-- follow check both need it). The Heartbeat wait lets Hittables' per-frame
		-- cache expire.
		local realRoot = bombFixture.rootOf(player)
		if realRoot then
			ctx.hiddenRoot = realRoot
			realRoot.Name = HIDDEN_ROOT_NAME
			task.wait(bombFixture.POLL_SEC)
			local part = bombFixture.seeker(model, 1)
			local before = if part then part.Position else Vector3.zero
			bombFixture.advance(bombs, clock, STEP_SEC)
			local after = if part then part.Position else Vector3.zero
			ctx.nobodyFollows = bombs:followOf(model, 1) == nil
			ctx.nobodyAttr = model:GetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE)
			local moved = after - before
			ctx.keptHeading = moved.Magnitude > 0
				and moved.Unit:Dot(Vector3.zAxis) > 1 - HEADING_TOLERANCE

			realRoot.Name = ROOT_NAME
			task.wait(bombFixture.POLL_SEC)
			bombFixture.advance(bombs, clock, STEP_SEC)
			ctx.backFollows = bombs:followOf(model, 1) == player
		end
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
		if ctx.restAttr ~= 0 then
			return false, string.format("BombTargetUserId was %s while the puzzle rested, expected 0", tostring(ctx.restAttr))
		end
		if not ctx.targetFollows or ctx.targetAttr ~= ctx.player.UserId then
			return false, string.format("the seeker did not follow the nearest player at the hatch (BombTargetUserId %s)", tostring(ctx.targetAttr))
		end
		if not ctx.nobodyFollows or ctx.nobodyAttr ~= 0 then
			return false, string.format("with no living player the seeker followed someone (BombTargetUserId %s)", tostring(ctx.nobodyAttr))
		end
		if not ctx.keptHeading then
			return false, "with nobody to follow the seeker did not keep flying along its heading"
		end
		if not ctx.backFollows then
			return false, "the seeker did not chase again when the player's root was back"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		-- The root must be called what the game expects, whatever happened.
		if ctx.hiddenRoot then
			ctx.hiddenRoot.Name = ROOT_NAME
		end
		bombFixture.finish(ctx)
	end,
}
