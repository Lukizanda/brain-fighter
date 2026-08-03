--!strict

----------------------------------------------------------------------
-- BlockShootValidation
----------------------------------------------------------------------
-- Trust checks for the ConsumeBlock remote, split out of the service so
-- they can be exercised by the Hardening test suite without a live
-- remote fire. Each check returns (ok, reason) — the reason string is
-- for the server log only and is never sent back to the client.
--
-- These are deliberately instance-level checks. They bound *what* a
-- client may destroy and *how fast*; they do not and cannot verify the
-- letter actually reached that player's word buffer, which lives
-- client-side. See wiki/systems/BlockShootService.md § Trust model.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local BlockShootConstants = require(script.Parent.BlockShootConstants)

local TypeValidation = script.Parent.Parent.Utility.TypeValidation
local validateInstance = require(TypeValidation.validateInstance)
local validateVector3 = require(TypeValidation.validateVector3)

local BlockShootValidation = {}

-- Is `block` a real, still-live LetterBlock in the world?
--
-- validateInstance is what rejects the classic exploit of passing a
-- table shaped like a Model. The IsDescendantOf(workspace) check does
-- double duty: it rejects the LetterBlocks.Template sitting in
-- ReplicatedStorage, and it makes a double-consume race a no-op, since
-- the first Destroy already unparented the block.
function BlockShootValidation.checkBlock(block: any): (Model?, string?)
	if not validateInstance(block, "Model") then
		return nil, "not a Model instance"
	end
	local model = block :: Model

	if not model:IsDescendantOf(workspace) then
		return nil, "not in workspace (already consumed, or not a world block)"
	end

	if not CollectionService:HasTag(model, LetterBlocks.TAG) then
		return nil, string.format("missing %s tag", LetterBlocks.TAG)
	end

	return model, nil
end

-- Is `block` close enough to the firing player's character to be a shot
-- they could plausibly have taken? Bounds cross-arena block griefing to
-- a fixed radius around the player.
function BlockShootValidation.checkRange(character: Model?, block: Model): (boolean, string?)
	if not character then
		return false, "no character"
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "no HumanoidRootPart"
	end

	local origin = (root :: BasePart).Position
	local blockPos = block:GetPivot().Position
	if not validateVector3(origin) or not validateVector3(blockPos) then
		return false, "non-finite position"
	end

	local distance = (blockPos - origin).Magnitude
	if distance > BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS then
		return false, string.format(
			"out of range (%.0f > %d studs)",
			distance,
			BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS
		)
	end

	return true, nil
end

return BlockShootValidation
