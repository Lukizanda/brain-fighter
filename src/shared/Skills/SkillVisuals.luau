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
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxConfig   = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

local SHOCKWAVE_THICKNESS_STUDS = 0.4
local SHOCKWAVE_DEFAULT_COLOR   = Color3.fromRGB(255, 210, 0)
local SHOCKWAVE_TRANSPARENCY    = 0.35
local SHOCKWAVE_LIFETIME_SEC    = 0.5
local SHOCKWAVE_Y_OFFSET        = -2

local BARRIER_DEFAULT_SIZE     = Vector3.new(16, 10, 2)
local BARRIER_DEFAULT_COLOR    = Color3.fromRGB(120, 118, 110)
local BARRIER_DEFAULT_LIFETIME = 6

export type ShockwaveOpts = {
	color: Color3?,
	transparency: number?,
	lifetimeSec: number?,
	cosmeticEffectId: string?,
	yOffset: number?,
}

export type BarrierOpts = {
	size: Vector3?,
	color: Color3?,
	lifetimeSec: number?,
	cosmeticEffectId: string?,
}

local SkillVisuals = {}

function SkillVisuals.spawnShockwave(center: Vector3, radius: number, opts: ShockwaveOpts?): BasePart
	local o            = opts or {}
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
		local cosmeticEffect = VfxConfig.EFFECTS[o.cosmeticEffectId]
		if cosmeticEffect then
			spawnEffect(cosmeticEffect, barrier)
		end
	end

	return barrier
end

return SkillVisuals
