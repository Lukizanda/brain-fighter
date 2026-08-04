--!strict

----------------------------------------------------------------------
-- FreezeVfx — persistent status visual for the freeze effect.
----------------------------------------------------------------------
-- Lives in the "status visual" lane, separate from the burst-VFX path
-- through VfxConfig + VfxController.spawnEffect. See
-- wiki/systems/SkillPipeline.md § "VFX layers".
--
-- Burst-vs-persistent split: bursts are fire-and-forget particles
-- (cast/impact). Status visuals are welded geometry that persists for
-- the duration of an active status. They share the same color source
-- (VfxConfig.COLORS) but use a different runtime because the
-- ParticleEmitter pipeline doesn't carry "weld parts to limbs for N
-- seconds" semantics.
--
-- CLIENT ONLY, and driven by the `_frozen` attribute rather than called
-- from the freeze handler. `client/Vfx/FreezeVfxController` is the sole
-- caller; nothing else should invoke start/stop directly.
--
-- This used to run on whichever VM applied the effect, which meant a
-- player-cast freeze built one set of shards on the server (replicating
-- down) and another on the caster's client, welded to the same limbs.
-- It looked *almost* right — two identical ice shells overlapping — which
-- is why it survived so long. Welded Parts and tweens do replicate, so
-- unlike a ParticleEmitter burst this was never invisible; it was double.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Logger    = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("FreezeVfx")

-- Per-limb shards are emitted on every visible BasePart of the character.
-- Rig-agnostic by design: R15 players, the Patroller-based bosses, and the
-- custom BossBrain rig all share this path. The previous hardcoded R15 limb
-- list silently produced zero shards on BossBrain (no "Head"/"UpperTorso"),
-- which is why bosses looked un-encased.
local MIN_PART_VOLUME = 0.5      -- studs³; filter out attachment-only stubs

local OVERSIZE       = 1.7
-- VfxConfig.COLORS.blue.glow is #80C0FF == (128, 192, 255) — same hue as
-- the previous hardcoded ICE_COLOR, now sourced from the single palette.
local ICE_COLOR      = VfxConfig.COLORS.blue.glow
local TRANSPARENCY   = 0.35
local EXPAND_TIME    = 0.4
local COLLAPSE_TIME  = 0.2
local ROT_RANGE_XZ   = math.rad(35)

local _active: { [Humanoid]: { Part } } = {}

local function makeExpandTween(p: Part, targetSize: Vector3): Tween
	return TweenService:Create(
		p,
		TweenInfo.new(EXPAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
end

local function makeCollapseTween(p: Part): Tween
	return TweenService:Create(
		p,
		TweenInfo.new(COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0, 0, 0) }
	)
end

local FreezeVfx = {}

function FreezeVfx.start(humanoid: Humanoid, _durationSec: number)
	-- Server shards would replicate down and land on top of the caster's
	-- own local set. Refuse rather than degrade, matching `spawnEffect`:
	-- the flag is the contract, and only clients render it.
	if RunService:IsServer() then
		log:warnThrottled("server_call", 5, string.format(
			"refused on the server — freeze shards are client-drawn from the " ..
			"`_frozen` attribute. Set the flag via SkillEffects instead.\n%s",
			debug.traceback()
		))
		return
	end
	if _active[humanoid] then return end

	local character = humanoid.Parent
	if not character then return end

	local parts: { Part } = {}

	for _, desc in (character :: Instance):GetDescendants() do
		if not desc:IsA("BasePart") then continue end
		local limb = desc :: BasePart
		if limb.Name == "HumanoidRootPart" then continue end
		-- Skip Accessory contents (hats, hair, handles) — they read as costume,
		-- not body, and would litter the encasement with floating shards.
		if limb:FindFirstAncestorOfClass("Accessory") then continue end
		local sz = limb.Size
		if sz.X * sz.Y * sz.Z < MIN_PART_VOLUME then continue end

		local rx = (math.random() * 2 - 1) * ROT_RANGE_XZ
		local ry = math.random() * math.pi * 2
		local rz = (math.random() * 2 - 1) * ROT_RANGE_XZ

		local icePart = Instance.new("Part")
		icePart.Name        = "IceShard"
		icePart.Material    = Enum.Material.Ice
		icePart.Color       = ICE_COLOR
		icePart.Transparency = TRANSPARENCY
		icePart.CanCollide  = false
		icePart.Anchored    = false
		icePart.CastShadow  = false
		icePart.Size        = Vector3.new(0.1, 0.1, 0.1)
		icePart.CFrame      = limb.CFrame * CFrame.Angles(rx, ry, rz)
		icePart.Parent      = workspace

		local weld = Instance.new("WeldConstraint")
		weld.Part0  = icePart
		weld.Part1  = limb
		weld.Parent = icePart

		makeExpandTween(icePart, limb.Size * OVERSIZE):Play()

		table.insert(parts, icePart)
	end

	_active[humanoid] = parts
end

function FreezeVfx.stop(humanoid: Humanoid)
	local parts = _active[humanoid]
	if not parts then return end
	_active[humanoid] = nil

	for _, p in parts do
		if not p.Parent then continue end
		makeCollapseTween(p):Play()
		task.delay(COLLAPSE_TIME, function()
			if p.Parent then p:Destroy() end
		end)
	end
end

return FreezeVfx
