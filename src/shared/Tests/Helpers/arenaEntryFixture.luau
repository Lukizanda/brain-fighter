--!strict

----------------------------------------------------------------------
-- arenaEntryFixture
----------------------------------------------------------------------
-- Runtime fixtures for the ArenaEntryService tests: tagged pads and arrival
-- points in the workspace, and a throwaway arena session the harness player
-- can stand in. Everything it makes it removes in `cleanup`.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local NoOpMode = require(ReplicatedStorage.Shared.GameMode.Modes.NoOpMode)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local FIXTURE_PART_SIZE = Vector3.new(8, 1, 8)
local FIXTURE_ARENA_ID = "EntryTestArena"

export type Fixture = {
	arenaId: string,
	part: (self: Fixture, tag: string, arenaId: string, cframe: CFrame) -> BasePart,
	enter: (self: Fixture, player: Player) -> boolean,
	cleanup: (self: Fixture, player: Player?) -> (),
	parts: { BasePart },
	homeId: string?,
	created: boolean,
}

local Fixture = {}
Fixture.__index = Fixture

function Fixture.part(self: Fixture, tag: string, arenaId: string, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = FIXTURE_PART_SIZE
	part.CFrame = cframe
	part:SetAttribute(Arena.ID_ATTRIBUTE, arenaId)
	part.Parent = workspace
	CollectionService:AddTag(part, tag)
	table.insert(self.parts, part)
	return part
end

-- Put the player into the fixture's throwaway arena session.
function Fixture.enter(self: Fixture, player: Player): boolean
	local home = SessionRegistry.forPlayer(player)
	if not home then
		return false
	end
	self.homeId = home:getArenaId()
	SessionRegistry.create(self.arenaId, NoOpMode)
	self.created = true
	return SessionRegistry.transferPlayer(player, self.arenaId)
end

function Fixture.cleanup(self: Fixture, player: Player?)
	-- A real teleport leaves the arrival protection window open on the
	-- character; clear it so the next test's damage is not swallowed.
	local character = player and player.Character
	if character then
		character:SetAttribute(HealthConstants.PROTECTED_UNTIL_ATTRIBUTE, nil)
	end
	if player and self.homeId and SessionRegistry.forPlayer(player) ~= SessionRegistry.forArena(self.homeId) then
		SessionRegistry.transferPlayer(player, self.homeId)
	end
	if self.created then
		SessionRegistry.destroy(self.arenaId)
		self.created = false
	end
	for _, part in self.parts do
		part:Destroy()
	end
	table.clear(self.parts)
end

local function new(): Fixture
	return setmetatable({
		arenaId = FIXTURE_ARENA_ID,
		parts = {},
		homeId = nil,
		created = false,
	}, Fixture) :: any
end

return {
	new = new,
}
