--!strict

----------------------------------------------------------------------
-- bossEntranceFixture
----------------------------------------------------------------------
-- Runtime fixture for the boss-entrance tests. Drives the REAL BossService
-- (a Script, so it cannot be required) through the same two doors the game
-- uses: the arena's RoundStarted / RoundEnded BindableEvents, and, for the
-- arrival, ArenaEntryService.handleTouch with the harness player's real
-- character. What it builds, on top of `arenaEntryFixture`'s throwaway
-- arena session:
--
--   * a `BossPoint` part for that arena, naming a boss type registered here
--     for the test only (a copy of Wizard with the delay under test), so no
--     shipped config is touched and the real arena's boss is not involved;
--   * optionally an `ArenaEntryPad` and an `ArenaArrivalPoint`.
--
-- The boss is a real rig. The BossPoint sits far from the arrival point
-- (beyond the boss's detection range) so it never hunts the harness player,
-- and every round is ended in `cleanup`, which destroys the boss.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local BossSpawner = require(ServerScriptService.Server.Boss.Scripts.BossSpawner)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent
local roundEndedEvent = ServerScriptService.Server.GameMode.Events.RoundEnded :: BindableEvent

local TEST_TYPE_NAME = "EntranceTestBoss"
local BOSS_POINT_NAME = "BossPoint"
local PAD_HEIGHT = 600
local ARRIVAL_HEIGHT = 700
-- Distance along X between the BossPoint and the arrival point: well past
-- the Wizard's detectionRange (100).
local BOSS_POINT_X = 400
local POLL_SEC = 0.05

export type Options = {
	-- Seconds of entrance delay on the test boss type; nil = no delay.
	entranceDelaySec: number?,
	-- Whether the arena has an entry pad (and an arrival point).
	withPad: boolean,
	-- Lets a test adjust the test boss type's spec before the boss exists
	-- (the hunger tests give it eat values).
	configureSpec: ((spec: any) -> ())?,
}

export type Fixture = {
	arenaId: string,
	entry: arenaEntryFixture.Fixture,
	bossPoint: BasePart?,
	pad: BasePart?,
	roundOpen: boolean,
	homeId: string?,
}

local Fixture = {}
Fixture.__index = Fixture

local function new(): Fixture
	local entry = arenaEntryFixture.new()
	return setmetatable({
		arenaId = entry.arenaId,
		entry = entry,
		bossPoint = nil,
		pad = nil,
		roundOpen = false,
		homeId = nil,
	}, Fixture) :: any
end

-- Put the player in the throwaway arena and lay out the parts. False when
-- the player could not be moved in.
function Fixture.build(self: Fixture, player: Player, options: Options): boolean
	ArenaEntryService.resetState()
	if not self.entry:enter(player) then
		return false
	end
	self.homeId = self.entry.homeId

	local spec: any = table.clone(BossConfig.BOSS_TYPES.Wizard)
	spec.name = TEST_TYPE_NAME
	spec.entranceDelaySec = options.entranceDelaySec
	if options.configureSpec then
		options.configureSpec(spec)
	end
	;(BossConfig.BOSS_TYPES :: any)[TEST_TYPE_NAME] = spec

	local bossPoint = Instance.new("Part")
	bossPoint.Name = BOSS_POINT_NAME
	bossPoint.Anchored = true
	bossPoint.CanCollide = true
	bossPoint.Size = Vector3.new(30, 1, 30)
	bossPoint.CFrame = CFrame.new(BOSS_POINT_X, PAD_HEIGHT, 0)
	bossPoint:SetAttribute(Arena.ID_ATTRIBUTE, self.arenaId)
	bossPoint:SetAttribute("BossType", TEST_TYPE_NAME)
	bossPoint.Parent = workspace
	table.insert(self.entry.parts, bossPoint)
	self.bossPoint = bossPoint

	if options.withPad then
		self.pad = self.entry:part(ArenaEntryConstants.PAD_TAG, self.arenaId, CFrame.new(0, PAD_HEIGHT, 0))
		self.entry:part(ArenaEntryConstants.ARRIVAL_TAG, self.arenaId, CFrame.new(0, ARRIVAL_HEIGHT, 0))
	end
	return true
end

function Fixture.startRound(self: Fixture)
	self.roundOpen = true
	roundStartedEvent:Fire({}, self.arenaId)
end

function Fixture.endRound(self: Fixture)
	if self.roundOpen then
		self.roundOpen = false
		roundEndedEvent:Fire(nil, nil, self.arenaId, nil)
	end
end

-- The player steps on the entry pad for real: ArenaEntryService decides,
-- teleports and announces `PlayerEntered`.
function Fixture.arrive(self: Fixture, player: Player): string?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not self.pad or not hrp then
		return nil
	end
	return ArenaEntryService.handleTouch(self.pad, hrp)
end

-- The boss BossService has spawned for this arena, if any.
function Fixture.boss(self: Fixture): Model?
	for _, instance in CollectionService:GetTagged(BossSpawner.BOSS_TAG) do
		if instance:IsA("Model") and instance:GetAttribute(Arena.ID_ATTRIBUTE) == self.arenaId then
			return instance
		end
	end
	return nil
end

-- Is the BossPoint carrying the countdown tell (tag and attribute)?
function Fixture.tellUp(self: Fixture, tag: string): boolean
	return self.bossPoint ~= nil and CollectionService:HasTag(self.bossPoint, tag)
end

-- Poll until `predicate` holds; returns seconds waited, or nil on timeout.
function Fixture.waitFor(_self: Fixture, predicate: () -> boolean, timeoutSec: number): number?
	local started = os.clock()
	while os.clock() - started < timeoutSec do
		if predicate() then
			return os.clock() - started
		end
		task.wait(POLL_SEC)
	end
	return if predicate() then os.clock() - started else nil
end

-- End the round (destroying any boss), send the player home, remove every
-- part and the test boss type. Safe to call after a failed `build`.
function Fixture.cleanup(self: Fixture, player: Player?)
	-- Home first, so the RoundEnded below finds an empty roster: no
	-- analytics line for the harness player, no HUD sentinel to anyone.
	if player and self.homeId and SessionRegistry.forPlayer(player) ~= SessionRegistry.forArena(self.homeId) then
		SessionRegistry.transferPlayer(player, self.homeId)
	end
	self:endRound()
	task.wait()
	local leftover = self:boss()
	if leftover then
		leftover:Destroy()
	end
	self.entry:cleanup(player)
	;(BossConfig.BOSS_TYPES :: any)[TEST_TYPE_NAME] = nil
	ArenaEntryService.resetState()
end

return {
	new = new,
}
