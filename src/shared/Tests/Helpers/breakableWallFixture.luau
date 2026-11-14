--!strict

----------------------------------------------------------------------
-- breakableWallFixture
----------------------------------------------------------------------
-- Arena suite fixture: tagged wall parts of the test's own, in their own
-- arena id, plus the two sources a damage event can come from (a
-- Boss-tagged rig and a non-boss one), and the real SkillEvents to fire at
-- the REAL BreakableWallService. Everything it creates is destroyed by
-- `destroy()`, which every test calls from teardown.
--
-- Walls are made at runtime, after boot, which is itself the "walls tagged
-- after boot are picked up" case. They sit far above the playable place so
-- nothing a character does can touch them, except the one test that puts a
-- rig inside a wall on purpose.
--
-- Events are BindableEvents, delivered at the next resumption point, so a
-- fire and an assertion cannot share a frame: use `settle()` between them.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BossSpawner = require(ServerScriptService.Server.Boss.Scripts.BossSpawner)
local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)

local skillEvents = ReplicatedStorage.Shared.Skills.SkillEvents
local worldImpactEvent = skillEvents.WorldImpact :: BindableEvent
local aoeImpactEvent = skillEvents.AoeImpact :: BindableEvent
local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent

local FIXTURE_FOLDER_NAME = "BreakableWallTestFixture"
-- Far above the playable place; nothing walks here.
local FIXTURE_ORIGIN = Vector3.new(0, 4000, 0)
local DEFAULT_WALL_SIZE = Vector3.new(20, 12, 2)
local WALL_SPACING_STUDS = 80
local DEFAULT_ZONE_SIZE = Vector3.new(30, 12, 30)
local GATE_WALL_HEALTH = 1
local GATE_REGEN_SEC = 0.5
local RESPAWN_WAIT_SEC = 10
local RESPAWN_SETTLE_SEC = 1
local RESPAWN_POLL_SEC = 0.1
-- One frame is enough for a Bindable; the rest is slack for the
-- CollectionService signal that registers a freshly tagged wall.
local SETTLE_SEC = 0.15

local fixture = {}
fixture.__index = fixture

export type WallOptions = {
	maxHealth: number?,
	regenSec: number?,
	arenaId: string?,
	size: Vector3?,
	gateId: string?,
}

export type ZoneOptions = {
	arenaId: string?,
	size: Vector3?,
	cframe: CFrame?,
}

export type Fixture = typeof(setmetatable({} :: {
	arenaId: string,
	folder: Folder,
	made: { Instance },
	wallCount: number,
	restorePlayer: (() -> ())?,
	killedPlayer: Player?,
	killedCharacter: Model?,
}, fixture))

fixture.SETTLE_SEC = SETTLE_SEC

function fixture.new(arenaId: string): Fixture
	local folder = Instance.new("Folder")
	folder.Name = FIXTURE_FOLDER_NAME
	folder.Parent = workspace
	return setmetatable({
		arenaId = arenaId,
		folder = folder,
		made = {},
		wallCount = 0,
		restorePlayer = nil,
		killedPlayer = nil,
		killedCharacter = nil,
	}, fixture)
end

-- A tagged wall in this fixture's arena (or `options.arenaId`). Attributes
-- go on before the tag so the service reads them when it registers.
function fixture.wall(self: Fixture, name: string, options: WallOptions?): BasePart
	local opts: WallOptions = options or {}
	self.wallCount += 1
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = opts.size or DEFAULT_WALL_SIZE
	part.Position = FIXTURE_ORIGIN + Vector3.new(self.wallCount * WALL_SPACING_STUDS, 0, 0)
	part:SetAttribute(Arena.ID_ATTRIBUTE, opts.arenaId or self.arenaId)
	if opts.maxHealth then
		part:SetAttribute(C.Authored.MaxHealth, opts.maxHealth)
	end
	if opts.regenSec then
		part:SetAttribute(C.Authored.RegenSec, opts.regenSec)
	end
	if opts.gateId then
		part:SetAttribute(C.Authored.GateId, opts.gateId)
	end
	part.Parent = self.folder
	CollectionService:AddTag(part, C.TAG)
	return part
end

-- A Boss-tagged rig. Not parented: the service only asks `HasTag`, and an
-- unparented Model cannot be picked up by any other boss-aware system.
function fixture.boss(self: Fixture): Model
	local rig = Instance.new("Model")
	rig.Name = "BreakableWallTestBoss"
	CollectionService:AddTag(rig, BossSpawner.BOSS_TAG)
	table.insert(self.made, rig)
	return rig
end

-- A rig that is not the boss: what a player's character or an NPC looks
-- like to the service.
function fixture.bystander(self: Fixture): Model
	local rig = Instance.new("Model")
	rig.Name = "BreakableWallTestBystander"
	table.insert(self.made, rig)
	return rig
end

-- A rig with a Humanoid and one anchored part at `position`, for the
-- "re-seal waits while a character is inside" case.
function fixture.character(self: Fixture, position: Vector3): Model
	local rig = Instance.new("Model")
	rig.Name = "BreakableWallTestCharacter"
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Anchored = true
	body.Size = Vector3.new(2, 4, 1)
	body.Position = position
	body.Parent = rig
	Instance.new("Humanoid").Parent = rig
	rig.Parent = self.folder
	table.insert(self.made, rig)
	return rig
end

-- A tagged gate hold zone: invisible, non-colliding, anchored. Placed by
-- `cframe` (default: a free slot far from every wall). Attributes go on
-- before the tag, like walls.
function fixture.zone(self: Fixture, name: string, gateId: string?, options: ZoneOptions?): BasePart
	local opts: ZoneOptions = options or {}
	self.wallCount += 1
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = opts.size or DEFAULT_ZONE_SIZE
	part.CFrame = opts.cframe or CFrame.new(FIXTURE_ORIGIN + Vector3.new(self.wallCount * WALL_SPACING_STUDS, 0, 0))
	part:SetAttribute(Arena.ID_ATTRIBUTE, opts.arenaId or self.arenaId)
	if gateId then
		part:SetAttribute(C.Authored.GateId, gateId)
	end
	part.Parent = self.folder
	CollectionService:AddTag(part, C.ZONE_TAG)
	return part
end

-- Moves the REAL player's character to `position` (anchored there so it
-- does not fall) and remembers where it was; `destroy()` puts it back. The
-- service decides "player" by Players, so a stand-in rig cannot be one.
function fixture.placePlayer(self: Fixture, player: Player, position: Vector3): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if self.restorePlayer == nil then
		local original = root.CFrame
		local wasAnchored = root.Anchored
		self.restorePlayer = function()
			if root.Parent then
				root.CFrame = original
				root.Anchored = wasAnchored
			end
		end
	end
	root.Anchored = true
	root.CFrame = CFrame.new(position)
	return root
end

-- Kills the real player's character; `destroy()` respawns it. Returns false
-- when there is no living character to kill.
function fixture.killPlayer(self: Fixture, player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	self.killedPlayer = player
	self.killedCharacter = player.Character
	humanoid.Health = 0
	return true
end

-- A one-hit wall with a short RegenSec, named gate `gateId`, broken right
-- now by a boss fireball. Returns nil when it did not break.
function fixture.brokenGate(self: Fixture, name: string, gateId: string?, arenaId: string?): BasePart?
	local wall = self:wall(name, {
		maxHealth = GATE_WALL_HEALTH,
		regenSec = GATE_REGEN_SEC,
		gateId = gateId,
		arenaId = arenaId,
	})
	local boss = self:boss()
	self:settle()
	self:fireballs(wall, boss, GATE_WALL_HEALTH)
	if self:stateOf(wall) ~= C.State.Broken then
		return nil
	end
	return wall
end

-- How long a gate test waits for a re-seal that should happen, and for one
-- that should not: the regen time plus a few retry intervals.
fixture.GATE_REGEN_SEC = GATE_REGEN_SEC
fixture.RESEAL_WAIT_SEC = GATE_REGEN_SEC + C.REGEN_RETRY_SEC + 0.4
fixture.HOLD_WAIT_SEC = GATE_REGEN_SEC + C.REGEN_RETRY_SEC * 3

function fixture.settle(_self: Fixture)
	task.wait(SETTLE_SEC)
end

function fixture.fireballs(self: Fixture, wall: BasePart, source: Instance?, count: number)
	for _ = 1, count do
		worldImpactEvent:Fire(wall, wall.Position, "FireballVolley", source)
	end
	self:settle()
end

function fixture.slam(self: Fixture, center: Vector3, radius: number, source: Instance?)
	aoeImpactEvent:Fire(center, radius, "GroundSlam", source)
	self:settle()
end

function fixture.roundStarted(self: Fixture, arenaId: string)
	roundStartedEvent:Fire({}, arenaId)
	self:settle()
end

function fixture.stateOf(_self: Fixture, wall: BasePart): any
	return wall:GetAttribute(C.Published.State)
end

function fixture.healthOf(_self: Fixture, wall: BasePart): any
	return wall:GetAttribute(C.Published.Health)
end

function fixture.destroy(self: Fixture)
	local restore = self.restorePlayer
	if restore then
		self.restorePlayer = nil
		restore()
	end
	local killed = self.killedPlayer
	if killed then
		self.killedPlayer = nil
		-- The game respawns a dead player on its own after a few seconds;
		-- a LoadCharacter of ours on top of that would replace the new
		-- character in the middle of the next test. So wait for the game's
		-- respawn and only force one if it never comes.
		local deadCharacter = self.killedCharacter
		local function respawned(): boolean
			local character = killed.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			return character ~= deadCharacter
				and humanoid ~= nil
				and humanoid.Health > 0
				and character:FindFirstChild("HumanoidRootPart") ~= nil
		end
		local deadline = os.clock() + RESPAWN_WAIT_SEC
		while not respawned() and os.clock() < deadline do
			task.wait(RESPAWN_POLL_SEC)
		end
		if not respawned() then
			killed:LoadCharacter()
			while not respawned() do
				task.wait(RESPAWN_POLL_SEC)
			end
		end
		-- Let the respawn finish placing the character before the next test.
		task.wait(RESPAWN_SETTLE_SEC)
	end
	for _, instance in self.made do
		instance:Destroy()
	end
	table.clear(self.made)
	self.folder:Destroy()
end

return fixture
