--!strict

----------------------------------------------------------------------
-- bomb_every_second_volley — every second would-be volley is a seeker salvo; a type without the config never throws; a type with both prefers the bomb
----------------------------------------------------------------------
-- MODULE LEVEL: BossStates' AttackPrep.onEnter on a stand-in boss, run by
-- hand, reading what it selected. The phase offers one attack at a time so
-- the selection is not random:
--   FireballVolley only, with a BossBombs object  -> volley, SporeLob, volley,
--                                                    SporeLob... (the lob keeps
--                                                    the "SporeLob" name so the
--                                                    client telegraph plays)
--   the same type without the bomb config         -> volley every time
--   GroundSlam only                                -> slam every time, and slams
--                                                     do not move the count
--   bombs AND a spore lobber                       -> the bomb's cadence; the
--                                                     spore stand-in is never asked
-- Also checks the config gate: the Brain lobs bombs, the Wizard does not.
--
-- NOT covered: the real boss choosing between its attacks at random, and the
-- windup the player sees (a client view is needed, vfx-sfx.md).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)
local BossStates = require(ServerScriptService.Server.Boss.Scripts.BossStates)

local ARENA_ID = "BombSelect"
local NEAR_STUDS = 10
local SELECTIONS = 6

-- What AttackPrep selects, `count` times in a row, for a phase that offers
-- only `attack`.
local function selections(boss: Model, humanoid: Humanoid, root: BasePart, spec: any, bombs: any, spores: any, attack: string, count: number): { string }
	local prep = BossStates.build()[BossStates.State.AttackPrep]
	local out: { string } = {}
	for _ = 1, count do
		local bb: any = {
			npc = boss,
			humanoid = humanoid,
			humanoidRootPart = root,
			bossTypeSpec = spec,
			currentPhaseSpec = { availableAttacks = { attack } },
			distanceToNearest = NEAR_STUDS,
			animations = {},
			bombs = bombs,
			spores = spores,
		}
		prep.onEnter(bb)
		table.insert(out, tostring(bb.selectedAttack))
	end
	return out
end

local function alternates(list: { string }, first: string, second: string): boolean
	for index, name in list do
		if name ~= (if index % 2 == 1 then first else second) then
			return false
		end
	end
	return true
end

local function all(list: { string }, name: string): boolean
	for _, value in list do
		if value ~= name then
			return false
		end
	end
	return true
end

return {
	name = "bomb_every_second_volley",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local boss, humanoid, root = ctx.hf:fakeBoss()
		ctx.brainLobs = BossBombs.isEnabledFor(BossConfig.BOSS_TYPES.Brain)
		ctx.wizardLobs = BossBombs.isEnabledFor(BossConfig.BOSS_TYPES.Wizard)

		local spec = bombFixture.spec()
		local bombs = BossBombs.new(boss, humanoid, root, spec)
		ctx.built = bombs ~= nil
		if not bombs then
			return
		end
		ctx.withConfig = selections(boss, humanoid, root, spec, bombs, nil, BossConstants.VOLLEY_ATTACK, SELECTIONS)

		-- The same type with the bomb numbers taken away: no object at all.
		local plain: any = table.clone(spec)
		for key in plain do
			if string.sub(key, 1, 4) == "bomb" then
				plain[key] = nil
			end
		end
		ctx.plainObject = BossBombs.new(boss, humanoid, root, plain)
		ctx.withoutConfig = selections(boss, humanoid, root, plain, ctx.plainObject, nil, BossConstants.VOLLEY_ATTACK, SELECTIONS)

		-- Slams do not count toward the lob and are never replaced.
		ctx.slams = selections(boss, humanoid, root, spec, bombs, nil, "GroundSlam", SELECTIONS)
		-- 6 volleys were counted above, so the next is the 7th (not a lob), the
		-- one after the 8th: a slam in between changed nothing.
		ctx.afterSlams = selections(boss, humanoid, root, spec, bombs, nil, BossConstants.VOLLEY_ATTACK, 2)
		bombs:destroy()

		-- Both lobbers: the bomb decides, the spore stand-in is never asked.
		local bothBombs = BossBombs.new(boss, humanoid, root, spec)
		local sporeCalls = 0
		local sporeStandIn = {
			replacesVolley = function(): boolean
				sporeCalls += 1
				return true
			end,
		}
		ctx.both = selections(boss, humanoid, root, spec, bothBombs, sporeStandIn, BossConstants.VOLLEY_ATTACK, SELECTIONS)
		ctx.sporeCalls = sporeCalls
		if bothBombs then
			bothBombs:destroy()
		end

		-- A zero-count type is off.
		ctx.zeroCountObject = BossBombs.new(boss, humanoid, root, bombFixture.spec({ bombSeekerSpeed = 0 }))
		-- And one whose cadence is 0 never lobs either.
		ctx.zeroEveryObject = BossBombs.new(boss, humanoid, root, bombFixture.spec({ bombEveryNthAttack = 0 }))
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.brainLobs then
			return false, "the Brain's shipped config does not enable the bomb"
		end
		if ctx.wizardLobs then
			return false, "the Wizard (no bomb config) is enabled for the bomb"
		end
		if not ctx.built then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		if not alternates(ctx.withConfig, BossConstants.VOLLEY_ATTACK, BossConstants.SPORE_LOB_ATTACK) then
			return false, "with the config the selections were " .. table.concat(ctx.withConfig, ",")
				.. ", expected volley and lob alternating, starting with a volley"
		end
		if ctx.plainObject ~= nil then
			return false, "a type without the bomb config got a BossBombs object"
		end
		if not all(ctx.withoutConfig, BossConstants.VOLLEY_ATTACK) then
			return false, "a type without the config selected " .. table.concat(ctx.withoutConfig, ",") .. ", expected only volleys"
		end
		if not all(ctx.slams, "GroundSlam") then
			return false, "GroundSlam selection changed: " .. table.concat(ctx.slams, ",")
		end
		if not alternates(ctx.afterSlams, BossConstants.VOLLEY_ATTACK, BossConstants.SPORE_LOB_ATTACK) then
			return false, "after six slams the next volleys were " .. table.concat(ctx.afterSlams, ",")
				.. ", expected a volley then a lob (slams must not move the count)"
		end
		if not alternates(ctx.both, BossConstants.VOLLEY_ATTACK, BossConstants.SPORE_LOB_ATTACK) then
			return false, "with bombs and spores the selections were " .. table.concat(ctx.both, ",")
		end
		if ctx.sporeCalls ~= 0 then
			return false, "the spore lobber was asked although the type has a bomb"
		end
		if ctx.zeroCountObject ~= nil then
			return false, "a type with bombSeekerSpeed 0 still got a BossBombs object"
		end
		if ctx.zeroEveryObject ~= nil then
			return false, "a type with bombEveryNthAttack 0 still got a BossBombs object"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
