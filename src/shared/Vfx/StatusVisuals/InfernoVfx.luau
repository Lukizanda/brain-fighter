--!strict

----------------------------------------------------------------------
-- InfernoVfx — persistent status visual for a burning rig.
----------------------------------------------------------------------
-- Sibling of FreezeVfx, and built to the same contract: the "status
-- visual" lane, separate from the burst-VFX path through VfxConfig +
-- spawnEffect. See wiki/systems/SkillPipeline.md § "VFX layers".
--
-- The split is the same one freeze made. A burst is fire-and-forget
-- particles at a point; a status visual is geometry attached to a rig for
-- as long as the status lasts. Inferno needs both, and they are two
-- different things: `impact_damage_t3` is the detonation, this is the
-- three seconds of the boss being on fire afterwards.
--
-- Where freeze welds Parts, this parents ParticleEmitters straight onto
-- the limbs. That difference matters for teardown: shards are parented to
-- workspace and outlive their rig unless something destroys them, which is
-- why FreezeVfxController has to cache the Humanoid and cover three exit
-- paths. Emitters parented into the rig are collected with it, so the only
-- leak here would be the Highlight — hence the single `_active` entry that
-- owns every instance, including that.
--
-- **Engulfing is the whole point**, and it is why this exists at all
-- rather than a bigger burst on the HumanoidRootPart. A point emitter is
-- a bonfire the boss happens to be standing in; per-limb emitters using
-- Sphere/Surface emission are the boss itself alight, and they follow the
-- rig as it walks, staggers and turns.
--
-- CLIENT ONLY, and driven by the `_burning` attribute rather than called
-- from the burn handler. `client/Vfx/InfernoVfxController` is the sole
-- caller; nothing else should invoke start/stop directly.
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Logger    = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("InfernoVfx")

local VfxTemplates: Instance? = ReplicatedStorage:WaitForChild("VfxTemplates", 10)

-- Rig-agnostic limb selection, matching FreezeVfx. R15 players, the
-- Patroller-based bosses and the custom BossBrain rig all come through
-- here, and a hardcoded R15 limb list produced zero effect on BossBrain
-- (no "Head"/"UpperTorso") — the bug that made bosses look un-encased.
local MIN_PART_VOLUME = 0.5 -- studs³; filters out attachment-only stubs

-- Ceiling on how many limbs carry flame.
--
-- `VfxConfig.PERF.maxEmitters` is 32 and this is not the only thing
-- drawing: the eruption that starts the burn is three emitters of its own,
-- and a second player casting into the same fight doubles everything. Two
-- accessory layers (smoke, embers) ride on top of the per-limb count, so
-- twelve keeps a fully-burning boss at fourteen emitters — comfortably
-- inside budget with room for a concurrent cast.
--
-- Limbs are taken largest-first, so what gets dropped on an unusually
-- dense rig is fingers and accessory stubs, not the torso.
local MAX_FLAME_LIMBS = 12

-- Flame rate and size both scale with limb girth, so a torso is a bonfire
-- and a forearm is a sleeve of flame. Without this every limb emits
-- identically and a rig reads as a cluster of same-sized candles.
local FLAME_RATE_PER_AREA = 9.0
local FLAME_RATE_MIN      = 6
local FLAME_RATE_MAX      = 30
-- >1 so flames overhang the limb they come off. At 1.0 the fire sits
-- exactly inside the silhouette and reads as a texture, not a fire.
local FLAME_SIZE_FACTOR = 2.2

-- Smoke and embers are per-rig, not per-limb: they read as coming off the
-- whole burning mass, and thirteen copies of each would cost the frame
-- budget for no visible gain. Both ride the largest limb.
local SMOKE_RATE = 9
local SMOKE_SIZE = 7.0
local EMBER_RATE = 22
local EMBER_SIZE = 0.45

-- The body glow. Oscillated rather than held, because a constant fill
-- reads as a selection highlight; a pulsing one reads as something burning
-- from the inside.
local HIGHLIGHT_FILL_MIN   = 0.55
local HIGHLIGHT_FILL_MAX   = 0.85
local HIGHLIGHT_OUTLINE    = 0.35
local HIGHLIGHT_PULSE_SEC  = 0.45

-- Light flicker.
--
-- Much dimmer than the first pass, which ran at brightness 6 over a
-- 34-stud range and lit the entire arena orange — the floor, the far
-- walls and the letter blocks all read as being inside the fire. A burn
-- should pool warm light on the ground the rig is standing on and fall off
-- well before the walls; 2.2 over 22 studs does that. The eruption's
-- one-shot flash (spawnEffect, brightness 6) can afford to be bright
-- because it lasts 0.45 s, where this one holds for the whole burn.
local LIGHT_BRIGHTNESS_MIN = 0.9
local LIGHT_BRIGHTNESS_MAX = 2.2
local LIGHT_RANGE_STUDS    = 22
local LIGHT_FLICKER_SEC    = 0.17

local IGNITE_SEC = 0.18

-- How long after `stop` the emitters stay parented, so already-emitted
-- particles can finish their flight instead of vanishing mid-flame.
-- Must cover the longest lifetime on the three templates (FireSmoke, 2.2 s).
local BURNOUT_SEC = 2.4
local FADE_SEC    = 0.5

type Active = {
	emitters: { ParticleEmitter },
	highlight: Highlight?,
	light: PointLight?,
	tweens: { Tween },
}

local _active: { [Humanoid]: Active } = {}

-- Clone a template by name, or nil if it was never authored. Templates
-- live in ReplicatedStorage.VfxTemplates as Studio-side instances, so a
-- fresh clone of the place that never ran the setup has none of them —
-- degrade to a quieter fire rather than erroring mid-cast.
local function cloneTemplate(name: string): ParticleEmitter?
	if not VfxTemplates then return nil end
	local template = VfxTemplates:FindFirstChild(name)
	if not template or not template:IsA("ParticleEmitter") then
		log:warn(string.format("template %q missing or wrong class — skipping", name))
		return nil
	end
	return (template :: ParticleEmitter):Clone()
end

-- Every visible body part big enough to carry fire, largest first.
local function collectLimbs(character: Model): { BasePart }
	local limbs: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if not desc:IsA("BasePart") then continue end
		local limb = desc :: BasePart
		if limb.Name == "HumanoidRootPart" then continue end
		-- Skip Accessory contents for the same reason FreezeVfx does: hats
		-- and hair read as costume, not body, and setting them alight
		-- independently of the head looks like a bug.
		if limb:FindFirstAncestorOfClass("Accessory") then continue end
		-- And skip Tools, which FreezeVfx never had to think about because
		-- ice shards on a staff are barely visible. Fire is not: the
		-- Spelling Staff's Handle is 5.75 studs tall, which gave it the
		-- largest girth on the whole rig, pinned it to FLAME_RATE_MAX, and
		-- turned "the target is on fire" into "the target is holding a
		-- torch" — it was the only plume you could see. A held object is
		-- also the wrong subject: the boss carries no Tool, so this would
		-- have made a burning player look nothing like a burning boss.
		if limb:FindFirstAncestorOfClass("Tool") then continue end
		local sz = limb.Size
		if sz.X * sz.Y * sz.Z < MIN_PART_VOLUME then continue end
		table.insert(limbs, limb)
	end

	table.sort(limbs, function(a: BasePart, b: BasePart): boolean
		local av = a.Size.X * a.Size.Y * a.Size.Z
		local bv = b.Size.X * b.Size.Y * b.Size.Z
		return av > bv
	end)

	-- Truncate rather than thin out: the largest twelve are the ones that
	-- define the silhouette, and a sampled subset would leave visible gaps.
	while #limbs > MAX_FLAME_LIMBS do
		table.remove(limbs)
	end
	return limbs
end

local function girthOf(part: BasePart): number
	local s = part.Size
	return (s.X + s.Y + s.Z) / 3
end

-- Ramp a rate-based emitter up from nothing instead of switching it on.
-- A boss that is suddenly at full blaze on one frame reads as a graphical
-- pop; ~0.2 s of ignition reads as catching fire.
local function igniteEmitter(emitter: ParticleEmitter, targetRate: number): Tween
	emitter.Rate    = 0
	emitter.Enabled = true
	local tween = TweenService:Create(
		emitter,
		TweenInfo.new(IGNITE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rate = targetRate }
	)
	tween:Play()
	return tween
end

local function pulse(instance: Instance, property: string, to: number, durationSec: number): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(durationSec, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ [property] = to }
	)
	tween:Play()
	return tween
end

local InfernoVfx = {}

function InfernoVfx.start(humanoid: Humanoid)
	-- Server-side flames would replicate down and land on top of the
	-- caster's own local set, exactly the double-render FreezeVfx shipped
	-- with. Refuse rather than degrade — the attribute is the contract.
	if RunService:IsServer() then
		log:warnThrottled("server_call", 5, string.format(
			"refused on the server — flames are client-drawn from the " ..
			"`_burning` attribute. Set the flag via SkillEffects instead.\n%s",
			debug.traceback()
		))
		return
	end
	if _active[humanoid] then return end

	local character = humanoid.Parent
	if not character or not character:IsA("Model") then return end

	local limbs = collectLimbs(character :: Model)
	if #limbs == 0 then return end

	local entry: Active = { emitters = {}, highlight = nil, light = nil, tweens = {} }
	_active[humanoid] = entry

	-- Flame on every limb. Parented to the BasePart rather than to an
	-- Attachment on purpose: a ParticleEmitter parented to a part inherits
	-- that part's volume for its emission shape, so the template's
	-- Sphere/Surface/Outward settings spawn flame across the whole limb.
	-- Parented to an Attachment the same emitter is a unit-sized puff at a
	-- single point, which is the bonfire-vs-burning-boss difference.
	for _, limb in limbs do
		local flame = cloneTemplate("FireFlame")
		if not flame then break end
		local girth = girthOf(limb)
		flame.Name  = "InfernoFlame"
		flame.Color = VfxConfig.FIRE.flame
		flame.Size  = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, girth * FLAME_SIZE_FACTOR * 0.6),
			NumberSequenceKeypoint.new(0.4, girth * FLAME_SIZE_FACTOR),
			NumberSequenceKeypoint.new(1.0, girth * FLAME_SIZE_FACTOR * 0.7),
		})
		flame.Parent = limb

		local rate = math.clamp(girth * girth * FLAME_RATE_PER_AREA, FLAME_RATE_MIN, FLAME_RATE_MAX)
		table.insert(entry.tweens, igniteEmitter(flame, rate))
		table.insert(entry.emitters, flame)
	end

	-- Smoke and embers ride the biggest limb — index 1, since collectLimbs
	-- sorted by volume.
	local core = limbs[1]

	local smoke = cloneTemplate("FireSmoke")
	if smoke then
		smoke.Name  = "InfernoSmoke"
		smoke.Color = VfxConfig.FIRE.smoke
		smoke.Size  = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, SMOKE_SIZE * 0.5),
			NumberSequenceKeypoint.new(1.0, SMOKE_SIZE),
		})
		smoke.Parent = core
		table.insert(entry.tweens, igniteEmitter(smoke, SMOKE_RATE))
		table.insert(entry.emitters, smoke)
	end

	local ember = cloneTemplate("FireEmber")
	if ember then
		ember.Name  = "InfernoEmber"
		ember.Color = VfxConfig.FIRE.ember
		ember.Size  = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, EMBER_SIZE),
			NumberSequenceKeypoint.new(1.0, 0.0),
		})
		ember.Parent = core
		table.insert(entry.tweens, igniteEmitter(ember, EMBER_RATE))
		table.insert(entry.emitters, ember)
	end

	-- Body glow. Occluded rather than AlwaysOnTop: a burning boss visible
	-- through the arena walls would be a wallhack, and Stone Wall exists
	-- specifically so players can break line of sight.
	local highlight = Instance.new("Highlight")
	highlight.Name              = "InfernoHighlight"
	highlight.FillColor         = VfxConfig.FIRE.light
	highlight.OutlineColor      = VfxConfig.FIRE.light
	highlight.FillTransparency  = HIGHLIGHT_FILL_MAX
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE
	highlight.DepthMode         = Enum.HighlightDepthMode.Occluded
	highlight.Adornee           = character
	highlight.Parent            = character
	entry.highlight = highlight
	table.insert(entry.tweens, pulse(highlight, "FillTransparency", HIGHLIGHT_FILL_MIN, HIGHLIGHT_PULSE_SEC))

	-- Honours the same PERF switch as spawnEffect's burst light: on a
	-- machine already dropping frames, a three-second dynamic light on a
	-- moving rig is exactly the cost worth shedding first.
	if VfxConfig.PERF.allowLights then
		local hrp = (character :: Model):FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local light = Instance.new("PointLight")
			light.Name       = "InfernoLight"
			light.Color      = VfxConfig.FIRE.light
			light.Brightness = LIGHT_BRIGHTNESS_MAX
			light.Range      = LIGHT_RANGE_STUDS
			light.Shadows    = false
			light.Parent     = hrp :: BasePart
			entry.light = light
			table.insert(entry.tweens, pulse(light, "Brightness", LIGHT_BRIGHTNESS_MIN, LIGHT_FLICKER_SEC))
		end
	end
end

function InfernoVfx.stop(humanoid: Humanoid)
	local entry = _active[humanoid]
	if not entry then return end
	_active[humanoid] = nil

	-- Cancel first. A pulse tween left running would keep writing
	-- FillTransparency and fight the fade-out below for as long as the
	-- Highlight survives, so the boss would strobe on its way out.
	for _, tween in entry.tweens do
		tween:Cancel()
	end

	-- Stop emitting, but leave the emitters parented: particles already in
	-- flight belong to the emitter, and destroying it now deletes them
	-- mid-air. The fire goes out by burning down, not by being switched off.
	for _, emitter in entry.emitters do
		if emitter.Parent then
			emitter.Enabled = false
			Debris:AddItem(emitter, BURNOUT_SEC)
		end
	end

	local highlight = entry.highlight
	if highlight and highlight.Parent then
		TweenService:Create(
			highlight,
			TweenInfo.new(FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FillTransparency = 1, OutlineTransparency = 1 }
		):Play()
		Debris:AddItem(highlight, FADE_SEC + 0.1)
	end

	local light = entry.light
	if light and light.Parent then
		TweenService:Create(
			light,
			TweenInfo.new(FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }
		):Play()
		Debris:AddItem(light, FADE_SEC + 0.1)
	end
end

return InfernoVfx
