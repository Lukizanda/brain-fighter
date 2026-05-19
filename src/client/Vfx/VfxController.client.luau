--!strict

----------------------------------------------------------------------
-- VfxController (Phase C — local player)
----------------------------------------------------------------------
-- Listens to CastAction.spellResolved and spawns ParticleEmitter
-- bursts at the caster's staff tip (cast VFX) and on the target's
-- HumanoidRootPart (impact VFX).
--
-- Remote broadcast to other clients (BroadcastSpellVfx / SpellVfxEvent)
-- is Phase C step 2 — not yet wired here.
----------------------------------------------------------------------

local Debris           = game:GetService("Debris")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger     = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig  = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local CastAction = require(ReplicatedStorage.Shared.CastAction)

local log         = Logger.new("VfxController")
local LocalPlayer = Players.LocalPlayer

local VfxTemplates = ReplicatedStorage:WaitForChild("VfxTemplates", 10)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function applyEmitterOverrides(emitter: ParticleEmitter, spec: VfxConfig.EmitterSpec)
	if spec.color then
		emitter.Color = ColorSequence.new(spec.color.primary)
		emitter.LightEmission = 0.5
	end
	if spec.lifetime    then emitter.Lifetime    = spec.lifetime    end
	if spec.size        then emitter.Size        = spec.size        end
	if spec.speed       then emitter.Speed       = spec.speed       end
	if spec.spreadAngle then emitter.SpreadAngle = spec.spreadAngle end
	if spec.rotation    then emitter.Rotation    = spec.rotation    end
	if spec.transparency then emitter.LightTransparency = 0 end -- keep as authored; transparency field is a hint
end

local function spawnEffect(effectSpec: VfxConfig.EffectSpec, anchorPart: BasePart | Attachment)
	if not effectSpec.emitters then return end

	local att = Instance.new("Attachment")
	att.Parent = anchorPart
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

-- Walk character → equipped Tool → Handle → Tip attachment.
-- Falls back to HumanoidRootPart so VFX always fires somewhere.
local function resolveStaffTip(character: Model): BasePart | Attachment
	local tool = character:FindFirstChildWhichIsA("Tool")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle then
			local tip = handle:FindFirstChild("Tip")
			if tip and tip:IsA("Attachment") then
				return tip
			end
		end
	end
	return (character:FindFirstChild("HumanoidRootPart") :: BasePart)
end

-- Resolve the HumanoidRootPart for whatever `target` CastAction passed.
-- target may be a Humanoid (its .Parent is the character) or a Model.
local function resolveTargetRoot(target: any): BasePart?
	if typeof(target) ~= "Instance" then return nil end
	local model: Model?
	if target:IsA("Humanoid") then
		model = target.Parent :: Model
	elseif target:IsA("Model") then
		model = target
	end
	if not model then return nil end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp :: BasePart else nil
end

----------------------------------------------------------------------
-- Main signal connection
----------------------------------------------------------------------

CastAction.spellResolved:Connect(function(
	spec   : any,  -- SpellRegistry.Spec (typed loosely to avoid circular dep)
	_caster: any,
	target : any
)
	local character = LocalPlayer.Character
	if not character then return end

	-- Cast VFX at staff tip
	local castEffectId = VfxConfig.resolveCastId(spec.color, spec.tier)
	local castEffect   = VfxConfig.EFFECTS[castEffectId]
	if castEffect then
		local anchor = resolveStaffTip(character)
		spawnEffect(castEffect, anchor)
		log:infoThrottled("cast_vfx", 2, string.format("cast vfx: %s @ %s", castEffectId, anchor.Name))
	end

	-- Impact VFX at target
	local firstImpact = spec.skill and spec.skill.onImpact and spec.skill.onImpact[1]
	if firstImpact and target then
		local impactEffectId = VfxConfig.resolveImpactId(firstImpact.kind)
		local impactEffect   = VfxConfig.EFFECTS[impactEffectId]
		if impactEffect then
			local targetRoot = resolveTargetRoot(target)
			if targetRoot then
				spawnEffect(impactEffect, targetRoot)
				log:infoThrottled("impact_vfx", 2, string.format("impact vfx: %s @ %s", impactEffectId, targetRoot.Name))
			end
		end
	end
end)

log:info("ready")
