--!strict

----------------------------------------------------------------------
-- CosmeticRing — a flat ground marker: an outline plus a fill that grows.
----------------------------------------------------------------------
-- Geometry and Parts only, so both the lob telegraph (CosmeticLob) and the
-- armed-spore burst radius (SporeLetterVisuals) can require it without
-- depending on each other, the Skills layer or the Boss layer.
--
-- One thin invisible Part lying on the surface with a top-face SurfaceGui:
-- a round Frame with a UIStroke is the outline, a second round Frame scaled
-- from the centre is the fill. It reads as an outline, not a slab, so
-- several can overlap. No image assets (third-party images do not load).
--
-- Client-local and nothing here can block a ray: CanCollide, CanQuery and
-- CanTouch are all false. The caller owns the lifetime (`destroy`).
----------------------------------------------------------------------

local CosmeticRing = {}

-- The top face is drawn at this density, so a stroke of N studs is the same
-- width on a 3-stud marker and an 8-stud one.
local PIXELS_PER_STUD = 32
-- The Part is a sheet; the SurfaceGui is on its top face.
local SHEET_THICKNESS_STUDS = 0.1
-- How far above the surface the top face sits, so it does not z-fight.
local SURFACE_CLEARANCE_STUDS = 0.15
-- 0.3 broke up into dashes at 30 studs (playtest 2026-11-20).
local DEFAULT_STROKE_STUDS = 0.6
local DEFAULT_OUTLINE_TRANSPARENCY = 0.1
local DEFAULT_FILL_TRANSPARENCY = 0.6
local FULL_CORNER_RADIUS = 0.5
local DIAMETER_PER_RADIUS = 2
local CENTRE = 0.5
local PART_NAME = "CosmeticRing"

export type RingStyle = {
	radius: number,
	color: Color3,
	-- Defaults to `color`.
	fillColor: Color3?,
	strokeStuds: number?,
	outlineTransparency: number?,
	fillTransparency: number?,
}

export type Ring = {
	part: Part,
	-- 0 to 1: the fill's radius as a fraction of the marker's.
	setFill: (fraction: number) -> (),
	destroy: () -> (),
}

local function round(frame: Frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(FULL_CORNER_RADIUS, 0)
	corner.Parent = frame
end

-- `ground` is the surface point the ring is centred on.
function CosmeticRing.new(ground: Vector3, style: RingStyle): Ring
	local diameter = style.radius * DIAMETER_PER_RADIUS
	local strokeStuds = style.strokeStuds or DEFAULT_STROKE_STUDS
	local strokePixels = math.max(1, math.floor(strokeStuds * PIXELS_PER_STUD))

	local part = Instance.new("Part")
	part.Name = PART_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(diameter, SHEET_THICKNESS_STUDS, diameter)
	part.CFrame = CFrame.new(
		ground.X,
		ground.Y + SURFACE_CLEARANCE_STUDS - SHEET_THICKNESS_STUDS * CENTRE,
		ground.Z
	)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.Adornee = part
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Parent = part

	-- Inset by the stroke so the outline is not clipped by the canvas edge.
	local outline = Instance.new("Frame")
	outline.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	outline.Position = UDim2.fromScale(CENTRE, CENTRE)
	outline.Size = UDim2.new(1, -strokePixels * 2, 1, -strokePixels * 2)
	outline.BackgroundTransparency = 1
	outline.Parent = gui
	round(outline)

	local stroke = Instance.new("UIStroke")
	stroke.Color = style.color
	stroke.Thickness = strokePixels
	stroke.Transparency = style.outlineTransparency or DEFAULT_OUTLINE_TRANSPARENCY
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = outline

	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	fill.Position = UDim2.fromScale(CENTRE, CENTRE)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = style.fillColor or style.color
	fill.BackgroundTransparency = style.fillTransparency or DEFAULT_FILL_TRANSPARENCY
	fill.BorderSizePixel = 0
	fill.Visible = false
	fill.Parent = outline
	round(fill)

	part.Parent = workspace

	return {
		part = part,
		setFill = function(fraction: number)
			local clamped = math.clamp(fraction, 0, 1)
			fill.Visible = clamped > 0
			fill.Size = UDim2.fromScale(clamped, clamped)
		end,
		destroy = function()
			part:Destroy()
		end,
	}
end

return CosmeticRing
