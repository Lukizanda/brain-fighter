--!strict

----------------------------------------------------------------------
-- ensurePatroller
----------------------------------------------------------------------
-- NPC suite fixture: a Patroller rig of the test's own, driven by a
-- live NPCController, that a test can read `CurrentState` off and
-- expect to react to the player.
--
-- It is always the fixture's own clone (`Patroller_Fixture`), never the
-- arena's boot-spawned `Patroller_1`. Reusing the arena NPC was the
-- pre-chunk-9 shape and stopped working once NPCs became per-arena:
-- the arena rig lives on the far side of the place, path-fails from
-- there, wanders into the DeathZone mid-suite, and — since Perception
-- now scans only the roster of the arena named by the rig's `ArenaId`
-- — cannot see a harness player who sits in the Lobby session anyway.
--
-- So `ensure(player)`:
--   * clones ServerStorage.AIWorldData.Rigs.Patroller,
--   * stamps it with the player's arena (`Arena.idOf(player)`) so its
--     Perception scans the roster the player is actually in, and with
--     `Archetype = Patroller.name` so a fixture kill carries the same
--     cause a real NPC's would,
--   * stands it on the floor a little east of the player's character
--     (world +X — the lobby floor extends well past 60 studs east of
--     the spawn pads, whichever way the character happens to face),
--   * wires its NPCController but does NOT tick it yet.
--
-- The tick starts on `fixture:engage()`, which each suite calls once
-- its own setup is ready — after teleporting the player into range, or
-- after `npc_deals_damage`'s wait for the player's health to settle.
-- Ticking from `ensure()` let the rig open fire during that wait, so
-- the health never settled and the suite failed in setup.
--
-- `teardown()` always owns the rig: it disconnects, destroys the
-- controller and removes the Model.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local Patroller = require(ReplicatedStorage.Shared.NPC.Archetypes.Patroller)
local NPCController = require(ServerScriptService.Server.NPC.Scripts.NPCController)

-- Distinct from NPCService's `Patroller_<n>` names so the fixture can
-- never be mistaken for, or collide with, an arena set's rig.
local FIXTURE_NAME = "Patroller_Fixture"
-- Where the rig is stood relative to the player's character: inside
-- combat range on the world X axis, a little above the floor so it
-- drops onto it rather than clipping in.
local FIXTURE_DISTANCE = NPCConstants.COMBAT_ENGAGE_DISTANCE - 10
local FIXTURE_HEIGHT = 3
-- Fallback when there is no character to stand next to.
local FALLBACK_POSITION = Vector3.new(0, 10, 0)

export type Fixture = {
	npc: Model,
	controller: NPCController.NPCControllerInstance,
	tickConnection: RBXScriptConnection?,
	-- Start ticking the controller. Idempotent.
	engage: (self: Fixture) -> (),
}

local Helpers = {}

local function engage(self: Fixture)
	if self.tickConnection then
		return
	end
	local controller = self.controller
	self.tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		controller:tick(dt)
	end)
end

function Helpers.ensure(player: Player?): Fixture?
	local aiWorldData = ServerStorage:FindFirstChild("AIWorldData")
	local rigs = aiWorldData and aiWorldData:FindFirstChild("Rigs")
	local template = rigs and rigs:FindFirstChild("Patroller")
	if not template or not template:IsA("Model") then
		return nil
	end

	local npc = (template :: Model):Clone()
	npc.Name = FIXTURE_NAME

	local position = FALLBACK_POSITION
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		position = hrp.Position + Vector3.new(FIXTURE_DISTANCE, FIXTURE_HEIGHT, 0)
	end
	npc:PivotTo(CFrame.new(position))

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Patroller.walkSpeed
	end

	-- The arena whose roster this rig perceives, and what its kills are
	-- credited to — the same two stamps NPCService puts on a real spawn.
	if player then
		npc:SetAttribute(Arena.ID_ATTRIBUTE, Arena.idOf(player))
	end
	npc:SetAttribute(NPCConstants.ARCHETYPE_ATTRIBUTE, Patroller.name)

	npc.Parent = Workspace

	local controller = NPCController.new(npc, Patroller, nil)
	if not controller then
		npc:Destroy()
		return nil
	end

	local fixture: Fixture = {
		npc = npc,
		controller = controller,
		tickConnection = nil,
		engage = engage,
	}
	return fixture
end

function Helpers.teardown(fixture: Fixture?)
	if not fixture then
		return
	end
	if fixture.tickConnection then
		fixture.tickConnection:Disconnect()
		fixture.tickConnection = nil
	end
	fixture.controller:destroy()
	if fixture.npc.Parent then
		fixture.npc:Destroy()
	end
end

return Helpers
