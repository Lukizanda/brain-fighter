--!strict

----------------------------------------------------------------------
-- BossHunger
----------------------------------------------------------------------
-- "Hungry brain" (Phase 8 stage 9, wiki/design/boss-arena.md § Hungry brain).
-- Every `eatIntervalSec` the living boss eats the nearest letter block within
-- `eatRadius` studs of itself, in its own arena, and heals `eatHealFraction`
-- of its maximum health. The letters around the boss become urgent: pop them
-- or the fight gets longer.
--
-- One small object per boss, ticked by BossController alongside perception and
-- the state machine. It exists because the boss's own behaviour belongs to the
-- Boss system, but it is not an AI state: eating happens whatever the boss is
-- doing (walking, winding up an attack), so it is a timer beside the state
-- machine rather than a state in it. The controller is created only after the
-- boss has spawned and stops ticking when it dies, which gives "not during the
-- entrance" and "not when dead" for free; the hold before an entrance spawn
-- has no controller at all.
--
-- It does not touch blocks. BlockSpawner owns them: this asks the arena's pool,
-- through BlockPoolRegistry, to take the nearest eligible block (the pool
-- excludes word-kit letters and freed fossil letters by construction) and gets
-- back where it was and what it was. The heal goes through Health's
-- `applyDamage.heal`, the one writer of Humanoid.Health. What the player sees
-- goes through VfxBroadcast; nothing here draws and nothing makes a sound of
-- its own.
--
-- Switched off, with no cost, when `eatIntervalSec` or `eatRadius` is missing
-- or 0 or less. `eatHealFraction` 0 or missing still eats, heals nothing and
-- sends no heal cue.
--
-- Frozen: the boss does not eat while its character carries the `_frozen`
-- attribute (SkillConstants.FROZEN_ATTRIBUTE, written by SkillEffects' freeze,
-- the only status that holds a boss today; no stun status exists in the
-- code). The interval does not run while frozen, so a thaw does not bite at
-- once.
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
		_healFraction: number,
		-- Seconds the interval has run since the last bite attempt.
		_elapsedSec: number,
	},
	BossHunger
))

-- Does this boss type eat at all?
function BossHunger.isEnabledFor(typeSpec: BossTypes.BossTypeSpec): boolean
	local interval = typeSpec.eatIntervalSec
	local radius = typeSpec.eatRadius
	return interval ~= nil and radius ~= nil and interval > 0 and radius > 0
end

-- Nil when the type does not eat, so the controller holds no timer for it.
function BossHunger.new(
	boss: Model,
	humanoid: Humanoid,
	root: BasePart,
	typeSpec: BossTypes.BossTypeSpec
): BossHungerInstance?
	if not BossHunger.isEnabledFor(typeSpec) then
		return nil
	end
	return setmetatable({
		_boss = boss,
		_humanoid = humanoid,
		_root = root,
		_intervalSec = typeSpec.eatIntervalSec :: number,
		_radius = typeSpec.eatRadius :: number,
		_healFraction = math.max(typeSpec.eatHealFraction or 0, 0),
		_elapsedSec = 0,
	}, BossHunger)
end

-- One bite: take the block, show it, heal.
function BossHunger._bite(self: BossHungerInstance)
	local arenaId = Arena.idOf(self._boss)
	local rootPosition = self._root.Position
	local taken = BlockPoolRegistry.takeNearestEligible(arenaId, rootPosition, self._radius)
	if taken == nil then
		return
	end

	-- The stream from where the block was to the boss: the existing laser
	-- beam, since the collect stream is bound to a player (see BossConstants).
	VfxBroadcast.beam(taken.position, rootPosition)

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
		"[%s] ate %s (%s) %.1f studs away, healed %.1f (HP %.0f/%.0f)",
		arenaId, taken.letter, taken.color, (taken.position - rootPosition).Magnitude,
		healed, self._humanoid.Health, self._humanoid.MaxHealth
	))
end

-- Called every Heartbeat by BossController while the boss lives.
function BossHunger.tick(self: BossHungerInstance, dt: number)
	if self._humanoid.Health <= 0 then
		return
	end
	if self._boss:GetAttribute(SkillConstants.FROZEN_ATTRIBUTE) then
		return
	end
	self._elapsedSec += dt
	if self._elapsedSec < self._intervalSec then
		return
	end
	self._elapsedSec = 0
	self:_bite()
end

return BossHunger
