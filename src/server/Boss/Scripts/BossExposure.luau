--!strict

----------------------------------------------------------------------
-- BossExposure
----------------------------------------------------------------------
-- The boss's vulnerability windows (wiki/design/boss-movement.md § Vulnerability
-- windows, stage 11c; numbers in BossConfig, `exposed*`):
--   * after an attack listed in `exposedAfterAttackSec` (the Brain: Ground
--     Slam) the boss is stuck for that long: stunned (it stands still in
--     Cooldown and cannot leave it) and exposed;
--   * when its word ward breaks it staggers with its core open: exposed for
--     `exposedOnWardBreakSec`.
-- While exposed every hit on it is multiplied by `exposedDamageMultiplier`.
--
-- Who owns what. This object decides WHEN the boss is stunned or exposed; it
-- is one small object per boss like BossWard and BossHunger, called by
-- BossController (`onAttackFinished`, `onWardBroken`, `tick`). The stun hold
-- itself is BossStates' (it reads `stunnedUntil` off the blackboard, which
-- only this object writes). How much a hit does is a damage rule and belongs
-- to Health: this object opens a window through `shared/Health/Vulnerability`
-- and never touches Humanoid.Health, so spore pops and spells are multiplied
-- alike and the ward's health floor still cuts a multiplied hit.
--
-- What the player sees: `ExposedUntil` and `StunnedUntil` on the boss Model,
-- in workspace:GetServerTimeNow() time (the only clock both VMs share), read
-- by the client puppet's Exposed pose layer. Cleared once the window closes.
--
-- Switched off, with no cost, for a type without a multiplier above 1.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Vulnerability = require(ReplicatedStorage.Shared.Health.Vulnerability)

local log = Logger.new("BossExposure")

local BossExposure = {}
BossExposure.__index = BossExposure

export type BossExposureInstance = typeof(setmetatable(
	{} :: {
		_boss: Model,
		_bb: BossTypes.BossBlackboard,
		_afterAttackSec: { [string]: number },
		_onWardBreakSec: number,
		_multiplier: number,
		_destroyed: boolean,
	},
	BossExposure
))

-- Does this boss type have vulnerability windows at all?
function BossExposure.isEnabledFor(spec: BossTypes.BossTypeSpec): boolean
	local multiplier = spec.exposedDamageMultiplier
	return multiplier ~= nil and multiplier > 1
end

-- Nil when the type has no windows, so the controller holds nothing for it.
function BossExposure.new(boss: Model, bb: BossTypes.BossBlackboard, spec: BossTypes.BossTypeSpec): BossExposureInstance?
	if not BossExposure.isEnabledFor(spec) then
		return nil
	end
	return setmetatable({
		_boss = boss,
		_bb = bb,
		_afterAttackSec = spec.exposedAfterAttackSec or {},
		_onWardBreakSec = spec.exposedOnWardBreakSec or 0,
		_multiplier = spec.exposedDamageMultiplier :: number,
		_destroyed = false,
	}, BossExposure)
end

-- Open (or extend) the exposed window: the multiplier through Health, the
-- instant for the client.
function BossExposure._expose(self: BossExposureInstance, sec: number, why: string)
	local closesAt = Vulnerability.grant(self._boss, sec, self._multiplier)
	self._boss:SetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE, closesAt)
	log:info(string.format("%s exposed %.1f s (%s), damage x%.2f", self._boss.Name, sec, why, self._multiplier))
end

-- Hold the boss still for `sec`. A stun never shortens one already running.
function BossExposure._stun(self: BossExposureInstance, sec: number)
	local bb = self._bb
	bb.stunnedUntil = math.max(bb.stunnedUntil or 0, os.clock() + sec)
	local closesAt = workspace:GetServerTimeNow() + sec
	local published = self._boss:GetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE)
	if typeof(published) == "number" and published > closesAt then
		closesAt = published
	end
	self._boss:SetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE, closesAt)
end

-- An attack has finished (BossStates calls the blackboard's onAttackFinished
-- on entering Cooldown).
function BossExposure.onAttackFinished(self: BossExposureInstance, attack: string)
	if self._destroyed then
		return
	end
	local sec = self._afterAttackSec[attack]
	if sec == nil or sec <= 0 then
		return
	end
	self:_stun(sec)
	self:_expose(sec, attack)
end

-- The word ward's last letter was popped.
function BossExposure.onWardBroken(self: BossExposureInstance)
	if self._destroyed or self._onWardBreakSec <= 0 then
		return
	end
	self:_expose(self._onWardBreakSec, "ward broken")
end

function BossExposure.isExposed(self: BossExposureInstance): boolean
	return Vulnerability.multiplierFor(self._boss) > 1
end

function BossExposure.isStunned(self: BossExposureInstance): boolean
	local untilAt = self._bb.stunnedUntil
	return untilAt ~= nil and os.clock() < untilAt
end

-- Called every Heartbeat by BossController: take down the published
-- instants once their windows have closed. (Nothing depends on this to stop
-- the multiplier or the stun; both are read against the clock.)
function BossExposure.tick(self: BossExposureInstance)
	if self._destroyed then
		return
	end
	local now = workspace:GetServerTimeNow()
	local exposedUntil = self._boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE)
	if typeof(exposedUntil) == "number" and now >= exposedUntil then
		self._boss:SetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE, nil)
		Vulnerability.clear(self._boss)
	end
	local stunnedUntil = self._boss:GetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE)
	if typeof(stunnedUntil) == "number" and now >= stunnedUntil then
		self._boss:SetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE, nil)
	end
end

-- The controller is going (boss dead, round ended): no window outlives it.
function BossExposure.destroy(self: BossExposureInstance)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._bb.stunnedUntil = nil
	self._boss:SetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE, nil)
	self._boss:SetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE, nil)
	Vulnerability.clear(self._boss)
end

return BossExposure
