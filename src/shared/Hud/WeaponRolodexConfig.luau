----------------------------------------------------------------------
-- WeaponRolodexConfig
----------------------------------------------------------------------
-- Styling for the single-card weapon rolodex. The card is a square,
-- sized to the icon area. A vertical gradient behind the icon
-- (solid at the bottom, transparent at the top) highlights the
-- icon silhouette against the world. Ammo and slot labels overlay
-- the icon as small pill-shaped badges.
----------------------------------------------------------------------

local WeaponRolodexConfig = {
	-- Uniform scale applied to the whole Rolodex container. 1 = 100%, 0.8 = 80%.
	-- Shrinks/grows dimensions, text sizes, padding, and margins together
	-- without needing to retune individual knobs.
	UI_SCALE = 0.8,

	-- Card — square, dimensions match the icon area
	CARD_SIZE = 160,
	-- Card corner radius. UDim.new(0, 8) = rounded rect with 8px corners.
	-- UDim.new(0.5, 0) = perfect circle (assumes square CARD_SIZE).
	-- UDim.new(0, 0) = sharp square.
	CARD_CORNER_RADIUS = UDim.new(0.95, 0),

	-- Gradient background (UIGradient on the card frame).
	-- Color is constant; transparency varies along the rotation axis.
	GRADIENT_COLOR = Color3.fromRGB(18, 22, 38),
	GRADIENT_BOTTOM_TRANSPARENCY = 0.15,
	GRADIENT_TOP_TRANSPARENCY = 1.0,
	GRADIENT_ROTATION = 45, -- 0 = top, 1 = bottom in the sequence
	-- Fraction of the gradient axis that stays fully transparent before the
	-- fade to the bottom colour begins (0-1). 0 = classic linear ramp across
	-- the whole card; 0.5 = only the bottom half of the axis fades, so the
	-- opaque glow is compressed into that corner. Higher = tighter corner.
	GRADIENT_FALLOFF_START = 0.6,

	ACTIVE_BORDER_COLOR = Color3.fromRGB(240, 200, 80),
	BORDER_THICKNESS = 0,

	-- Icon — fills the card (weapon render already has its own padding
	-- baked in, so no extra padding layer needed here)
	ICON_CORNER_RADIUS = 8,

	-- Ammo pill (bottom-right overlay) — firearms only
	AMMO_FONT = Enum.Font.GothamBold,
	AMMO_TEXT_SIZE = 20,
	AMMO_TEXT_COLOR = Color3.fromRGB(240, 240, 245),
	AMMO_PILL_BG_COLOR = Color3.fromRGB(8, 8, 12),
	AMMO_PILL_BG_TRANSPARENCY = 0.2,
	AMMO_PILL_CORNER_RADIUS = 6,
	AMMO_PILL_PADDING_X = 8,
	AMMO_PILL_PADDING_Y = 3,
	-- Offset from the bottom-right corner of the card. Bump Y to pull the
	-- pill up; bump X to pull it inward toward the card centre.
	AMMO_PILL_MARGIN_X = 2,
	AMMO_PILL_MARGIN_Y = 16,

	-- Slot label (top-left overlay) — tiny role tag (PRIMARY / MELEE).
	-- Set SHOW_SLOT_LABEL to false to hide the pill entirely (also hides the
	-- "No Weapon" empty-state text, which renders in the same pill).
	SHOW_SLOT_LABEL = false,
	SLOT_LABEL_FONT = Enum.Font.GothamMedium,
	SLOT_LABEL_TEXT_SIZE = 11,
	SLOT_LABEL_TEXT_COLOR = Color3.fromRGB(210, 210, 220),
	SLOT_LABEL_PILL_BG_COLOR = Color3.fromRGB(8, 8, 12),
	SLOT_LABEL_PILL_BG_TRANSPARENCY = 0.3,
	SLOT_LABEL_PILL_CORNER_RADIUS = 4,
	SLOT_LABEL_PILL_PADDING_X = 6,
	SLOT_LABEL_PILL_PADDING_Y = 2,
	SLOT_LABEL_PILL_MARGIN = 6,

	-- Special indicator card — stacked above the main card. Smaller so the
	-- main (active Normal) card stays the attention anchor. Empty state
	-- shows a placeholder silhouette instead of hiding.
	SPECIAL_CARD_SCALE = 0.7, -- multiplier of CARD_SIZE
	SPECIAL_CARD_SPACING = 10, -- pixels between special card and main card
	SPECIAL_EMPTY_TEXT = "No Special",
	-- When no Special is held we fade the card further so the empty slot
	-- reads as absent rather than just unlit.
	SPECIAL_EMPTY_GRADIENT_BOTTOM_TRANSPARENCY = 0.7,

	-- Cooldown overlay shown on the Special card when _cooldownEnd is in
	-- the future. Covers the icon with a dark tint + centered countdown.
	COOLDOWN_OVERLAY_COLOR = Color3.fromRGB(0, 0, 0),
	COOLDOWN_OVERLAY_TRANSPARENCY = 0.45,
	COOLDOWN_TEXT_FONT = Enum.Font.GothamBold,
	COOLDOWN_TEXT_COLOR = Color3.fromRGB(240, 240, 245),
	COOLDOWN_TEXT_SIZE = 32,

	-- Dot indicators (below card, show weapon count + current index)
	DOT_SIZE = 6,
	DOT_SPACING = 8,
	DOT_ACTIVE_COLOR = Color3.fromRGB(240, 200, 80),
	DOT_INACTIVE_COLOR = Color3.fromRGB(80, 80, 90),
	DOT_ROW_OFFSET_Y = 6,

	-- Swipe detection
	SWIPE_MIN_DISTANCE = 30, -- pixels: minimum drag to register as swipe
	SWIPE_MAX_VERTICAL = 50, -- pixels: max vertical drift before swipe is rejected

	-- Slide animation
	SLIDE_TWEEN_TIME = 0.15,
	SLIDE_TWEEN_STYLE = Enum.EasingStyle.Quad,
	SLIDE_TWEEN_DIRECTION = Enum.EasingDirection.Out,
	SLIDE_OFFSET_X = 40,

	-- Empty state (no weapons held) — hide gradient, show text
	EMPTY_TEXT = "No Weapon",
	EMPTY_TEXT_COLOR = Color3.fromRGB(120, 120, 130),
	EMPTY_GRADIENT_BOTTOM_TRANSPARENCY = 1,

	-- Text stroke for readability when overlay falls on the icon
	TEXT_STROKE_COLOR = Color3.fromRGB(0, 0, 0),
	TEXT_STROKE_TRANSPARENCY = 0.3,
}

return WeaponRolodexConfig
