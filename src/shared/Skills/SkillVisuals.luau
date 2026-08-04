--!strict

----------------------------------------------------------------------
-- SkillVisuals
----------------------------------------------------------------------
-- Visual primitives reused across SkillDelivery handlers:
--
--   spawnShockwave(center, radius, opts) — a thin neon cylinder lying on
--     the ground plane, with an optional cosmetic-effect overlay.
--   spawnBarrier(footCFrame, opts)       — an anchored collidable slab
--     standing on the ground; the Stone Wall body.
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
	cosmeticEffectId: string?,
}

local SkillVisuals = {}

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
function SkillVisuals.spawnBarrier(footCFrame: CFrame, opts: BarrierOpts?): BasePart
	local o           = opts or {}
	local size        = o.size        or BARRIER_DEFAULT_SIZE
	local color       = o.color       or BARRIER_DEFAULT_COLOR
	local lifetimeSec = o.lifetimeSec or BARRIER_DEFAULT_LIFETIME

	local barrier = Instance.new("Part")
	barrier.Name       = "SkillBarrier"
	barrier.Size       = size
	barrier.CFrame     = footCFrame * CFrame.new(0, size.Y / 2, 0)
	barrier.Anchored   = true
	barrier.CanCollide = true
	barrier.Color      = color
	barrier.Material   = Enum.Material.Slate
	barrier.Parent     = workspace
	Debris:AddItem(barrier, lifetimeSec)

	if o.cosmeticEffectId then
		if RunService:IsServer() then
			-- By position, not by Instance reference, even though the Part
			-- is right here. An Instance argument that hasn't replicated to
			-- a given client yet arrives as nil, and this fires on the same
			-- frame the Part is created — the exact window where that bites.
			-- The barrier is anchored and never moves, so its centre is a
			-- stable anchor and the race just doesn't exist.
			VfxBroadcast.playAt(o.cosmeticEffectId, barrier.Position)
		else
			local cosmeticEffect = VfxConfig.EFFECTS[o.cosmeticEffectId]
			if cosmeticEffect then
				spawnEffect(cosmeticEffect, barrier)
			end
		end
	end

	return barrier
end

return SkillVisuals
