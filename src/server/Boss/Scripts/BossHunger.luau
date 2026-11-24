--!strict

----------------------------------------------------------------------
-- BossHunger
----------------------------------------------------------------------
-- "Hungry brain" with the letter pull (Phase 8 stage 9,
-- wiki/design/boss-arena.md § Letter pull). Every `eatIntervalSec` the living
-- boss with no letter already in tow picks the nearest eligible letter block
-- within `eatRadius` studs of itself, measured horizontally (the letters
-- float well above the boss), in its own arena, and starts pulling it toward
-- itself in two phases ("lash and yank"). The MARK holds the letter where it
-- is for `eatMarkSec`; a player can pop it. The YANK then carries it to the
-- boss over `eatSnapSec` on an ease-in (TowCurve), following the boss as the
-- boss moves, and it lands exactly at the end of the yank. When it lands (it
-- is within `eatReach` studs of the boss's root) it is eaten and the boss
-- heals `eatHealFraction` of its maximum health. A player can pop the letter
-- at any point first; the boss then goes hungry and the interval starts again
-- from zero.
--
-- One small object per boss, ticked by BossController alongside perception and
-- the state machine. It exists because the boss's own behaviour belongs to the
-- Boss system, but it is not an AI state: hunger runs whatever the boss is
-- doing (walking, winding up an attack), so it is a timer beside the state
-- machine rather than a state in it. The controller is created only after the
-- boss has spawned and stops ticking when it dies, which gives "not during the
-- entrance" and "not when dead" for free; the hold before an entrance spawn
-- has no controller at all.
--
-- It does not touch blocks. BlockSpawner owns them, including a block's
-- position while it is in tow: this asks the arena's pool, through
-- BlockPoolRegistry, to begin a tow (the pool excludes word-kit letters and
-- freed fossil letters by construction), tells it each tick where the boss is
-- now, and learns whether the block is still moving, arrived or is gone. The
-- heal goes through Health's `applyDamage.heal`, the one writer of
-- Humanoid.Health. What the player sees goes through VfxBroadcast (the heal
-- cue) and through the tow state the pool publishes on the block, which a
-- client script draws as a tether; nothing here draws and nothing makes a
-- sound of its own.
--
-- Switched off, with no cost, when `eatIntervalSec` or `eatRadius` is missing
-- or 0 or less. A type that has both but no positive `eatMarkSec`,
-- `eatSnapSec` or `eatReach` is a config mistake and also does not eat, with
-- a warning. (`eatPullSpeed` is legacy and only the fight simulator reads it.)
-- `eatHealFraction` 0 or missing still pulls and eats, heals nothing and
-- sends no heal cue.
--
-- Frozen: while its character carries the `_frozen` attribute
-- (SkillConstants.FROZEN_ATTRIBUTE, written by SkillEffects' freeze, the only
-- status that holds a boss today; no stun status exists in the code) the
-- boss does not advance a letter in tow (the mark timer does not run, the yank
-- does not move; it hangs where it is) and the interval does not run, so a
-- thaw neither bites at once nor loses the meal. Clients are told the clock is
-- stopped, and given the shifted times on the thaw.
--
-- Ending: a letter in tow is removed (the pool's normal removal, so the zone
-- refills as after a pop) when the boss dies, when its controller is
-- destroyed or when the round ends (BossController.destroy calls destroy()).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local TowCurve = require(ReplicatedStorage.Shared.BlockSpawner.TowCurve)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BlockPoolRegistry = require(ServerScriptService.Server.BlockSpawner.BlockPoolRegistry)

local log = Logger.new("BossHunger")

local BossHunger = {}
BossHunger.__index = BossHunger

export type BossHungerInstance = typeof(setmetatable(
	{} :: {
		_boss: Model,
		_humanoid: Humanoid,
		_root: BasePart,
		_intervalSec: number,
		_radius: number,
		_markSec: number,
		_snapSec: number,
		-- Seconds the tow in progress has run (mark, then yank), not
		-- counting time the boss was frozen.
		_towClockSec: number,
		-- How far along the yank the letter was placed last tick (0..1).
		_snapFraction: number,
		-- The published schedule says the clock is stopped (frozen).
		_schedulePaused: boolean,
		_reach: number,
		_healFraction: number,
		-- Seconds the interval has run since the last pull attempt or the
		-- end of the last tow.
		_elapsedSec: number,
		-- The letter being pulled, if any. At most one.
		_tow: BlockPoolRegistry.Tow?,
		_destroyed: boolean,
	},
	BossHunger
))

local function isPositive(value: number?): boolean
	return value ~= nil and value > 0
end

-- Does this boss type eat at all?
function BossHunger.isEnabledFor(typeSpec: BossTypes.BossTypeSpec): boolean
	return isPositive(typeSpec.eatIntervalSec)
		and isPositive(typeSpec.eatRadius)
		and isPositive(typeSpec.eatMarkSec)
		and isPositive(typeSpec.eatSnapSec)
		and isPositive(typeSpec.eatReach)
end

-- Nil when the type does not eat, so the controller holds no timer for it.
function BossHunger.new(
	boss: Model,
	humanoid: Humanoid,
	root: BasePart,
	typeSpec: BossTypes.BossTypeSpec
): BossHungerInstance?
	if not BossHunger.isEnabledFor(typeSpec) then
		-- A type that otherwise eats but lacks the pull numbers is a mistake
		-- worth saying out loud; a type with no appetite is simply quiet.
		if isPositive(typeSpec.eatIntervalSec) and isPositive(typeSpec.eatRadius) then
			log:warn(string.format(
				"%s has eatIntervalSec and eatRadius but eatMarkSec %s / eatSnapSec %s / eatReach %s is not positive — hunger is off",
				tostring(typeSpec.name), tostring(typeSpec.eatMarkSec), tostring(typeSpec.eatSnapSec),
				tostring(typeSpec.eatReach)
			))
		end
		return nil
	end
	return setmetatable({
		_boss = boss,
		_humanoid = humanoid,
		_root = root,
		_intervalSec = typeSpec.eatIntervalSec :: number,
		_radius = typeSpec.eatRadius :: number,
		_markSec = typeSpec.eatMarkSec :: number,
		_snapSec = typeSpec.eatSnapSec :: number,
		_towClockSec = 0,
		_snapFraction = 0,
		_schedulePaused = false,
		_reach = typeSpec.eatReach :: number,
		_healFraction = math.max(typeSpec.eatHealFraction or 0, 0),
		_elapsedSec = 0,
		_tow = nil,
		_destroyed = false,
	}, BossHunger)
end

-- The tow ended and the interval starts again. When the letter was not eaten
-- (popped, boss died) the yank times come off the boss too; when it was, they
-- stay so the body can play the gulp that follows the landing.
function BossHunger._endTow(self: BossHungerInstance, eaten: boolean)
	self._tow = nil
	self._elapsedSec = 0
	self._towClockSec = 0
	self._snapFraction = 0
	self._schedulePaused = false
	self._boss:SetAttribute(BossConstants.EATING_AT_ATTRIBUTE, nil)
	if not eaten then
		self._boss:SetAttribute(BossConstants.EAT_SNAP_AT_ATTRIBUTE, nil)
		self._boss:SetAttribute(BossConstants.EAT_LANDS_AT_ATTRIBUTE, nil)
	end
end

-- Publishes when the mark ends and the letter lands, on the letter (through
-- the pool, the one writer of its attributes) and on the boss, from the tow's
-- running clock. `paused` stamps the letter's schedule as stopped now (the
-- boss is frozen); the next call without it resumes with shifted times.
function BossHunger._publishSchedule(self: BossHungerInstance, tow: BlockPoolRegistry.Tow, paused: boolean)
	local now = workspace:GetServerTimeNow()
	local snapAt = now + (self._markSec - self._towClockSec)
	local arriveAt = snapAt + self._snapSec
	BlockPoolRegistry.scheduleTow(Arena.idOf(self._boss), tow.block, {
		beganAt = now - self._towClockSec,
		snapAt = snapAt,
		arriveAt = arriveAt,
		pausedAt = if paused then now else nil,
	})
	self._schedulePaused = paused
	if not paused then
		self._boss:SetAttribute(BossConstants.EAT_SNAP_AT_ATTRIBUTE, snapAt)
		self._boss:SetAttribute(BossConstants.EAT_LANDS_AT_ATTRIBUTE, arriveAt)
	end
end

-- Tells every client's puppet where the letter in tow is, so the body can
-- lean toward it (wiki/design/boss-movement.md). Cleared in _endTow.
function BossHunger._publishEatingAt(self: BossHungerInstance, tow: BlockPoolRegistry.Tow)
	if tow.block.Parent then
		-- Only when it has moved enough to matter: the pull advances every
		-- Heartbeat, and each write is a replicated attribute change.
		local at = tow.block:GetPivot().Position
		local last = self._boss:GetAttribute(BossConstants.EATING_AT_ATTRIBUTE)
		if typeof(last) ~= "Vector3" or (last - at).Magnitude >= BossConstants.EATING_AT_MIN_MOVE then
			self._boss:SetAttribute(BossConstants.EATING_AT_ATTRIBUTE, at)
		end
	end
end

-- The letter came within reach: it is already removed by the pool; heal.
function BossHunger._eat(self: BossHungerInstance, tow: BlockPoolRegistry.Tow)
	local healed = 0
	if self._healFraction > 0 then
		local result = applyDamage.heal({
			targetHumanoid = self._humanoid,
			amount = self._humanoid.MaxHealth * self._healFraction,
			cause = BossConstants.HUNGER_HEAL_CAUSE,
		})
		healed = if result then result.healed else 0
		if healed > 0 then
			VfxBroadcast.playOn(BossConstants.HUNGER_HEAL_VFX, self._root)
		end
	end

	log:info(string.format(
		"[%s] ate %s (%s), healed %.1f (HP %.0f/%.0f)",
		Arena.idOf(self._boss), tow.letter, tow.color, healed, self._humanoid.Health, self._humanoid.MaxHealth
	))
end

-- Interval ran out with nothing in tow: pick a letter and start pulling it.
function BossHunger._startTow(self: BossHungerInstance)
	local arenaId = Arena.idOf(self._boss)
	local tow = BlockPoolRegistry.beginTow(arenaId, self._root.Position, self._radius)
	if tow == nil then
		return
	end
	self._tow = tow
	self._towClockSec = 0
	self._snapFraction = 0
	self:_publishSchedule(tow, false)
	self:_publishEatingAt(tow)
	log:info(string.format("[%s] pulling %s (%s)", arenaId, tow.letter, tow.color))
end

-- One step of the tow in progress.
function BossHunger._advanceTow(self: BossHungerInstance, tow: BlockPoolRegistry.Tow, dt: number)
	local arenaId = Arena.idOf(self._boss)
	local target = self._root.Position
	self._towClockSec += dt

	-- advanceTow's own speed * dt step is fed so that the block lands on the
	-- ease-in curve; its reach is 0 until the final tick, so the block is eaten
	-- when the yank ends (never early, even when it started within eatReach).
	local speed = 0
	local reach = 0
	local snapElapsed = self._towClockSec - self._markSec
	if snapElapsed > 0 then
		local fraction = TowCurve.fraction(snapElapsed, self._snapSec)
		local isFinal = snapElapsed >= self._snapSec
		if isFinal then
			reach = self._reach
		end
		-- Move this fraction of the way still to go, which puts the block on
		-- the curve exactly when the target holds still and tracks it when it
		-- does not.
		local remaining = 1 - self._snapFraction
		local share = if remaining > 0 then (fraction - self._snapFraction) / remaining else 1
		if dt > 0 then
			local toTarget = (target - tow.block:GetPivot().Position).Magnitude
			speed = toTarget * share / dt
		end
		self._snapFraction = fraction
	end

	local step = BlockPoolRegistry.advanceTow(arenaId, tow.block, target, speed, reach, dt)
	if step == "moving" then
		self:_publishEatingAt(tow)
		return
	end
	self:_endTow(step == "arrived")
	if step == "arrived" then
		self:_eat(tow)
	else
		log:info(string.format("[%s] lost %s (%s): popped or removed before it arrived", arenaId, tow.letter, tow.color))
	end
end

-- Remove a letter in tow, if there is one (death, controller destroyed, round
-- ended). Safe to call twice.
function BossHunger._release(self: BossHungerInstance)
	local tow = self._tow
	if tow == nil then
		return
	end
	BlockPoolRegistry.cancelTow(Arena.idOf(self._boss), tow.block)
	self:_endTow(false)
end

-- Called every Heartbeat by BossController while the boss lives.
function BossHunger.tick(self: BossHungerInstance, dt: number)
	if self._destroyed then
		return
	end
	if self._humanoid.Health <= 0 then
		self:_release()
		return
	end
	local tow = self._tow
	if self._boss:GetAttribute(SkillConstants.FROZEN_ATTRIBUTE) then
		-- Hold everything, and tell clients the schedule's clock stopped.
		if tow ~= nil and not self._schedulePaused then
			self:_publishSchedule(tow, true)
		end
		return
	end
	if tow ~= nil then
		-- Thawed: give clients the times shifted by the time held.
		if self._schedulePaused then
			self:_publishSchedule(tow, false)
		end
		self:_advanceTow(tow, dt)
		return
	end
	self._elapsedSec += dt
	if self._elapsedSec < self._intervalSec then
		return
	end
	self._elapsedSec = 0
	self:_startTow()
end

-- The controller is going (boss dead, round ended): drop the letter.
function BossHunger.destroy(self: BossHungerInstance)
	if self._destroyed then
		return
	end
	self:_release()
	self._destroyed = true
end

return BossHunger
