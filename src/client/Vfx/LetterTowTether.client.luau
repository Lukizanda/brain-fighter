--!strict

----------------------------------------------------------------------
-- LetterTowTether
----------------------------------------------------------------------
-- Draws the line between a letter block that is being pulled and the thing
-- pulling it, for as long as the tow lasts. The server (BlockSpawner's tow
-- API; the boss's hunger asks for it) tags the block with
-- `TowConstants.TAG` and publishes the point it is pulled toward as
-- `TowConstants.TARGET_ATTRIBUTE`, refreshed every tick, so the target can
-- move (the boss walks). The server draws nothing: this script owns what a
-- player sees (wiki/design/boss-arena.md § Letter pull, docs/agents/vfx-sfx.md).
--
-- A one-shot VfxBroadcast beam would not do: a tow lasts seconds and both
-- ends move. So: a Beam between an attachment on the block's cube (which
-- LetterBlockAnimator moves, so the line follows the block's bob and its
-- travel) and an attachment on a small invisible client-only part that eases
-- toward the published target. Tinted with the block's own colour, the way
-- the collect stream is. Everything here is client-local and is removed when
-- the tag comes off or the block goes (eaten, popped, torn down).
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TowConstants = require(ReplicatedStorage.Shared.BlockSpawner.TowConstants)
local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LetterTowTether")

local CUBE_CHILD_NAME = "Cube"
local END_PART_SIZE = Vector3.one * 0.2

type Tether = {
	endPart: Part,
	-- Whether the end part has been placed yet; it snaps to the first
	-- published target instead of easing in from the origin.
	placed: boolean,
}

local tethers: { [Model]: Tether } = {}

local function removeTether(block: Model)
	local tether = tethers[block]
	if tether == nil then
		return
	end
	tethers[block] = nil
	tether.endPart:Destroy()
	local cube = block:FindFirstChild(CUBE_CHILD_NAME)
	local attachment = cube and cube:FindFirstChild(TowConstants.TETHER_BLOCK_ATTACHMENT_NAME)
	if attachment then
		attachment:Destroy()
	end
end

local function addTether(instance: Instance)
	if not instance:IsA("Model") or tethers[instance] ~= nil then
		return
	end
	local block: Model = instance
	local cube = block:FindFirstChild(CUBE_CHILD_NAME)
	if cube == nil or not cube:IsA("BasePart") then
		return
	end

	local tint = Colors.tint(tostring(block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)))

	local startAttachment = Instance.new("Attachment")
	startAttachment.Name = TowConstants.TETHER_BLOCK_ATTACHMENT_NAME
	startAttachment.Parent = cube

	local endPart = Instance.new("Part")
	endPart.Name = TowConstants.TETHER_END_PART_NAME
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.CastShadow = false
	endPart.Transparency = 1
	endPart.Size = END_PART_SIZE
	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = TowConstants.TETHER_END_ATTACHMENT_NAME
	endAttachment.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Name = TowConstants.TETHER_BEAM_NAME
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.Color = ColorSequence.new(tint)
	beam.LightEmission = TowConstants.TETHER_LIGHT_EMISSION
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = TowConstants.TETHER_SEGMENTS
	beam.Width0 = TowConstants.TETHER_WIDTH_AT_BLOCK
	beam.Width1 = TowConstants.TETHER_WIDTH_AT_TARGET
	beam.CurveSize0 = TowConstants.TETHER_CURVE_STUDS
	beam.CurveSize1 = -TowConstants.TETHER_CURVE_STUDS
	beam.Transparency = NumberSequence.new(TowConstants.TETHER_TRANSPARENCY)
	beam.Parent = endPart

	-- Parked at the block until the first target arrives (the tag and the
	-- attributes replicate independently), so nothing flashes at the origin.
	endPart.Position = cube.Position
	endPart.Parent = workspace

	tethers[block] = { endPart = endPart, placed = false }
end

for _, block in ipairs(CollectionService:GetTagged(TowConstants.TAG)) do
	addTether(block)
end
CollectionService:GetInstanceAddedSignal(TowConstants.TAG):Connect(addTether)
CollectionService:GetInstanceRemovedSignal(TowConstants.TAG):Connect(function(instance)
	if instance:IsA("Model") then
		removeTether(instance)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	for block, tether in pairs(tethers) do
		if block.Parent == nil then
			removeTether(block)
			continue
		end
		local target = block:GetAttribute(TowConstants.TARGET_ATTRIBUTE)
		if typeof(target) ~= "Vector3" then
			continue
		end
		if not tether.placed then
			tether.placed = true
			tether.endPart.Position = target
		else
			tether.endPart.Position = tether.endPart.Position:Lerp(
				target,
				1 - math.exp(-TowConstants.FOLLOW_RATE_PER_SEC * dt)
			)
		end
	end
end)

log:info("LetterTowTether started")
