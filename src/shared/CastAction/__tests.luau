--!strict

----------------------------------------------------------------------
-- CastAction smoke tests
----------------------------------------------------------------------
-- Self-contained — exposes `M.run()` which throws on any assertion
-- failure and prints `[CastAction.__tests] all scenarios passed` on
-- success.
--
-- Tier costs pinned to SpellRegistry.TIER_COSTS = { 5, 10, 20, 40 }
-- (wiki/design/gameplay-loop.md § "Spell tier thresholds"). Energy
-- thresholds in the scenarios below are chosen so the highest
-- affordable tier matches the expected pick. If the cost table
-- changes, the thresholds and expected spells need to move too.
--
-- Projectile vs instant: Firebolt (T1) / Fireball (T2) / Volley (T4)
-- are projectile delivery. The dummy in these tests sits parented to
-- `script` (not workspace), so a launched projectile never finds a
-- collidable target — the cast still returns ok=true (delivery
-- accepted), but no health change is observable. Instant-delivery
-- spells (Inferno T3, Mend G-T1) still synchronously mutate Humanoid
-- health and are the canonical end-to-end damage/heal cases.
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

-- Build a fresh dummy Model+Humanoid+HumanoidRootPart parented to `script`
-- so it's discoverable in the explorer during a debug session but cleans
-- up when the test calls model:Destroy(). The HRP lets resolveTargetPosition
-- succeed for projectile-delivery spells, so the executor returns ok=true
-- instead of refunding on "no resolvable target position".
local function makeDummy(initialHealth: number?): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = "CastActionTestDummy"
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = TEST_MAX_HEALTH
	humanoid.Health = initialHealth or TEST_MAX_HEALTH
	humanoid.Parent = model
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Anchored = true
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Parent = model
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

	-- 2. tapReservoir red=15 → Fireball (T2, cost 10); red=5.
	-- Fireball is projectile delivery — cast accepted, but the dummy
	-- isn't a Player or tagged, so no on-hit damage applies. We assert
	-- the cast pipeline, not damage.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 15)
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == true, `tap red=15: ok should be true, got reason "{tostring(res.reason)}"`)
		assert(res.cast ~= nil, "tap red=15: cast should be present")
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Fireball", `tap red=15: name should be "Fireball", got "{tostring(cast.name)}"`)
		assert(cast.tier == 2, `tap red=15: tier should be 2, got {tostring(cast.tier)}`)
		assert(cast.color == "red", `tap red=15: color should be "red", got "{tostring(cast.color)}"`)
		assert(res.drained == 10, `tap red=15: drained should be 10, got {tostring(res.drained)}`)
		assert(r:get("red") == 5, `tap red=15: reservoir.red should be 5, got {r:get("red")}`)
		model:Destroy()
		r:destroy()
	end

	-- 3. tapReservoir red=30 → Inferno (T3, cost 20); red=10; HP 100→50.
	-- Inferno is instant delivery — synchronous damage applies.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 30)
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == true, `tap red=30: ok should be true, got reason "{tostring(res.reason)}"`)
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Inferno", `tap red=30: name should be "Inferno", got "{tostring(cast.name)}"`)
		assert(cast.tier == 3, `tap red=30: tier should be 3, got {tostring(cast.tier)}`)
		assert(res.drained == 20, `tap red=30: drained should be 20, got {tostring(res.drained)}`)
		assert(r:get("red") == 10, `tap red=30: reservoir.red should be 10, got {r:get("red")}`)
		assert(nearly(humanoid.Health, 50), `tap red=30: Health should be 50 after Inferno (0.5×MaxHP), got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	-- 4. tapReservoir red=160 (caps at CAP_PER_COLOR=60) → Volley
	-- (T4, cost 40); red ends 20 (60 − 40).
	-- Volley is projectile delivery — cast accepted, no damage observable.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 160)
		local res = CastAction.tapReservoir("red", r, humanoid, humanoid)
		assert(res.ok == true, `tap red=160: ok should be true, got reason "{tostring(res.reason)}"`)
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Volley", `tap red=160: name should be "Volley", got "{tostring(cast.name)}"`)
		assert(cast.tier == 4, `tap red=160: tier should be 4, got {tostring(cast.tier)}`)
		assert(res.drained == 40, `tap red=160: drained should be 40, got {tostring(res.drained)}`)
		assert(r:get("red") == 20, `tap red=160: reservoir.red should be 20 (60 cap − 40), got {r:get("red")}`)
		model:Destroy()
		r:destroy()
	end

	-- 5. castSpecific(red, 1) with red=80 (caps at 60) → Firebolt
	-- (T1, cost 5); red ends 55. Firebolt is projectile — assert cast,
	-- not damage.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 80)
		local res = CastAction.castSpecific("red", 1, r, humanoid, humanoid)
		assert(res.ok == true, `specific(red,1) red=80: ok should be true, got reason "{tostring(res.reason)}"`)
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Firebolt", `specific(red,1): name should be "Firebolt", got "{tostring(cast.name)}"`)
		assert(cast.tier == 1, `specific(red,1): tier should be 1, got {tostring(cast.tier)}`)
		assert(res.drained == 5, `specific(red,1): drained should be 5, got {tostring(res.drained)}`)
		assert(r:get("red") == 55, `specific(red,1): reservoir.red should be 55 (60 cap − 5), got {r:get("red")}`)
		model:Destroy()
		r:destroy()
	end

	-- 6. castSpecific(red, 3) with red=15 → "cannot afford Inferno"
	-- (Inferno costs 20); red unchanged at 15.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 15)
		local res = CastAction.castSpecific("red", 3, r, humanoid, humanoid)
		assert(res.ok == false, "specific(red,3) red=15: ok should be false")
		assert(res.reason ~= nil, "specific(red,3) red=15: reason should be present")
		local reason = res.reason :: string
		assert(
			string.find(reason, "cannot afford", 1, true) ~= nil,
			`specific(red,3) red=15: reason should mention "cannot afford", got "{reason}"`
		)
		assert(
			string.find(reason, "Inferno", 1, true) ~= nil,
			`specific(red,3) red=15: reason should mention "Inferno", got "{reason}"`
		)
		assert(r:get("red") == 15, `specific(red,3) red=15: reservoir.red should remain 15, got {r:get("red")}`)
		assert(nearly(humanoid.Health, TEST_MAX_HEALTH), "specific(red,3) red=15: Health untouched")
		model:Destroy()
		r:destroy()
	end

	-- 7. castSpecific("yellow", 1) → fizzle "invalid color/tier: …".
	-- SpellRegistry.getSpell raises on unknown color; CastAction
	-- pcalls and surfaces a uniform {ok=false, reason=…} return.
	do
		local model, humanoid = makeDummy()
		local r = EnergyReservoirs.new()
		r:add("red", 100) -- caps at 60; shouldn't be consumed
		local res = CastAction.castSpecific("yellow" :: any, 1, r, humanoid, humanoid)
		assert(res.ok == false, "specific(yellow,1): ok should be false")
		assert(res.reason ~= nil, "specific(yellow,1): reason should be present")
		local reason = res.reason :: string
		assert(
			string.find(reason, "invalid", 1, true) ~= nil,
			`specific(yellow,1): reason should mention "invalid", got "{reason}"`
		)
		assert(
			string.find(reason, "yellow", 1, true) ~= nil
				or string.find(reason, "color", 1, true) ~= nil,
			`specific(yellow,1): reason should mention "yellow" or "color", got "{reason}"`
		)
		assert(r:get("red") == 60, "specific(yellow,1): no energy drained (cap 60)")
		model:Destroy()
		r:destroy()
	end

	-- 8. tapReservoir red=15 target=nil → Fireball is projectile; with
	-- target=nil there's no resolvable target position, so the executor
	-- refuses ({ok=false, reason="projectile requires a target …"}) and
	-- CastAction REFUNDS so red ends back at 15.
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
		assert(nearly(humanoid.Health, TEST_MAX_HEALTH), "refund: Health untouched")
		model:Destroy()
		r:destroy()
	end

	-- 9. castSpecific(green, 1) target=nil → Mend (T1 heal, cost 5).
	-- Heal target=nil falls back to caster; pass the dummy as caster and
	-- set its Health to 50 so the +15% MaxHealth heal lands observably.
	-- (Why castSpecific instead of tapReservoir: green=15 affords both
	-- Mend T1 and Stone Wall T2; tap would pick T2 which has no heal.)
	do
		local model, humanoid = makeDummy(50)
		local r = EnergyReservoirs.new()
		r:add("green", 15)
		local res = CastAction.castSpecific("green", 1, r, humanoid, nil)
		assert(res.ok == true, `specific(green,1) nil target: ok should be true, got "{tostring(res.reason)}"`)
		local cast = res.cast :: { color: string, tier: number, name: string }
		assert(cast.name == "Mend", `specific(green,1): name should be "Mend", got "{tostring(cast.name)}"`)
		assert(cast.color == "green", `specific(green,1): color should be "green", got "{tostring(cast.color)}"`)
		assert(res.drained == 5, `specific(green,1): drained should be 5, got {tostring(res.drained)}`)
		assert(r:get("green") == 10, `specific(green,1): reservoir.green should be 10, got {r:get("green")}`)
		-- Mend = +15% MaxHealth = +15. 50 + 15 = 65.
		assert(nearly(humanoid.Health, 65), `specific(green,1): Health should be 65 after Mend, got {humanoid.Health}`)
		model:Destroy()
		r:destroy()
	end

	print("[CastAction.__tests] all scenarios passed")
	return true
end

return M
