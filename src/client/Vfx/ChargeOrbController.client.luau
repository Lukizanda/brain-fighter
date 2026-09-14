--!strict

----------------------------------------------------------------------
-- ChargeOrbController
----------------------------------------------------------------------
-- Raises and drops the ChargeOrbVfx orb on every *other* player, driven
-- purely by the `_chargeColor` / `_chargeTier` attributes. The binding is
-- CharacterAttributeWatcher's — see its header for why a replicated
-- attribute is what makes "everyone sees your windup" nearly free. The orb
-- is only worth building because everyone *does* see it: it is the PvP
-- tell.
--
-- **The local player is deliberately skipped** (`includeLocalPlayer =
-- false`). SpellMenuGui drives ChargeOrbVfx directly off the same gesture
-- that fires the remote, so the caster's own orb appears on the press frame
-- with zero RTT. Drawing it here as well would fight that: two writers for
-- one orb, and the replicated one arrives a round trip late and stepped
-- rather than smooth.
--
-- **Players only, no tagged rigs** (refactor chunk 10's open question).
-- The previous version watched every damageable rig on the theory that a
-- boss windup could reuse this lane. It now has its own —
-- `SkillVisuals.spawnTelegraph`, which this chunk added — and nothing
-- writes the charge attributes on a boss or an NPC (ChargeStateService
-- writes them for players, SpellMenuGui locally for the caster). Watching
-- rigs was binding connections to rigs that could never light up, and if a
-- boss ever does charge a spell the telegraph is the lane that should show
-- it, because its duration is known server-side.
--
-- The gameplay facts the orb needs — the roster's top tier and this
-- colour's spell names — are read here and passed in. ChargeOrbVfx no
-- longer queries SpellRegistry itself.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAttributeWatcher = require(ReplicatedStorage.Shared.Vfx.CharacterAttributeWatcher)
local ChargeOrbVfx   = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.ChargeOrbVfx)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local SpellRegistry  = require(ReplicatedStorage.Shared.SpellRegistry)

local log = Logger.new("ChargeOrbController")

local COLOR_ATTR = SkillConstants.CHARGE_COLOR_ATTR
local TIER_ATTR  = SkillConstants.CHARGE_TIER_ATTR

-- A remote observer learns about discrete tier crossings only, so there is
-- no progress to animate between them: inventing one would be animating a
-- number nobody sent. The caster's own orb (SpellMenuGui) feeds a live
-- alpha off the builder's hold clock instead.
local OBSERVED_TIER_ALPHA = 0

-- `atCeiling` is the caster's own affordability state and does not cross
-- the wire; an observer never strains the orb.
local OBSERVED_AT_CEILING = false

-- The last colour an orb was raised for, per character. The edge flag: a
-- tier write while the colour is unchanged must re-tune the existing orb,
-- not tear it down and build another.
local _orbColor: { [Model]: string } = {}

local function readColor(character: Model): string?
	local value = character:GetAttribute(COLOR_ATTR)
	return if typeof(value) == "string" and value ~= "" then value :: string else nil
end

local function readTier(character: Model): number
	local value = character:GetAttribute(TIER_ATTR)
	return if typeof(value) == "number" then value :: number else 0
end

-- The roster facts ChargeOrbVfx draws from. `pcall`ed because the colour
-- arrives off a replicated attribute: the server only ever writes one of
-- the three school names, but a surprise value should cost this orb its
-- name label rather than throw inside a signal handler.
--
-- SpellMenuGui builds the same table for the caster's own orb, from the
-- same two registry calls.
local function chargeInputsFor(color: string): ChargeOrbVfx.ChargeInputs
	local tierNames: { string } = {}
	local ok, count = pcall(SpellRegistry.tierCount, color :: any)
	if ok and typeof(count) == "number" then
		for tier = 1, count :: number do
			tierNames[tier] = SpellRegistry.getSpell(color :: any, tier).name
		end
	else
		log:warnThrottled("bad_color", 5, string.format("no spells for charge colour %q", color))
	end
	return { topTier = SpellRegistry.NUM_TIERS, tierNames = tierNames }
end

local watcher = CharacterAttributeWatcher.new({
	label              = "ChargeOrbController",
	attributes         = { COLOR_ATTR, TIER_ATTR },
	includeTaggedRigs  = false,
	includeLocalPlayer = false,

	handlers = {
		onRefresh = function(character: Model, _humanoid: Humanoid, _initial: boolean)
			local color = readColor(character)

			if not color then
				-- The charge ended. Which *way* it ended is carried by the tier
				-- the server left behind on the same frame it cleared the
				-- colour: a positive tier is a cast going out and gets the
				-- release flash, zero is a cancel and collapses quietly.
				-- Reading it after the colour has gone is safe because
				-- ChargeStateService writes the tier first (see its `finish`).
				if _orbColor[character] then
					_orbColor[character] = nil
					local tier = readTier(character)
					if tier > 0 then
						ChargeOrbVfx.release(character, tier)
					else
						ChargeOrbVfx.stop(character)
					end
				end
				return
			end

			if _orbColor[character] ~= color then
				-- A colour change mid-charge is not legal today (the builder
				-- allows one press at a time), but tearing down and rebuilding
				-- is the honest response if one ever arrives.
				if _orbColor[character] then
					ChargeOrbVfx.stop(character)
				end
				_orbColor[character] = color
				ChargeOrbVfx.start(character, color, chargeInputsFor(color))
			end

			ChargeOrbVfx.setTier(character, readTier(character), OBSERVED_TIER_ALPHA, OBSERVED_AT_CEILING)
		end,

		-- Cosmetic-only, so the orb can outlive its holder in ways the
		-- attributes cannot: a character destroyed outright never fires an
		-- attribute change.
		onDetach = function(character: Model, _humanoid: Humanoid)
			_orbColor[character] = nil
			ChargeOrbVfx.stop(character)
		end,

		onDied = function(character: Model, _humanoid: Humanoid)
			_orbColor[character] = nil
			ChargeOrbVfx.stop(character)
		end,
	},
})

watcher:enable()

-- Rojo replaces this script on every sync; see FreezeVfxController.
script.Destroying:Connect(function()
	watcher:destroy()
	table.clear(_orbColor)
end)

log:info(string.format("ready — watching %d character(s), local player excluded (%s)",
	watcher:watchedCount(),
	tostring(Players.LocalPlayer and Players.LocalPlayer.Name)
))
