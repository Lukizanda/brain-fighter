--!strict

----------------------------------------------------------------------
-- bomb_not_under_ward — no salvo while the word ward is up; the cadence still counts the slot
----------------------------------------------------------------------
-- MODULE LEVEL: BossBombs.replacesVolley on a stand-in boss whose `WardUp`
-- attribute (what BossWard publishes) is set by hand. Every second volley is a
-- lob (the shipped cadence), so:
--   volley 1 (ward up)    no
--   volley 2 (ward up)    no, though it would have been the lob
--   volley 3 (ward down)  no (odd)
--   volley 4 (ward down)  yes
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local ARENA_ID = "BombWard"

return {
	name = "bomb_not_under_ward",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local boss, humanoid, root = ctx.hf:fakeBoss()
		local bombs = BossBombs.new(boss, humanoid, root, bombFixture.spec())
		if not bombs then
			return
		end
		ctx.bombs = bombs
		boss:SetAttribute(BossConstants.WARD_UP_ATTRIBUTE, true)
		ctx.first = bombs:replacesVolley()
		ctx.second = bombs:replacesVolley()
		boss:SetAttribute(BossConstants.WARD_UP_ATTRIBUTE, nil)
		ctx.third = bombs:replacesVolley()
		ctx.fourth = bombs:replacesVolley()
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.bombs then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		if ctx.first or ctx.second then
			return false, "a lob was chosen while the ward was up"
		end
		if ctx.third then
			return false, "the third volley was a lob"
		end
		if not ctx.fourth then
			return false, "the fourth volley, ward down, was not a lob"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.bombs then
			ctx.bombs:destroy()
		end
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
