--!strict

----------------------------------------------------------------------
-- VfxController (Phase C — local + broadcast)
----------------------------------------------------------------------
-- Listens to CastAction.spellResolved and spawns ParticleEmitter
-- bursts at the caster's staff tip (cast VFX) and on the target's
-- HumanoidRootPart (impact VFX).
--
-- Also broadcasts via BroadcastSpellVfx so other clients see the
-- effect, and receives SpellVfxEvent to play effects cast by others.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger      = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig   = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local CastAction  = require(ReplicatedStorage.Shared.CastAction)
local spawnEffect = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

local log         = Logger.new("VfxController")
local LocalPlayer = Players.LocalPlayer

local Remotes           = ReplicatedStorage.Shared.Vfx.Remotes
local BroadcastSpellVfx = Remotes:WaitForChild("BroadcastSpellVfx") :: RemoteEvent
local SpellVfxEvent     = Remotes:WaitForChild("SpellVfxEvent")     :: RemoteEvent

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

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

-- Resolve every renderable impact effect id for a skill (one per unique
-- effect kind in `skill.onImpact`). Dedupes by kind so a hypothetical
-- "damage + damage" entry doesn't double-emit. Returns ids that have a
-- matching `VfxConfig.EFFECTS` entry; missing ones are silently dropped.
local function resolveImpactEffectIds(skill: any): { string }
	local ids: { string } = {}
	if not (skill and skill.onImpact) then return ids end
	local seen: { [string]: true } = {}
	for _, entry in skill.onImpact do
		local kind = entry.kind
		if kind and not seen[kind] then
			seen[kind] = true
			local id = VfxConfig.resolveImpactId(kind)
			if VfxConfig.EFFECTS[id] then
				table.insert(ids, id)
			end
		end
	end
	return ids
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

	-- Impact VFX at target — one burst per unique effect kind on the skill.
	local impactTargetRoot: BasePart? = if target then resolveTargetRoot(target) else nil
	local impactEffectIds: { string } = resolveImpactEffectIds(spec.skill)
	if impactTargetRoot then
		for _, id in impactEffectIds do
			spawnEffect(VfxConfig.EFFECTS[id], impactTargetRoot)
			log:infoThrottled("impact_vfx_" .. id, 2, string.format("impact vfx: %s @ %s", id, impactTargetRoot.Name))
		end
	end

	-- Broadcast to other clients
	BroadcastSpellVfx:FireServer({
		color           = spec.color,
		tier            = spec.tier,
		castEffectId    = if VfxConfig.EFFECTS[castEffectId] then castEffectId else nil,
		impactEffectIds = impactEffectIds,
		impactTarget    = impactTargetRoot,
	})
end)

SpellVfxEvent.OnClientEvent:Connect(function(payload: any)
	if payload.senderUserId == LocalPlayer.UserId then return end

	-- Cast burst at the sender's staff tip
	if payload.castEffectId then
		local castEffect = VfxConfig.EFFECTS[payload.castEffectId]
		local senderPlayer = if typeof(payload.senderUserId) == "number"
			then Players:GetPlayerByUserId(payload.senderUserId)
			else nil
		local senderChar = senderPlayer and senderPlayer.Character
		if castEffect and senderChar then
			local anchor = resolveStaffTip(senderChar)
			spawnEffect(castEffect, anchor)
		end
	end

	-- Impact bursts — one spawn per unique effect kind from the sender.
	local impactTarget = payload.impactTarget
	if impactTarget and typeof(impactTarget) == "Instance" and impactTarget:IsA("BasePart")
		and typeof(payload.impactEffectIds) == "table"
	then
		for _, id in payload.impactEffectIds do
			local impactEffect = VfxConfig.EFFECTS[id]
			if impactEffect then
				spawnEffect(impactEffect, impactTarget)
			end
		end
	end
end)

log:info("ready")
