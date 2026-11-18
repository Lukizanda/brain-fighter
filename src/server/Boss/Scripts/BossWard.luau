--!strict

----------------------------------------------------------------------
-- BossWard
----------------------------------------------------------------------
-- The boss's word ward (wiki/design/ai-playtest.md, the ward decision;
-- numbers in BossConfig, `ward*`). The boss's health cannot be taken below
-- `wardAtHpFraction` of its maximum until the ward has been broken: the hit
-- that would cross that line lands on it instead, `wardLetterCount` letter
-- blocks appear and orbit the boss, and nothing hurts the boss until every
-- one has been popped. Popping one is a normal pop (the letter goes to the
-- popper's buffer through ConsumeBlock). When the last is gone the boss can
-- be hurt again, for the rest of its life: a boss has one ward.
--
-- The second half of the fight being faster is NOT this object's doing: it is
-- an ordinary phase (BossConfig `phases`, a second entry at the same health
-- fraction), applied by BossPhaseManager and BossController as any phase is.
--
-- Who owns what. The boss decides when the ward goes up, where its letters
-- are and when it is broken; this object is that decision, one small object
-- per boss like BossHunger and BossSpores, ticked by BossController. Whether
-- a hit lands is a damage rule and belongs to Health: this object only sets
-- and clears the boss's health floor (shared/Health/HealthFloor) and never
-- touches Humanoid.Health. The BLOCKS belong to BlockSpawner: a ward letter
-- is spawned, moved and removed only through BlockPoolRegistry
-- (spawnWardLetter / moveWardLetter / clearWardLetters), which is also why
-- one is in no density count or quota and is never towed. A pop needs no
-- signal: a ward letter leaves the world only by being popped or cleared, so
-- a letter whose block is gone was popped.
--
-- What the player sees: the letters themselves are real blocks. The ward
-- going up, a ring pulsing round the boss while it holds and the ward
-- breaking go through VfxBroadcast with existing effect ids as stand-ins
-- (BossConstants.WARD_*). Nothing here draws or makes a sound of its own.
--
-- While the ward is up the boss does not eat (BossController asks `isUp`
-- and skips the hunger tick), so a fight cannot be stalled into a heal.
--
-- A ward that cannot hang its letters (the arena has no block pool) would
-- leave the boss unkillable, so it is dropped at once with a warning.
--
-- Switched off, with no cost, for a type that does not configure the ward
-- (Wizard). A type that configures it but wrongly warns once and has none.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local HealthFloor = require(ReplicatedStorage.Shared.Health.HealthFloor)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local BlockPoolRegistry = require(ServerScriptService.Server.BlockSpawner.BlockPoolRegistry)

local log = Logger.new("BossWard")

local TAU = math.pi * 2

-- The ward's life: waiting for the boss to reach the line, holding, broken.
local STATE_ARMED = "armed"
local STATE_UP = "up"
local STATE_DOWN = "down"

local BossWard = {}
BossWard.__index = BossWard

export type BossWardInstance = typeof(setmetatable(
	{} :: {
		_boss: Model,
		_humanoid: Humanoid,
		_root: BasePart,
		_floor: number,
		_count: number,
		_orbitRadius: number,
		_orbitHeight: number,
		_orbitPeriodSec: number,
		_letterTable: string,
		_colors: { string },
		_state: string,
		-- Live ward letters and the angle each started at.
		_letters: { { block: Model, angle: number } },
		_upSec: number,
		_pulseInSec: number,
		_destroyed: boolean,
	},
	BossWard
))

local function isPositive(value: number?): boolean
	return value ~= nil and value > 0
end

-- Why a type that asks for the ward cannot have it, or nil when it can.
local function configProblem(spec: BossTypes.BossTypeSpec): string?
	local fraction = spec.wardAtHpFraction :: number
	if fraction >= 1 then
		return "wardAtHpFraction is not below 1"
	end
	if not isPositive(spec.wardLetterCount) then
		return "wardLetterCount is not positive"
	end
	if not isPositive(spec.wardOrbitRadius) then
		return "wardOrbitRadius is not positive"
	end
	if not isPositive(spec.wardOrbitPeriodSec) then
		return "wardOrbitPeriodSec is not positive"
	end
	local letterTable = spec.wardLetterTable
	if letterTable == nil or not LetterTables.isValid(letterTable) then
		return "wardLetterTable " .. tostring(letterTable) .. " is not a letter table"
	end
	local colors = spec.wardColors
	if colors == nil or #colors == 0 then
		return "wardColors is empty"
	end
	for _, color in colors do
		if LetterBlocks.COLOR_TINTS[color] == nil then
			return "wardColors holds unknown colour " .. tostring(color)
		end
	end
	return nil
end

-- Does this boss type have a ward at all?
function BossWard.isEnabledFor(spec: BossTypes.BossTypeSpec): boolean
	return isPositive(spec.wardAtHpFraction) and configProblem(spec) == nil
end

-- Nil when the type has no ward, so the controller holds nothing for it.
-- A boss with one has its health floor set from this moment.
function BossWard.new(boss: Model, humanoid: Humanoid, root: BasePart, spec: BossTypes.BossTypeSpec): BossWardInstance?
	if not isPositive(spec.wardAtHpFraction) then
		return nil
	end
	local problem = configProblem(spec)
	if problem ~= nil then
		log:warn(string.format("%s asks for a word ward but %s — it will have none", tostring(spec.name), problem))
		return nil
	end
	local self: BossWardInstance = setmetatable({
		_boss = boss,
		_humanoid = humanoid,
		_root = root,
		_floor = humanoid.MaxHealth * (spec.wardAtHpFraction :: number),
		_count = math.max(1, math.floor(spec.wardLetterCount :: number)),
		_orbitRadius = spec.wardOrbitRadius :: number,
		_orbitHeight = spec.wardOrbitHeight or 0,
		_orbitPeriodSec = spec.wardOrbitPeriodSec :: number,
		_letterTable = spec.wardLetterTable :: string,
		_colors = spec.wardColors :: { string },
		_state = STATE_ARMED,
		_letters = {},
		_upSec = 0,
		_pulseInSec = 0,
		_destroyed = false,
	}, BossWard)
	HealthFloor.set(boss, self._floor)
	return self
end

-- Is the ward holding right now (letters out, the boss unhurtable)?
function BossWard.isUp(self: BossWardInstance): boolean
	return self._state == STATE_UP
end

-- Ward letters still to pop.
function BossWard.lettersLeft(self: BossWardInstance): number
	return #self._letters
end

-- Where the letter that started at `angle` is now.
function BossWard._orbitPoint(self: BossWardInstance, angle: number): Vector3
	local turned = angle + self._upSec / self._orbitPeriodSec * TAU
	return self._root.Position
		+ Vector3.new(math.cos(turned) * self._orbitRadius, self._orbitHeight, math.sin(turned) * self._orbitRadius)
end

function BossWard._pulse(self: BossWardInstance)
	VfxBroadcast.shockwave(self._root.Position, self._orbitRadius, {
		color = BossConstants.WARD_RING_COLOR,
		lifetimeSec = BossConstants.WARD_RING_SEC,
	})
end

-- The boss has reached the line: hang the letters.
function BossWard._raise(self: BossWardInstance)
	local arenaId = Arena.idOf(self._boss)
	self._upSec = 0
	for index = 1, self._count do
		local angle = index / self._count * TAU
		local letter = LetterTables.pick(self._letterTable)
		local color = if Wildcard.isWildcard(letter) then Wildcard.COLOR else self._colors[math.random(1, #self._colors)]
		local block = BlockPoolRegistry.spawnWardLetter(arenaId, letter, color, self:_orbitPoint(angle))
		if block ~= nil then
			table.insert(self._letters, { block = block, angle = angle })
		end
	end
	if #self._letters == 0 then
		log:warn(string.format("[%s] no block pool to hang ward letters in — the ward is dropped", arenaId))
		self:_drop(false)
		return
	end
	self._state = STATE_UP
	self._boss:SetAttribute(BossConstants.WARD_UP_ATTRIBUTE, true)
	self._boss:SetAttribute(BossConstants.WARD_LETTERS_LEFT_ATTRIBUTE, #self._letters)
	self._pulseInSec = BossConstants.WARD_PULSE_EVERY_SEC
	VfxBroadcast.playAt(BossConstants.WARD_UP_VFX, self._root.Position)
	self:_pulse()
	log:info(string.format("[%s] word ward up at %.0f health, %d letters", arenaId, self._humanoid.Health, #self._letters))
end

-- The ward is over: the boss can be hurt again. `broken` is false when it
-- ended without being popped away (no pool, the boss going).
function BossWard._drop(self: BossWardInstance, broken: boolean)
	self._state = STATE_DOWN
	table.clear(self._letters)
	self._boss:SetAttribute(BossConstants.WARD_UP_ATTRIBUTE, nil)
	self._boss:SetAttribute(BossConstants.WARD_LETTERS_LEFT_ATTRIBUTE, nil)
	HealthFloor.clear(self._boss)
	if broken then
		VfxBroadcast.playAt(BossConstants.WARD_DOWN_VFX, self._root.Position)
		log:info(string.format("[%s] word ward broken", Arena.idOf(self._boss)))
	end
end

-- Called every Heartbeat by BossController while the boss lives.
function BossWard.tick(self: BossWardInstance, dt: number)
	if self._destroyed or self._state == STATE_DOWN then
		return
	end
	if self._humanoid.Health <= 0 then
		self:_clear()
		return
	end

	if self._state == STATE_ARMED then
		if self._humanoid.Health <= self._floor + BossConstants.WARD_HEALTH_TOLERANCE then
			self:_raise()
		end
		return
	end

	-- Up: carry the letters round, forget the popped ones.
	self._upSec += dt
	local arenaId = Arena.idOf(self._boss)
	for index = #self._letters, 1, -1 do
		local entry = self._letters[index]
		if entry.block.Parent == nil or not BlockPoolRegistry.moveWardLetter(arenaId, entry.block, self:_orbitPoint(entry.angle)) then
			table.remove(self._letters, index)
		end
	end
	if #self._letters == 0 then
		self:_drop(true)
		return
	end
	self._boss:SetAttribute(BossConstants.WARD_LETTERS_LEFT_ATTRIBUTE, #self._letters)
	self._pulseInSec -= dt
	if self._pulseInSec <= 0 then
		self._pulseInSec = BossConstants.WARD_PULSE_EVERY_SEC
		self:_pulse()
	end
end

-- Remove the letters and the floor without the "broken" cue.
function BossWard._clear(self: BossWardInstance)
	local wasUp = self._state == STATE_UP
	self:_drop(false)
	if wasUp then
		BlockPoolRegistry.clearWardLetters(Arena.idOf(self._boss))
	end
end

-- The controller is going (boss dead, round ended): the ward goes with it.
function BossWard.destroy(self: BossWardInstance)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:_clear()
end

return BossWard
