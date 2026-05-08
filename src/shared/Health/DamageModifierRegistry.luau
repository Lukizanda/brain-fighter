local HealthConstants = require(script.Parent.HealthConstants)
local DamageTypes = require(script.Parent.DamageTypes)

type DamageRequest = DamageTypes.DamageRequest

local DamageModifierRegistry = {}

local function headshotModifier(request: DamageRequest): (DamageRequest, string?)
	if request.hitZone == DamageTypes.HitZone.Head then
		request.baseDamage = request.baseDamage * HealthConstants.HEADSHOT_MULTIPLIER
		return request, "Headshot"
	elseif request.hitZone == DamageTypes.HitZone.Limb then
		request.baseDamage = request.baseDamage * HealthConstants.LIMB_MULTIPLIER
		return request, "Limb"
	end
	return request, nil
end

local function armorModifier(request: DamageRequest): (DamageRequest, string?)
	local character = request.targetHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return request, nil
	end

	local armor = character:GetAttribute(HealthConstants.ARMOR_ATTRIBUTE)
	if not armor or armor <= 0 then
		return request, nil
	end

	local reduction = math.clamp(armor / 100, 0, 0.8)
	request.baseDamage = request.baseDamage * (1 - reduction)
	return request, string.format("Armor(-%d%%)", math.floor(reduction * 100))
end

local function shieldModifier(request: DamageRequest): (DamageRequest, string?)
	local character = request.targetHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return request, nil
	end

	local shield = character:GetAttribute(HealthConstants.SHIELD_ATTRIBUTE)
	if not shield or shield <= 0 then
		return request, nil
	end

	local absorbed = math.min(shield, request.baseDamage)
	character:SetAttribute(HealthConstants.SHIELD_ATTRIBUTE, shield - absorbed)
	request.baseDamage = request.baseDamage - absorbed

	if not request.metadata then
		request.metadata = {}
	end
	request.metadata._shieldAbsorbed = absorbed

	return request, string.format("Shield(-%d)", absorbed)
end

DamageModifierRegistry.modifiers = {
	headshotModifier,
	armorModifier,
	shieldModifier,
}

function DamageModifierRegistry.resolve(request: DamageRequest): (number, number, { string })
	local appliedModifiers: { string } = {}
	local totalAbsorbed = 0

	for _, modifier in DamageModifierRegistry.modifiers do
		local label
		request, label = modifier(request)
		if label then
			table.insert(appliedModifiers, label)
		end
	end

	if request.metadata and request.metadata._shieldAbsorbed then
		totalAbsorbed = request.metadata._shieldAbsorbed
	end

	local finalDamage = math.max(0, request.baseDamage)
	return finalDamage, totalAbsorbed, appliedModifiers
end

return DamageModifierRegistry
