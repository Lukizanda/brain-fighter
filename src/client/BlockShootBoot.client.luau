--!strict

----------------------------------------------------------------------
-- BlockShootBoot
----------------------------------------------------------------------
-- Client input handler: left-click → raycast → hit LetterBlock →
-- append (letter, color) to the player's WordBuffer → fire
-- ConsumeBlock remote so the server destroys the block.
--
-- Gated by MindFullManager — shooting is blocked while the 12-slot
-- buffer is full.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local PlayerSession = require(script.Parent.PlayerSession)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BlockShootBoot")
local player = Players.LocalPlayer

local consumeRemote = ReplicatedStorage.Shared.BlockShoot.Remotes.ConsumeBlock :: RemoteEvent

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshRaycastFilter()
	local character = player.Character
	if character then
		raycastParams.FilterDescendantsInstances = { character }
	else
		raycastParams.FilterDescendantsInstances = {}
	end
end

player.CharacterAdded:Connect(refreshRaycastFilter)
if player.Character then
	refreshRaycastFilter()
end

local function onInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local session = PlayerSession.get()
	if session.mindFullManager:isMindFull() then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	refreshRaycastFilter()

	local mousePos = input.Position
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local result = workspace:Raycast(
		ray.Origin,
		ray.Direction * BlockShoot.MAX_RAYCAST_DISTANCE,
		raycastParams
	)

	if not result then
		return
	end

	local block = BlockShoot.findLetterBlock(result.Instance)
	if not block then
		return
	end

	local letter, color = BlockShoot.readBlock(block)
	if not letter or not color then
		return
	end

	local appended = session.wordBuffer:append(letter, color)
	if not appended then
		return
	end

	consumeRemote:FireServer(block)
	log:info(string.format("consumed %s (%s)", letter, color))
end

UserInputService.InputBegan:Connect(onInputBegan)
log:info("BlockShootBoot started")
