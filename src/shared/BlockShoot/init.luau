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

local KeyConstants = require(ReplicatedStorage.Shared.BlockSpawner.KeyConstants)
local SporeConstants = require(ReplicatedStorage.Shared.BlockSpawner.SporeConstants)
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
-- Deliberately shorter than the arena. The default arena's eight
-- BlockSpawnVolume parts span roughly 240 × 259 studs together (corner to
-- corner ~353) — per-arena since Phase 6 stage 2, and this is the one the
-- game ships with — so the far edge of
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

-- Whether the block carries the spore mark. Read before the block is
-- destroyed (a destroyed Model keeps its attributes, but a listener cannot
-- be told which block it was) and passed on as a plain flag: what a spore
-- does is not this module's business.
function BlockShoot.isSpore(block: Model): boolean
	return block:GetAttribute(SporeConstants.ATTRIBUTE) == true
end

-- The block's own, shorter tap reach in studs (key letters), or nil for a
-- block that can be popped from as far as any other. Measured from the
-- character's root to the block, not along the camera ray: "walk up to it"
-- has to mean the same whatever the zoom.
function BlockShoot.reachOf(block: Model): number?
	local reach = block:GetAttribute(KeyConstants.POP_REACH_ATTRIBUTE)
	if type(reach) == "number" and reach > 0 then
		return reach
	end
	return nil
end

-- Is `from` (a character's root position) close enough to pop `block`, as
-- far as the block's own reach goes? True for a block without one.
function BlockShoot.withinOwnReach(block: Model, from: Vector3, toleranceStuds: number?): boolean
	local reach = BlockShoot.reachOf(block)
	if reach == nil then
		return true
	end
	return (block:GetPivot().Position - from).Magnitude <= reach + (toleranceStuds or 0)
end

return BlockShoot
