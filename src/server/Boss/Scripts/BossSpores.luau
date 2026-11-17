--!strict

----------------------------------------------------------------------
-- BossSpores
----------------------------------------------------------------------
-- The boss's spore lob (wiki/design/ai-playtest.md, the spore decision;
-- numbers in BossConfig, `spore*`). Every `sporeEveryNthAttack`th attack that
-- would have been a FireballVolley is a lob instead: the boss throws
-- `sporeCount` letter blocks that land within `sporeLandRadius` studs
-- (horizontal) of its target `sporeFlightSec` seconds later. Each lands as a
-- spore: an ordinary poppable letter that bursts `sporeFuseSec` after landing
-- for `sporeBurstDamage` to every player of the arena within
-- `sporeBurstRadius` studs, and is gone. Popping one is a normal pop (the
-- letter goes to the popper's buffer through ConsumeBlock); the spore does not
-- burst and the boss takes `sporePopDamageFraction` of its maximum health,
-- credited to the popper.
--
-- Who owns what. The boss decides when to lob, where the spores land and what
-- a burst or a pop does; this object is that decision, one small object per
-- boss like BossHunger. It is not a state in the state machine: BossStates
-- asks it (`replacesVolley`) when the selection is a volley and hands it the
-- lob (`beginLob`) when the Attack state starts, and BossController ticks it
-- so a spore bursts whatever the boss is doing. The BLOCK belongs to
-- BlockSpawner: a spore is spawned, tracked and removed only through
-- BlockPoolRegistry (spawnSpore / removeSpore / clearSpores), which is also
-- why a spore is in no density count or quota and is never towed. A pop
-- reaches this object as the BlockConsumed event BlockShootService already
-- fires, with a trailing `wasSpore` flag it read off the block before
-- destroying it; BlockShootService does nothing else with the flag.
--
-- What the player sees goes through VfxBroadcast with existing effect ids as
-- stand-ins (BossConstants.SPORE_*): the throw, a ring where each spore will
-- land, the landing and the burst. The fuse itself is drawn on the block by
-- the client script SporeLetterVisuals from the expiry time the pool
-- publishes. Nothing here draws or makes a sound of its own.
--
-- Damage goes through Health's applyDamage.process, the one writer of
-- Humanoid.Health: the burst with `sourcePlayer = nil` (it is the boss's, and
-- a player target is never PvP-gated without a source player), the pop damage
-- to the boss with the popper as `sourcePlayer` so the damage confirmation,
-- analytics and kill credit work. Burst targets are the players of the boss's
-- arena from Hittables, the same set the boss's other area damage uses.
--
-- Timing uses `workspace:GetServerTimeNow()` throughout (never os.clock): the
-- fuse time is the one the pool published on the block, which is what the
-- client counts down to.
--
-- Ending: the controller's destroy() (boss dead, round ended) removes every
-- spore of the arena through the registry. A spore popped by a player, or
-- removed some other way, simply drops out of the list.
--
-- Switched off, with no cost, for a type that does not configure the lob
-- (Wizard). A type that configures it but wrongly (a number missing, an
-- unknown letter table, no usable colour) warns once and does not lob.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local SporeConstants = require(ReplicatedStorage.Shared.BlockSpawner.SporeConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Hittables = require(ReplicatedStorage.Shared.Skills.Hittables)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BlockPoolRegistry = require(ServerScriptService.Server.BlockSpawner.BlockPoolRegistry)

local log = Logger.new("BossSpores")

local TAU = math.pi * 2

local BossSpores = {}
BossSpores.__index = BossSpores

-- One live spore: the block, where it floats and where it stands on the
-- ground (the ring is drawn there), and when its fuse runs out.
type Spore = {
	block: Model,
	position: Vector3,
	ground: Vector3,
	burstAt: number,
}

-- A lob in flight: where each spore will land (ground point) and when.
type Lob = {
	landAt: number,
	grounds: { Vector3 },
	onLanded: () -> (),
}

export type BossSporesInstance = typeof(setmetatable(
	{} :: {
		_boss: Model,
		_humanoid: Humanoid,
		_root: BasePart,
		_everyNth: number,
		_count: number,
		_landRadius: number,
		_flightSec: number,
		_fuseSec: number,
		_burstDamage: number,
		_burstRadius: number,
		_popFraction: number,
		_hoverHeight: number,
		_letterTable: string,
		_colors: { string },
		-- Attacks that would have been a volley, counted since the boss spawned.
		_volleys: number,
		_lob: Lob?,
		_live: { Spore },
		_popConnection: RBXScriptConnection?,
		_destroyed: boolean,
	},
	BossSpores
))

local function isPositive(value: number?): boolean
	return value ~= nil and value > 0
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Why a type that asks for the lob cannot have it, or nil when it can.
local function configProblem(spec: BossTypes.BossTypeSpec): string?
	if not isPositive(spec.sporeCount) then
		return "sporeCount is not positive"
	end
	if not isPositive(spec.sporeLandRadius) then
		return "sporeLandRadius is not positive"
	end
	if not isPositive(spec.sporeFlightSec) then
		return "sporeFlightSec is not positive"
	end
	if not isPositive(spec.sporeFuseSec) then
		return "sporeFuseSec is not positive"
	end
	if not isPositive(spec.sporeBurstRadius) then
		return "sporeBurstRadius is not positive"
	end
	local letterTable = spec.sporeLetterTable
	if letterTable == nil or not LetterTables.isValid(letterTable) then
		return "sporeLetterTable " .. tostring(letterTable) .. " is not a letter table"
	end
	local colors = spec.sporeColors
	if colors == nil or #colors == 0 then
		return "sporeColors is empty"
	end
	for _, color in colors do
		if LetterBlocks.COLOR_TINTS[color] == nil then
			return "sporeColors holds unknown colour " .. tostring(color)
		end
	end
	return nil
end

-- Does this boss type lob at all?
function BossSpores.isEnabledFor(spec: BossTypes.BossTypeSpec): boolean
	return isPositive(spec.sporeEveryNthAttack) and configProblem(spec) == nil
end

-- Nil when the type does not lob, so the controller holds nothing for it.
function BossSpores.new(
	boss: Model,
	humanoid: Humanoid,
	root: BasePart,
	spec: BossTypes.BossTypeSpec
): BossSporesInstance?
	if not isPositive(spec.sporeEveryNthAttack) then
		return nil
	end
	local problem = configProblem(spec)
	if problem ~= nil then
		log:warn(string.format("%s asks for a spore lob but %s — it will not lob", tostring(spec.name), problem))
		return nil
	end
	local self: BossSporesInstance = setmetatable({
		_boss = boss,
		_humanoid = humanoid,
		_root = root,
		_everyNth = math.max(1, math.floor(spec.sporeEveryNthAttack :: number)),
		_count = math.max(1, math.floor(spec.sporeCount :: number)),
		_landRadius = spec.sporeLandRadius :: number,
		_flightSec = spec.sporeFlightSec :: number,
		_fuseSec = spec.sporeFuseSec :: number,
		_burstDamage = math.max(spec.sporeBurstDamage or 0, 0),
		_burstRadius = spec.sporeBurstRadius :: number,
		_popFraction = math.max(spec.sporePopDamageFraction or 0, 0),
		_hoverHeight = math.max(spec.sporeHoverHeight or 0, 0),
		_letterTable = spec.sporeLetterTable :: string,
		_colors = spec.sporeColors :: { string },
		_volleys = 0,
		_lob = nil,
		_live = {},
		_popConnection = nil,
		_destroyed = false,
	}, BossSpores)

	local blockConsumed = ServerScriptService.Server.BlockShoot.Events.BlockConsumed :: BindableEvent
	self._popConnection = blockConsumed.Event:Connect(function(player: Player, _letter: any, _color: any, arenaId: any, wasSpore: any)
		if wasSpore == true and arenaId == Arena.idOf(self._boss) then
			self:_onPopped(player)
		end
	end)
	return self
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

-- Called once for every attack that would have been a FireballVolley: true
-- for every Nth, which is a lob instead. (The simulator counts every attack,
-- slams included; this counts volleys only, as the user's rule reads. They
-- differ only when slams fall between volleys.)
function BossSpores.replacesVolley(self: BossSporesInstance): boolean
	self._volleys += 1
	return self._volleys % self._everyNth == 0
end

----------------------------------------------------------------------
-- The lob
----------------------------------------------------------------------

-- The ground under `point`: a raycast down past the boss, the players and the
-- letter blocks, or a fixed drop below the target's root when nothing is hit
-- (a bare test arena).
function BossSpores._groundBelow(self: BossSporesInstance, point: Vector3, rootY: number, arenaId: string): number
	local ignore: { Instance } = { self._boss }
	for _, hittable in Hittables.collect(BroadcastAudience.forArena(arenaId), arenaId) do
		table.insert(ignore, hittable.model)
	end
	for _, block in CollectionService:GetTagged(LetterBlocks.TAG) do
		table.insert(ignore, block)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local origin = Vector3.new(point.X, rootY + BossConstants.SPORE_GROUND_PROBE_UP_STUDS, point.Z)
	local hit = workspace:Raycast(
		origin,
		Vector3.new(0, -(BossConstants.SPORE_GROUND_PROBE_UP_STUDS + BossConstants.SPORE_GROUND_PROBE_DOWN_STUDS), 0),
		params
	)
	if hit then
		return hit.Position.Y
	end
	return rootY - BossConstants.SPORE_ROOT_TO_FEET_STUDS
end

-- Start a lob at `targetPosition` (the target's root). `onLanded` runs from
-- tick() when the spores have landed. False when a lob is already in the air
-- or the boss is dead; `onLanded` never runs then.
function BossSpores.beginLob(self: BossSporesInstance, targetPosition: Vector3, onLanded: () -> ()): boolean
	if self._destroyed or self._lob ~= nil or self._humanoid.Health <= 0 then
		return false
	end
	local arenaId = Arena.idOf(self._boss)
	local grounds: { Vector3 } = {}
	for _ = 1, self._count do
		local angle = math.random() * TAU
		local distance = math.random() * self._landRadius
		local x = targetPosition.X + math.cos(angle) * distance
		local z = targetPosition.Z + math.sin(angle) * distance
		local groundY = self:_groundBelow(Vector3.new(x, targetPosition.Y, z), targetPosition.Y, arenaId)
		table.insert(grounds, Vector3.new(x, groundY, z))
	end
	self._lob = {
		landAt = workspace:GetServerTimeNow() + self._flightSec,
		grounds = grounds,
		onLanded = onLanded,
	}

	-- The throw, and a ring on the ground at each landing spot for the flight.
	VfxBroadcast.playAt(
		BossConstants.SPORE_LOB_VFX,
		self._root.Position + Vector3.new(0, BossConstants.SPORE_LOB_ORIGIN_HEIGHT_STUDS, 0)
	)
	for _, ground in grounds do
		VfxBroadcast.shockwave(ground, self._burstRadius, {
			color = BossConstants.SPORE_RING_COLOR,
			lifetimeSec = self._flightSec,
		})
	end
	log:info(string.format("[%s] lobbing %d spores (land in %.1fs)", arenaId, self._count, self._flightSec))
	return true
end

-- The flight is over: the spores appear at their landing spots.
function BossSpores._land(self: BossSporesInstance, lob: Lob)
	local arenaId = Arena.idOf(self._boss)
	for _, ground in lob.grounds do
		local letter = LetterTables.pick(self._letterTable)
		local color = if Wildcard.isWildcard(letter) then Wildcard.COLOR else self._colors[math.random(1, #self._colors)]
		local position = ground + Vector3.new(0, self._hoverHeight, 0)
		local block = BlockPoolRegistry.spawnSpore(arenaId, letter, color, position, self._fuseSec)
		if block ~= nil then
			local published = block:GetAttribute(SporeConstants.EXPIRES_ATTRIBUTE)
			table.insert(self._live, {
				block = block,
				position = position,
				ground = ground,
				burstAt = if type(published) == "number" then published else workspace:GetServerTimeNow() + self._fuseSec,
			})
			VfxBroadcast.playAt(BossConstants.SPORE_LAND_VFX, position)
		else
			log:warn(string.format("[%s] no block pool to land a spore in", arenaId))
		end
	end
end

----------------------------------------------------------------------
-- Burst and pop
----------------------------------------------------------------------

-- The fuse ran out with the spore still there: remove it, hurt the players
-- inside the radius.
function BossSpores._burst(self: BossSporesInstance, spore: Spore)
	local arenaId = Arena.idOf(self._boss)
	BlockPoolRegistry.removeSpore(arenaId, spore.block)
	VfxBroadcast.playAt(BossConstants.SPORE_BURST_VFX, spore.position)
	VfxBroadcast.shockwave(spore.ground, self._burstRadius, {
		color = BossConstants.SPORE_RING_COLOR,
		lifetimeSec = BossConstants.SPORE_BURST_RING_SEC,
	})

	local hit = 0
	for _, hittable in Hittables.collect(BroadcastAudience.forArena(arenaId), arenaId) do
		-- Players only, as the boss's slam is: not its own arena's NPCs.
		if hittable.player == nil then
			continue
		end
		if horizontalDistance(hittable.hrp.Position, spore.position) > self._burstRadius then
			continue
		end
		applyDamage.process({
			sourcePlayer = nil,
			targetHumanoid = hittable.hum,
			baseDamage = self._burstDamage,
			damageType = DamageTypes.DamageType.Explosion,
			hitZone = DamageTypes.HitZone.Torso,
			timestamp = os.clock(),
			cause = BossConstants.SPORE_BURST_CAUSE,
		})
		hit += 1
	end
	log:info(string.format("[%s] a spore burst, %d player(s) hit", arenaId, hit))
end

-- A player popped a spore of this boss's arena: the boss pays for it.
function BossSpores._onPopped(self: BossSporesInstance, popper: Player)
	if self._destroyed or self._popFraction <= 0 or self._humanoid.Health <= 0 then
		return
	end
	applyDamage.process({
		sourcePlayer = popper,
		targetHumanoid = self._humanoid,
		baseDamage = self._humanoid.MaxHealth * self._popFraction,
		damageType = DamageTypes.DamageType.Spell,
		hitZone = DamageTypes.HitZone.Torso,
		timestamp = os.clock(),
		cause = BossConstants.SPORE_POP_CAUSE,
	})
end

----------------------------------------------------------------------
-- Tick and ending
----------------------------------------------------------------------

-- Called every Heartbeat by BossController while the boss lives.
function BossSpores.tick(self: BossSporesInstance)
	if self._destroyed then
		return
	end
	if self._humanoid.Health <= 0 then
		self:_clear()
		return
	end
	local now = workspace:GetServerTimeNow()

	local lob = self._lob
	if lob ~= nil and now >= lob.landAt then
		self._lob = nil
		self:_land(lob)
		lob.onLanded()
	end

	-- Backwards, so a burst can drop its entry as it goes. A spore whose block
	-- is gone was popped (the pop damage is paid by the BlockConsumed
	-- listener) or removed by something else: either way, no burst.
	for index = #self._live, 1, -1 do
		local spore = self._live[index]
		if spore.block.Parent == nil then
			table.remove(self._live, index)
		elseif now >= spore.burstAt then
			table.remove(self._live, index)
			self:_burst(spore)
		end
	end
end

-- Spores that have landed and not yet burst or been popped.
function BossSpores.liveCount(self: BossSporesInstance): number
	return #self._live
end

-- Drop the lob in the air and remove every spore of the arena, no burst.
function BossSpores._clear(self: BossSporesInstance)
	self._lob = nil
	table.clear(self._live)
	BlockPoolRegistry.clearSpores(Arena.idOf(self._boss))
end

-- The controller is going (boss dead, round ended): the spores go with it.
function BossSpores.destroy(self: BossSporesInstance)
	if self._destroyed then
		return
	end
	self._destroyed = true
	local connection = self._popConnection
	if connection ~= nil then
		connection:Disconnect()
		self._popConnection = nil
	end
	self:_clear()
end

return BossSpores
