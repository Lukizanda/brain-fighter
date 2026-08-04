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

local DamageTypes    = require(ReplicatedStorage.Shared.Health.DamageTypes)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillBuffs     = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local SkillInterrupt = require(ReplicatedStorage.Shared.Skills.SkillInterrupt)
local SkillTypes     = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)

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
-- `conns` holds the one-shot Died/Destroying cleanup connections; without
-- them a humanoid that dies or despawns mid-freeze leaks its entry forever
-- (the timer paths bail on the deadline check and never purge).
type FreezeState = {
	originalSpeed: number,
	restoreAt: number,
	conns: { RBXScriptConnection },
}
local _freezeState: { [Humanoid]: FreezeState } = {}

-- Timer callbacks fire a hair early; treat "within epsilon of the
-- deadline" as expired so an extend-then-restore race can't strand state.
local RESTORE_EPSILON_SEC = 0.01

-- Raise or drop the flag that drives the ice shards.
--
-- This handler runs on both VMs, and deliberately writes on both. The
-- server's write is the one that replicates, so every client sees a
-- frozen rig; the casting client's own write never leaves that machine
-- but paints its shards on the cast frame instead of after the round
-- trip. When the server's value lands it matches, so no second signal
-- fires. Same arrangement `_shield` uses — see [[systems/VisualEffects]].
--
-- Nothing here draws. `FreezeVfxController` owns every Instance.
local function setFrozenFlag(h: Humanoid, frozen: boolean)
	local character = h.Parent
	if not character then return end
	-- nil rather than false to clear: an attribute set to false still
	-- exists, and a rig would accumulate one dead flag per freeze it ever
	-- survived.
	character:SetAttribute(SkillConstants.FROZEN_ATTRIBUTE, if frozen then true else nil)
end

-- Single teardown path for a freeze: timer expiry passes
-- restoreSpeed=true, death/removal passes false (no point writing
-- WalkSpeed on a dead or destroyed humanoid).
local function purgeFreeze(h: Humanoid, restoreSpeed: boolean)
	local state = _freezeState[h]
	if not state then return end
	_freezeState[h] = nil
	for _, conn in state.conns do
		conn:Disconnect()
	end
	if restoreSpeed and h.Parent then
		h.WalkSpeed = state.originalSpeed
	end
	setFrozenFlag(h, false)
	SkillInterrupt.unsilence(h)
end

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
		-- Stasis-style debuffs multiply damage dealt TO this target. Applied
		-- here rather than in each branch's arithmetic so every damage path
		-- (applyDamage, MaxHP fraction, flat) honours it identically.
		local amp = SkillBuffs.damageAmp(h)
		if spec.useApplyDamage and _applyDamage then
			_applyDamage.process({
				sourcePlayer   = nil,
				targetHumanoid = h,
				baseDamage     = (spec.amount or 0) * amp,
				damageType     = spec.damageType or DamageTypes.DamageType.Bullet,
				hitZone        = spec.hitZone or DamageTypes.HitZone.Torso,
				timestamp      = os.clock(),
			})
		elseif spec.fractionOfMaxHP then
			local fraction: number = spec.fractionOfMaxHP
			h.Health = math.max(0, h.Health - fraction * h.MaxHealth * amp)
		else
			h.Health = math.max(0, h.Health - (spec.amount or 0) * amp)
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
					if s and os.clock() >= s.restoreAt - RESTORE_EPSILON_SEC then
						purgeFreeze(h, true)
					end
				end)
			end
		else
			state = { originalSpeed = h.WalkSpeed, restoreAt = now + duration, conns = {} }
			_freezeState[h] = state
			h.WalkSpeed = 0
			-- One-shot death/removal cleanup: the timer paths above never
			-- purge a humanoid that dies or despawns mid-freeze. HealthChanged
			-- backs up Died because the Dead state transition is unreliable on
			-- partial/synthetic rigs; purgeFreeze is idempotent so overlapping
			-- fires are harmless.
			table.insert(state.conns, h.Died:Connect(function()
				purgeFreeze(h, false)
			end))
			table.insert(state.conns, h.HealthChanged:Connect(function(health: number)
				if health <= 0 then purgeFreeze(h, false) end
			end))
			table.insert(state.conns, h.Destroying:Connect(function()
				purgeFreeze(h, false)
			end))
			-- Fresh freeze interrupts the target's pending scheduled casts
			-- (e.g. remaining shots of a FireballVolley stagger) AND silences
			-- any new casts the target tries to start while frozen — without
			-- silence, the boss state machine would just kick off another
			-- FireballVolley on its next Attack tick. Already-launched
			-- projectiles are independent and keep flying. Both ops are
			-- skipped on the extend-freeze branch because the target was
			-- already silenced when the first freeze landed.
			SkillInterrupt.cancelCastsBy(target)
			SkillInterrupt.silence(target)
			setFrozenFlag(h, true)
			task.delay(duration, function()
				local s = _freezeState[h]
				if s and os.clock() >= s.restoreAt - RESTORE_EPSILON_SEC then
					purgeFreeze(h, true)
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

	-- Grants a flat absorb pool. Falls back to the source the same way
	-- heal does, so a self-cast Shield (target=nil) lands on the caster.
	--
	-- The pool is only authoritative where `applyDamage` runs — the
	-- server. A client-set attribute never replicates upward, so a shield
	-- that isn't relayed through SpellCastService protects nothing; see
	-- wiki/systems/SkillPipeline.md § Damage paths.
	shield = function(spec: EffectSpec, target: any, source: any): Result
		local h = resolveHumanoid(target) or resolveHumanoid(source)
		if not h then return { ok = false, reason = "shield requires a Humanoid" } end
		local amount: number = spec.amount or 0
		if amount <= 0 then return { ok = false, reason = "shield requires a positive amount" } end
		if not SkillBuffs.grantShield(h, amount) then
			return { ok = false, reason = "shield target has no character Model" }
		end
		return { ok = true }
	end,

	-- Timed stat modifier. `buffKind` names the modifier (not `kind`,
	-- which is already taken by the effect dispatch itself).
	buff = function(spec: EffectSpec, target: any, source: any): Result
		local h = resolveHumanoid(target) or resolveHumanoid(source)
		if not h then return { ok = false, reason = "buff requires a Humanoid" } end
		local buffKind = spec.buffKind
		if typeof(buffKind) ~= "string" then
			return { ok = false, reason = "buff requires a buffKind" }
		end
		local magnitude: number = spec.magnitude or 1
		if not SkillBuffs.applyBuff(h, buffKind :: string, magnitude, spec.durationSec) then
			return { ok = false, reason = "buff target not resolvable" }
		end
		return { ok = true }
	end,
}

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Read-only probe: is `target` currently tracked by the freeze registry?
-- For tests/diagnostics — the 5.1 leak fix is verified by this going
-- false after a mid-freeze death or despawn.
function SkillEffects.isFrozen(target: any): boolean
	local h = resolveHumanoid(target)
	return h ~= nil and _freezeState[h] ~= nil
end

----------------------------------------------------------------------
-- Preconditions
----------------------------------------------------------------------
-- "Would this effect be refused?", answered without applying it.
--
-- Every reason an effect handler can return `ok = false` is knowable from
-- (spec, target, source) alone — none of them depends on the outcome of a
-- simulation. That is what lets CastAction check affordability and
-- resolvability BEFORE it drains, instead of draining, running the whole
-- thing, and refunding when it turns out the cast had nowhere to land.
--
-- These mirror the guards at the top of each handler exactly. They must
-- never be STRICTER than the handler, or a cast the game would have
-- honoured gets refused. Looser is survivable — the handler still refuses,
-- and CastAction's backstop refunds — but the pair is meant to agree, and
-- the Skills suite pins the ones that matter.
--
-- Pure. Reads only. Safe to call from a predicted run.
local function needsTargetHumanoid(reason: string)
	return function(_spec: EffectSpec, target: any, _source: any): Result
		if not resolveHumanoid(target) then return { ok = false, reason = reason } end
		return { ok = true }
	end
end

SkillEffects.preconditions = {
	damage  = needsTargetHumanoid("damage requires Humanoid target"),
	freeze  = needsTargetHumanoid("freeze requires Humanoid target"),

	-- knockup also needs somewhere to put the velocity.
	knockup = function(_spec: EffectSpec, target: any, _source: any): Result
		local h = resolveHumanoid(target)
		if not h then return { ok = false, reason = "knockup requires Humanoid target" } end
		local char = h.Parent
		local hrp = char and (char :: Model):FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then return { ok = false, reason = "no HumanoidRootPart" } end
		return { ok = true }
	end,

	-- heal, shield and buff all fall back to the source, so a self-cast
	-- with target = nil is legal for them and not for the two above.
	heal = function(_spec: EffectSpec, target: any, source: any): Result
		if not (resolveHumanoid(target) or resolveHumanoid(source)) then
			return { ok = false, reason = "heal requires a Humanoid" }
		end
		return { ok = true }
	end,

	shield = function(spec: EffectSpec, target: any, source: any): Result
		local h = resolveHumanoid(target) or resolveHumanoid(source)
		if not h then return { ok = false, reason = "shield requires a Humanoid" } end
		if (spec.amount or 0) <= 0 then
			return { ok = false, reason = "shield requires a positive amount" }
		end
		-- SkillBuffs.grantShield hangs the pool off the character Model, so
		-- a Humanoid with no Model ancestor cannot hold one.
		if not h:FindFirstAncestorOfClass("Model") then
			return { ok = false, reason = "shield target has no character Model" }
		end
		return { ok = true }
	end,

	buff = function(spec: EffectSpec, target: any, source: any): Result
		if not (resolveHumanoid(target) or resolveHumanoid(source)) then
			return { ok = false, reason = "buff requires a Humanoid" }
		end
		if typeof(spec.buffKind) ~= "string" then
			return { ok = false, reason = "buff requires a buffKind" }
		end
		return { ok = true }
	end,
}

-- Pure precondition check for one effect spec. Never mutates.
function SkillEffects.canApply(spec: EffectSpec, target: any, source: any?): Result
	local check = SkillEffects.preconditions[spec.kind]
	if not check then
		return { ok = false, reason = "unknown effect kind: " .. tostring(spec.kind) }
	end
	return check(spec, target, source)
end

function SkillEffects.apply(spec: EffectSpec, target: any, source: any?): Result
	local handler = SkillEffects.handlers[spec.kind]
	if not handler then
		log:warn(("unknown effect kind: %s"):format(tostring(spec.kind)))
		return { ok = false, reason = "unknown effect kind: " .. tostring(spec.kind) }
	end
	return handler(spec, target, source)
end

return SkillEffects
