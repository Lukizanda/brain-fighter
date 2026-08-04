--!strict

----------------------------------------------------------------------
-- ShieldVfxController
----------------------------------------------------------------------
-- Raises and drops the ShieldVfx bubble on every player character in
-- sight, driven purely by the `_shield` character attribute.
--
-- Attribute-driven rather than called from SkillEffects.shield because
-- the *grant* and the *drain* live in different systems: SkillBuffs adds
-- to the pool, and
-- DamageModifierRegistry.shieldModifier subtracts from it inside
-- applyDamage. A start-on-cast hook would have no matching stop-on-
-- absorb hook. The attribute is the one place both sides meet, so
-- watching it gets appear/thin-out/pop for free.
--
-- Replication does the multiplayer work: the authoritative pool is set
-- by the server (SpellCastService relay) on a replicated character
-- Model, so every client's copy of this script sees every player's
-- shield without a broadcast RemoteEvent. The casting client also writes
-- the attribute locally, which is what makes its own bubble appear on
-- the cast frame instead of after the round trip.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger          = require(ReplicatedStorage.Shared.Core.Logger)
local ShieldVfx       = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.ShieldVfx)

local log = Logger.new("ShieldVfxController")

local SHIELD_ATTRIBUTE = HealthConstants.SHIELD_ATTRIBUTE

-- One entry per character currently being watched. Cleared on respawn,
-- on the player leaving, and on the character leaving the workspace.
local _watched: { [Model]: { RBXScriptConnection } } = {}

local function readPool(character: Model): number
	local value = character:GetAttribute(SHIELD_ATTRIBUTE)
	return if typeof(value) == "number" then value :: number else 0
end

-- Separates the two ways a pool reaches zero. Damage draining it is a
-- break the player should see and hear; SkillBuffs clearing it on death
-- is bookkeeping, and popping a bubble over a corpse reads as a reward.
local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function unwatch(character: Model)
	local conns = _watched[character]
	if conns then
		_watched[character] = nil
		for _, conn in conns do
			conn:Disconnect()
		end
	end
	ShieldVfx.stop(character)
end

local function watch(character: Model)
	if _watched[character] then return end

	local conns: { RBXScriptConnection } = {}
	_watched[character] = conns

	local function refresh()
		local pool = readPool(character)
		if pool > 0 then
			ShieldVfx.update(character, pool)
		elseif ShieldVfx.isActive(character) and isAlive(character) then
			ShieldVfx.shatter(character)
		else
			-- Nothing was up, or the holder is already dead — quiet teardown.
			ShieldVfx.stop(character)
		end
	end

	table.insert(conns, character:GetAttributeChangedSignal(SHIELD_ATTRIBUTE):Connect(refresh))

	-- The bubble is cosmetic-only, so it can outlive its holder in ways
	-- the pool itself can't: SkillBuffs clears the attribute on death,
	-- but a character destroyed outright never fires that change. Both
	-- exits are covered here.
	table.insert(conns, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			unwatch(character)
		end
	end))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(conns, humanoid.Died:Connect(function()
			ShieldVfx.stop(character)
		end))
	end

	-- A late joiner's first sight of an already-shielded player arrives as
	-- an initial attribute value, not as a change signal.
	refresh()
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	player.CharacterRemoving:Connect(unwatch)
	if player.Character then
		watch(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	if player.Character then
		unwatch(player.Character)
	end
end)

log:info("ready")
