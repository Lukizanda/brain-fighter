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

local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local TAG = "LetterBlock"
local LETTER_ATTRIBUTE = "Block.Letter"
local COLOR_ATTRIBUTE = "Block.Color"

-- Gold marks the wildcard block. It sits alongside the three reservoir
-- colors deliberately: a player scanning the arena should be able to
-- pick a ★ out of a field of red/green/blue at a glance.
local COLOR_TINTS: { [string]: Color3 } = {
	red = Color3.fromHex("#dc2626"),
	green = Color3.fromHex("#16a34a"),
	blue = Color3.fromHex("#2563eb"),
	[Wildcard.COLOR] = Color3.fromHex("#eab308"),
}

local DEFAULT_LETTER = "A"
local DEFAULT_COLOR = "red"

----------------------------------------------------------------------
-- Face border
----------------------------------------------------------------------
-- A flat tinted cube has no silhouette: against the skybox or a lit
-- floor there is nothing separating the block from what is behind it,
-- and at distance the fill washes toward the background. A dark edge
-- on every face gives each block a hard outline and reads as the
-- chunky, cel-shaded look in wiki/design/ArtDirection.md.
--
-- Drawn as a UIStroke inside the face SurfaceGuis rather than as a
-- Highlight per block. Roblox renders a bounded number of Highlights
-- (~31) and the arena holds 40, so a permanent one per block would
-- exceed the budget and drop outlines unpredictably -- the same reason
-- BlockTapController keeps a single reused hover Highlight. GUI strokes
-- have no such cap, and a face the camera cannot see is not drawn, so
-- what renders is exactly the visible silhouette.
local BORDER_FRAME_NAME = "Border"

-- Thickness is in canvas pixels and needs no scaling: Model:ScaleTo
-- scales SurfaceGui.PixelsPerStud inversely to the part (4 studs x 50
-- and 6 studs x 33.3 are both a 200 px canvas) and leaves
-- UIStroke.Thickness alone, so one constant holds at any BLOCK_SCALE.
local BORDER_THICKNESS_PIXELS = 12

-- The stroke is the block's own tint driven most of the way to black,
-- not a shared black -- a red block's edge is deep maroon and a blue
-- one's is navy, so the silhouette still carries colour identity at the
-- distance where the fill has washed out.
--
-- Dark is forced rather than chosen. White is already the hover outline
-- and grey the out-of-reach one (BlockTapConfig), so a permanent light
-- border would leave the hover cue with nothing left to say. The
-- inverse constraint is on wiki/systems/LetterBlock.md: an outline in
-- the block's *own* tint is invisible against the block.
local BORDER_DARKEN = 0.72
local BLACK = Color3.new(0, 0, 0)

-- The border frame is inset by exactly its own thickness so a
-- centre-applied stroke lands flush with the canvas edge instead of
-- half outside it, where the face bounds would clip it.
local BORDER_INSET_PIXELS = BORDER_THICKNESS_PIXELS

-- The border frames the face, so it wins when it overlaps the glyph.
local BORDER_Z_INDEX = 2

----------------------------------------------------------------------
-- Face panel + glyph contrast
----------------------------------------------------------------------
-- A white glyph on a saturated fill is only moderate contrast, and the
-- fill is the loudest thing on the block, so the letter loses -- which
-- is backwards for a game where the letter is the thing you are
-- reading. The fix is to flip the glyph's immediate background rather
-- than the whole block: a dark plate inset in the face, with a bright
-- tinted glyph on top.
--
-- Deliberately NOT by darkening the cube body. The border above draws
-- its contrast from sitting on a bright fill; darkening the body would
-- collapse the two to the same value, and the border cannot be
-- lightened to compensate because white and grey are the hover and
-- out-of-reach cues. Keeping the body saturated also keeps a bold
-- colour ring between panel and border, which is what still reads at
-- the distance where a glyph is too small to resolve.
local PANEL_FRAME_NAME = "Panel"

-- Inset from the 200 px face, leaving ~14 px of cube colour visible on
-- each side between the border's inner edge and the plate.
local PANEL_INSET_PIXELS = 26
local PANEL_DARKEN = 0.84
local PANEL_Z_INDEX = 1

-- The glyph goes light-tinted rather than plain white: a red block's
-- letter reads hot red and a blue one's icy blue, so colour identity is
-- carried twice (body and glyph) instead of once.
local LETTER_LIGHTEN = 0.75
local WHITE = Color3.new(1, 1, 1)

-- The letter is TextScaled across the full face, so at authored size it
-- runs straight into the border. Pulling it in sits it inside the plate
-- with a margin, and makes a face read as a framed panel rather than a
-- sticker.
local LETTER_INSET_SCALE = 0.64
local LETTER_Z_INDEX = 3
local LETTER_LABEL_NAME = "Letter"

----------------------------------------------------------------------
-- Value tell
----------------------------------------------------------------------
-- A Q is worth ten times an E and until now they looked identical, so
-- scanning the arena was a hunt rather than a decision. The ambient
-- mana emitter carries it: the more a letter is worth, the more sparks
-- it throws and the bigger they are. Motion is the channel that
-- survives peripheral vision, which is exactly where a block the player
-- has not looked at yet lives.
--
-- Continuous in the Scrabble value rather than banded into rarity
-- tiers: EnergyEconomy's values already are the scale, and a threshold
-- here would invent a second one free to drift from it.
local EMITTER_RATE_AT_MIN_VALUE = 6
local EMITTER_RATE_AT_MAX_VALUE = 26

-- The template tapers Size from 0.30 to 0 over a spark's life. Only the
-- start point is driven, so the taper's shape survives.
local EMITTER_SIZE_AT_MIN_VALUE = 0.24
local EMITTER_SIZE_AT_MAX_VALUE = 0.62
local EMITTER_SIZE_END = 0

local MIN_LETTER_VALUE = 1
local MAX_LETTER_VALUE = 10

local log = Logger.new("LetterBlocks")

local LetterBlocks = {}

LetterBlocks.TAG = TAG
LetterBlocks.LETTER_ATTRIBUTE = LETTER_ATTRIBUTE
LetterBlocks.COLOR_ATTRIBUTE = COLOR_ATTRIBUTE
LetterBlocks.COLOR_TINTS = COLOR_TINTS

local TemplatePath = script:WaitForChild("Template")
LetterBlocks.Template = TemplatePath

-- Find-or-create rather than create: applyVisualState is documented
-- idempotent and re-runs whenever a block's attributes change, so a
-- blind Instance.new would stack a fresh border on every call.
local function applyFaceBorder(surface: SurfaceGui, tint: Color3)
	local existing = surface:FindFirstChild(BORDER_FRAME_NAME)
	local border: Frame
	if existing and existing:IsA("Frame") then
		border = existing
	else
		border = Instance.new("Frame")
		border.Name = BORDER_FRAME_NAME
		border.BackgroundTransparency = 1
		border.AnchorPoint = Vector2.new(0.5, 0.5)
		border.Position = UDim2.fromScale(0.5, 0.5)
		border.Size = UDim2.new(1, -BORDER_INSET_PIXELS, 1, -BORDER_INSET_PIXELS)
		border.ZIndex = BORDER_Z_INDEX
		border.Parent = surface
	end

	local strokeChild = border:FindFirstChildOfClass("UIStroke")
	local stroke: UIStroke
	if strokeChild then
		stroke = strokeChild
	else
		stroke = Instance.new("UIStroke")
		stroke.Thickness = BORDER_THICKNESS_PIXELS
		stroke.Parent = border
	end

	stroke.Color = tint:Lerp(BLACK, BORDER_DARKEN)
end

-- Same find-or-create contract as the border, for the same reason.
local function applyFacePanel(surface: SurfaceGui, tint: Color3)
	local existing = surface:FindFirstChild(PANEL_FRAME_NAME)
	local panel: Frame
	if existing and existing:IsA("Frame") then
		panel = existing
	else
		panel = Instance.new("Frame")
		panel.Name = PANEL_FRAME_NAME
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.new(1, -PANEL_INSET_PIXELS * 2, 1, -PANEL_INSET_PIXELS * 2)
		panel.BorderSizePixel = 0
		panel.ZIndex = PANEL_Z_INDEX
		panel.Parent = surface
	end

	panel.BackgroundColor3 = tint:Lerp(BLACK, PANEL_DARKEN)
end

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

-- EnergyEconomy.letterValue returns 0 for a wildcard: a star has no
-- fixed Scrabble value because it becomes whatever letter the word
-- needs. For the tell that has to read as the TOP of the scale, not the
-- bottom -- a star is the most valuable thing in the arena, and 0 would
-- render it the dullest block on screen.
local function tellValueFor(letter: string): number
	if Wildcard.isWildcard(letter) then
		return MAX_LETTER_VALUE
	end
	return math.clamp(EnergyEconomy.letterValue(letter), MIN_LETTER_VALUE, MAX_LETTER_VALUE)
end

-- `scale` is the block's current Model scale, and it is load-bearing.
-- Model:ScaleTo scales ParticleEmitter.Size (it is a length) but not
-- Rate, and spawn() applies the visual state *before* it scales. Sizing
-- against the current scale makes both orderings agree: at spawn the
-- scale is still 1 and ScaleTo multiplies afterwards; on an idempotent
-- re-apply the block is already scaled and nothing multiplies again.
-- Writing the bare constant would make a re-applied block's sparks
-- shrink by BLOCK_SCALE against a freshly spawned one.
--
-- UIStroke.Thickness and UDim offsets are NOT scaled this way -- the
-- face canvas stays 200 px at any scale -- so only Size needs it.
local function applyValueTell(emitter: ParticleEmitter, letter: string, scale: number)
	local alpha = (tellValueFor(letter) - MIN_LETTER_VALUE) / (MAX_LETTER_VALUE - MIN_LETTER_VALUE)

	emitter.Rate = lerp(EMITTER_RATE_AT_MIN_VALUE, EMITTER_RATE_AT_MAX_VALUE, alpha)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, lerp(EMITTER_SIZE_AT_MIN_VALUE, EMITTER_SIZE_AT_MAX_VALUE, alpha) * scale),
		NumberSequenceKeypoint.new(1, EMITTER_SIZE_END),
	})
end

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

	local scale = block:GetScale()

	for _, child in ipairs(cube:GetChildren()) do
		if child:IsA("SurfaceGui") then
			-- Panel first: it is the plate the glyph is read against, and
			-- the border is what frames both.
			applyFacePanel(child, tint)
			applyFaceBorder(child, tint)

			local label = child:FindFirstChild(LETTER_LABEL_NAME)
			if label and label:IsA("TextLabel") then
				-- Wildcards store "*" but read as "★" on the block face.
				label.Text = Wildcard.toDisplay(letter)
				-- Geometry and colour are set here rather than in the
				-- template so the glyph and the panel and border that
				-- frame it stay defined together -- the template lives in
				-- the .rbxl, where it would drift out of step silently.
				label.AnchorPoint = Vector2.new(0.5, 0.5)
				label.Position = UDim2.fromScale(0.5, 0.5)
				label.Size = UDim2.fromScale(LETTER_INSET_SCALE, LETTER_INSET_SCALE)
				label.TextColor3 = tint:Lerp(WHITE, LETTER_LIGHTEN)
				label.ZIndex = LETTER_Z_INDEX
			end
		elseif child:IsA("ParticleEmitter") then
			child.Color = ColorSequence.new(tint)
			applyValueTell(child, letter, scale)
		end
	end
end

LetterBlocks.applyVisualState = applyVisualState

-- Only reached if the Template's Cube is missing, which means the .rbxl
-- and the code have diverged. Matches the authored 4x4x4 so a spacing
-- calculation degrades to "right for the shipped prefab" rather than 0.
local TEMPLATE_STUDS_FALLBACK = 4

-- Diameter of the sphere a block sweeps as it turns -- a cube's
-- circumsphere, edge * sqrt(3). Two blocks whose centres are at least
-- this far apart cannot intersect at ANY orientation.
--
-- This is the number the spawner needs, and it lives here rather than as
-- a constant in GameConfig because it is a fact about the prefab's
-- geometry. It used to be hand-set (BLOCK_MIN_SPACING = 4) with a
-- comment asking whoever changed BLOCK_SCALE to update it by hand; that
-- coupling broke silently the moment BLOCK_SCALE went to 1.5, leaving a
-- 4-stud spacing rule guarding 6-stud blocks.
function LetterBlocks.tumbleDiameter(): number
	local cube = TemplatePath:FindFirstChild("Cube")
	local edge = if cube and cube:IsA("BasePart") then cube.Size.X else TEMPLATE_STUDS_FALLBACK
	return edge * GameConfig.BLOCK_SCALE * math.sqrt(3)
end

function LetterBlocks.spawn(letter: string, color: string, cframe: CFrame, parent: Instance?): Model
	assert(typeof(letter) == "string" and #letter >= 1, "letter must be a non-empty string")
	assert(COLOR_TINTS[color] ~= nil, "unknown color: " .. tostring(color))

	local block = TemplatePath:Clone()
	-- normalize() keeps the wildcard as "*" and reduces anything else to
	-- a single uppercase character.
	block:SetAttribute(LETTER_ATTRIBUTE, Wildcard.normalize(letter))
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
