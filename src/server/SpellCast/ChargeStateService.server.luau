--!strict

----------------------------------------------------------------------
-- ChargeStateService
----------------------------------------------------------------------
-- Publishes "this player is winding up a spell" to everyone else.
--
-- The client that is charging tells the server which colour it is holding
-- and which tier it has reached; this service validates that and writes it
-- as two attributes on the player's character Model. Because the
-- character is server-owned, those writes replicate to every client for
-- free, and `client/Vfx/ChargeOrbController` on each of them draws the
-- orb. No fan-out RemoteEvent, no per-frame traffic — see
-- SkillConstants.CHARGE_COLOR_ATTR for the full argument, and
-- wiki/systems/ChargeCast.md for the shape of the gesture.
--
-- **Its own file, not a branch in SpellCastService.** Different remote,
-- different lifecycle, and a different trust posture: a cast changes
-- health and mana and is validated accordingly, whereas a charge state
-- moves nothing but pixels. Folding a purely cosmetic broadcast into the
-- handler that debits the energy ledger would put the two on one rate
-- limit and one rejection path for no reason.
--
-- **Trust.** Nothing here is authoritative and nothing here needs to be.
-- A client that lies about its charge draws a wrong-sized ball over its
-- own head; the spell it eventually casts is priced by SpellCastService
-- against EnergyLedger exactly as before. What IS enforced is that the
-- payload is well-formed — a real colour, a real tier for that colour —
-- so a malformed fire can't write junk onto a replicated character.
--
-- Every rejection drops the request and logs; nothing throws, so one bad
-- payload can never take the handler down for other players.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger           = require(ReplicatedStorage.Shared.Core.Logger)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)
local SkillConstants   = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local SpellRegistry    = require(ReplicatedStorage.Shared.SpellRegistry)

local SpellCastConstants = require(script.Parent.SpellCastConstants)
local RateLimiter        = require(script.Parent.Parent.Utility.RateLimiter)

local log = Logger.new("ChargeStateService")

local chargeRemote = ReplicatedStorage.Shared.SpellCast.Remotes.ChargeState :: RemoteEvent

local COLOR_ATTR = SkillConstants.CHARGE_COLOR_ATTR
local TIER_ATTR  = SkillConstants.CHARGE_TIER_ATTR

local VALID_COLORS: { [string]: true } = {}
for _, color in EnergyReservoirs.COLORS do
	VALID_COLORS[color] = true
end

local VALID_PHASES: { [string]: true } = { start = true, tier = true, ["end"] = true }

local chargeLimiter = RateLimiter.new(
	SpellCastConstants.CHARGE_BURST_CAPACITY,
	SpellCastConstants.CHARGE_REFILL_PER_SEC
)

-- Same one-token-per-(player, reason) budget SpellCastService uses, for
-- the same reason: the first instance of each rejection is always
-- reported, and a looping client cannot flood the output.
local rejectionLogBudget = RateLimiter.new(1, 1 / SpellCastConstants.REJECTION_LOG_THROTTLE_SEC)

local function reject(player: Player, reason: string)
	local key = string.format("%d:%s", player.UserId, reason)
	if rejectionLogBudget:consume(key) then
		log:warn(string.format("rejected ChargeState from %s — %s", player.Name, reason))
	end
end

-- Tier 0 is legal: it is the transient between the press landing and the
-- charge reaching T1, and it is what `end` carries for a cancel.
local function validTier(color: string, tier: any): number?
	if typeof(tier) ~= "number" then return nil end
	local n = tier :: number
	if n ~= math.floor(n) or n < 0 then return nil end
	if n > SpellRegistry.tierCount(color :: any) then return nil end
	return n
end

local function clear(character: Model)
	character:SetAttribute(TIER_ATTR, nil)
	character:SetAttribute(COLOR_ATTR, nil)
end

chargeRemote.OnServerEvent:Connect(function(player: Player, phase: any, color: any, tier: any)
	if not chargeLimiter:consume(player) then
		reject(player, "rate limit")
		return
	end

	if typeof(phase) ~= "string" or not VALID_PHASES[phase :: string] then
		reject(player, "invalid phase")
		return
	end

	local character = player.Character
	if not character then
		-- Ordinary during the respawn gap — a charge in flight when the
		-- caster dies arrives with nothing to write to. Silent.
		return
	end

	if phase == "end" then
		-- Tier first, colour second, and the order is load-bearing:
		-- ChargeOrbController reads the tier on the frame the colour clears
		-- to decide between the release flash and a quiet collapse. Clearing
		-- the colour first would leave it reading a tier that is already
		-- gone, and every cast would look like a cancel.
		local finalTier = if typeof(tier) == "number" then math.max(math.floor(tier :: number), 0) else 0
		character:SetAttribute(TIER_ATTR, finalTier)
		character:SetAttribute(COLOR_ATTR, nil)
		return
	end

	if typeof(color) ~= "string" or not VALID_COLORS[color :: string] then
		reject(player, "invalid color")
		return
	end
	local validatedColor = color :: string

	local validatedTier = validTier(validatedColor, tier)
	if validatedTier == nil then
		reject(player, "invalid tier")
		return
	end

	if phase == "start" then
		character:SetAttribute(COLOR_ATTR, validatedColor)
		character:SetAttribute(TIER_ATTR, validatedTier)
		return
	end

	-- phase == "tier". A tier update for a colour nobody is holding is an
	-- out-of-order fire (or a client skipping `start`); drop it rather than
	-- inventing a charge from a mid-sequence message.
	if character:GetAttribute(COLOR_ATTR) ~= validatedColor then
		reject(player, "tier update without an open charge")
		return
	end
	character:SetAttribute(TIER_ATTR, validatedTier)
end)

-- A dead or despawning player must never leave an orb behind. The
-- character being destroyed takes its attributes with it, but a *death*
-- does not — the rig stays in the workspace, and without this the orb
-- would hang over the corpse until respawn.
local function bindCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			clear(character)
		end)
	end
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(clear)
	if player.Character then
		bindCharacter(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	chargeLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
	if player.Character then
		clear(player.Character)
	end
end)

log:info("ChargeStateService ready — charge orb state replicating via character attributes")
