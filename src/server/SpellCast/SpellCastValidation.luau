--!strict

----------------------------------------------------------------------
-- SpellCastValidation
----------------------------------------------------------------------
-- Trust checks for the SpellCastServer remote, split out of the service
-- so the Hardening suite can exercise them without a live remote fire.
-- Each check returns (value/ok, reason); the reason is server-log only.
--
-- What these DO cover: the spell is one the registry actually defines,
-- the caster is a living character, and the target is a living Model
-- inside the range the client's auto-targeter could have locked.
--
-- What they do NOT cover: whether the caster could afford the spell.
-- That needs energy state the server does not hold — see
-- wiki/systems/SpellCastService.md § Trust model.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local SpellCastConstants = require(script.Parent.SpellCastConstants)

local TypeValidation = script.Parent.Parent.Utility.TypeValidation
local validateInstance = require(TypeValidation.validateInstance)
local validateNumber = require(TypeValidation.validateNumber)
local validateVector3 = require(TypeValidation.validateVector3)

local SpellCastValidation = {}

-- Resolve (color, tier) to a registry Spec, or nil + reason.
--
-- The type guards run before the registry call rather than leaning on
-- the pcall alone: getSpell's asserts assume string/number arguments,
-- so a table color reaches string.format inside the error path. Guard
-- first, then pcall as the backstop for any tier the roster leaves
-- undefined (green and blue stop at T3 while red has a T4).
function SpellCastValidation.resolveSpec(color: any, tier: any): (SpellRegistry.Spec?, string?)
	if typeof(color) ~= "string" then
		return nil, string.format("color is %s, expected string", typeof(color))
	end
	if not validateNumber(tier) then
		-- validateNumber rejects NaN as well as the wrong type, and NaN
		-- still reports typeof "number" — say which it was, or the log
		-- reads "tier is number, expected number".
		if typeof(tier) == "number" then
			return nil, "tier is NaN"
		end
		return nil, string.format("tier is %s, expected number", typeof(tier))
	end

	local ok, specOrErr = pcall(SpellRegistry.getSpell, color :: any, tier)
	if not ok then
		return nil, string.format("unknown spell %s/%s", color, tostring(tier))
	end

	local spec = specOrErr :: SpellRegistry.Spec?
	if spec == nil then
		-- getSpell accepts the tier range but the per-color table can be
		-- shorter than NUM_TIERS, so a valid-looking tier can still miss.
		return nil, string.format("no spell defined at %s/%s", color, tostring(tier))
	end

	return spec, nil
end

-- Is the caster a living character that can legitimately cast?
function SpellCastValidation.checkCaster(character: any): (Model?, string?)
	if not validateInstance(character, "Model") then
		return nil, "caster is not a Model"
	end
	local model = character :: Model

	if not model:IsDescendantOf(workspace) then
		return nil, "caster not in workspace"
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, "caster has no Humanoid"
	end
	if humanoid.Health <= 0 then
		return nil, "caster is dead"
	end

	return model, nil
end

-- Is `target` something this caster could legitimately have locked?
-- Returns the Model on success.
--
-- Liveness is deliberately NOT checked here. A target dying or
-- despawning between the client's lock and the server's read is
-- ordinary play, so the service drops that case quietly; everything
-- this function rejects is a payload the client had no business
-- sending, and is worth a log line.
function SpellCastValidation.checkTarget(target: any, caster: Model): (Model?, string?)
	if not validateInstance(target, "Model") then
		return nil, string.format("target is %s, expected Model", typeof(target))
	end
	local model = target :: Model

	if not model:IsDescendantOf(workspace) then
		return nil, "target not in workspace"
	end

	local casterPos = caster:GetPivot().Position
	local targetPos = model:GetPivot().Position
	if not validateVector3(casterPos) or not validateVector3(targetPos) then
		return nil, "non-finite position"
	end

	local distance = (targetPos - casterPos).Magnitude
	if distance > SpellCastConstants.MAX_TARGET_DISTANCE_STUDS then
		return nil, string.format(
			"target out of range (%.0f > %d studs)",
			distance,
			SpellCastConstants.MAX_TARGET_DISTANCE_STUDS
		)
	end

	return model, nil
end

return SpellCastValidation
