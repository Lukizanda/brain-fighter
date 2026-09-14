--!strict

----------------------------------------------------------------------
-- MotePath
----------------------------------------------------------------------
-- The curved flight a small glowing Part takes from somewhere in the
-- world to a *moving* destination, shared by the two effects that draw
-- one (refactor chunk 10, audit F28):
--
--   ChargeOrbVfx — mana pulled off a ring at the caster's feet up into
--                  the charge orb above their head
--   collectStream — a popped block's mana flowing onto the player who
--                  popped it
--
-- Both had their own copy of the same three things: a quadratic Bézier,
-- a control point bowed sideways in a random roll around the direction of
-- travel, and a per-mote flight time shaved by a jitter fraction. The
-- copies had already drifted in the way duplicated maths does — same
-- formulas, different spellings — so a fix to the swirl would have had to
-- be made twice, and the second one silently forgotten.
--
-- What stays with the callers is every *number*: ring radius, mote size,
-- curve amount, flight length. Those are the look of one effect, and the
-- two effects are not supposed to match — a block's take is a quick shower
-- off a surface, a charge is a slow inward pull. Only the shape of the
-- motion lives here.
--
-- The destination is passed per frame to `positionAt` rather than baked
-- into the Path, because in both callers it is attached to something that
-- is running: a mote whose endpoint was fixed at spawn curves gracefully
-- into the patch of ground where its target used to be.
--
-- Pure maths and Instance-free: nothing here creates, parents or destroys
-- anything, so it is safe on either VM and needs no VM check.
----------------------------------------------------------------------

-- A mote's flight, fixed at spawn. `control` is the Bézier's P1, already
-- bowed; `origin` is P0. P2 arrives per frame.
export type Path = {
	origin: Vector3,
	control: Vector3,
	duration: number,
}

-- Where the bow is hung: halfway along the straight line to the target.
-- Pulling it toward either end would make the swirl lopsided.
local CONTROL_MIDPOINT_ALPHA = 0.5

-- The bow's length, as a band of the caller's curve amount. Never zero at
-- the bottom of the band: a mote with no bow travels the straight line
-- every other mote is bowing away from, which reads as one stray.
local BOW_MIN_FRACTION  = 0.3
local BOW_SPAN_FRACTION = 0.7

-- Below this a Vector3 is treated as having no direction at all, and the
-- fallback axis is used instead. Covers a mote that spawned on top of its
-- own target and a travel vector that happens to lie along the world up
-- axis, both of which would otherwise produce a zero-length cross product
-- and a NaN bow.
local DEGENERATE_MAGNITUDE = 0.01

local MotePath = {}

-- A fraction inside a named band — the one-line idiom both callers used
-- inline for radius, bow and flight jitter. Here so the bands can be
-- named constants at their call sites instead of two bare literals buried
-- in an expression.
function MotePath.jitterFraction(minFraction: number, spanFraction: number): number
	return minFraction + math.random() * spanFraction
end

-- A uniformly-signed direction in the unit cube, normalised. Used by
-- callers that spawn motes on a shell around a point rather than on a
-- ring; `Vector3.yAxis` for the vanishingly rare all-zero draw.
function MotePath.randomDirection(): Vector3
	local dir = Vector3.new(
		math.random() * 2 - 1,
		math.random() * 2 - 1,
		math.random() * 2 - 1
	)
	if dir.Magnitude < DEGENERATE_MAGNITUDE then
		return Vector3.yAxis
	end
	return dir.Unit
end

-- The flight from `spawnAt` to wherever `toward` is now.
--
-- `curveStuds` is how far the path bows sideways at its widest, before the
-- band above is applied; the roll around the travel axis is random per
-- mote, which is what makes a cloud spiral in instead of collapsing into
-- one plane. `flightJitter` only ever shortens the flight — callers tear
-- their motes down on a shared clock, so a mote handed a longer one would
-- be destroyed in mid-air short of its target.
function MotePath.new(
	spawnAt: Vector3,
	toward: Vector3,
	curveStuds: number,
	flightSec: number,
	flightJitter: number
): Path
	local travel = toward - spawnAt
	local axis = if travel.Magnitude > DEGENERATE_MAGNITUDE then travel.Unit else Vector3.yAxis

	local perp = axis:Cross(Vector3.yAxis)
	if perp.Magnitude < DEGENERATE_MAGNITUDE then
		-- Travelling straight up or down: any horizontal axis will do.
		perp = axis:Cross(Vector3.xAxis)
	end

	local roll = CFrame.fromAxisAngle(axis, math.random() * math.pi * 2)
	local bow = (roll * perp.Unit)
		* (curveStuds * MotePath.jitterFraction(BOW_MIN_FRACTION, BOW_SPAN_FRACTION))

	return {
		origin   = spawnAt,
		control  = spawnAt:Lerp(toward, CONTROL_MIDPOINT_ALPHA) + bow,
		duration = flightSec * (1 - math.random() * flightJitter),
	}
end

-- Quadratic Bézier sample. P2 is the live destination, passed in rather
-- than stored — see the header.
function MotePath.positionAt(path: Path, toward: Vector3, alpha: number): Vector3
	local inv = 1 - alpha
	return (path.origin * (inv * inv))
		+ (path.control * (2 * inv * alpha))
		+ (toward * (alpha * alpha))
end

-- Motes shrink as they arrive, so the cloud visually enters its
-- destination instead of piling up on it and popping out. `endScale` is
-- the fraction of `baseSize` left on landing.
function MotePath.sizeAt(baseSize: number, endScale: number, alpha: number): number
	return baseSize * (1 - (1 - endScale) * alpha)
end

return MotePath
