--!strict

----------------------------------------------------------------------
-- HealthFloor
----------------------------------------------------------------------
-- A health value a character cannot be damaged below while it is set. Owned
-- by Health: how much of a hit lands is a damage rule, so the rule lives in
-- the modifier chain (`DamageModifierRegistry`, the floor modifier, last in
-- the chain) and `applyDamage.process` stays the one writer of
-- Humanoid.Health. Whoever *sets* the floor (today the boss's word ward,
-- Boss/Scripts/BossWard) never touches Humanoid.Health.
--
-- A hit that would cross the floor is cut down to land exactly on it; a hit
-- on a character already at or under the floor does nothing. The floor does
-- not heal: setting one above the current health leaves the health alone.
--
-- The floor is one character attribute holding hit points. `set` and `clear`
-- are its only writers.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)

local ATTRIBUTE = HealthConstants.HEALTH_FLOOR_ATTRIBUTE

local HealthFloor = {}

-- The character's floor in hit points, or nil when it has none.
function HealthFloor.get(character: Instance): number?
	local value = character:GetAttribute(ATTRIBUTE)
	if typeof(value) == "number" and value > 0 then
		return value :: number
	end
	return nil
end

-- Hold the character's health at or above `hitPoints` against damage.
function HealthFloor.set(character: Instance, hitPoints: number)
	character:SetAttribute(ATTRIBUTE, hitPoints)
end

function HealthFloor.clear(character: Instance)
	character:SetAttribute(ATTRIBUTE, nil)
end

return HealthFloor
