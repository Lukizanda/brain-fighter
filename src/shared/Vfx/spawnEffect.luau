--!strict

----------------------------------------------------------------------
-- spawnEffect — shared runtime for VfxConfig.EFFECTS entries.
----------------------------------------------------------------------
-- Single implementation used by both VfxController (cast/impact bursts
-- on a staff tip / target HRP) and SkillDelivery (cosmetic layer on
-- projectile/AoE physical Parts). Anchoring is the caller's choice —
-- this function only needs a BasePart or Attachment to parent under.
--
-- Templates live in ReplicatedStorage.VfxTemplates as ParticleEmitter
-- instances (Studio-side). Missing templates are logged once per call
-- and skipped — the system gracefully degrades when a template was
-- never authored for a given EffectSpec.
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger    = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("spawnEffect")

local VfxTemplates: Instance? = ReplicatedStorage:WaitForChild("VfxTemplates", 10)

-- A SoundSpec whose id is still the authoring placeholder. VfxConfig ships
-- these for effects whose SFX hasn't been sourced yet; playing one would
-- spam "Unable to load sound" every cast.
local UNSET_SOUND_IDS: { [string]: true } = {
	["rbxassetid://0"] = true,
	[""] = true,
}

-- Ceiling on how long a spell Sound may sit in the world waiting for
-- Ended. Ended never fires for an id that fails to load, so without this
-- a bad asset leaks one Instance per cast.
local SOUND_MAX_LIFETIME_SEC = 10

local DEFAULT_SOUND_VOLUME = 0.8

-- Sounds are parented to the anchor (a BasePart or Attachment), which is
-- what makes them 3D-positional. Deliberately NOT parented to the emitter
-- attachment: that one is destroyed on `totalDurationSec`, which is the
-- length of the *particle* burst and is routinely shorter than the sound.
local function playSound(spec: VfxConfig.SoundSpec, anchorPart: BasePart | Attachment)
	if UNSET_SOUND_IDS[spec.soundId] then return end

	local sound = Instance.new("Sound")
	sound.Name     = "VfxSound"
	sound.SoundId  = spec.soundId
	sound.Volume   = spec.volume or DEFAULT_SOUND_VOLUME
	-- One asset reused across every cast of a spell gets repetitive fast;
	-- a per-play pitch jitter is the cheapest way to break that up.
	if spec.pitchRange then
		local r = spec.pitchRange
		sound.PlaybackSpeed = r.Min + math.random() * (r.Max - r.Min)
	end
	sound.Parent = anchorPart
	sound:Play()

	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, SOUND_MAX_LIFETIME_SEC)
end

local function applyEmitterOverrides(emitter: ParticleEmitter, spec: VfxConfig.EmitterSpec)
	if spec.color then
		emitter.Color = ColorSequence.new(spec.color.primary)
		emitter.LightEmission = 0.5
	end
	if spec.lifetime     then emitter.Lifetime     = spec.lifetime     end
	if spec.size         then emitter.Size         = spec.size         end
	if spec.speed        then emitter.Speed        = spec.speed        end
	if spec.spreadAngle  then emitter.SpreadAngle  = spec.spreadAngle  end
	if spec.rotation     then emitter.Rotation     = spec.rotation     end
	if spec.transparency then emitter.Transparency = spec.transparency end
	if spec.rate         then emitter.Rate         = spec.rate         end
end

local function spawnEffect(effectSpec: VfxConfig.EffectSpec, anchorPart: BasePart | Attachment)
	-- Audio first, and outside the emitters guard: several effects are
	-- sound-only or particle-less (and the emitter-less early return used
	-- to drop their sound silently).
	if effectSpec.sound then
		playSound(effectSpec.sound, anchorPart)
	end

	if not effectSpec.emitters then return end

	local att = Instance.new("Attachment")
	att.Parent = anchorPart
	if effectSpec.upward then
		att.WorldCFrame = CFrame.lookAt(att.WorldPosition, att.WorldPosition + Vector3.yAxis)
	end
	Debris:AddItem(att, effectSpec.totalDurationSec + 0.1)

	for _, emitterSpec in effectSpec.emitters do
		if not VfxTemplates then
			log:warn("VfxTemplates not found — skipping emitter")
			continue
		end
		local template = VfxTemplates:FindFirstChild(emitterSpec.template)
		if not template or not template:IsA("ParticleEmitter") then
			log:warn(string.format("template %q missing or wrong class — skipping", emitterSpec.template))
			continue
		end

		local emitter = template:Clone() :: ParticleEmitter
		applyEmitterOverrides(emitter, emitterSpec)
		emitter.Parent = att

		if emitterSpec.emitCount then
			emitter.Enabled = false
			emitter:Emit(emitterSpec.emitCount)
			Debris:AddItem(emitter, effectSpec.totalDurationSec)
		elseif emitterSpec.durationSec then
			emitter.Enabled = true
			task.delay(emitterSpec.durationSec, function()
				if emitter.Parent then emitter.Enabled = false end
			end)
			Debris:AddItem(emitter, effectSpec.totalDurationSec)
		end
	end
end

return spawnEffect
