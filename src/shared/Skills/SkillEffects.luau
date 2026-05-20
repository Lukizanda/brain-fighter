--!strict

----------------------------------------------------------------------
-- SkillEffects
----------------------------------------------------------------------
-- Pure effect handlers for the unified skill pipeline.
-- Each handler: (spec, target, source?) → Result
--
-- Never branches on caster type. Context-specific concerns (cost,
-- mana, staff tips, cooldowns) stay in the caller (SpellExecutor or
-- BossStates). Registries receive only the EffectSpec and an opaque
-- target/source.
--
-- Damage paths:
--   useApplyDamage = true  → applyDamage.process (server-only, boss attacks)
--   fractionOfMaxHP        → direct MaxHealth fraction (client spells)
--   amount (default)       → direct flat damage write
--
-- applyDamage is conditionally loaded (nil on client); the useApplyDamage
-- branch is silently skipped when nil (client uses direct Health write).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local Logger      = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes  = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local FreezeVfx   = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.FreezeVfx)

type EffectSpec = SkillTypes.EffectSpec

export type Result = { ok: boolean, reason: string? }

local log = Logger.new("SkillEffects")

-- Server-only; nil on client. Boss attacks use applyDamage.process;
-- player spells use direct Health writes (client-authoritative).
local _applyDamage: { process: (any) -> any? }? = nil
if RunService:IsServer() then
	local ss = game:GetService("ServerScriptService")
	local ok, mod = pcall(require, ss.Server.Health.Scripts.HealthService.applyDamage)
	if ok then
		_applyDamage = mod
	else
		log:warn("applyDamage not found on server — useApplyDamage path disabled")
	end
end

-- Per-Humanoid freeze bookkeeping. Re-freezes extend the expiry
-- rather than overwriting the saved WalkSpeed (which would record 0).
local _freezeState: { [Humanoid]: { originalSpeed: number, restoreAt: number } } = {}

local function resolveHumanoid(target: any): Humanoid?
	if typeof(target) ~= "Instance" then return nil end
	local inst = target :: Instance
	if inst:IsA("Humanoid") then return inst :: Humanoid end
	if inst:IsA("Model") then return (inst :: Model):FindFirstChildOfClass("Humanoid") end
	return nil
end

----------------------------------------------------------------------
-- Handlers
----------------------------------------------------------------------

local SkillEffects = {}

SkillEffects.handlers = {

	damage = function(spec: EffectSpec, target: any, source: any): Result
		local h = resolveHumanoid(target)
		if not h then return { ok = false, reason = "damage requires Humanoid target" } end
		if spec.useApplyDamage and _applyDamage then
			_applyDamage.process({
				sourcePlayer   = nil,
				targetHumanoid = h,
				baseDamage     = spec.amount or 0,
				damageType     = spec.damageType or DamageTypes.DamageType.Bullet,
				hitZone        = spec.hitZone or DamageTypes.HitZone.Torso,
				timestamp      = os.clock(),
			})
		elseif spec.fractionOfMaxHP then
			local fraction: number = spec.fractionOfMaxHP
			h.Health = math.max(0, h.Health - fraction * h.MaxHealth)
		else
			h.Health = math.max(0, h.Health - (spec.amount or 0))
		end
		return { ok = true }
	end,

	heal = function(spec: EffectSpec, target: any, source: any): Result
		-- Heals the target if present, else falls back to the source (self-heal).
		local h = resolveHumanoid(target) or resolveHumanoid(source)
		if not h then return { ok = false, reason = "heal requires a Humanoid" } end
		local fraction: number = spec.fractionOfMaxHP or 0
		h.Health = math.min(h.MaxHealth, h.Health + fraction * h.MaxHealth)
		return { ok = true }
	end,

	freeze = function(spec: EffectSpec, target: any, _source: any): Result
		local h = resolveHumanoid(target)
		if not h then return { ok = false, reason = "freeze requires Humanoid target" } end
		local duration: number = spec.durationSec or 1.0
		local now = os.clock()
		local state = _freezeState[h]
		if state then
			-- Extend the freeze; reschedule cleanup only if the deadline moved
			local extended = math.max(state.restoreAt, now + duration)
			if extended > state.restoreAt then
				state.restoreAt = extended
				task.delay(extended - now, function()
					local s = _freezeState[h]
					if s and os.clock() >= s.restoreAt - 0.01 then
						if h.Parent then h.WalkSpeed = s.originalSpeed end
						FreezeVfx.stop(h)
						_freezeState[h] = nil
					end
				end)
			end
		else
			state = { originalSpeed = h.WalkSpeed, restoreAt = now + duration }
			_freezeState[h] = state
			h.WalkSpeed = 0
			FreezeVfx.start(h, duration)
			task.delay(duration, function()
				local s = _freezeState[h]
				if s and os.clock() >= s.restoreAt - 0.01 then
					if h.Parent then h.WalkSpeed = s.originalSpeed end
					FreezeVfx.stop(h)
					_freezeState[h] = nil
				end
			end)
		end
		return { ok = true }
	end,

	knockup = function(spec: EffectSpec, target: any, _source: any): Result
		local h = resolveHumanoid(target)
		if not h then return { ok = false, reason = "knockup requires Humanoid target" } end
		local force: number = spec.force or 50
		local char = h.Parent
		local hrp = char and (char :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then return { ok = false, reason = "no HumanoidRootPart" } end
		local bp = hrp :: BasePart
		bp.AssemblyLinearVelocity = Vector3.new(
			bp.AssemblyLinearVelocity.X,
			force,
			bp.AssemblyLinearVelocity.Z
		)
		return { ok = true }
	end,

	-- Stubs for future systems; always succeed so every spell in the
	-- registry is callable end-to-end before those systems ship.
	shield = function(spec: EffectSpec, _target: any, _source: any): Result
		log:info(("shield stub — durationSec=%s"):format(tostring(spec.durationSec)))
		return { ok = true }
	end,

	buff = function(spec: EffectSpec, _target: any, _source: any): Result
		log:info(("buff stub — kind=%s"):format(tostring(spec.kind)))
		return { ok = true }
	end,

	wall = function(spec: EffectSpec, _target: any, _source: any): Result
		log:info(("wall stub — durationSec=%s"):format(tostring(spec.durationSec)))
		return { ok = true }
	end,
}

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function SkillEffects.apply(spec: EffectSpec, target: any, source: any?): Result
	local handler = SkillEffects.handlers[spec.kind]
	if not handler then
		log:warn(("unknown effect kind: %s"):format(tostring(spec.kind)))
		return { ok = false, reason = "unknown effect kind: " .. tostring(spec.kind) }
	end
	return handler(spec, target, source)
end

return SkillEffects
