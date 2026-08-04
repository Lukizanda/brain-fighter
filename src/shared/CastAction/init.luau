--!strict

----------------------------------------------------------------------
-- CastAction
----------------------------------------------------------------------
-- The "Cast" step of the gameplay loop (see
-- wiki/design/gameplay-loop.md § "Cast (reservoir-driven)"). Wires the
-- two cast UX gestures into actual spell fires:
--
--   tap a reservoir         → CastAction.tapReservoir(color, …)
--                             fires the highest currently-affordable
--                             tier of that color (casual fast path).
--   drag-from → release on  → CastAction.castSpecific(color, tier, …)
--   tier entry                fires that specific tier (strategic
--                             path; supports "save big, fire small").
--
-- Both gestures resolve to the same pipeline:
--   1. Look up the spec.       (SpellRegistry)
--   2. Verify affordability.   (EnergyReservoirs:canAfford / get)
--   3. Drain the cost.         (EnergyReservoirs:drain)
--   4. Run the effect.         (SpellExecutor.cast)
--   5. On executor failure, REFUND the cost — if the executor refuses
--      (e.g. damage spell with no target), the player shouldn't lose
--      mana. The refund policy is documented in
--      wiki/systems/CastAction.md.
--
-- CastAction owns no state. It's a thin seam between three Phase 1/2
-- modules so the cast contract lives in one file rather than scattered
-- across HUD handlers (per concepts/SingleOwnership: only CastAction
-- writes via `:drain` on the reservoirs).
--
-- Tracker [NIM-10] — wiki/design/build-plan.md Phase 2.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)

local log = Logger.new("CastAction")

local NO_AFFORDABLE_TIER = "no affordable tier"

export type Color = SpellRegistry.Color

export type CastSummary = {
	color: Color,
	tier: number,
	name: string,
}

export type CastResult = {
	ok: boolean,
	reason: string?,
	cast: CastSummary?,
	drained: number?,
}

local CastAction = {}

-- Fires on the casting client's VM after every successful cast.
-- Server VM creates the same BindableEvent but no listener connects there.
local _spellResolvedBindable = Instance.new("BindableEvent")
CastAction.spellResolved = _spellResolvedBindable.Event :: RBXScriptSignal

local function fail(reason: string): CastResult
	return { ok = false, reason = reason }
end

local function success(spec: SpellRegistry.Spec): CastResult
	return {
		ok = true,
		cast = {
			color = spec.color,
			tier = spec.tier,
			name = spec.name,
		},
		drained = spec.cost,
	}
end

-- Validate → drain → execute pipeline. Used by both tapReservoir and
-- castSpecific once the caller has nailed down a concrete `spec`.
--
-- The order used to be drain → execute → refund if the executor refused.
-- That worked only because the caster's client ran the whole spell itself
-- and could see the refusal. It doesn't survive the delivery moving
-- server-side, and it was never necessary: every reason a cast can be
-- refused is knowable up front from (spec, target). So the check happens
-- before the reservoir is touched, and a refused cast costs nothing
-- because nothing was ever taken.
--
-- Drain MUST be guaranteed affordable by the caller before invocation
-- (we assert with the EnergyReservoirs contract — if `drain` returns
-- false here, the call site is buggy, not the user).
local function drainAndCast(
	spec: SpellRegistry.Spec,
	reservoirs: EnergyReservoirs.EnergyReservoirs,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	local resolvable = SpellExecutor.canCast(spec, caster, target)
	if not resolvable.ok then
		local reason = resolvable.reason or "cast cannot resolve"
		log:info(string.format("cast refused — %s (%s)", spec.name, reason))
		return fail(reason)
	end

	local drained = reservoirs:drain(spec.color, spec.cost)
	if not drained then
		-- Caller bug: didn't gate on canAfford before invoking. Report
		-- as a hard error rather than silently fizzling — the contract
		-- with EnergyReservoirs is that drain is total or not at all.
		error(
			string.format(
				"CastAction: drain(%s, %d) failed despite affordability check — caller contract violation",
				spec.color,
				spec.cost
			),
			2
		)
	end

	-- Always "predicted": CastAction is the client cast path by
	-- construction — it drains the client-owned reservoir, and the server
	-- enters the pipeline through SpellCastService instead. The
	-- authoritative run of this same cast happens there.
	-- No predictedBy: this run IS the prediction, and it draws directly
	-- rather than broadcasting, so there is nobody to exclude.
	local executorResult = SpellExecutor.cast(spec, caster, target, { mode = "predicted" })
	if executorResult.ok then
		log:info(string.format("cast ok — %s (color=%s tier=%d cost=%d)", spec.name, spec.color, spec.tier, spec.cost))
		_spellResolvedBindable:Fire(spec, caster, target)
		return success(spec)
	end

	-- Backstop, and it should be unreachable: canCast just said this would
	-- resolve. Reaching here means a precondition in SkillEffects or
	-- SkillDelivery disagrees with the handler it mirrors. Refund anyway —
	-- the player shouldn't pay for our bug — and warn, because a silent
	-- refund here would hide the drift indefinitely.
	reservoirs:add(spec.color, spec.cost)
	local reason = executorResult.reason or "executor returned ok=false without a reason"
	log:warn(string.format(
		"cast refunded — %s (%s). canCast passed but the cast refused; " ..
		"a precondition has drifted from its handler.",
		spec.name, reason
	))
	return fail(reason)
end

-- Which spell would a tap on this reservoir fire right now? Returns nil
-- when the reservoir can't afford even T1.
--
-- Exposed because the caller has to know the spell *before* the cast in
-- order to prepare for it — the HUD needs it to decide whether to hunt
-- for an enemy target (see SpellRegistry.needsEnemyTarget). Keeping the
-- selection rule here means the HUD can't drift out of sync with what
-- tapReservoir actually picks.
function CastAction.resolveTapSpec(
	color: Color,
	reservoirs: EnergyReservoirs.EnergyReservoirs
): SpellRegistry.Spec?
	local affordable = SpellRegistry.listAffordableSpells(color, reservoirs:get(color))
	-- listAffordableSpells is sorted ascending; highest affordable is last.
	return affordable[#affordable]
end

-- Tap-cast: fire the highest currently-affordable tier of `color`.
-- Returns `{ ok = false, reason = "no affordable tier" }` when the
-- reservoir can't even afford T1 (cost 5) — the HUD can decide
-- whether to surface a fizzle animation.
function CastAction.tapReservoir(
	color: Color,
	reservoirs: EnergyReservoirs.EnergyReservoirs,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	local spec = CastAction.resolveTapSpec(color, reservoirs)
	if not spec then
		log:info(string.format("tap fizzle — %s reservoir below T1 (energy=%d)", color, reservoirs:get(color)))
		return fail(NO_AFFORDABLE_TIER)
	end

	return drainAndCast(spec, reservoirs, caster, target)
end

-- Drag-cast: fire the explicitly-chosen `(color, tier)` spell. The
-- player saw the menu and picked this tier deliberately — usually the
-- "save big, fire small" path where the highest affordable is *not*
-- what they want.
--
-- Invalid color/tier (validation lives in SpellRegistry.getSpell) is
-- caught here via pcall and surfaced as a uniform `{ ok = false }`
-- return — callers benefit from a single failure shape instead of
-- having to wrap CastAction in their own pcall.
function CastAction.castSpecific(
	color: Color,
	tier: number,
	reservoirs: EnergyReservoirs.EnergyReservoirs,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	local lookupOk, specOrErr = pcall(SpellRegistry.getSpell, color, tier)
	if not lookupOk then
		log:info(string.format("castSpecific fizzle — invalid color/tier: %s", tostring(specOrErr)))
		return fail(string.format("invalid color/tier: %s", tostring(specOrErr)))
	end
	local spec = specOrErr :: SpellRegistry.Spec

	if not reservoirs:canAfford(color, spec.cost) then
		log:info(
			string.format(
				"castSpecific fizzle — cannot afford %s (cost %d, have %d)",
				spec.name,
				spec.cost,
				reservoirs:get(color)
			)
		)
		return fail(string.format("cannot afford %s (cost %d, have %d)", spec.name, spec.cost, reservoirs:get(color)))
	end

	return drainAndCast(spec, reservoirs, caster, target)
end

return CastAction
