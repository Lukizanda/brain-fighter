--!strict

----------------------------------------------------------------------
-- SkillBuffs
----------------------------------------------------------------------
-- Per-Humanoid registry for the two status effects that aren't freeze:
--
--   buff   — timed stat modifiers (currently only "damageAmp", the
--            multiplier Stasis puts on a frozen target so follow-up
--            spells hit harder).
--   shield — a flat absorb pool that eats incoming damage before it
--            reaches Health.
--
-- Why the shield is an attribute and the buffs are a table:
-- `DamageModifierRegistry.shieldModifier` (shared/Health) already reads
-- and drains a `_shield` attribute off the character Model inside
-- `applyDamage.process` — the exact path boss attacks take. Storing the
-- pool anywhere else would mean reimplementing absorption on a path
-- that already has it. So ownership splits: Skills *grants* the pool,
-- Health *drains* it. Nothing else writes the attribute.
--
-- Buffs have no such consumer, so they live in a plain per-Humanoid
-- table read by SkillEffects.damage at apply time.
--
-- Registry semantics are per-VM, same as SkillInterrupt: the client
-- casts player spells and the server re-applies them via
-- SpellCastService, so both VMs build their own view.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)

export type BuffKind = "damageAmp"

-- expiresAt = nil means the buff runs until purged (death/despawn).
type BuffEntry = {
	magnitude: number,
	expiresAt: number?,
}

local NO_AMP = 1.0

local _buffs: { [Humanoid]: { [string]: BuffEntry } } = {}

-- One-shot Died/HealthChanged/Destroying connections, hooked the first
-- time a humanoid gains a buff or a shield. Mirrors SkillInterrupt: the
-- happy paths (expiry, absorb-to-zero) don't cover a humanoid that dies
-- mid-effect, and an indefinite shield has no timer to fall back on.
local _cleanupConns: { [Humanoid]: { RBXScriptConnection } } = {}

local function resolveHumanoid(target: any): Humanoid?
	if typeof(target) ~= "Instance" then return nil end
	local inst = target :: Instance
	if inst:IsA("Humanoid") then return inst :: Humanoid end
	if inst:IsA("Model") then return (inst :: Model):FindFirstChildOfClass("Humanoid") end
	return nil
end

local function resolveCharacter(h: Humanoid): Model?
	return h:FindFirstAncestorOfClass("Model")
end

-- Drop every entry for `h` and disconnect its hooks. Idempotent — the
-- three cleanup signals can all fire for one death.
local function purge(h: Humanoid)
	local conns = _cleanupConns[h]
	if conns then
		_cleanupConns[h] = nil
		for _, conn in conns do
			conn:Disconnect()
		end
	end
	_buffs[h] = nil
	local character = resolveCharacter(h)
	if character then
		character:SetAttribute(HealthConstants.SHIELD_ATTRIBUTE, nil)
	end
end

local function ensureCleanupHook(h: Humanoid)
	if _cleanupConns[h] then return end
	local conns: { RBXScriptConnection } = {}
	_cleanupConns[h] = conns
	table.insert(conns, h.Died:Connect(function()
		purge(h)
	end))
	-- Backs up Died, which never fires on partial/synthetic rigs.
	table.insert(conns, h.HealthChanged:Connect(function(health: number)
		if health <= 0 then purge(h) end
	end))
	table.insert(conns, h.Destroying:Connect(function()
		purge(h)
	end))
end

local SkillBuffs = {}

-- The pool projects a spherical shell around its holder, centred on
-- HumanoidRootPart. Two systems have to agree on it exactly: SkillDelivery
-- stops projectiles at its surface, and ShieldVfx draws the bubble. If they
-- disagree, shots die on empty air or pass visibly through the glass.
--
-- Fixed rather than measured off the live rig: a bounding box breathes with
-- the walk animation, and a hit volume that grows and shrinks per frame is
-- neither testable nor fair. 4.2 studs comfortably contains an R15 rig (HRP
-- sits mid-torso, ~2.8 studs below the top of the head) and matches the
-- bubble that shipped with the visual.
SkillBuffs.SHELL_RADIUS_STUDS = 4.2

-- What deflecting one projectile costs the pool.
--
-- Flat, and deliberately far below what the shot would have dealt. The
-- shell is a barrier that destroys projectiles, not a damage sponge that
-- happens to stop them: charging full damage per deflection made a 40
-- pool worth 2.6 of Brain's fireballs, which inside a 30-shot volley is
-- indistinguishable from no shield at all.
--
-- Damage that arrives any other way — GroundSlam, melee, anything that
-- reaches the body — still drains the pool at full value through
-- `DamageModifierRegistry.shieldModifier`. The asymmetry is the point:
-- deflection is cheap, absorption is not.
SkillBuffs.SHELL_BLOCK_COST = 5

----------------------------------------------------------------------
-- Buffs
----------------------------------------------------------------------

-- Apply a timed stat modifier. A second application of the same kind
-- overwrites rather than stacks — re-casting Stasis on an already-
-- amplified target refreshes the window instead of squaring the
-- multiplier.
function SkillBuffs.applyBuff(target: any, buffKind: string, magnitude: number, durationSec: number?): boolean
	local h = resolveHumanoid(target)
	if not h then return false end
	ensureCleanupHook(h)
	local entries = _buffs[h]
	if not entries then
		entries = {}
		_buffs[h] = entries
	end
	entries[buffKind] = {
		magnitude = magnitude,
		expiresAt = durationSec and (os.clock() + durationSec) or nil,
	}
	return true
end

-- Expiry is evaluated lazily on read rather than by a timer: an expired
-- entry on a living humanoid is harmless (it's filtered here) and bounded
-- by the number of buff kinds, while death and despawn are covered by
-- purge. That removes a whole class of timer/death races.
local function readBuff(h: Humanoid, buffKind: string): number?
	local entries = _buffs[h]
	if not entries then return nil end
	local entry = entries[buffKind]
	if not entry then return nil end
	if entry.expiresAt and os.clock() >= entry.expiresAt then
		entries[buffKind] = nil
		if next(entries) == nil then _buffs[h] = nil end
		return nil
	end
	return entry.magnitude
end

-- Multiplier applied to damage dealt TO this target. 1.0 when unbuffed.
function SkillBuffs.damageAmp(target: any): number
	local h = resolveHumanoid(target)
	if not h then return NO_AMP end
	return readBuff(h, "damageAmp") or NO_AMP
end

-- Read-only probe for tests/diagnostics.
function SkillBuffs.hasBuff(target: any, buffKind: string): boolean
	local h = resolveHumanoid(target)
	return h ~= nil and readBuff(h, buffKind) ~= nil
end

----------------------------------------------------------------------
-- Shield
----------------------------------------------------------------------

-- Add `amount` to the target's absorb pool. Pools are additive so a
-- Sanctuary layered on a Shield is worth both, and they carry no expiry
-- — the pool lasts until damage drains it or the holder dies (design
-- call 2026-08-03; give it a duration here if playtest says otherwise).
function SkillBuffs.grantShield(target: any, amount: number): boolean
	local h = resolveHumanoid(target)
	if not h then return false end
	local character = resolveCharacter(h)
	if not character then return false end
	ensureCleanupHook(h)
	local existing = character:GetAttribute(HealthConstants.SHIELD_ATTRIBUTE)
	local current = typeof(existing) == "number" and (existing :: number) or 0
	character:SetAttribute(HealthConstants.SHIELD_ATTRIBUTE, current + amount)
	return true
end

-- Drain up to `amount` from the pool; returns how much was actually
-- absorbed (0 when unshielded).
--
-- This is the second of exactly two drain sites. The other is
-- `DamageModifierRegistry.shieldModifier`, which handles damage that
-- reaches the body through `applyDamage`. This one handles damage that
-- never gets there because the shell stopped it — a projectile eaten at
-- the bubble never runs an effect handler at all, so it has no other way
-- to charge the pool. Player spells make the split load-bearing rather
-- than cosmetic: they write Humanoid.Health directly and never touch
-- `applyDamage`, so without this a blocked player projectile would drain
-- nothing. Still nothing else writes the attribute.
function SkillBuffs.consumeShield(target: any, amount: number): number
	if amount <= 0 then return 0 end
	local h = resolveHumanoid(target)
	if not h then return 0 end
	local character = resolveCharacter(h)
	if not character then return 0 end
	local existing = character:GetAttribute(HealthConstants.SHIELD_ATTRIBUTE)
	local current = typeof(existing) == "number" and (existing :: number) or 0
	if current <= 0 then return 0 end
	local absorbed = math.min(current, amount)
	character:SetAttribute(HealthConstants.SHIELD_ATTRIBUTE, current - absorbed)
	return absorbed
end

-- Remaining absorb pool, 0 when unshielded. Read-only — the drain side
-- belongs to `consumeShield` and DamageModifierRegistry.
function SkillBuffs.getShield(target: any): number
	local h = resolveHumanoid(target)
	if not h then return 0 end
	local character = resolveCharacter(h)
	if not character then return 0 end
	local existing = character:GetAttribute(HealthConstants.SHIELD_ATTRIBUTE)
	return typeof(existing) == "number" and (existing :: number) or 0
end

-- Exposed for tests and for future respawn wiring; normal teardown runs
-- off the Died/Destroying hooks.
function SkillBuffs.purge(target: any)
	local h = resolveHumanoid(target)
	if h then purge(h) end
end

return SkillBuffs
