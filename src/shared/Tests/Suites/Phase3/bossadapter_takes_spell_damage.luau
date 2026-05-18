local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossAdapter = require(ReplicatedStorage.Shared.BossAdapter)
local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

local TEST_HP = 100

return {
	name = "BossAdapter takes damage from SpellExecutor",

	setup = function(ctx)
		ctx.boss = BossAdapter.spawn({
			maxHealth = TEST_HP,
			position = Vector3.new(0, 50, -60),
		})
		ctx.target = BossAdapter.getTarget()
		ctx.spell = SpellRegistry.getSpell("red", 1)
	end,

	run = function(ctx)
		ctx.result = SpellExecutor.cast(ctx.spell, ctx.target, ctx.target)
	end,

	verify = function(ctx)
		if not ctx.result.ok then
			return false, "SpellExecutor.cast returned not ok: " .. tostring(ctx.result.reason)
		end

		local hp = ctx.target.Health
		if hp >= TEST_HP then
			return false, string.format("Boss HP unchanged: %.1f (expected less than %d)", hp, TEST_HP)
		end

		local expectedDamage = ctx.spell.skill.onImpact[1].fractionOfMaxHP * TEST_HP
		local actualDamage = TEST_HP - hp
		local delta = math.abs(actualDamage - expectedDamage)
		if delta > 0.1 then
			return false, string.format(
				"damage mismatch: expected %.1f, got %.1f (spell=%s, fraction=%.2f)",
				expectedDamage, actualDamage, ctx.spell.name, ctx.spell.skill.onImpact[1].fractionOfMaxHP
			)
		end

		return true, string.format(
			"%s dealt %.1f damage to Boss (HP %d -> %.1f)",
			ctx.spell.name, actualDamage, TEST_HP, hp
		)
	end,

	teardown = function(_ctx)
		BossAdapter.despawn()
	end,
}
