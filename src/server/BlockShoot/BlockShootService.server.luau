--!strict

----------------------------------------------------------------------
-- BlockShootService
----------------------------------------------------------------------
-- Server handler for ConsumeBlock remote. Validates the block is a
-- tagged LetterBlock, then destroys it. The BlockSpawner's
-- CollectionService removed-signal handler auto-refills the arena.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BlockShootService")

local consumeRemote = ReplicatedStorage.Shared.BlockShoot.Remotes.ConsumeBlock :: RemoteEvent

consumeRemote.OnServerEvent:Connect(function(_player: Player, block: any)
	if typeof(block) ~= "Instance" then
		return
	end
	if not block:IsA("Model") then
		return
	end
	if not CollectionService:HasTag(block, LetterBlocks.TAG) then
		return
	end
	block:Destroy()
end)

log:info("BlockShootService ready")
