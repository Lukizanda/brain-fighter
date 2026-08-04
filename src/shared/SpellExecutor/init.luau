--!strict

----------------------------------------------------------------------
-- SpellExecutor
----------------------------------------------------------------------
-- Resolves the caster's origin CFrame and dispatches to
-- SkillDelivery.deliver(spec.skill, ctx).
--
-- All spell effect logic now lives in SkillEffects (damage, heal,
-- freeze, knockup, shield, buff). All delivery logic lives in
-- SkillDelivery (instant, projectile, aoe, world_spawn). This
-- module is a thin adapter: origin resolution + ctx construction.
--
-- `target` is legitimately nil for self-buffs and placement spells; the
-- effect handlers fall back to ctx.source and world_spawn places
-- relative to the caster.
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

-- Resolve the caster Model the same way `cast` does, so a precondition
-- check and the cast it guards agree about what the source is.
local function resolveSource(caster: Humanoid | Model): Instance?
	if typeof(caster) ~= "Instance" then return nil end
	local inst = caster :: Instance
	return if inst:IsA("Humanoid") then (inst :: Humanoid).Parent :: Instance? else inst
end

-- "Would this cast be refused?", without casting it.
--
-- Lets CastAction decide before it drains rather than after. Pure — no
-- state is read that a cast would change, and nothing is written — so it
-- is safe to call from anywhere, including a predicted run.
function SpellExecutor.canCast(
	spec: SpellRegistry.Spec,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil
): CastResult
	return SkillDelivery.canDeliver(spec.skill, target, resolveSource(caster))
end

-- `run` is required rather than defaulted. A default would mean a new call
-- site silently picks a side, which is the exact ad-hoc-ness it exists to
-- remove — the caller always knows which run it is starting, so it says
-- so. It is a table rather than positional arguments because its two
-- fields constrain each other: only an authoritative run can have been
-- predicted by someone. See wiki/design/client-server-boundary.md.
function SpellExecutor.cast(
	spec: SpellRegistry.Spec,
	caster: Humanoid | Model,
	target: Humanoid | Model | Vector3 | nil,
	run: SkillTypes.RunContext
): CastResult
	local origin = resolveSpellOrigin(caster)

	local source = resolveSource(caster)

	local ctx: SkillTypes.DeliveryCtx = {
		origin = origin,
		target = target,
		source = source,
		mode = run.mode,
		predictedBy = run.predictedBy,
	}

	return SkillDelivery.deliver(spec.skill, ctx)
end

return SpellExecutor
