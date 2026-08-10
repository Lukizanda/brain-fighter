--!strict

----------------------------------------------------------------------
-- BlockShoot
----------------------------------------------------------------------
-- Shared helpers for the block-consume loop. BlockTapController
-- (client) handles input wiring; BlockShootService (server) handles
-- destruction. This module provides the traversal + read utilities
-- both sides need.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

-- How far a tap can reach.
--
-- Raised 200 → 1400 on 2026-08-10. 200 could not cross the arena: the
-- BlockSpawnVolume parts span roughly 240 × 259 studs, so corner to
-- corner is ~353 studs and the far half of the field was simply
-- unpoppable from where you stood.
--
-- Everything downstream derives from this one number — the server's
-- MAX_CONSUME_DISTANCE_STUDS and the Hardening suite's out-of-range
-- fixture both scale with it — so this is the only place reach is
-- tuned.
local MAX_RAYCAST_DISTANCE = 1400

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
