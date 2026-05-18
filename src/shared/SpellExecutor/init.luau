--!strict

----------------------------------------------------------------------
-- SpellExecutor
----------------------------------------------------------------------
-- Resolves the caster's origin CFrame and dispatches to
-- SkillDelivery.deliver(spec.skill, ctx).
--
-- All spell effect logic now lives in SkillEffects (damage, heal,
-- freeze, knockup, shield stubs). All delivery logic lives in
-- SkillDelivery (instant, projectile, aoe, world_spawn). This
-- module is a thin adapter: origin resolution + ctx construction.
--
-- Origin resolution order:
--   1. Attachment named "Tip" on the active Tool's Handle
--   2. Handle CFrame if no Tip attachment
--   3. HumanoidRootPart CFrame as final fallback
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillDelivery = require(ReplicatedStorage.Shared.Skills.SkillDelivery)
local SkillTypes       = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local SpellRegistry    = require(ReplicatedStorage.Shared.SpellRegistry)

export type CastResult = SkillDelivery.Result

----------------------------------------------------------------------
-- Origin resolution
----------------------------------------------------------------------

local function resolveSpellOrigin(caster: Humanoid | Model): CFrame
	local character: Model?
	if typeof(caster) == "Instance" then
		local inst = caster :: Instance
		if inst:IsA("Humanoid") then
			character = (inst :: Humanoid).Parent :: Model?
		elseif inst:IsA("Model") then
			character = inst :: Model
		end
	end
	if not character then return CFrame.new() end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle then
			local tip = handle:FindFirstChild("Tip")
			if tip and tip:IsA("Attachment") then
				return (tip :: Attachment).WorldCFrame
			end
			if handle:IsA("BasePart") then
				return (handle :: BasePart).CFrame
			end
		end
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp :: BasePart).CFrame or CFrame.new()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

local SpellExecutor = {}

function SpellExecutor.cast(
	spec: SpellRegistry.Spec,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	local origin = resolveSpellOrigin(caster)

	local source: Instance? = nil
	if typeof(caster) == "Instance" then
		local inst = caster :: Instance
		source = if inst:IsA("Humanoid") then (inst :: Humanoid).Parent :: Instance? else inst
	end

	local ctx: SkillTypes.DeliveryCtx = {
		origin = origin,
		target = target,
		source = source,
	}

	return SkillDelivery.deliver(spec.skill, ctx)
end

return SpellExecutor
