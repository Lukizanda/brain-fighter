--!strict

----------------------------------------------------------------------
-- BlockShoot
----------------------------------------------------------------------
-- Shared helpers for the block-shoot input loop. The boot script
-- (client) handles input wiring; the service (server) handles
-- destruction. This module provides the traversal + read utilities
-- both sides need.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

local MAX_RAYCAST_DISTANCE = 200

local BlockShoot = {}

BlockShoot.MAX_RAYCAST_DISTANCE = MAX_RAYCAST_DISTANCE

function BlockShoot.findLetterBlock(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("Model") and CollectionService:HasTag(current, LetterBlocks.TAG) then
			return current :: Model
		end
		current = current.Parent
	end
	return nil
end

function BlockShoot.readBlock(block: Model): (string?, string?)
	local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
	local color = block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
	return letter, color
end

return BlockShoot
