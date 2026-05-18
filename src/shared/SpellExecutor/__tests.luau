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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SpellExecutor.Tests")

local TEST_MAX_HEALTH = 100
local TEST_WALK_SPEED = 16
local HEALTH_TOLERANCE = 0.01
local WALK_SPEED_TOLERANCE = 0.01
-- Slack on top of the 1s Frost Nip duration so the task.delay restore
-- has resolved before we assert. Empirically 0.15s is comfortable.
local FREEZE_WAIT_SEC = 1.15

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
		"damage 20% (Fireball) on 100/100 HP drops to 80",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("red", 2), humanoid, humanoid)
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 80, HEALTH_TOLERANCE, "Health after Fireball")
			model:Destroy()
		end,
	},
	{
		"damage on already-dead target clamps at 0",
		function()
			local model, humanoid = makeDummy(0)
			local res = SpellExecutor.cast(SpellRegistry.getSpell("red", 3), humanoid, humanoid)
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 0, HEALTH_TOLERANCE, "Health clamped")
			model:Destroy()
		end,
	},
	{
		"heal 15% (Mend) on 50/100 -> 65",
		function()
			local model, humanoid = makeDummy(50)
			local res = SpellExecutor.cast(SpellRegistry.getSpell("green", 1), humanoid, humanoid)
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
			local res = SpellExecutor.cast(spec, humanoid, humanoid)
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 100, HEALTH_TOLERANCE, "Health capped at MaxHealth")
			model:Destroy()
		end,
	},
	{
		"heal with nil target falls back to caster",
		function()
			local model, humanoid = makeDummy(50)
			local res = SpellExecutor.cast(SpellRegistry.getSpell("green", 1), humanoid, nil)
			expectEq(res.ok, true, "ok")
			expectNear(humanoid.Health, 65, HEALTH_TOLERANCE, "Heal applied to caster")
			model:Destroy()
		end,
	},
	{
		"freeze (Frost Nip 1s) sets WalkSpeed=0, restores after duration",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("blue", 1), humanoid, humanoid)
			expectEq(res.ok, true, "ok")
			expectEq(humanoid.WalkSpeed, 0, "WalkSpeed during freeze")
			task.wait(FREEZE_WAIT_SEC)
			expectNear(humanoid.WalkSpeed, TEST_WALK_SPEED, WALK_SPEED_TOLERANCE, "WalkSpeed restored")
			model:Destroy()
		end,
	},
	{
		"shield stub (Blue T2 Shield) returns ok=true",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("blue", 2), humanoid, humanoid)
			expectEq(res.ok, true, "ok")
			expectEq(res.reason, nil, "no reason on success")
			model:Destroy()
		end,
	},
	{
		"wall stub (Green T2 Stone Wall) accepts Vector3 target",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("green", 2), humanoid, Vector3.new(10, 0, 10))
			expectEq(res.ok, true, "ok")
			model:Destroy()
		end,
	},
	{
		"buff stub returns ok=true",
		function()
			local model, humanoid = makeDummy()
			-- No pure 'buff' spell exists in the prototype roster, so we
			-- synthesize a spec to cover the stub branch.
			local spec = makeSpec("buff", { durationSec = 5 }, "TestBuff")
			local res = SpellExecutor.cast(spec, humanoid, humanoid)
			expectEq(res.ok, true, "ok")
			model:Destroy()
		end,
	},
	{
		"unknown kind returns ok=false with reason mentioning the kind",
		function()
			local model, humanoid = makeDummy()
			local spec = makeSpec("lightning", {}, "WeirdSpell")
			local res = SpellExecutor.cast(spec, humanoid, humanoid)
			expectEq(res.ok, false, "ok")
			expectContains(res.reason, "lightning", "reason mentions kind")
			model:Destroy()
		end,
	},
	{
		"damage with nil target returns ok=false",
		function()
			local model, humanoid = makeDummy()
			local res = SpellExecutor.cast(SpellRegistry.getSpell("red", 1), humanoid, nil)
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
