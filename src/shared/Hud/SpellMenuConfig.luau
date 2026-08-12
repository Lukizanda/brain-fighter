----------------------------------------------------------------------
-- SpellMenuConfig
----------------------------------------------------------------------
-- Default styling for the three-color spell cast panel.
--
-- The panels are **circles**: mana fills outward from the centre and the
-- tier thresholds are concentric rings. See wiki/systems/ChargeCast.md
-- § Circular panels for what that shape encodes honestly and what it
-- does not, and for the arc-gauge alternative held in reserve.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local SpellMenuConfig = {
	-- Matches DashButtonConfig.SIZE, which is the circle sitting directly
	-- below these in the BottomRight column — three panels of a different
	-- diameter to the button under them reads as a mistake.
	--
	-- This is also the lever if the column gets too tall: at 180 with the
	-- touch-only DASH button visible the stack is ~776px at the 1080
	-- reference height, which is most of a phone screen.
	PANEL_DIAMETER = 180,
	BUTTON_GAP     = 10,
	-- Every layer in a panel is a circle: a square Frame carrying this
	-- corner radius. One constant, so the whole stack reverts to a rounded
	-- rectangle with a single edit if the circles do not work out.
	PANEL_CORNER_RADIUS = UDim.new(0.5, 0),

	-- Per-color panel backgrounds
	COLORS = {
		red   = { bg = Color3.fromRGB(180, 55, 55),  label = ""   },
		green = { bg = Color3.fromRGB(50, 155, 65),  label = "" },
		blue  = { bg = Color3.fromRGB(55, 105, 195), label = ""  },
	},

	-- Fill: dim base layer (always-visible "empty" disc) and the animated
	-- disc that grows out of the centre.
	--
	-- The base carries a second value for the below-T1 state, so a panel
	-- that cannot cast *recedes* as well as draining to grey. Alpha and
	-- saturation are separate channels and the eye reads them separately —
	-- grey alone still holds its ground in the layout, where grey plus
	-- transparent falls back behind the panels that matter.
	--
	-- Deliberately the dead value that moves rather than the live one.
	-- Making castable panels more opaque would brighten all three at once
	-- on a full reservoir, which is exactly when the HUD is already at its
	-- loudest; pushing the dead ones back costs nothing at that moment and
	-- pays out when only one colour is live.
	FILL_BASE_TRANSPARENCY      = 0.72,
	FILL_BASE_TRANSPARENCY_DEAD = 0.88,
	FILL_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FILL_MAX   = EnergyReservoirs.CAP_PER_COLOR,

	-- How mana maps to the disc's diameter: fraction = (mana / CAP) ^ N.
	--
	--   N = 1    diameter tracks mana. The tier rings land at 8 / 17 / 33 /
	--            67% of the panel — exactly where the old bar's notches sat
	--            — so the 5/10/20/40 cost curve reads unchanged: the first
	--            three tiers are bunched near the middle and whip past,
	--            while T4 is a long way out. Because area grows as the
	--            square, the disc looks emptier than the numeral says.
	--   N = 0.5  area tracks mana. The disc leaps out of the centre on the
	--            first few points and then crawls, and the rings space out
	--            almost evenly — which flatters the cost curve by hiding
	--            that T4 costs double T3.
	--
	-- One lever with two call sites behind it (the fill disc and every ring
	-- that has to line up with it), because which of these reads better is
	-- a feel question and the answer is expected to move.
	FILL_RADIUS_EXPONENT = 1,

	-- The disc's shading ramp, as a *multiplier* over its BackgroundColor3
	-- rather than as two absolute colours.
	--
	-- It used to be a ColorSequence of the panel's own hue, which meant the
	-- colour lived in two places at once (BackgroundColor3 and the
	-- gradient, multiplied together). That made the below-T1 desaturation
	-- below impossible to express as a tween, because TweenService cannot
	-- tween a ColorSequence. With the gradient reduced to a neutral ramp,
	-- BackgroundColor3 carries all the hue and one tween drains it. On a
	-- disc the top-lit ramp also does the work of making it read as a
	-- sphere rather than a flat coin.
	FILL_GRADIENT_BOTTOM_TINT = Color3.fromRGB(150, 150, 150),
	FILL_GRADIENT_TOP_TINT    = Color3.fromRGB(255, 255, 255),

	-- Text
	LABEL_FONT  = Enum.Font.GothamBold,
	LABEL_SIZE  = 26,
	TEXT_COLOR  = Color3.fromRGB(255, 255, 255),
	TEXT_STROKE = 0.5,

	-- Persistent mana numeral ("35/60"), in the middle of the circle.
	--
	-- Replaces the transient popup that used to appear on tap: a number you
	-- only see *after* committing to a cast is the wrong side of the
	-- decision, and hold-to-charge needs it readable the whole time,
	-- because it counts down live against the reserve band as the charge
	-- climbs.
	--
	-- It sat inset from the top-right corner while the panels were
	-- rectangles. On a circle the corners of the bounding box are empty
	-- space *outside* the disc, so the numeral floated in the void — and
	-- retiring the spell name freed up the centre. It now sits over the
	-- fill, so it carries a heavier stroke than a label on a flat
	-- background would need.
	NUMERAL_FONT   = Enum.Font.GothamBold,
	NUMERAL_SIZE   = 28,
	NUMERAL_HEIGHT = 30,
	NUMERAL_COLOR  = Color3.fromRGB(255, 255, 255),
	NUMERAL_DIM_COLOR = Color3.fromRGB(170, 170, 185),
	-- The reserved portion, shown while a charge is held. Matches
	-- CHARGE_RESERVE_COLOR so the number and the band read as one thing.
	NUMERAL_RESERVED_COLOR = Color3.fromRGB(255, 236, 150),
	NUMERAL_STROKE = 0.15,

	-- ── Tier rings ────────────────────────────────────────────────────
	-- Concentric rings at each TIER_COSTS threshold, drawn as a UIStroke on
	-- a circular Frame so the ring traces the corner radius exactly. The
	-- fill was continuous and therefore unreadable: memorizing CAT (5 red)
	-- moves a 0–60 fill by 8%, a barely visible nudge for what is actually
	-- a whole T1 cast. The ring it crosses is the event.
	--
	-- Heavier than the flat bar's notches, because a full-width horizontal
	-- line put a lot of ink on screen and the T1 ring — 8% of the panel
	-- across — puts down a small fraction of that. Weight is how it stays
	-- legible at MIN_SCALE.
	-- Dark rather than white, which is what the bar's notches were: a white
	-- line reads fine over a dim bar, but these rings spend most of their
	-- life sitting *on top of* a lit fill disc, where white on bright is
	-- almost nothing. A dark ring reads as a groove against both the fill
	-- and the empty base, and it is what makes the panel look turned rather
	-- than drawn.
	NOTCH_COLOR         = Color3.fromRGB(18, 16, 24),
	NOTCH_THICKNESS     = 3,
	NOTCH_TRANSPARENCY  = 0.45,
	-- The ring for the tier a held charge has currently reached, which
	-- inverts to white — the one moment it should be the brightest thing on
	-- the panel rather than the darkest.
	NOTCH_ACTIVE_COLOR        = Color3.fromRGB(255, 255, 255),
	NOTCH_ACTIVE_TRANSPARENCY = 0,
	NOTCH_THICKNESS_ACTIVE    = 6,
	NOTCH_TWEEN         = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- ── Below-T1 treatment ────────────────────────────────────────────
	-- A panel that cannot cast anything is drained toward grey, so
	-- "castable" is a state you can see across the whole HUD at a glance
	-- rather than a spell name you have to read. Snaps to full colour on
	-- the frame T1 becomes affordable, alongside the afford bounce.
	DESATURATED_GREY  = Color3.fromRGB(96, 96, 104),
	-- 0 = untouched, 1 = fully grey.
	DESATURATED_BLEND = 0.72,
	DESATURATED_TWEEN = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- ── Hold-to-charge ────────────────────────────────────────────────
	-- The annulus eaten out of the *outer* edge of the fill while a charge
	-- is held: the mana this release is about to spend. Nothing is drained
	-- until release (see wiki/systems/ChargeCast.md § Reserve, spend on
	-- release), so cancelling snaps the band away and costs nothing.
	--
	-- Built as a stroke on a circle sized to the post-spend radius, thick
	-- enough to reach the pre-spend radius — so the band always hugs the
	-- fill edge and eats inward, the radial reading of the band that used
	-- to sit at the top of the bar.
	CHARGE_RESERVE_COLOR        = Color3.fromRGB(255, 236, 150),
	CHARGE_RESERVE_TRANSPARENCY = 0.25,
	-- A UIStroke on a zero-size Frame does not render, and a T4 release
	-- spends the entire reservoir — so the inner edge is floored just off
	-- zero and the band survives its own extreme case.
	CHARGE_RESERVE_MIN_INNER_SCALE = 0.02,
	CHARGE_RESERVE_TWEEN        = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Snapping back on cancel is deliberately faster than growing: the
	-- refund should feel like nothing happened, not like an animation.
	CHARGE_RELEASE_TWEEN        = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- At the affordability ceiling the panel pulses instead of climbing —
	-- "this is as big as it gets", with no text.
	--
	-- A halo around the rim rather than a wash over the whole panel: the
	-- wash competed with the fill disc for the same pixels, and a ring
	-- outside the largest possible fill competes with nothing. It is also
	-- its own instance rather than a UIScale pulse, because
	-- playAffordBounce already owns the panel's UIScale and two systems
	-- tweening one property is the fight concepts/SingleOwnership exists to
	-- stop.
	CHARGE_CEILING_PULSE_COLOR = Color3.fromRGB(255, 255, 255),
	CHARGE_CEILING_RING_THICKNESS = 8,
	CHARGE_CEILING_PULSE_MIN   = 0.75,
	CHARGE_CEILING_PULSE_MAX   = 0.15,
	CHARGE_CEILING_PULSE_TWEEN = TweenInfo.new(
		0.42,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	),

	-- ── Ready glow ────────────────────────────────────────────────────
	-- A panel that can afford at least T1 breathes a coloured halo at its
	-- rim. The desaturation above already says "this one is dead"; nothing
	-- said "this one is loaded, press it", and a *negative* cue is the
	-- weaker half of the pair — grey only reads as grey once you have a lit
	-- panel next to it to compare against, which is exactly the case that
	-- does not hold when all three are drained or all three are full.
	--
	-- Two strokes rather than one, because a single UIStroke is a hard line
	-- and reads as a border — a thing the panel *has* — where a crisp edge
	-- over a soft inner bloom reads as light coming off it. Both breathe on
	-- one tween each, in phase.
	--
	-- Deliberately slow. The ceiling pulse below is 0.42s and means "act
	-- now, this is as big as it gets"; at ~1.2s this one is an idle
	-- heartbeat that should never compete with it for attention. The two
	-- never share the rim anyway — the glow is suppressed for whichever
	-- colour is being pressed.
	READY_GLOW_LIGHTEN         = 70,
	READY_GLOW_THICKNESS       = 4,
	READY_GLOW_DIM             = 0.62,
	READY_GLOW_BRIGHT          = 0.05,
	-- The inner bloom: thicker, fainter, and inset so it stays inside the
	-- rim. Keeping it inward-facing is what stops the halo eating BUTTON_GAP
	-- — only the 4px crisp stroke bleeds outward, so two adjacent lit panels
	-- still have 2px of air between them.
	READY_BLOOM_THICKNESS      = 10,
	READY_BLOOM_DIM            = 1,
	READY_BLOOM_BRIGHT         = 0.72,
	READY_GLOW_TWEEN = TweenInfo.new(
		1.2,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	),

	-- ── Ready motes ───────────────────────────────────────────────────
	-- Sparks orbiting just inside the rim while the panel can cast. The
	-- halo alone is a static shape that the eye stops seeing; motion is
	-- what survives peripheral vision, and the cast panels live in the
	-- corner of the screen where that is the only vision they get.
	--
	-- **Not a ParticleEmitter** — that is a 3D instance and does not exist
	-- in a ScreenGui. These are plain circular Frames on a transparent ring
	-- whose *Rotation* is tweened, so the orbit costs one tween per panel
	-- and no per-frame code. Being circles already, the panels made this
	-- the cheap option; on the old rectangles it would have needed a
	-- Heartbeat and a path.
	READY_MOTE_COUNT   = 6,
	READY_MOTE_SIZE    = 6,
	-- Sizes and twinkle periods are jittered per mote so the ring reads as
	-- six sparks rather than one rotating cog. Without it, three panels
	-- lit by the same Memorize twinkle in lockstep, which looks mechanical.
	READY_MOTE_SIZE_JITTER = 2,
	-- Fraction of the panel *radius*. At 0.46 of a 180px panel a 6px mote
	-- sits just inside the 4px glow stroke, so nothing crosses BUTTON_GAP.
	READY_MOTE_RADIUS  = 0.46,
	-- Lit well past the halo: a spark reads as a spark by being near-white
	-- at its core, and only keeps the panel's hue at the edges.
	READY_MOTE_LIGHTEN = 130,
	READY_MOTE_DIM     = 0.85,
	READY_MOTE_BRIGHT  = 0.1,
	READY_MOTE_ORBIT_SECONDS   = 6,
	READY_MOTE_TWINKLE_SECONDS = 0.9,
	READY_MOTE_TWINKLE_JITTER  = 0.35,
	-- Linear and non-reversing: 360° is the same picture as 0°, so the
	-- repeat is seamless and an eased orbit would visibly stall at the loop.
	READY_MOTE_ORBIT_TWEEN_STYLE = Enum.EasingStyle.Linear,

	-- UI VFX tweens
	AFFORD_BOUNCE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	AFFORD_BOUNCE_SCALE = 1.08,
	FIRED_FLASH_TWEEN   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FIRED_DIM_TWEEN     = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

return SpellMenuConfig
