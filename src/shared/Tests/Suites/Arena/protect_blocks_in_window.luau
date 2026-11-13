--!strict

----------------------------------------------------------------------
-- protect_blocks_in_window — damage is dropped inside the window, not after
----------------------------------------------------------------------
-- Drives the real `applyDamage.process` (the one damage path) against a bare
-- rig with a Humanoid. Inside a protection window the hit returns nil and
-- Health does not move; once the window has closed the same hit lands. A
-- control rig with no window takes the hit throughout, so "blocked" cannot
-- be a rig that simply takes no damage.
--
-- Also pins the one exemption: a death-zone hit lands inside a window, so a
-- protected character cannot hang in the void.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local Protection = require(ReplicatedStorage.Shared.Health.Protection)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)

local START_HEALTH = 100
local HIT = 10
local WINDOW_SEC = 0.3
-- Past the window by more than a frame of slack.
local AFTER_WINDOW_WAIT_SEC = WINDOW_SEC + 0.25
local LONG_WINDOW_SEC = 60

local function rig(): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = "ProtectTestRig"
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = START_HEALTH
	humanoid.Health = START_HEALTH
	humanoid.Parent = model
	return model, humanoid
end

local function hit(humanoid: Humanoid, cause: string): any
	return applyDamage.process({
		sourcePlayer = nil,
		targetHumanoid = humanoid,
		baseDamage = HIT,
		damageType = DamageTypes.DamageType.Spell,
		hitZone = DamageTypes.HitZone.Torso,
		timestamp = os.clock(),
		cause = cause,
	})
end

return {
	name = "protect_blocks_in_window",

	setup = function(ctx: any)
		ctx.made = {}
	end,

	run = function(ctx: any)
		local model, humanoid = rig()
		table.insert(ctx.made, model)
		local controlModel, control = rig()
		table.insert(ctx.made, controlModel)

		-- Inside the window.
		Protection.grant(model, WINDOW_SEC)
		ctx.activeInside = Protection.isActive(model)
		ctx.resultInside = hit(humanoid, "FireballVolley")
		ctx.healthInside = humanoid.Health

		-- Control: no window, same hit.
		hit(control, "FireballVolley")
		ctx.controlHealth = control.Health

		-- After the window.
		task.wait(AFTER_WINDOW_WAIT_SEC)
		ctx.activeAfter = Protection.isActive(model)
		ctx.resultAfter = hit(humanoid, "FireballVolley")
		ctx.healthAfter = humanoid.Health

		-- The death-zone exemption, inside a long window.
		Protection.grant(model, LONG_WINDOW_SEC)
		local before = humanoid.Health
		hit(humanoid, DamageTypes.Cause.DeathZone)
		ctx.deathZoneLanded = humanoid.Health < before

		-- A window never shortens.
		local closesAt = Protection.closesAt(model) or 0
		Protection.grant(model, WINDOW_SEC)
		ctx.shortened = (Protection.closesAt(model) or 0) < closesAt
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.activeInside then
			return false, "the window was not active right after the grant"
		end
		if ctx.resultInside ~= nil or ctx.healthInside ~= START_HEALTH then
			return false, string.format("a hit inside the window was not dropped (result=%s, health=%s)",
				tostring(ctx.resultInside), tostring(ctx.healthInside))
		end
		if ctx.controlHealth ~= START_HEALTH - HIT then
			return false, string.format("the unprotected control took %s, expected %d",
				tostring(START_HEALTH - ctx.controlHealth), HIT)
		end
		if ctx.activeAfter then
			return false, "the window was still active after it should have closed"
		end
		if ctx.resultAfter == nil or ctx.healthAfter ~= START_HEALTH - HIT then
			return false, string.format("a hit after the window did not land (result=%s, health=%s)",
				tostring(ctx.resultAfter), tostring(ctx.healthAfter))
		end
		if not ctx.deathZoneLanded then
			return false, "a death-zone hit was blocked by protection"
		end
		if ctx.shortened then
			return false, "a shorter grant shortened the window"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		for _, instance in ctx.made do
			instance:Destroy()
		end
	end,
}
