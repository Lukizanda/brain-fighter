--!strict

----------------------------------------------------------------------
-- ChargeOrbController
----------------------------------------------------------------------
-- Raises and drops the ChargeOrbVfx orb on every *other* character in
-- sight, driven purely by the `_chargeColor` / `_chargeTier` attributes.
--
-- Sibling of ShieldVfxController, and the same argument for being
-- attribute-driven: the character Model is server-owned, so a server
-- write replicates to every client with no fan-out RemoteEvent, and a
-- late joiner sees an already-charging player because the values are
-- simply there when they arrive. That is what makes "everyone sees your
-- windup" nearly free, and the orb is only worth building because
-- everyone *does* see it — it is the PvP tell.
--
-- **The local player is deliberately skipped.** SpellMenuGui drives
-- ChargeOrbVfx directly off the same gesture that fires the remote, so
-- the caster's own orb appears on the press frame with zero RTT. Drawing
-- it here as well would fight that: two writers for one orb, and the
-- replicated one arrives a round trip late and stepped rather than
-- smooth.
--
-- Boss and NPC rigs are watched too (via SkillConstants.DAMAGEABLE_TAGS),
-- so a future boss windup can reuse this lane instead of
-- BossWindupClient's bespoke per-frame glow. Nothing writes those
-- attributes on a boss today; the watcher costs nothing until something
-- does.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local ChargeOrbVfx   = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.ChargeOrbVfx)

local log = Logger.new("ChargeOrbController")

local COLOR_ATTR = SkillConstants.CHARGE_COLOR_ATTR
local TIER_ATTR  = SkillConstants.CHARGE_TIER_ATTR

local localPlayer = Players.LocalPlayer

-- One entry per character being watched, holding its connections and the
-- last colour we raised an orb for. The cached colour is the edge flag:
-- a tier write while the colour is unchanged must re-tune the existing
-- orb, not tear it down and build another.
type Watch = {
	connections: { RBXScriptConnection },
	color: string?,
}

local _watched: { [Model]: Watch } = {}

local function readColor(character: Model): string?
	local value = character:GetAttribute(COLOR_ATTR)
	return if typeof(value) == "string" and value ~= "" then value :: string else nil
end

local function readTier(character: Model): number
	local value = character:GetAttribute(TIER_ATTR)
	return if typeof(value) == "number" then value :: number else 0
end

local function unwatch(character: Model)
	local entry = _watched[character]
	if entry then
		_watched[character] = nil
		for _, conn in entry.connections do
			conn:Disconnect()
		end
	end
	ChargeOrbVfx.stop(character)
end

local function watch(character: Model)
	if _watched[character] then return end
	-- The local player owns their own orb. See the header.
	if localPlayer and localPlayer.Character == character then return end

	local entry: Watch = { connections = {}, color = nil }
	_watched[character] = entry

	local function refresh()
		local color = readColor(character)

		if not color then
			-- The charge ended. Which *way* it ended is carried by the tier
			-- the server left behind on the same frame it cleared the colour:
			-- a positive tier is a cast going out and gets the release flash,
			-- zero is a cancel and collapses quietly. Reading it after the
			-- colour has gone is safe because ChargeStateService writes the
			-- tier first (see its `finish`).
			if entry.color then
				entry.color = nil
				if readTier(character) > 0 then
					ChargeOrbVfx.release(character, readTier(character))
				else
					ChargeOrbVfx.stop(character)
				end
			end
			return
		end

		if entry.color ~= color then
			-- A colour change mid-charge is not legal today (the builder
			-- allows one press at a time), but tearing down and rebuilding is
			-- the honest response if one ever arrives.
			if entry.color then
				ChargeOrbVfx.stop(character)
			end
			entry.color = color
			ChargeOrbVfx.start(character, color)
		end

		-- alpha stays 0 for a remote observer: this VM only ever learns about
		-- discrete tier crossings, and inventing progress between them would
		-- be an animation of a number nobody sent.
		ChargeOrbVfx.setTier(character, readTier(character), 0, false)
	end

	table.insert(entry.connections, character:GetAttributeChangedSignal(COLOR_ATTR):Connect(refresh))
	table.insert(entry.connections, character:GetAttributeChangedSignal(TIER_ATTR):Connect(refresh))

	-- Cosmetic-only, so the orb can outlive its holder in ways the
	-- attributes cannot: a character destroyed outright never fires an
	-- attribute change. Both exits are covered.
	table.insert(entry.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			unwatch(character)
		end
	end))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(entry.connections, humanoid.Died:Connect(function()
			ChargeOrbVfx.stop(character)
		end))
	end

	-- A late joiner's first sight of an already-charging player arrives as
	-- an initial attribute value, not as a change signal.
	refresh()
end

local function bindPlayer(player: Player)
	if player == localPlayer then return end
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

for _, tag in SkillConstants.DAMAGEABLE_TAGS do
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("Model") then
			watch(instance :: Model)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			watch(instance :: Model)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			unwatch(instance :: Model)
		end
	end)
end

log:info("ready")
