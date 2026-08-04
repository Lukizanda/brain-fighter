--!strict

----------------------------------------------------------------------
-- SpellExecutor smoke tests
----------------------------------------------------------------------
-- Run via execute_luau:
--
--   local M = require(game.ReplicatedStorage.Shared.SpellExecutor.__tests)
--   local passed, failed = M.runAll()
--
-- Logs "[TEST PASS]" / "[TEST FAIL]" lines so output is parseable.
-- Test dummies are parented to `script` (this ModuleScript), so they
-- live under ReplicatedStorage.Shared.SpellExecutor.__tests during
-- the run and are Destroyed at the end of each case.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local SkillBuffs = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SpellExecutor.Tests")

local TEST_MAX_HEALTH = 100
local TEST_WALK_SPEED = 16
local HEALTH_TOLERANCE = 0.01
local WALK_SPEED_TOLERANCE = 0.01
-- Frost Nip's freeze duration is read from the registry so this test
-- tracks tuning changes (it was originally written against a 1s freeze
-- that was later tuned to 3s and went stale). Slack covers the
-- task.delay restore resolving after the duration elapses.
local FREEZE_RESTORE_SLACK_SEC = 0.25
local function frostNipFreezeSec(): number
	for _, entry in SpellRegistry.getSpell("blue", 1).skill.onImpact do
		if (entry :: any).kind == "freeze" then
			return (entry :: any).durationSec
		end
	end
	error("Frost Nip freeze entry not found in registry")
end
-- Fireball projectile test geometry: the tagged target sits this far
-- from the caster, high above the map so death zones, NPCs, and the
-- boss can't interfere with the flight path or splash.
local PROJECTILE_TARGET_DISTANCE = 10
local PROJECTILE_TEST_ALTITUDE = 400
local PROJECTILE_HIT_TIMEOUT_SEC = 3
local PROJECTILE_HIT_POLL_SEC = 0.05

local M = {}

local function expectEq(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("[%s] expected %s, got %s", label, tostring(expected), tostring(actual)),
			2
		)
	end
end

local function expectNear(actual: number, expected: number, tolerance: number, label: string)
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"[%s] expected ~%s (±%s), got %s",
				label,
				tostring(expected),
				tostring(tolerance),
				tostring(actual)
			),
			2
		)
	end
end

local function expectContains(haystack: string?, needle: string, label: string)
	if not haystack or not string.find(haystack, needle, 1, true) then
		error(
			string.format("[%s] expected substring %q, got %s", label, needle, tostring(haystack)),
			2
		)
	end
end

local function makeDummy(initialHealth: number?, walkSpeed: number?): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = "SpellExecutorTestDummy"
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = TEST_MAX_HEALTH
	humanoid.Health = initialHealth or TEST_MAX_HEALTH
	humanoid.WalkSpeed = walkSpeed or TEST_WALK_SPEED
	humanoid.Parent = model
	model.Parent = script
	return model, humanoid
end

local function makeSpec(kind: string, params: { [string]: any }, name: string?): SpellRegistry.Spec
	local specName = name or string.format("Test%s", kind)
	local onImpactEntry: { [string]: any } = { kind = kind }
	for k, v in params do
		onImpactEntry[k] = v
	end
	return {
		name          = specName,
		color         = "red" :: any,
		tier          = 1,
		cost          = 10,
		targetingMode = "auto" :: any,
		skill         = {
			name           = specName,
			delivery       = "instant",
			deliveryParams = {},
			onImpact       = { onImpactEntry :: any },
		} :: any,
	}
end

local cases: { { any } } = {
	{
		"damage 20% (Fireball) projectile hits tagged target, 100 -> 80",
		function()
			-- Projectile delivery skips the caster, aims at the target's
			-- HumanoidRootPart, and only detects models carrying a
			-- Damageable/NPC/Boss tag — so this needs a real two-rig setup
			-- in workspace, not the self-cast the old instant path allowed.
			local function makeRig(name: string, xOffset: number): (Model, Humanoid)
				local model, humanoid = makeDummy()
				model.Name = name
				local hrp = Instance.new("Part")
				hrp.Name = "HumanoidRootPart"
				hrp.Anchored = true
				hrp.CanCollide = false
				hrp.Size = Vector3.new(2, 2, 1)
				hrp.CFrame = CFrame.new(xOffset, PROJECTILE_TEST_ALTITUDE, 0)
				hrp.Parent = model
				model.Parent = workspace
				return model, humanoid
			end

			local casterModel, casterHumanoid = makeRig("FireballTestCaster", 0)
			local targetModel, targetHumanoid = makeRig("FireballTestTarget", PROJECTILE_TARGET_DISTANCE)
			CollectionService:AddTag(targetModel, "Damageable")

			local res = SpellExecutor.cast(SpellRegistry.getSpell("red", 2), casterHumanoid, targetHumanoid, "authoritative")
			expectEq(res.ok, true, "ok")

			local deadline = os.clock() + PROJECTILE_HIT_TIMEOUT_SEC
			while targetHumanoid.Health > 80 + HEALTH_TOLERANCE and os.clock() < deadline do
				task.wait(PROJECTILE_HIT_POLL_SEC)
			end
			expectNear(targetHumanoid.Health, 80, HEALTH_TOLERANCE, "Health after Fireball impact")

			casterModel:Destroy()
			targetModel:Destroy()
		end,
	},
	{
		"damage on already-dead target clamps at 0",
		function()
			local model, humanoid = makeDummy(0)
			local res = SpellExecutor.cast(SpellRegistry.getSpell("red", 3), humanoid, humanoid, "authoritative")
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 0, HEALTH_TOLERANCE, "Health clamped")
			model:Destroy()
		end,
	},
	{
		"heal 15% (Mend) on 50/100 -> 65",
		function()
			local model, humanoid = makeDummy(50)
			local res = SpellExecutor.cast(SpellRegistry.getSpell("green", 1), humanoid, humanoid, "authoritative")
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 65, HEALTH_TOLERANCE, "Health after Mend")
			model:Destroy()
		end,
	},
	{
		"heal 50% on 95/100 caps at 100",
		function()
			local model, humanoid = makeDummy(95)
			local spec = makeSpec("heal", { fractionOfMaxHP = 0.50 }, "TestBigHeal")
			local res = SpellExecutor.cast(spec, humanoid, humanoid, "authoritative")
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 100, HEALTH_TOLERANCE, "Health capped at MaxHealth")
			model:Destroy()
		end,
	},
	{
		"heal with nil target falls back to caster",
		function()
			local model, humanoid = makeDummy(50)
			local res = SpellExecutor.cast(SpellRegistry.getSpell("green", 1), humanoid, nil, "authoritative")
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 65, HEALTH_TOLERANCE, "Heal applied to caster")
			model:Destroy()
		end,
	},
	{
		"freeze (Frost Nip) sets WalkSpeed=0, restores after registry duration",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("blue", 1), humanoid, humanoid, "authoritative")
			expectEq(res.ok, true, "ok")
			expectEq(humanoid.WalkSpeed, 0, "WalkSpeed during freeze")
			task.wait(frostNipFreezeSec() + FREEZE_RESTORE_SLACK_SEC)
			expectNear(humanoid.WalkSpeed, TEST_WALK_SPEED, WALK_SPEED_TOLERANCE, "WalkSpeed restored")
			model:Destroy()
		end,
	},
	-- Phase 5.2: shield / world_spawn / buff are real. These three were the
	-- 5.1 "fails with unimplemented so the cast refunds" cases.
	{
		"shield (Blue T2 Shield) grants an absorb pool on the caster",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("blue", 2), humanoid, humanoid, "authoritative")
			expectEq(res.ok, true, "ok")
			if SkillBuffs.getShield(humanoid) <= 0 then
				error("expected a positive shield pool after casting Shield", 2)
			end
			model:Destroy()
		end,
	},
	{
		"world_spawn (Green T2 Stone Wall) succeeds at a placement point",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("green", 2), humanoid, Vector3.new(10, 0, 10), "authoritative")
			-- Succeeds on both VMs, but only the server spawns the barrier:
			-- a client-side Part can't block the server-owned boss, and the
			-- server's copy replicates down. The client branch returns ok so
			-- CastAction doesn't refund a cast the server is about to honour.
			expectEq(res.ok, true, "ok")
			model:Destroy()
		end,
	},
	{
		"buff applies a damageAmp that multiplies subsequent damage",
		function()
			local model, humanoid = makeDummy()
			-- No pure 'buff' spell exists in the roster (Stasis pairs it with
			-- a freeze), so synthesize a spec to isolate the branch.
			local spec = makeSpec("buff", { buffKind = "damageAmp", magnitude = 2.0, durationSec = 5 }, "TestBuff")
			local res = SpellExecutor.cast(spec, humanoid, humanoid, "authoritative")
			expectEq(res.ok, true, "ok")
			expectEq(SkillBuffs.damageAmp(humanoid), 2.0, "damageAmp")
			model:Destroy()
		end,
	},
	{
		"unknown kind returns ok=false with reason mentioning the kind",
		function()
			local model, humanoid = makeDummy()
			local spec = makeSpec("lightning", {}, "WeirdSpell")
			local res = SpellExecutor.cast(spec, humanoid, humanoid, "authoritative")
			expectEq(res.ok, false, "ok")
			expectContains(res.reason, "lightning", "reason mentions kind")
			model:Destroy()
		end,
	},
	{
		"damage with nil target returns ok=false",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("red", 1), humanoid, nil, "authoritative")
			expectEq(res.ok, false, "ok")
			expectContains(res.reason, "target", "reason mentions target")
			model:Destroy()
		end,
	},
}

function M.runAll(): (number, number)
	local passed, failed = 0, 0
	for _, case in cases do
		local label = case[1] :: string
		local fn = case[2] :: () -> ()
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			log:info(string.format("[TEST PASS] %s", label))
		else
			failed += 1
			log:warn(string.format("[TEST FAIL] %s — %s", label, tostring(err)))
		end
	end
	log:info(string.format("[SPELLEXECUTOR TESTS] %d passed, %d failed", passed, failed))
	return passed, failed
end

return M
