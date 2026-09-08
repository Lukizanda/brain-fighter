--!strict

----------------------------------------------------------------------
-- ensurePatroller
----------------------------------------------------------------------
-- NPC suite fixture: guarantees `workspace.Patroller_1` exists and is
-- being driven by a live NPCController before a test reads its
-- `CurrentState` attribute or expects it to react to the player.
--
-- The common case is a no-op: NPCService.server.luau boot-spawns
-- Patroller_1 (and friends) from ServerStorage.AIWorldData spawn
-- points a few seconds into every playtest, well before
-- TestAutoRunner's STARTUP_DELAY_SECONDS wait elapses. `ensure()`
-- reuses that instance (`created = false`) and does nothing further.
--
-- If the place has no AIWorldData spawn points configured, no
-- Patroller_1 exists at all. In that case this clones the raw rig
-- from ServerStorage.AIWorldData.Rigs.Patroller, wires it to its own
-- NPCController (the same module NPCService uses), and ticks it on
-- Heartbeat for the duration of the test. `teardown()` only tears
-- down what `ensure()` created — a boot-spawned Patroller_1 is never
-- touched, since other systems (and other tests in the same "all" run)
-- depend on it staying alive.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Patroller = require(ReplicatedStorage.Shared.NPC.Archetypes.Patroller)
local NPCController = require(ServerScriptService.Server.NPC.Scripts.NPCController)

local PATROLLER_NAME = "Patroller_1"
local FALLBACK_SPAWN_HEIGHT = 10

export type Fixture = {
	npc: Model,
	created: boolean,
	controller: NPCController.NPCControllerInstance?,
	tickConnection: RBXScriptConnection?,
}

local Helpers = {}

function Helpers.ensure(): Fixture?
	local existing = Workspace:FindFirstChild(PATROLLER_NAME)
	if existing and existing:IsA("Model") then
		return { npc = existing, created = false }
	end

	local aiWorldData = ServerStorage:FindFirstChild("AIWorldData")
	local rigs = aiWorldData and aiWorldData:FindFirstChild("Rigs")
	local template = rigs and rigs:FindFirstChild("Patroller")
	if not template or not template:IsA("Model") then
		return nil
	end

	local npc = (template :: Model):Clone()
	npc.Name = PATROLLER_NAME
	npc:PivotTo(CFrame.new(0, FALLBACK_SPAWN_HEIGHT, 0))

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Patroller.walkSpeed
	end

	npc.Parent = Workspace

	local controller = NPCController.new(npc, Patroller, nil)
	if not controller then
		npc:Destroy()
		return nil
	end

	local conn = RunService.Heartbeat:Connect(function(dt: number)
		controller:tick(dt)
	end)

	return { npc = npc, created = true, controller = controller, tickConnection = conn }
end

function Helpers.teardown(fixture: Fixture?)
	if not fixture or not fixture.created then
		return
	end
	if fixture.tickConnection then
		fixture.tickConnection:Disconnect()
	end
	if fixture.controller then
		fixture.controller:destroy()
	end
	if fixture.npc and fixture.npc.Parent then
		fixture.npc:Destroy()
	end
end

return Helpers
