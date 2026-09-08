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
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

local TEST_MAX_HEALTH = 100
local HEALTH_TOLERANCE = 0.01

local M = {}

local function nearly(a: number, b: number): boolean
	return math.abs(a - b) <= HEALTH_TOLERANCE
end

-- Build a fresh dummy Model+Humanoid+HumanoidRootPart parented to `script`
-- so it's discoverable in the explorer during a debug session but cleans
-- up when the test calls model:Destroy(). The HRP lets resolveTargetPosition
-- succeed for projectile-delivery spells, so the cast is allowed through
-- instead of being refused on "no resolvable target position".
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

	-- 1. castSpecific(red, 1) with red=80 (caps at 60) → Firebolt
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

	-- 2. castSpecific(red, 3) with red=15 → "cannot afford Inferno"
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

	-- 3. castSpecific("yellow", 1) → fizzle "invalid color/tier: …".
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

	-- 4. castSpecific(green, 1) target=nil → Mend (T1 heal, cost 5).
	--
	-- The point of this case is that a target-less heal is ACCEPTED: `heal`
	-- falls back to the caster. That distinction lives in
	-- SkillEffects.canApply and is what CastAction now gates on.
	--
	-- The heal landing is again not asserted here — predicted runs don't
	-- apply effects (Stage 3). Health starts at 50 anyway so that a
	-- regression putting the heal back would be visible as 65.
	-- (Why castSpecific instead of the highest-affordable tier: green=15
	-- affords both Mend T1 and Stone Wall T2, which has no heal.)
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
		assert(
			nearly(humanoid.Health, 50),
			`specific(green,1): predicted run must not heal; Health should still be 50, got {humanoid.Health}`
		)
		model:Destroy()
		r:destroy()
	end

	------------------------------------------------------------------
	-- resolveSpecAtCharge — hold-to-charge tier selection (Phase 5.8)
	------------------------------------------------------------------
	-- Pure: reads the reservoir and the clock, touches nothing. Hold
	-- durations are expressed as SpellRegistry.chargeTimeFor(t) rather
	-- than as literals, so these stay correct if MANA_FLOW_PER_SEC moves
	-- — and it is expected to, after the first feel-check playtest.

	local function chargeTime(tier: number): number
		return SpellRegistry.chargeTimeFor(tier)
	end

	-- Half the gap between two tiers' charge times. Used to sit a hold
	-- unambiguously *between* thresholds.
	local function midway(lowTier: number, highTier: number): number
		return (chargeTime(lowTier) + chargeTime(highTier)) / 2
	end

	-- 5. A hold on an empty reservoir never reaches T1, no matter how
	-- long. nil is the "cancel, cost nothing" signal — not a fizzled cast.
	do
		local r = EnergyReservoirs.new()
		local spec = CastAction.resolveSpecAtCharge("red", r, 10)
		assert(spec == nil, `charge red=0: should be nil, got "{spec and spec.name or "nil"}"`)
		r:destroy()
	end

	-- 6. A tap (zero hold) with plenty of mana fires T1, NOT the highest
	-- affordable tier — the player climbs to a big spell deliberately
	-- instead of being given one.
	do
		local r = EnergyReservoirs.new()
		r:add("red", 60)
		local spec = CastAction.resolveSpecAtCharge("red", r, 0)
		assert(spec ~= nil, "charge red=60 held=0: should resolve")
		local s = spec :: { name: string, tier: number }
		assert(s.tier == 1, `charge red=60 held=0: tier should be 1, got {s.tier}`)
		assert(s.name == "Firebolt", `charge red=60 held=0: name should be "Firebolt", got "{s.name}"`)
		assert(r:get("red") == 60, "charge is pure — reservoir must be untouched")
		r:destroy()
	end

	-- 7. The charge stops dead at the affordability ceiling. red=12 affords
	-- T1 (5) and T2 (10) but not T3 (20), so an arbitrarily long hold tops
	-- out at Fireball. This is the case the HUD's ceiling pulse marks.
	do
		local r = EnergyReservoirs.new()
		r:add("red", 12)
		local spec = CastAction.resolveSpecAtCharge("red", r, chargeTime(4) * 10)
		assert(spec ~= nil, "charge red=12 long hold: should resolve")
		local s = spec :: { name: string, tier: number }
		assert(s.tier == 2, `charge red=12 long hold: tier should clamp at 2, got {s.tier}`)
		assert(s.name == "Fireball", `charge red=12 long hold: name should be "Fireball", got "{s.name}"`)
		r:destroy()
	end

	-- 8. A hold sitting exactly ON a threshold resolves to the higher
	-- tier — the comparison is `chargeTimeFor(tier) <= heldSec`. Held one
	-- notch below it must still be the lower tier, which is what makes this
	-- an assertion about the boundary rather than about rounding luck.
	do
		local r = EnergyReservoirs.new()
		r:add("red", 60)

		local atThreshold = CastAction.resolveSpecAtCharge("red", r, chargeTime(3))
		assert(atThreshold ~= nil, "charge red=60 at T3 threshold: should resolve")
		assert(
			(atThreshold :: { tier: number }).tier == 3,
			`charge red=60 at T3 threshold: tier should be 3, got {(atThreshold :: { tier: number }).tier}`
		)

		local justBelow = CastAction.resolveSpecAtCharge("red", r, midway(2, 3))
		assert(justBelow ~= nil, "charge red=60 below T3 threshold: should resolve")
		assert(
			(justBelow :: { tier: number }).tier == 2,
			`charge red=60 below T3 threshold: tier should be 2, got {(justBelow :: { tier: number }).tier}`
		)

		r:destroy()
	end

	-- 9. Green and blue have no T4. Holding past red's T4 charge time with
	-- a full reservoir must still land on T3, because the roster ceiling
	-- binds before the clock does.
	do
		for _, color in { "green", "blue" } do
			local r = EnergyReservoirs.new()
			r:add(color :: any, 60)
			local spec = CastAction.resolveSpecAtCharge(color :: any, r, chargeTime(4) * 2)
			assert(spec ~= nil, `charge {color}=60 long hold: should resolve`)
			local s = spec :: { name: string, tier: number }
			assert(s.tier == 3, `charge {color}=60 long hold: tier should be 3 (no T4), got {s.tier}`)
			r:destroy()
		end
	end

	-- 10. chargeTimeFor is the contract the HUD and the resolver share, so
	-- pin its shape: T1 is free (a tap), and the times climb strictly with
	-- tier. A regression that made T1 cost time would make every tap fizzle.
	do
		assert(chargeTime(1) == 0, `chargeTimeFor(1) should be 0 (a tap), got {chargeTime(1)}`)
		for tier = 2, SpellRegistry.NUM_TIERS do
			assert(
				chargeTime(tier) > chargeTime(tier - 1),
				`chargeTimeFor must increase with tier; t{tier} = {chargeTime(tier)} vs t{tier - 1} = {chargeTime(tier - 1)}`
			)
		end
	end

	print("[CastAction.__tests] all scenarios passed")
	return true
end

return M
