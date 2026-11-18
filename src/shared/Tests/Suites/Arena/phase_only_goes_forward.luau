--!strict

----------------------------------------------------------------------
-- phase_only_goes_forward — the Brain enters phase 2 at half health and stays there when it heals back over the line
----------------------------------------------------------------------
-- MODULE LEVEL: BossPhaseManager over a bare Humanoid with the Brain's own
-- phase list. Health is written directly: this tests the manager's reading
-- of it, not the damage path.
--   * above the line: phase 1, no change reported;
--   * on the line: phase 2, change reported once;
--   * healed back over the line (the Brain eats letters): still phase 2.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossPhaseManager = require(ServerScriptService.Server.Boss.Scripts.BossPhaseManager)

local MAX_HEALTH = 1000
local ABOVE_LINE_SHARE = 0.1
local SECOND_PHASE = 2

return {
	name = "phase_only_goes_forward",

	run = function(ctx: any)
		local spec = BossConfig.BOSS_TYPES.Brain
		local second = spec.phases[SECOND_PHASE]
		if not second then
			return
		end
		ctx.hasSecond = true

		local model = Instance.new("Model")
		local humanoid = Instance.new("Humanoid")
		humanoid.MaxHealth = MAX_HEALTH
		humanoid.Health = MAX_HEALTH
		humanoid.Parent = model
		model.Parent = workspace
		ctx.model = model

		local manager = BossPhaseManager.new(humanoid, spec)
		ctx.changedAtFull = manager:update()
		ctx.indexAtFull = manager:getCurrentPhaseIndex()

		humanoid.Health = MAX_HEALTH * second.hpFraction
		ctx.changedOnLine = manager:update()
		ctx.indexOnLine = manager:getCurrentPhaseIndex()
		ctx.changedTwice = manager:update()

		humanoid.Health = MAX_HEALTH * (second.hpFraction + ABOVE_LINE_SHARE)
		ctx.changedOnHeal = manager:update()
		ctx.indexAfterHeal = manager:getCurrentPhaseIndex()
		ctx.speedAfterHeal = manager:getCurrentPhaseSpec().walkSpeed
		ctx.secondSpeed = second.walkSpeed
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.hasSecond then
			return false, "the Brain has no second phase"
		end
		if ctx.changedAtFull or ctx.indexAtFull ~= 1 then
			return false, "the boss was not in phase 1 at full health"
		end
		if not ctx.changedOnLine or ctx.indexOnLine ~= SECOND_PHASE then
			return false, "the boss did not enter phase 2 on the line"
		end
		if ctx.changedTwice then
			return false, "the phase change was reported twice"
		end
		if ctx.changedOnHeal or ctx.indexAfterHeal ~= SECOND_PHASE or ctx.speedAfterHeal ~= ctx.secondSpeed then
			return false, "healing back over the line took the boss out of phase 2"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.model then
			ctx.model:Destroy()
		end
	end,
}
