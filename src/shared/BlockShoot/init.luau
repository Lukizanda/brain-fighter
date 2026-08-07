--!strict

----------------------------------------------------------------------
-- BlockShoot
----------------------------------------------------------------------
-- Shared helpers for the block-shoot input loop. The LetterBlaster
-- controller (client) handles input wiring; the service (server)
-- handles destruction. This module provides the traversal + read
-- utilities both sides need.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local LetterBlasterConfig = require(ReplicatedStorage.Shared.LetterBlaster.LetterBlasterConfig)

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

-- The staff's Handle — the part everything about a shot hangs off. It
-- carries the Muzzle attachment the beam leaves from, and the Fire/Hit/
-- Fizzle Sounds, which live on it precisely because a Sound parented to a
-- BasePart is 3D-positional and one parented to the Tool is not.
function BlockShoot.resolveHandle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild(LetterBlasterConfig.HANDLE_NAME)
	if handle and handle:IsA("BasePart") then
		return handle :: BasePart
	end
	return nil
end

-- Where a shot leaves the staff, in world space.
--
-- Shared because both VMs need the same answer and must not disagree: the
-- firing client draws its own beam from here the frame it shoots, and the
-- server reads it again to tell every other client where that same beam
-- started. Deriving it server-side rather than accepting it in the
-- ConsumeBlock payload keeps the remote's trust surface exactly as narrow
-- as BlockShootValidation left it — a client can lie about which block it
-- shot, and is checked; it never gets to name a position at all.
--
-- Falls back to the Handle's own position if the Muzzle attachment is
-- missing (it is Studio-managed, not in the Rojo tree), and returns nil
-- if there is no Handle to fall back to.
function BlockShoot.muzzlePosition(tool: Tool): Vector3?
	local handle = BlockShoot.resolveHandle(tool)
	if not handle then
		return nil
	end
	local muzzle = handle:FindFirstChild(LetterBlasterConfig.MUZZLE_ATTACHMENT_NAME)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return handle.Position
end

function BlockShoot.readBlock(block: Model): (string?, string?)
	local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
	local color = block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
	return letter, color
end

return BlockShoot
