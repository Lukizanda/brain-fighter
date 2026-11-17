--!strict

----------------------------------------------------------------------
-- spore_every_second_volley — every second would-be volley is a spore lob; a type without the config never lobs
----------------------------------------------------------------------
-- MODULE LEVEL: BossStates' AttackPrep.onEnter on a stand-in boss, run by
-- hand, reading what it selected. The phase offers one attack at a time so
-- the selection is not random:
--   FireballVolley only, with a BossSpores object  -> volley, lob, volley, lob...
--   the same type without the spore config         -> volley every time
--   GroundSlam only                                 -> slam every time, and the
--                                                      count of volleys is not
--                                                      advanced by slams
-- Also checks the config gate itself: the Brain lobs, the Wizard does not.
--
-- NOT covered: the real boss choosing between its two attacks at random, and
-- the windup the player sees (a client view is needed, vfx-sfx.md).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossSpores = require(ServerScriptService.Server.Boss.Scripts.BossSpores)
local BossStates = require(ServerScriptService.Server.Boss.Scripts.BossStates)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local sporeFixture = require(ReplicatedStorage.Shared.Tests.Helpers.sporeFixture)

local ARENA_ID = "SporeSelect"
local ZONE_OFFSET = Vector3.new(0, 0, 30)
local NEVER_REFILL_SEC = 600
local NEAR_STUDS = 10
local SELECTIONS = 6

-- What AttackPrep selects, `count` times in a row, for a phase that offers
-- only `attack`.
local function selections(boss: Model, humanoid: Humanoid, root: BasePart, spec: any, spores: any, attack: string, count: number): { string }
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
	name = "spore_every_second_volley",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)

		ctx.brainLobs = BossSpores.isEnabledFor(BossConfig.BOSS_TYPES.Brain)
		ctx.wizardLobs = BossSpores.isEnabledFor(BossConfig.BOSS_TYPES.Wizard)

		local spec = sporeFixture.spec()
		local spores = BossSpores.new(boss, humanoid, root, spec)
		ctx.built = spores ~= nil
		if not spores then
			return
		end
		ctx.withConfig = selections(boss, humanoid, root, spec, spores, BossConstants.VOLLEY_ATTACK, SELECTIONS)

		-- The same type with the spore numbers taken away: no object at all.
		local plain: any = table.clone(BossConfig.BOSS_TYPES.Brain)
		for key in plain do
			if string.sub(key, 1, 5) == "spore" then
				plain[key] = nil
			end
		end
		ctx.plainObject = BossSpores.new(boss, humanoid, root, plain)
		ctx.withoutConfig = selections(boss, humanoid, root, plain, ctx.plainObject, BossConstants.VOLLEY_ATTACK, SELECTIONS)

		-- Slams do not count toward the lob and are never replaced.
		local slams = selections(boss, humanoid, root, spec, spores, "GroundSlam", SELECTIONS)
		ctx.slams = slams
		-- 6 volleys were counted above, so the next one is the 7th (not a lob),
		-- the one after the 8th: a slam in between changed nothing.
		ctx.afterSlams = selections(boss, humanoid, root, spec, spores, BossConstants.VOLLEY_ATTACK, 2)

		-- A lob never lobs without a lob in the air: a zero-count type is off.
		local zero = sporeFixture.spec({ sporeCount = 0 })
		ctx.zeroCountObject = BossSpores.new(boss, humanoid, root, zero)
		spores:destroy()
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.brainLobs then
			return false, "the Brain's shipped config does not enable the spore lob"
		end
		if ctx.wizardLobs then
			return false, "the Wizard (no spore config) is enabled for the lob"
		end
		if not ctx.built then
			return false, "BossSpores.new returned nil for a spore-configured type"
		end
		if not alternates(ctx.withConfig, BossConstants.VOLLEY_ATTACK, BossConstants.SPORE_LOB_ATTACK) then
			return false, "with the config the selections were " .. table.concat(ctx.withConfig, ",")
				.. ", expected volley and lob alternating, starting with a volley"
		end
		if ctx.plainObject ~= nil then
			return false, "a type without the spore config got a BossSpores object"
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
		if ctx.zeroCountObject ~= nil then
			return false, "a type with sporeCount 0 still got a BossSpores object"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
