--!strict

----------------------------------------------------------------------
-- ShieldVfx — persistent status visual for the absorb-shield effect.
----------------------------------------------------------------------
-- Same lane as FreezeVfx (see that file's header for the burst-vs-
-- persistent split): welded geometry that lives for as long as a status
-- is active, not a fire-and-forget particle burst.
--
-- The look deliberately echoes the spawn-protection ForceField that
-- GameModeService parents to a freshly spawned character, so "damage is
-- being eaten right now" reads the same whether it came from respawn
-- grace or from a cast Shield / Sanctuary.
--
-- It's a hand-built ball rather than a real ForceField instance because
-- the engine's ForceField exposes no color, size or opacity — and this
-- bubble has to sit in the blue ward palette (matching `impact_shield`)
-- and thin out as the absorb pool drains.
--
-- Driven entirely by the `_shield` character attribute, from
-- client/Vfx/ShieldVfxController. Nothing here reads or writes gameplay
-- state; SkillBuffs grants the pool and DamageModifierRegistry drains it.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local SkillBuffs  = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local VfxConfig   = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

-- Sparkle burst played when the pool is emptied. Carries the break SFX
-- too — it's a normal EFFECTS entry, so the sound rides along with it.
local BREAK_EFFECT_ID = "shield_break"

-- Same palette entry the `impact_shield` burst uses, so the ward shimmer
-- that lands on cast and the bubble it leaves behind are the same blue.
local BUBBLE_COLOR = VfxConfig.COLORS.blue.glow

-- Geometry comes from SkillBuffs, not from this file: the sphere drawn
-- here is the same sphere SkillDelivery stops projectiles against, and a
-- local copy of the number would drift the moment one side was tuned.
local BUBBLE_DIAMETER = SkillBuffs.SHELL_RADIUS_STUDS * 2

-- Opacity is the shield's health bar — the only readout the player gets
-- for a pool that has no HUD element. A full shield is a solid shell, a
-- nearly-spent one is barely there. Neither end goes fully opaque: the
-- player has to be able to see out of it.
local FULL_TRANSPARENCY  = 0.35
local EMPTY_TRANSPARENCY = 0.90

-- Bends the ramp between those two. Below 1 the shell keeps its body
-- through the early hits and then thins hard over the last sliver, so a
-- bubble that's one hit from popping looks like it.
local DEPLETION_CURVE = 0.7

-- Brief opaque pop when the pool takes a hit, so absorption is legible
-- even for chip damage that barely moves the opacity ramp.
local FLARE_TRANSPARENCY = 0.10
local FLARE_IN_TIME      = 0.06
local FLARE_OUT_TIME     = 0.22

local EXPAND_TIME   = 0.35
local COLLAPSE_TIME = 0.25
local FADE_TIME     = 0.20

-- A break flares the shell outward as it goes, rather than shrinking it.
-- Popping outward is what separates "it broke" from "it was switched off"
-- at a glance, before the sparkles even register.
local BREAK_EXPAND_FACTOR = 1.15
local BREAK_TIME          = 0.18

local SPAWN_DIAMETER = 0.2

type ActiveBubble = {
	bubble: Part,
	-- Largest pool this bubble has held. The absorb pool has no declared
	-- maximum (Sanctuary layers on top of Shield), so "how full is it"
	-- can only be measured against its own high-water mark.
	peak: number,
	amount: number,
}

local _active: { [Model]: ActiveBubble } = {}

local function transparencyFor(amount: number, peak: number): number
	local remaining = if peak > 0 then math.clamp(amount / peak, 0, 1) else 0
	return EMPTY_TRANSPARENCY + (FULL_TRANSPARENCY - EMPTY_TRANSPARENCY) * remaining ^ DEPLETION_CURVE
end

local function resolveRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp :: BasePart else nil
end

local ShieldVfx = {}

-- Raise the bubble on `character`. No-op if one is already up — use
-- `update` to re-tune an existing bubble to a new pool value.
function ShieldVfx.start(character: Model, amount: number)
	if _active[character] then return end

	local root = resolveRoot(character)
	if not root then return end

	local bubble = Instance.new("Part")
	bubble.Name         = "SpellShieldBubble"
	bubble.Shape        = Enum.PartType.Ball
	bubble.Material     = Enum.Material.ForceField
	bubble.Color        = BUBBLE_COLOR
	bubble.Transparency = transparencyFor(amount, amount)
	bubble.Size         = Vector3.new(SPAWN_DIAMETER, SPAWN_DIAMETER, SPAWN_DIAMETER)
	-- Centred on the root, not on the rig's bounding-box centre, because
	-- that's where SkillDelivery centres the shell it tests against.
	bubble.CFrame       = root.CFrame
	bubble.Anchored     = false
	bubble.CanCollide   = false
	-- CanQuery off is load-bearing, not hygiene: spell targeting and the
	-- projectile raycasts sweep workspace, and a body-sized ball around
	-- the caster would swallow every one of their own shots.
	bubble.CanQuery     = false
	bubble.CanTouch     = false
	bubble.CastShadow   = false
	-- Welded to a live rig, so it must not add weight to the assembly.
	bubble.Massless     = true
	-- Parented to workspace rather than the character: FreezeVfx shards
	-- every BasePart under the character, and a bubble living in there
	-- would grow its own ice shell on a freeze.
	bubble.Parent       = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = bubble
	weld.Part1  = root
	weld.Parent = bubble

	TweenService:Create(
		bubble,
		TweenInfo.new(EXPAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.new(BUBBLE_DIAMETER, BUBBLE_DIAMETER, BUBBLE_DIAMETER) }
	):Play()

	_active[character] = { bubble = bubble, peak = amount, amount = amount }
end

-- Re-tune an existing bubble to a new pool value: thinner as the pool
-- drains, with a flare on any decrease. Raises the bubble if none is up.
function ShieldVfx.update(character: Model, amount: number)
	local entry = _active[character]
	if not entry then
		ShieldVfx.start(character, amount)
		return
	end
	if not entry.bubble.Parent then return end

	local absorbed = amount < entry.amount
	entry.peak   = math.max(entry.peak, amount)
	entry.amount = amount

	local settled = transparencyFor(amount, entry.peak)

	if absorbed then
		local bubble = entry.bubble
		TweenService:Create(
			bubble,
			TweenInfo.new(FLARE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = FLARE_TRANSPARENCY }
		):Play()
		task.delay(FLARE_IN_TIME, function()
			-- The bubble may have been popped by a killing blow during the flare.
			if not bubble.Parent then return end
			TweenService:Create(
				bubble,
				TweenInfo.new(FLARE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = settled }
			):Play()
		end)
	else
		TweenService:Create(
			entry.bubble,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = settled }
		):Play()
	end
end

-- The shield failing under the last hit, as opposed to being cleared.
--
-- `stop` deflates quietly, which is right when the bubble is just
-- bookkeeping being torn down — a death, a despawn, a respawn. This one
-- is an event the player is meant to notice: the shell flares outward and
-- vanishes, leaving a sparkle burst (and the break SFX, which rides on
-- the same EFFECTS entry) behind at the holder's root.
--
-- Anchored to the root rather than to the bubble because the bubble is
-- about to be destroyed, and `spawnEffect` parents its emitters and its
-- sound to whatever anchor it's given — they'd be cut off mid-burst.
function ShieldVfx.shatter(character: Model)
	local entry = _active[character]
	if not entry then return end
	_active[character] = nil

	local bubble = entry.bubble
	if not bubble.Parent then return end

	local burst = VfxConfig.EFFECTS[BREAK_EFFECT_ID]
	local root  = resolveRoot(character)
	if burst and root then
		spawnEffect(burst, root)
	end

	TweenService:Create(
		bubble,
		TweenInfo.new(BREAK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = bubble.Size * BREAK_EXPAND_FACTOR, Transparency = 1 }
	):Play()
	task.delay(BREAK_TIME, function()
		if bubble.Parent then bubble:Destroy() end
	end)
end

-- Collapse and destroy. Idempotent — the pool draining to zero, the
-- holder dying and the character despawning can all fire for one bubble.
function ShieldVfx.stop(character: Model)
	local entry = _active[character]
	if not entry then return end
	_active[character] = nil

	local bubble = entry.bubble
	if not bubble.Parent then return end

	TweenService:Create(
		bubble,
		TweenInfo.new(COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0, 0, 0), Transparency = 1 }
	):Play()
	task.delay(COLLAPSE_TIME, function()
		if bubble.Parent then bubble:Destroy() end
	end)
end

-- Read-only probe for tests/diagnostics.
function ShieldVfx.isActive(character: Model): boolean
	return _active[character] ~= nil
end

return ShieldVfx
