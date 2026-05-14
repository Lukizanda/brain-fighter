--!strict

----------------------------------------------------------------------
-- CastAction smoke tests
----------------------------------------------------------------------
-- Self-contained — exposes `M.run()` which throws on any assertion
-- failure and prints `[CastAction.__tests] all scenarios passed` on
-- success.
--
-- Covers the nine scenarios from NIM-10:
--   1. tapReservoir red=0  → "no affordable tier", reservoir unchanged.
--   2. tapReservoir red=15 → casts Spark (T1, 10); red=5; HP 100→95.
--   3. tapReservoir red=50 → casts Fireball (T2, 30); red=20; HP 100→80.
--   4. tapReservoir red=160 (provided as 160 — exceeds 80 brief value
--      to verify the cap doesn't trip; brief said 160 → Inferno) →
--      casts Inferno (T3, 80); red=80; HP 100→50.
--   5. castSpecific(red,1) red=80 → casts Spark deliberately (save big);
--      red ends 70.
--   6. castSpecific(red,3) red=50 → fizzle "cannot afford Inferno";
--      red unchanged at 50.
--   7. castSpecific("yellow",1) → fizzle, reason mentions invalid color.
--   8. tapReservoir red=15 target=nil → executor refuses (damage
--      needs target); CastAction REFUNDS so red ends 15; result.ok=false
--      with reason mentioning target.
--   9. tapReservoir green=15 target=nil → Mend is a heal spell; the
--      executor falls back to the caster's Humanoid. Verify the heal
--      lands on the caster (re-using the same dummy as both caster and
--      target sink); reservoir drains by 10.
--
-- These tests are synchronous — CastAction calls only synchronous
-- methods. EnergyReservoirs.changed is Deferred, but we read state via
-- `:get(color)` which reflects the direct mutation immediately. See
-- wiki/systems/EnergyReservoirs.md § "Signal semantics".
--
-- Usage:
--   require(ReplicatedStorage.Shared.CastAction.__tests).run()
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CastAction = require(ReplicatedStorage.Shared.CastAction)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local TEST_MAX_HEALTH = 100
local HEALTH_TOLERANCE = 0.01

local M = {}

local function nearly(a: number, b: number): boolean
	return math.abs(a - b) <= HEALTH_TOLERANCE
end

-- Build a fresh dummy Model+Humanoid parented to `script` so it's
-- discoverable in the explorer during a debug session but cleans up
-- when the test calls model:Destroy().
local function makeDummy(initialHealth: number?): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = "CastActionTestDummy"
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = TEST_MAX_HEALTH
	humanoid.Health = initialHealth or TEST_MAX_HEALTH
	humanoid.Parent = model
	model.Parent = script
	return model, humanoid
end

function M.run()
	print("[CastAction.__tests] starting")

	-- 1. tapReservoir red=0 → "no affordable tier".
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == false, "tap red=0: ok should be false")
		assert(
			res.reason == "no affordable tier",
			`tap red=0: reason should be "no affordable tier", got "{tostring(res.reason)}"`
		)
		assert(res.cast == nil, "tap red=0: cast should be nil on failure")
		assert(res.drained == nil, "tap red=0: drained should be nil on failure")
		assert(r:get("red") == 0, "tap red=0: reservoir should remain 0")
		assert(nearly(humanoid.Health, TEST_MAX_HEALTH), "tap red=0: Health should be untouched")
		model:Destroy()
		r:destroy()
	end

	-- 2. tapReservoir red=15 → Spark (T1, cost 10); red=5; HP 100→95.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 15)
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == true, "tap red=15: ok should be true")
		assert(res.cast ~= nil, "tap red=15: cast should be present")
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Spark", `tap red=15: name should be "Spark", got "{tostring(cast.name)}"`)
		assert(cast.tier == 1, `tap red=15: tier should be 1, got {tostring(cast.tier)}`)
		assert(cast.color == "red", `tap red=15: color should be "red", got "{tostring(cast.color)}"`)
		assert(res.drained == 10, `tap red=15: drained should be 10, got {tostring(res.drained)}`)
		assert(r:get("red") == 5, `tap red=15: reservoir.red should be 5, got {r:get("red")}`)
		assert(nearly(humanoid.Health, 95), `tap red=15: Health should be 95, got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	-- 3. tapReservoir red=50 → Fireball (T2, cost 30); red=20; HP 100→80.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 50)
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == true, "tap red=50: ok should be true")
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Fireball", `tap red=50: name should be "Fireball", got "{tostring(cast.name)}"`)
		assert(cast.tier == 2, `tap red=50: tier should be 2, got {tostring(cast.tier)}`)
		assert(res.drained == 30, `tap red=50: drained should be 30, got {tostring(res.drained)}`)
		assert(r:get("red") == 20, `tap red=50: reservoir.red should be 20, got {r:get("red")}`)
		assert(nearly(humanoid.Health, 80), `tap red=50: Health should be 80, got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	-- 4. tapReservoir red=160 → Inferno (T3, cost 80); red=80; HP 100→50.
	--    Brief says "red=160" (the EnergyReservoirs cap); same energy as
	--    160 since Inferno costs 80 the highest tier still applies.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 160)
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == true, "tap red=160: ok should be true")
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Inferno", `tap red=160: name should be "Inferno", got "{tostring(cast.name)}"`)
		assert(cast.tier == 3, `tap red=160: tier should be 3, got {tostring(cast.tier)}`)
		assert(res.drained == 80, `tap red=160: drained should be 80, got {tostring(res.drained)}`)
		assert(r:get("red") == 80, `tap red=160: reservoir.red should be 80, got {r:get("red")}`)
		assert(nearly(humanoid.Health, 50), `tap red=160: Health should be 50, got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	-- 5. castSpecific(red, 1) with red=80 → Spark (deliberately, even
	--    though Inferno is also affordable); red ends 70; HP 100→95.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 80)
		local res = CastAction.castSpecific("red", 1, r, humanoid, humanoid)
		assert(res.ok == true, "specific(red,1) red=80: ok should be true")
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Spark", `specific(red,1): name should be "Spark", got "{tostring(cast.name)}"`)
		assert(cast.tier == 1, `specific(red,1): tier should be 1, got {tostring(cast.tier)}`)
		assert(res.drained == 10, `specific(red,1): drained should be 10, got {tostring(res.drained)}`)
		assert(r:get("red") == 70, `specific(red,1): reservoir.red should be 70, got {r:get("red")}`)
		assert(nearly(humanoid.Health, 95), `specific(red,1): Health should be 95, got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	-- 6. castSpecific(red, 3) with red=50 → "cannot afford Inferno";
	--    red unchanged at 50.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 50)
		local res = CastAction.castSpecific("red", 3, r, humanoid, humanoid)
		assert(res.ok == false, "specific(red,3) red=50: ok should be false")
		assert(res.reason ~= nil, "specific(red,3) red=50: reason should be present")
		local reason = res.reason :: string
		assert(
			string.find(reason, "cannot afford", 1, true) ~= nil,
			`specific(red,3) red=50: reason should mention "cannot afford", got "{reason}"`
		)
		assert(
			string.find(reason, "Inferno", 1, true) ~= nil,
			`specific(red,3) red=50: reason should mention "Inferno", got "{reason}"`
		)
		assert(r:get("red") == 50, `specific(red,3) red=50: reservoir.red should remain 50, got {r:get("red")}`)
		assert(nearly(humanoid.Health, TEST_MAX_HEALTH), "specific(red,3) red=50: Health untouched")
		model:Destroy()
		r:destroy()
	end

	-- 7. castSpecific("yellow", 1) → fizzle "invalid color/tier: …".
	--    SpellRegistry.getSpell raises on unknown color; CastAction
	--    pcalls and surfaces a uniform {ok=false, reason=…} return.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 100) -- shouldn't be consumed
		local res = CastAction.castSpecific("yellow" :: any, 1, r, humanoid, humanoid)
		assert(res.ok == false, "specific(yellow,1): ok should be false")
		assert(res.reason ~= nil, "specific(yellow,1): reason should be present")
		local reason = res.reason :: string
		assert(
			string.find(reason, "invalid", 1, true) ~= nil,
			`specific(yellow,1): reason should mention "invalid", got "{reason}"`
		)
		-- The underlying SpellRegistry error string contains the offending
		-- color literal; verify we propagated enough of it through.
		assert(
			string.find(reason, "yellow", 1, true) ~= nil
				or string.find(reason, "color", 1, true) ~= nil,
			`specific(yellow,1): reason should mention "yellow" or "color", got "{reason}"`
		)
		assert(r:get("red") == 100, "specific(yellow,1): no energy drained")
		model:Destroy()
		r:destroy()
	end

	-- 8. tapReservoir red=15 target=nil → executor refuses (Spark
	--    needs a damage target); CastAction REFUNDS so red ends back
	--    at 15; result.ok=false with reason mentioning target.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 15)
		local res = CastAction.tapReservoir("red", r, humanoid, nil)
		assert(res.ok == false, "refund: ok should be false")
		assert(res.reason ~= nil, "refund: reason should be present")
		local reason = res.reason :: string
		assert(
			string.find(reason, "target", 1, true) ~= nil,
			`refund: reason should mention "target", got "{reason}"`
		)
		assert(r:get("red") == 15, `refund: reservoir.red should be refunded back to 15, got {r:get("red")}`)
		assert(nearly(humanoid.Health, TEST_MAX_HEALTH), "refund: Health untouched (caster was the dummy, not target)")
		model:Destroy()
		r:destroy()
	end

	-- 9. tapReservoir green=15 target=nil → Mend (T1 heal). Heal
	--    target=nil falls back to caster; pass the dummy as caster and
	--    set its Health to 50 so the +15% heal is observable.
	do
		local model, humanoid = makeDummy(50)
		local r = EnergyReservoirs.new()
		r:add("green", 15)
		local res = CastAction.tapReservoir("green", r, humanoid, nil)
		assert(res.ok == true, "tap green=15 nil target: ok should be true")
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Mend", `tap green=15: name should be "Mend", got "{tostring(cast.name)}"`)
		assert(cast.color == "green", `tap green=15: color should be "green", got "{tostring(cast.color)}"`)
		assert(res.drained == 10, `tap green=15: drained should be 10, got {tostring(res.drained)}`)
		assert(r:get("green") == 5, `tap green=15: reservoir.green should be 5, got {r:get("green")}`)
		-- Mend = +15% MaxHealth = +15. 50 + 15 = 65.
		assert(nearly(humanoid.Health, 65), `tap green=15: Health should be 65 after Mend, got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	print("[CastAction.__tests] all scenarios passed")
	return true
end

return M
