--!strict

----------------------------------------------------------------------
-- SpellExecutor
----------------------------------------------------------------------
-- Runs a spell's effect against a caster/target. Dispatches on the
-- spec's effectSpec.kind discriminator.
--
-- MVP scope: damage, heal, freeze are fully implemented; shield, wall,
-- and buff are stubs that log + return ok=true so every spell in
-- SpellRegistry is CALLABLE end-to-end before the placement/buff
-- systems land (see wiki/design/build-plan.md Phase 2 / Phase 3).
--
-- Pure module — the only state we keep is per-Humanoid freeze
-- bookkeeping (so back-to-back freezes don't lose the saved
-- WalkSpeed). Caller owns cast cost, dictionary check, and targeting
-- UX; we trust the Spec came from SpellRegistry.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

local log = Logger.new("SpellExecutor")

-- Health clamp floor. Declared so the "clamp to 0" intent reads in
-- one place if we ever need a different lower bound (e.g., shields
-- that allow negative absorb pools).
local MIN_HEALTH = 0
-- task.delay re-arm threshold. If remaining time on a re-freeze is
-- below this, the restore fires immediately rather than scheduling
-- another microtask.
local RESTORE_REARM_SEC = 1e-3

export type CastResult = {
	ok: boolean,
	reason: string?,
}

type FreezeState = {
	originalSpeed: number,
	restoreAt: number,
}

-- Re-freezes EXTEND existing freezes (new expiry = max(current,
-- now+duration)) rather than replace the saved WalkSpeed. If we let
-- a second freeze overwrite originalSpeed it would record 0 (the
-- already-frozen speed) and fail to restore the true pre-freeze
-- value. Documented in wiki/systems/SpellExecutor.md.
local _freezeState: { [Humanoid]: FreezeState } = {}

local function resolveHumanoid(entity: Humanoid | Model | Vector3 | nil): Humanoid?
	if entity == nil then
		return nil
	end
	if typeof(entity) ~= "Instance" then
		return nil
	end
	local inst = entity :: Instance
	if inst:IsA("Humanoid") then
		return inst
	elseif inst:IsA("Model") then
		return inst:FindFirstChildOfClass("Humanoid")
	end
	return nil
end

local function isAlive(humanoid: Humanoid): boolean
	return humanoid.Parent ~= nil
end

local function fail(reason: string): CastResult
	return { ok = false, reason = reason }
end

local function success(): CastResult
	return { ok = true, reason = nil }
end

----------------------------------------------------------------------
-- Effect handlers
----------------------------------------------------------------------

local function applyDamage(spec: SpellRegistry.Spec, target: Humanoid?): CastResult
	if not target or not isAlive(target) then
		return fail("damage requires a Humanoid target")
	end
	local fraction: number = spec.effectSpec.fractionOfMaxHP
	local delta = fraction * target.MaxHealth
	local newHealth = target.Health - delta
	if newHealth < MIN_HEALTH then
		newHealth = MIN_HEALTH
	end
	target.Health = newHealth
	log:info(
		string.format(
			"%s -> %s, %.1f damage (Health %.1f/%.1f)",
			spec.name,
			target:GetFullName(),
			delta,
			target.Health,
			target.MaxHealth
		)
	)
	return success()
end

local function applyHeal(spec: SpellRegistry.Spec, target: Humanoid?): CastResult
	if not target or not isAlive(target) then
		return fail("heal requires a Humanoid target")
	end
	local fraction: number = spec.effectSpec.fractionOfMaxHP
	local delta = fraction * target.MaxHealth
	local newHealth = target.Health + delta
	if newHealth > target.MaxHealth then
		newHealth = target.MaxHealth
	end
	target.Health = newHealth
	log:info(
		string.format(
			"%s -> %s, %.1f heal (Health %.1f/%.1f)",
			spec.name,
			target:GetFullName(),
			delta,
			target.Health,
			target.MaxHealth
		)
	)
	return success()
end

local function applyFreeze(spec: SpellRegistry.Spec, target: Humanoid?): CastResult
	if not target or not isAlive(target) then
		return fail("freeze requires a Humanoid target")
	end
	local duration: number = spec.effectSpec.durationSec
	local now = os.clock()
	local newExpiry = now + duration

	local existing = _freezeState[target]
	if existing then
		if newExpiry > existing.restoreAt then
			existing.restoreAt = newExpiry
		end
		log:info(
			string.format(
				"%s -> %s, freeze extended (%.2fs remaining)",
				spec.name,
				target:GetFullName(),
				existing.restoreAt - now
			)
		)
		return success()
	end

	local state: FreezeState = {
		originalSpeed = target.WalkSpeed,
		restoreAt = newExpiry,
	}
	_freezeState[target] = state
	target.WalkSpeed = 0
	log:info(
		string.format(
			"%s -> %s, frozen for %.2fs (was WalkSpeed %.1f)",
			spec.name,
			target:GetFullName(),
			duration,
			state.originalSpeed
		)
	)

	local function tryRestore()
		if _freezeState[target] ~= state then
			return
		end
		local remaining = state.restoreAt - os.clock()
		if remaining > RESTORE_REARM_SEC then
			task.delay(remaining, tryRestore)
			return
		end
		_freezeState[target] = nil
		if isAlive(target) then
			target.WalkSpeed = state.originalSpeed
			log:info(
				string.format(
					"Freeze ended on %s, WalkSpeed -> %.1f",
					target:GetFullName(),
					state.originalSpeed
				)
			)
		end
	end

	task.delay(duration, tryRestore)
	return success()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

local SpellExecutor = {}

function SpellExecutor.cast(
	spec: SpellRegistry.Spec,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	local kind = spec.effectSpec.kind

	if kind == "damage" then
		return applyDamage(spec, resolveHumanoid(target))
	elseif kind == "heal" then
		-- Heal targets self when no explicit target is supplied — most
		-- "auto" heal spells (Mend, Sanctuary) are cast on the wizard.
		local resolved = if target == nil then resolveHumanoid(caster) else resolveHumanoid(target)
		return applyHeal(spec, resolved)
	elseif kind == "freeze" then
		return applyFreeze(spec, resolveHumanoid(target))
	elseif kind == "shield" then
		log:info(string.format("Shield stub — %s (caster=%s)", spec.name, tostring(caster)))
		return success()
	elseif kind == "wall" then
		log:info(string.format("Wall stub — %s at %s", spec.name, tostring(target)))
		return success()
	elseif kind == "buff" then
		log:info(string.format("Buff stub — %s (caster=%s)", spec.name, tostring(caster)))
		return success()
	end

	return fail(string.format("unknown effect kind: %s", tostring(kind)))
end

return SpellExecutor
