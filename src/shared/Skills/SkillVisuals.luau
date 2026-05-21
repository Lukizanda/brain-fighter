--!strict

----------------------------------------------------------------------
-- SkillVisuals
----------------------------------------------------------------------
-- Visual primitives reused across SkillDelivery handlers. Currently
-- exposes spawnShockwave(center, radius, opts): a thin neon cylinder
-- lying on the ground plane, with an optional cosmetic-effect overlay
-- attached via spawnEffect.
--
-- Lives next to SkillDelivery so handlers that need the same visual
-- (aoe windup, projectile splash impact) share one source of truth
-- instead of duplicating the Part construction inline.
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

export type ShockwaveOpts = {
	color: Color3?,
	transparency: number?,
	lifetimeSec: number?,
	cosmeticEffectId: string?,
	yOffset: number?,
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

return SkillVisuals
