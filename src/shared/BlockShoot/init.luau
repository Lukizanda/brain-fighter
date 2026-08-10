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
-- 200, the value LetterBlaster shipped with. It went to 1400 briefly on
-- 2026-08-10 while chasing a "range is too short" report, then back:
-- the reach was never the problem. Taps were landing only within ~30
-- studs because BlockTapController mispaired its mouse coordinate space
-- with the camera method, which capped effective reach far below this
-- number and made every value of it feel identical. See the aim note in
-- BlockTapController.tryPop.
--
-- Deliberately shorter than the arena. The BlockSpawnVolume parts span
-- roughly 240 × 259 studs (corner to corner ~353), so the far edge of
-- the field is out of reach by design — you close on blocks rather than
-- clearing the map from spawn. That also keeps the server's derived
-- bound meaningful as an anti-grief limit rather than a formality.
--
-- Everything downstream derives from this one number — the server's
-- MAX_CONSUME_DISTANCE_STUDS and the Hardening suite's out-of-range
-- fixture both scale with it — so this is the only place reach is
-- tuned.
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
