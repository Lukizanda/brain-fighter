----------------------------------------------------------------------
-- LetterBlocks
----------------------------------------------------------------------
-- API for spawning the floating letter blocks the player shoots to
-- spell words. The blocks live in the world; the Spawner (NIM-9)
-- decides WHEN to spawn them and WHAT letters, but the geometry +
-- visual state + tag membership all flow through here.
--
-- See wiki/systems/LetterBlock.md.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local TAG = "LetterBlock"
local LETTER_ATTRIBUTE = "Block.Letter"
local COLOR_ATTRIBUTE = "Block.Color"

local COLOR_TINTS: { [string]: Color3 } = {
	red = Color3.fromHex("#dc2626"),
	green = Color3.fromHex("#16a34a"),
	blue = Color3.fromHex("#2563eb"),
}

local DEFAULT_LETTER = "A"
local DEFAULT_COLOR = "red"

local log = Logger.new("LetterBlocks")

local LetterBlocks = {}

LetterBlocks.TAG = TAG
LetterBlocks.LETTER_ATTRIBUTE = LETTER_ATTRIBUTE
LetterBlocks.COLOR_ATTRIBUTE = COLOR_ATTRIBUTE
LetterBlocks.COLOR_TINTS = COLOR_TINTS

local TemplatePath = script:WaitForChild("Template")
LetterBlocks.Template = TemplatePath

local function applyVisualState(block: Model)
	local letter = block:GetAttribute(LETTER_ATTRIBUTE) or DEFAULT_LETTER
	local color = block:GetAttribute(COLOR_ATTRIBUTE) or DEFAULT_COLOR

	local cube = block:FindFirstChild("Cube")
	if not cube or not cube:IsA("BasePart") then
		log:warn("LetterBlock has no Cube child:", block:GetFullName())
		return
	end

	local tint = COLOR_TINTS[color] or COLOR_TINTS[DEFAULT_COLOR]
	cube.Color = tint

	for _, child in ipairs(cube:GetChildren()) do
		if child:IsA("SurfaceGui") then
			local label = child:FindFirstChildOfClass("TextLabel")
			if label then
				label.Text = letter
			end
		elseif child:IsA("ParticleEmitter") then
			child.Color = ColorSequence.new(tint)
		end
	end
end

LetterBlocks.applyVisualState = applyVisualState

function LetterBlocks.spawn(letter: string, color: string, cframe: CFrame, parent: Instance?): Model
	assert(typeof(letter) == "string" and #letter >= 1, "letter must be a non-empty string")
	assert(COLOR_TINTS[color] ~= nil, "unknown color: " .. tostring(color))

	local block = TemplatePath:Clone()
	block:SetAttribute(LETTER_ATTRIBUTE, letter:upper():sub(1, 1))
	block:SetAttribute(COLOR_ATTRIBUTE, color)
	applyVisualState(block)
	if GameConfig.BLOCK_SCALE ~= 1 then
		block:ScaleTo(GameConfig.BLOCK_SCALE)
	end
	block:PivotTo(cframe)
	CollectionService:AddTag(block, TAG)
	block.Parent = parent or workspace
	return block
end

return LetterBlocks
