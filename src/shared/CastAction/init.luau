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

-- Drain → execute → refund-on-failure pipeline. Used by both
-- tapReservoir and castSpecific once the caller has nailed down a
-- concrete `spec`.
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

	local executorResult = SpellExecutor.cast(spec, caster, target)
	if executorResult.ok then
		log:info(string.format("cast ok — %s (color=%s tier=%d cost=%d)", spec.name, spec.color, spec.tier, spec.cost))
		return success(spec)
	end

	-- SpellExecutor refused (e.g. damage spell with target=nil). Refund
	-- so the player doesn't lose mana to a downstream rejection.
	reservoirs:add(spec.color, spec.cost)
	local reason = executorResult.reason or "executor returned ok=false without a reason"
	log:info(string.format("cast refunded — %s (%s)", spec.name, reason))
	return fail(reason)
end

-- Tap-cast: fire the highest currently-affordable tier of `color`.
-- Returns `{ ok = false, reason = "no affordable tier" }` when the
-- reservoir can't even afford T1 (cost 10) — the HUD can decide
-- whether to surface a fizzle animation.
function CastAction.tapReservoir(
	color: Color,
	reservoirs: EnergyReservoirs.EnergyReservoirs,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	local energy = reservoirs:get(color)
	local affordable = SpellRegistry.listAffordableSpells(color, energy)
	if #affordable == 0 then
		log:info(string.format("tap fizzle — %s reservoir below T1 (energy=%d)", color, energy))
		return fail(NO_AFFORDABLE_TIER)
	end

	-- listAffordableSpells is sorted ascending; highest affordable is
	-- the last entry.
	local spec = affordable[#affordable]
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
