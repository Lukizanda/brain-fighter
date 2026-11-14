--!strict

----------------------------------------------------------------------
-- BossHunger
----------------------------------------------------------------------
-- "Hungry brain" with the letter pull (Phase 8 stage 9,
-- wiki/design/boss-arena.md § Letter pull). Every `eatIntervalSec` the living
-- boss with no letter already in tow picks the nearest eligible letter block
-- within `eatRadius` studs of itself, measured horizontally (the letters
-- float well above the boss), in its own arena, and starts pulling it toward
-- itself at `eatPullSpeed` studs a second, following the boss as the boss
-- moves. When the letter comes within `eatReach` studs of the boss's root it
-- is eaten and the boss heals `eatHealFraction` of its maximum health. A
-- player can pop the letter first; the boss then goes hungry and the interval
-- starts again from zero.
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
-- or 0 or less. A type that has both but no positive `eatPullSpeed` or
-- `eatReach` is a config mistake and also does not eat, with a warning.
-- `eatHealFraction` 0 or missing still pulls and eats, heals nothing and
-- sends no heal cue.
--
-- Frozen: while its character carries the `_frozen` attribute
-- (SkillConstants.FROZEN_ATTRIBUTE, written by SkillEffects' freeze, the only
-- status that holds a boss today; no stun status exists in the code) the
-- boss does not advance a letter in tow (it hangs where it is) and the
-- interval does not run, so a thaw neither bites at once nor loses the meal.
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
		_pullSpeed: number,
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
		and isPositive(typeSpec.eatPullSpeed)
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
				"%s has eatIntervalSec and eatRadius but eatPullSpeed %s / eatReach %s is not positive — hunger is off",
				tostring(typeSpec.name), tostring(typeSpec.eatPullSpeed), tostring(typeSpec.eatReach)
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
		_pullSpeed = typeSpec.eatPullSpeed :: number,
		_reach = typeSpec.eatReach :: number,
		_healFraction = math.max(typeSpec.eatHealFraction or 0, 0),
		_elapsedSec = 0,
		_tow = nil,
		_destroyed = false,
	}, BossHunger)
end

-- The tow ended and the boss goes hungry: the interval starts again.
function BossHunger._endTow(self: BossHungerInstance)
	self._tow = nil
	self._elapsedSec = 0
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
	log:info(string.format("[%s] pulling %s (%s)", arenaId, tow.letter, tow.color))
end

-- One step of the tow in progress.
function BossHunger._advanceTow(self: BossHungerInstance, tow: BlockPoolRegistry.Tow, dt: number)
	local arenaId = Arena.idOf(self._boss)
	local step = BlockPoolRegistry.advanceTow(
		arenaId, tow.block, self._root.Position, self._pullSpeed, self._reach, dt
	)
	if step == "moving" then
		return
	end
	self:_endTow()
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
	self:_endTow()
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
	if self._boss:GetAttribute(SkillConstants.FROZEN_ATTRIBUTE) then
		return
	end
	local tow = self._tow
	if tow ~= nil then
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
