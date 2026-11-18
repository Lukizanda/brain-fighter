--!strict

----------------------------------------------------------------------
-- KeyLetterVisuals
----------------------------------------------------------------------
-- Marks a gate's key letters (wiki/design/ai-playtest.md § Gate redesign) so
-- they read as "these open something" and show when the player is close
-- enough to pop them. A key letter is a letter block that carries a tap
-- reach of its own (KeyConstants.POP_REACH_ATTRIBUTE, written by the block
-- pool). Each gets a gold outline; its fill is faint while the local
-- character is out of that reach and brighter once inside it.
--
-- Client-only and cosmetic: the Highlight is created here, under the block,
-- and never replicated. The server decides whether a pop lands
-- (BlockShootValidation); BlockTapController refuses the tap first with the
-- same rule. Greybox look, no art.
--
-- A handful of key letters exist per arena (three or four per gate), well
-- inside the engine's budget of rendered Highlights.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local KeyConstants = require(ReplicatedStorage.Shared.BlockSpawner.KeyConstants)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("KeyLetterVisuals")
local C = KeyConstants

local player = Players.LocalPlayer

-- Marked blocks and their highlights.
local marks: { [Model]: Highlight } = {}
-- Blocks being watched for the reach attribute arriving after the tag.
local waiting: { [Model]: RBXScriptConnection } = {}

local function unmark(block: Model)
	local highlight = marks[block]
	if highlight then
		highlight:Destroy()
		marks[block] = nil
	end
	local connection = waiting[block]
	if connection then
		connection:Disconnect()
		waiting[block] = nil
	end
end

local function mark(block: Model)
	if marks[block] or BlockShoot.reachOf(block) == nil then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = C.HIGHLIGHT_NAME
	highlight.OutlineColor = C.OUTLINE_COLOR
	highlight.OutlineTransparency = C.OUTLINE_TRANSPARENCY
	highlight.FillColor = C.FILL_COLOR
	highlight.FillTransparency = C.FILL_TRANSPARENCY_FAR
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = block
	highlight.Parent = block
	marks[block] = highlight
end

local function watch(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local block = instance
	mark(block)
	-- The pool stamps the reach just after the block is tagged.
	if not marks[block] and not waiting[block] then
		waiting[block] = block:GetAttributeChangedSignal(C.POP_REACH_ATTRIBUTE):Connect(function()
			mark(block)
		end)
	end
end

CollectionService:GetInstanceAddedSignal(LetterBlocks.TAG):Connect(watch)
CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG):Connect(function(instance: Instance)
	if instance:IsA("Model") then
		unmark(instance)
	end
end)
for _, instance in CollectionService:GetTagged(LetterBlocks.TAG) do
	watch(instance)
end

local sinceRefresh = 0
RunService.Heartbeat:Connect(function(dt: number)
	sinceRefresh += dt
	if sinceRefresh < C.REFRESH_SEC then
		return
	end
	sinceRefresh = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for block, highlight in marks do
		local near = root ~= nil and root:IsA("BasePart") and BlockShoot.withinOwnReach(block, root.Position)
		highlight.FillTransparency = if near then C.FILL_TRANSPARENCY_NEAR else C.FILL_TRANSPARENCY_FAR
	end
end)

log:info("KeyLetterVisuals started")
