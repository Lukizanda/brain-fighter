--!strict

----------------------------------------------------------------------
-- SkillVisuals
----------------------------------------------------------------------
-- Visual primitives reused across SkillDelivery handlers:
--
--   spawnShockwave(center, radius, opts) — a thin neon cylinder lying on
--     the ground plane, with an optional cosmetic-effect overlay.
--   spawnBarrier(footCFrame, opts)       — an anchored collidable slab
--     that springs up out of the ground; the Stone Wall body.
--
-- Lives next to SkillDelivery so handlers that need the same visual
-- (aoe windup, projectile splash impact) share one source of truth
-- instead of duplicating the Part construction inline.
--
-- spawnBarrier is the only primitive here that collides. Everything
-- else is CanCollide = false cosmetics.
--
-- Which VM you're on is handled here, once, not at every call site.
-- Cosmetics can't be drawn server-side at all (spawnEffect refuses, and
-- the comment there says why), so the two cosmetic primitives broadcast
-- when called on the server and draw when called on a client. Handlers
-- just say what should happen and let this module route it.
--
-- `drawnLocallyBy` is the UserId of a client that has already drawn this
-- effect itself, so the broadcast can skip it and avoid showing them two.
--
-- **No caller passes it today** (Phase 5.6 Stage 4). Delivery is
-- authoritative-only and draws nothing on any client, so every effect
-- belongs to every client. It stays on the signature for Stage 6, whose
-- prediction layer will draw the caster's muzzle cue locally and will need
-- exactly this to stop the broadcast duplicating that one cue.
--
-- The `RunService:IsServer()` branch below is NOT a leftover of the old
-- dual-VM delivery, and does not go away with it. This module has two
-- kinds of caller and always will:
--
--   server, describing  — SkillDelivery raising an impact or a shockwave
--   client, drawing     — WorldVfxController rendering a received
--                         broadcast, CosmeticProjectile rendering its own
--                         impacts
--
-- The second kind is presentation. It is already on a machine with a
-- renderer and has no run context to consult, so routing on which VM we
-- are is the honest question here — unlike in SkillDelivery, where it was
-- standing in for "which of two simultaneous runs is this".
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)
local VfxConfig    = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect  = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

local SHOCKWAVE_THICKNESS_STUDS = 0.4
local SHOCKWAVE_DEFAULT_COLOR   = Color3.fromRGB(255, 210, 0)
local SHOCKWAVE_TRANSPARENCY    = 0.35
local SHOCKWAVE_LIFETIME_SEC    = 0.5
local SHOCKWAVE_Y_OFFSET        = -2

-- Floor on how long a point-effect anchor lives. Covers the sound tail,
-- which outlasts the particle burst for most entries.
local POINT_ANCHOR_MIN_LIFETIME_SEC = 4

local BARRIER_DEFAULT_SIZE     = Vector3.new(16, 10, 2)
local BARRIER_DEFAULT_COLOR    = Color3.fromRGB(120, 118, 110)
local BARRIER_DEFAULT_LIFETIME = 6

----------------------------------------------------------------------
-- Barrier rise
----------------------------------------------------------------------
-- The wall starts buried by its own full height — top face flush with
-- the ground — waits a beat, then climbs into place.
--
-- THE WAIT IS NOT PACING, IT IS CORRECTNESS. A Part's *initial*
-- replication is slower than the property updates that follow it: the
-- client gets the instance a chunk of a second after the server made it,
-- by which time the server has already moved it. The first version of
-- this shipped without the wait and measured 202.8 studs on the client's
-- very first frame of a wall that was created at 197.5 and settles at
-- 207.5 — so every client's first sight of it was a half-height slab
-- hanging in the air, mid-climb. Which is exactly what a pop looks like.
--
-- Holding still until every client has the Part is what makes the rise
-- something they can watch rather than something they arrive late to.
-- The dust starts at t=0, so the beat reads as the ground giving way
-- before the wall breaks through it rather than as a stall.
local BARRIER_TELL_SEC = 0.18

-- Long enough to read as heavy, short enough that a defensive cast still
-- lands in time to matter. Total time-to-solid is TELL + RISE.
local BARRIER_RISE_SEC = 0.55

-- Height rides the STEP response of a CRITICALLY damped second-order
-- system — a mass at rest that gets shoved, accelerates, and eases to a
-- stop without ever passing the mark.
--
-- Two properties, and both are load-bearing. Each replaced a version of
-- this rise that shipped and was rejected:
--
-- 1. STEP, not impulse. The impulse response the letter-block pop-in
--    uses, 1 - e^(-decay*a)*cos(omega*a), starts at its MAXIMUM velocity
--    — its slope at a=0 is `decay` — so it front-loads the travel and no
--    tuning moves that. The first rise used it and covered 72% of the
--    wall's height in the first 50 ms: on paper a spring, on screen a pop
--    with a wobble on the end. The step response leaves rest and
--    accelerates, spreading the motion across the window.
--
-- 2. CRITICALLY damped, so it cannot overshoot. The second rise was
--    underdamped and punched 10% of the wall's height past its resting
--    place before settling back. On a letter block that overshoot is
--    charm; on a slab standing on the ground it is a 1-stud gap of
--    daylight underneath, and the wall reads as leaping into the air at
--    the end of its own entrance. Nothing that rests on the floor may
--    overshoot upward — the floor is the thing it is arriving at.
--
-- Critical damping is exactly the boundary case: the fastest a
-- second-order system can reach its target WITHOUT crossing it. So this
-- is still a spring, and still nothing like a linear slide — it just has
-- no bounce left to spend. It also rules out `Enum.EasingStyle.Back`,
-- whose whole behaviour is the overshoot.
--
--     y(a) = 1 - e^(-rate*a) * (1 + rate*a)
--
-- Monotonic and bounded above by 1 for every a >= 0, which is the
-- guarantee the wall needs.

-- Rate of approach, in e-folds across the rise. Critical damping is
-- asymptotic — it never mathematically arrives — so this is the dial
-- that trades "still visibly creeping when the window ends" against
-- "stops so hard it reads as a cut". 6.6 leaves the slab 99% of the way
-- there at a=1; the remaining ~0.1 stud is snapped by the caller.
local BARRIER_RISE_RATE = 6.6

local BARRIER_RISE_EFFECT_ID      = "wall_rise_rumble"
local BARRIER_RISE_DUST_EFFECT_ID = "wall_rise_dust"

-- The plume is drawn at three points across the wall's base rather than
-- one. A single emitter under a 16-stud slab puts the whole cloud at the
-- centre and leaves both ends visibly rising out of nothing.
--
-- Only the centre point carries the rumble audio: three copies of one
-- sample started on the same frame phase against each other rather than
-- getting louder, and the sound is positional anyway.
--
-- Fraction of the half-width the outer two sit at. 1.0 would put them on
-- the corners, where half the cloud spills past the end of the wall.
local BARRIER_RISE_DUST_SPAN = 0.62

export type ShockwaveOpts = {
	color: Color3?,
	transparency: number?,
	lifetimeSec: number?,
	cosmeticEffectId: string?,
	yOffset: number?,
	-- UserId of the one client that draws this itself. Set it from
	-- dual-VM handlers; leave nil for server-only ones. See the header.
	drawnLocallyBy: number?,
}

export type BarrierOpts = {
	size: Vector3?,
	color: Color3?,
	lifetimeSec: number?,
	-- Played at the base when the slab lands, not when it's created.
	cosmeticEffectId: string?,
	-- Seconds the slab spends climbing out of the ground. 0 places it
	-- fully formed, which is what this used to do.
	riseSec: number?,
}

local SkillVisuals = {}

-- Critically damped step response on [0, 1]. Leaves 0 at rest,
-- accelerates, and eases to ~1 without ever exceeding it — so the slab
-- never lifts off the ground it is arriving at. The (1 + rate*a) factor
-- is what zeroes the initial velocity and what makes the approach
-- critical rather than merely exponential.
local function riseAlpha(alpha: number): number
	local x = BARRIER_RISE_RATE * alpha
	return 1 - math.exp(-x) * (1 + x)
end

-- Play a VfxConfig effect at a bare world position.
--
-- `spawnEffect` parents its emitters and its sound to an Instance, so an
-- effect that happens at a point in space — a shot dying on a shield
-- shell, with no Part left to hang it on — needs a throwaway one. The
-- anchor outlives the particle burst because it also carries the sound,
-- which routinely runs longer than `totalDurationSec`.
function SkillVisuals.spawnEffectAtPoint(position: Vector3, effectId: string, drawnLocallyBy: number?)
	-- Server: describe it and let every client build its own anchor. A
	-- server-built one would replicate the Part and the Sound but not the
	-- burst, which is the failure this routing exists to prevent.
	if RunService:IsServer() then
		VfxBroadcast.playAt(effectId, position, drawnLocallyBy)
		return
	end

	local effect = VfxConfig.EFFECTS[effectId]
	if not effect then return end

	local anchor = Instance.new("Part")
	anchor.Name         = "SkillEffectAnchor"
	anchor.Size         = Vector3.one
	anchor.CFrame       = CFrame.new(position)
	anchor.Anchored     = true
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.CastShadow   = false
	anchor.Parent       = workspace

	spawnEffect(effect, anchor)
	Debris:AddItem(anchor, math.max(effect.totalDurationSec, POINT_ANCHOR_MIN_LIFETIME_SEC))
end

-- Play a VfxConfig effect parented to an existing Instance — an impact
-- burst on the victim's HumanoidRootPart, a glow on a moving Part.
--
-- Only for targets that have existed for more than a frame. The server
-- sends an Instance reference, which arrives nil on any client that
-- hasn't replicated it yet; rigs and characters are long-lived, a Part
-- created this frame is not. For those, use spawnEffectAtPoint.
function SkillVisuals.spawnEffectOn(
	effectId: string,
	target: BasePart | Attachment,
	drawnLocallyBy: number?
)
	if RunService:IsServer() then
		VfxBroadcast.playOn(effectId, target, drawnLocallyBy)
		return
	end

	local effect = VfxConfig.EFFECTS[effectId]
	if not effect then return end
	spawnEffect(effect, target)
end

-- Returns the ring Part on a client, and nil on the server — the server
-- doesn't build one, it asks the clients to. No caller uses the return
-- value today; the type says so rather than handing back a fake Part.
function SkillVisuals.spawnShockwave(center: Vector3, radius: number, opts: ShockwaveOpts?): BasePart?
	local o            = opts or {}

	-- Purely cosmetic — CanCollide = false, no gameplay reads it — so
	-- unlike spawnBarrier there is no reason for the server to own one.
	-- Drawing it on each client also puts the ring exactly where that
	-- client saw the impact, instead of a replication frame behind.
	if RunService:IsServer() then
		VfxBroadcast.shockwave(center, radius, {
			color            = o.color,
			transparency     = o.transparency,
			lifetimeSec      = o.lifetimeSec,
			cosmeticEffectId = o.cosmeticEffectId,
			yOffset          = o.yOffset,
			drawnLocallyBy   = o.drawnLocallyBy,
		})
		return nil
	end

	local color        = o.color        or SHOCKWAVE_DEFAULT_COLOR
	local transparency = o.transparency or SHOCKWAVE_TRANSPARENCY
	local lifetimeSec  = o.lifetimeSec  or SHOCKWAVE_LIFETIME_SEC
	local yOffset      = o.yOffset      or SHOCKWAVE_Y_OFFSET

	local shockwave = Instance.new("Part")
	shockwave.Name         = "SkillShockwave"
	shockwave.Shape        = Enum.PartType.Cylinder
	shockwave.Size         = Vector3.new(SHOCKWAVE_THICKNESS_STUDS, radius * 2, radius * 2)
	shockwave.CFrame       = CFrame.new(center.X, center.Y + yOffset, center.Z)
		* CFrame.Angles(0, 0, math.pi / 2)
	shockwave.Anchored     = true
	shockwave.CanCollide   = false
	shockwave.Color        = color
	shockwave.Material     = Enum.Material.Neon
	shockwave.Transparency = transparency
	shockwave.Parent       = workspace
	Debris:AddItem(shockwave, lifetimeSec)

	if o.cosmeticEffectId then
		local cosmeticEffect = VfxConfig.EFFECTS[o.cosmeticEffectId]
		if cosmeticEffect then
			spawnEffect(cosmeticEffect, shockwave)
		end
	end

	return shockwave
end

-- Anchored, collidable slab standing on the ground. `footCFrame` is the
-- position and facing of the wall's *base* — the slab is raised by half
-- its height so it rests on that point instead of being buried to the
-- waist in it.
--
-- Collides with everything, including the caster. That's deliberate
-- (design call 2026-08-03): a wall you can walk through but the boss
-- can't reads as broken, and being able to box yourself in is what makes
-- placement a decision.
--
-- The one primitive here that stays server-built, and the split is the
-- point: the slab is gameplay — it has to be the same solid object for
-- everyone or it stops the boss on one machine and not another — while
-- the cosmetic overlay hanging off it is not. So the Part is created
-- here and replicates as normal, and the overlay is broadcast so each
-- client attaches its own emitters to its own copy of that Part.
--
-- The slab arrives from below rather than appearing: it is parented
-- already buried, then driven up on a spring (see the rise constants
-- above) with dust boiling off the base the whole way. Collision follows
-- the visual, because it IS the visual — one Part, moved. Nothing walks
-- through a wall that looks like it hasn't finished arriving, and nothing
-- gets blocked by one that looks like it isn't there yet.
function SkillVisuals.spawnBarrier(footCFrame: CFrame, opts: BarrierOpts?): BasePart
	local o           = opts or {}
	local size        = o.size        or BARRIER_DEFAULT_SIZE
	local color       = o.color       or BARRIER_DEFAULT_COLOR
	local lifetimeSec = o.lifetimeSec or BARRIER_DEFAULT_LIFETIME
	local riseSec     = o.riseSec     or BARRIER_RISE_SEC

	local settledCFrame = footCFrame * CFrame.new(0, size.Y / 2, 0)
	-- Buried by a full wall-height, so the top face starts flush with the
	-- ground and the first thing anyone sees is the crown breaking the
	-- surface. World-space offset, not local: footCFrame is a lookAt with
	-- no pitch today, but a sloped one would otherwise burrow the wall
	-- sideways.
	local buriedCFrame = settledCFrame - Vector3.new(0, size.Y, 0)

	local barrier = Instance.new("Part")
	barrier.Name       = "SkillBarrier"
	barrier.Size       = size
	-- Set before parenting. A Part that replicates once at its settled
	-- CFrame and then jumps underground is the pop this rise removes,
	-- reintroduced one frame earlier.
	barrier.CFrame     = if riseSec > 0 then buriedCFrame else settledCFrame
	barrier.Anchored   = true
	barrier.CanCollide = true
	barrier.Color      = color
	barrier.Material   = Enum.Material.Slate
	barrier.Parent     = workspace
	Debris:AddItem(barrier, lifetimeSec)

	-- The settle burst, once the slab is actually down. By position rather
	-- than by Instance: an Instance argument that hasn't replicated to a
	-- given client yet arrives as nil, and the barrier is a Part the server
	-- made moments ago. It's anchored and done moving by then, so the foot
	-- is a stable anchor and the race doesn't exist.
	local function playSettle()
		if o.cosmeticEffectId then
			SkillVisuals.spawnEffectAtPoint(footCFrame.Position, o.cosmeticEffectId)
		end
	end

	if riseSec <= 0 then
		playSettle()
		return barrier
	end

	-- Dust across the base, started on the same frame as the climb.
	local flankOffset = footCFrame.RightVector * (size.X / 2 * BARRIER_RISE_DUST_SPAN)
	SkillVisuals.spawnEffectAtPoint(footCFrame.Position, BARRIER_RISE_EFFECT_ID)
	SkillVisuals.spawnEffectAtPoint(footCFrame.Position + flankOffset, BARRIER_RISE_DUST_EFFECT_ID)
	SkillVisuals.spawnEffectAtPoint(footCFrame.Position - flankOffset, BARRIER_RISE_DUST_EFFECT_ID)

	-- Driven per frame rather than by a TweenService tween: the spring
	-- overshoots and rings, and no EasingStyle exposes those as dials.
	-- Server-side CFrame writes on an anchored Part replicate as ordinary
	-- property changes (unlike ParticleEmitter:Emit), so every client sees
	-- the same climb — provided it doesn't start before they have the
	-- Part, which is what BARRIER_TELL_SEC is for.
	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function(dt: number)
		-- Debris can reclaim the barrier mid-rise if a spec ever ships a
		-- lifetime shorter than its rise.
		if not barrier.Parent then
			if connection then connection:Disconnect() end
			return
		end

		elapsed += dt

		-- The tell. Buried and still, while the dust kicks up and the Part
		-- finishes replicating to everyone.
		local climbed = elapsed - BARRIER_TELL_SEC
		if climbed <= 0 then return end

		local alpha = math.min(climbed / riseSec, 1)
		if alpha >= 1 then
			barrier.CFrame = settledCFrame
			if connection then connection:Disconnect() end
			playSettle()
			return
		end

		-- riseAlpha is bounded above by 1, so this never extrapolates past
		-- the settled CFrame — the wall cannot rise off the floor.
		barrier.CFrame = buriedCFrame:Lerp(settledCFrame, riseAlpha(alpha))
	end)

	return barrier
end

return SkillVisuals
