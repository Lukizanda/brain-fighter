local HealthConstants = require(script.Parent.HealthConstants)
local DamageTypes = require(script.Parent.DamageTypes)

local function getHitZone(hitInstance: Instance?): string
	if not hitInstance then
		return DamageTypes.HitZone.Torso
	end

	local partName = hitInstance.Name

	for _, headPart in HealthConstants.HEAD_PARTS do
		if partName == headPart then
			return DamageTypes.HitZone.Head
		end
	end

	for _, torsoPart in HealthConstants.TORSO_PARTS do
		if partName == torsoPart then
			return DamageTypes.HitZone.Torso
		end
	end

	return DamageTypes.HitZone.Limb
end

return getHitZone
