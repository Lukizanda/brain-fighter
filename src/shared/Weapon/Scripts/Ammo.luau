----------------------------------------------------------------------
-- Ammo
----------------------------------------------------------------------
-- Pure math for the reserve-ammo model. A ranged weapon has:
--   _ammo          — rounds currently in the magazine (0..magazineSize)
--   _reserveAmmo   — spare rounds carried, refilled on pickup
--   magazineSize   — capacity of the magazine
--   maxReserveAmmo — cap for _reserveAmmo
--
-- Reload pulls from reserve into the magazine until either the magazine
-- is full or the reserve is empty. Pickup of a same-type weapon adds
-- `pickupAmmoBonus` rounds to the existing weapon's reserve, clamped.
--
-- This module only writes Tool attributes — all orchestration (remotes,
-- timers, UI) lives in the callers.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)

local Ammo = {}

-- Safely read a nonnegative integer attribute, defaulting to 0 if missing
local function readInt(tool: Tool, attr: string): number
	local v = tool:GetAttribute(attr)
	if typeof(v) == "number" then
		return math.max(0, math.floor(v))
	end
	return 0
end

-- Returns true if reloading would transfer at least one round
function Ammo.canReload(tool: Tool): boolean
	local ammo = readInt(tool, Constants.AMMO_ATTRIBUTE)
	local reserve = readInt(tool, Constants.RESERVE_AMMO_ATTRIBUTE)
	local magazineSize = readInt(tool, Constants.MAGAZINE_SIZE_ATTRIBUTE)
	if magazineSize == 0 then
		return false
	end
	return reserve > 0 and ammo < magazineSize
end

-- Transfers rounds from reserve into the magazine. Returns the number
-- of rounds moved (0 if no-op).
function Ammo.performReload(tool: Tool): number
	local ammo = readInt(tool, Constants.AMMO_ATTRIBUTE)
	local reserve = readInt(tool, Constants.RESERVE_AMMO_ATTRIBUTE)
	local magazineSize = readInt(tool, Constants.MAGAZINE_SIZE_ATTRIBUTE)
	if magazineSize == 0 then
		return 0
	end

	local needed = magazineSize - ammo
	local transfer = math.min(needed, reserve)
	if transfer <= 0 then
		return 0
	end

	tool:SetAttribute(Constants.AMMO_ATTRIBUTE, ammo + transfer)
	tool:SetAttribute(Constants.RESERVE_AMMO_ATTRIBUTE, reserve - transfer)
	return transfer
end

-- Adds reserve ammo, clamped to maxReserveAmmo (or no cap if unset).
-- Returns the actual number of rounds added after clamping.
function Ammo.addReserve(tool: Tool, amount: number): number
	if amount <= 0 then
		return 0
	end
	local reserve = readInt(tool, Constants.RESERVE_AMMO_ATTRIBUTE)
	local cap = tool:GetAttribute(Constants.MAX_RESERVE_AMMO_ATTRIBUTE)

	local newReserve = reserve + math.floor(amount)
	if typeof(cap) == "number" then
		newReserve = math.min(newReserve, math.floor(cap))
	end

	local added = newReserve - reserve
	if added > 0 then
		tool:SetAttribute(Constants.RESERVE_AMMO_ATTRIBUTE, newReserve)
	end
	return added
end

return Ammo
