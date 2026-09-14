--!strict

----------------------------------------------------------------------
-- ShieldVfxController
----------------------------------------------------------------------
-- Raises and drops the ShieldVfx bubble on every player character in
-- sight, driven purely by the `_shield` character attribute.
--
-- Attribute-driven rather than called from SkillEffects.shield because
-- the *grant* and the *drain* live in different systems: SkillBuffs adds
-- to the pool, and DamageModifierRegistry.shieldModifier subtracts from
-- it inside applyDamage. A start-on-cast hook would have no matching
-- stop-on-absorb hook. The attribute is the one place both sides meet, so
-- watching it gets appear/thin-out/pop for free. The binding itself is
-- CharacterAttributeWatcher's — see its header.
--
-- **Players only, no tagged rigs** (refactor chunk 10's open question).
-- The absorb pool is granted by selfTarget spells, so only a player can
-- hold one; and the two places that test a shot against the shell —
-- SkillDelivery on the server, CosmeticProjectile on the client — both
-- scan players alone. A bubble on a boss would be a bubble nothing
-- deflects against, which is worse than no bubble. If boss shields ever
-- land, all three change together: flip `includeTaggedRigs` here, widen
-- `Hittables`-based shell collection there.
--
-- This controller also owns the one gameplay number the drawing needs —
-- the shell diameter. ShieldVfx no longer reads SkillBuffs itself, so the
-- bubble and the sphere that actually stops projectiles cannot drift apart
-- while leaving the Vfx layer independent of the Skills layer.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAttributeWatcher = require(ReplicatedStorage.Shared.Vfx.CharacterAttributeWatcher)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger          = require(ReplicatedStorage.Shared.Core.Logger)
local ShieldVfx       = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.ShieldVfx)
local SkillBuffs      = require(ReplicatedStorage.Shared.Skills.SkillBuffs)

local log = Logger.new("ShieldVfxController")

local SHIELD_ATTRIBUTE = HealthConstants.SHIELD_ATTRIBUTE

-- The gameplay shell, drawn at its true size. `SkillBuffs.SHELL_RADIUS_STUDS`
-- is what SkillDelivery measures a deflection against.
local SHELL_DIAMETER_STUDS = SkillBuffs.SHELL_RADIUS_STUDS * 2

local function readPool(character: Model): number
	local value = character:GetAttribute(SHIELD_ATTRIBUTE)
	return if typeof(value) == "number" then value :: number else 0
end

local watcher = CharacterAttributeWatcher.new({
	label              = "ShieldVfxController",
	attributes         = { SHIELD_ATTRIBUTE },
	includeTaggedRigs  = false,
	includeLocalPlayer = true,

	handlers = {
		onRefresh = function(character: Model, humanoid: Humanoid, _initial: boolean)
			local pool = readPool(character)
			if pool > 0 then
				ShieldVfx.update(character, pool, SHELL_DIAMETER_STUDS)
			elseif ShieldVfx.isActive(character) and humanoid.Health > 0 then
				-- Separates the two ways a pool reaches zero. Damage draining
				-- it is a break the player should see and hear; SkillBuffs
				-- clearing it on death is bookkeeping, and popping a bubble
				-- over a corpse reads as a reward.
				ShieldVfx.shatter(character)
			else
				-- Nothing was up, or the holder is already dead — quiet teardown.
				ShieldVfx.stop(character)
			end
		end,

		-- The bubble is cosmetic-only, so it can outlive its holder in ways
		-- the pool itself cannot: SkillBuffs clears the attribute on death,
		-- but a character destroyed outright never fires that change.
		onDetach = function(character: Model, _humanoid: Humanoid)
			ShieldVfx.stop(character)
		end,

		onDied = function(character: Model, _humanoid: Humanoid)
			ShieldVfx.stop(character)
		end,
	},
})

watcher:enable()

-- Rojo replaces this script on every sync; see FreezeVfxController.
script.Destroying:Connect(function()
	watcher:destroy()
end)

log:info("ready")
