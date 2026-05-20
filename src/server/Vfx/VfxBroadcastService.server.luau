--!strict
----------------------------------------------------------------------
-- VfxBroadcastService
----------------------------------------------------------------------
-- Relays client spell-cast VFX requests to all other clients.
--
-- Flow (R2):
--   1. Casting client fires BroadcastSpellVfx:FireServer(payload)
--      immediately after CastAction.spellResolved fires.
--   2. This service validates the payload (rate + type + target).
--   3. On pass, fires SpellVfxEvent:FireAllClients({...senderUserId}).
--   4. Receiving clients skip if senderUserId == LocalPlayer.UserId
--      (they already played the VFX locally from spellResolved).
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local Remotes = ReplicatedStorage.Shared.Vfx.Remotes
local BroadcastSpellVfx = Remotes.BroadcastSpellVfx :: RemoteEvent
local SpellVfxEvent     = Remotes.SpellVfxEvent     :: RemoteEvent

local MAX_RATE_PER_SECOND = 4
local VALID_COLORS = { red = true, green = true, blue = true }
local MIN_TIER = 1
-- Tier 4 (Volley) is in the SpellRegistry roster.
local MAX_TIER = 4
-- Defensive cap. Today the registry tops out at ~3 unique kinds per skill
-- (Sanctuary = heal + shield). Anything beyond suggests payload tampering.
local MAX_IMPACT_EFFECT_IDS = 8

-- Per-player sliding window: count + window end timestamp (os.clock seconds)
local playerRates: { [number]: { count: number, resetAt: number } } = {}

local function checkRate(userId: number): boolean
	local now = os.clock()
	local entry = playerRates[userId]
	if not entry or now >= entry.resetAt then
		playerRates[userId] = { count = 1, resetAt = now + 1 }
		return true
	end
	if entry.count >= MAX_RATE_PER_SECOND then
		return false
	end
	entry.count += 1
	return true
end

local function validatePayload(player: Player, payload: any): boolean
	if type(payload) ~= "table" then
		return false
	end

	if not checkRate(player.UserId) then
		return false
	end

	if not VALID_COLORS[payload.color] then
		return false
	end

	local tier = payload.tier
	if type(tier) ~= "number" or tier < MIN_TIER or tier > MAX_TIER then
		return false
	end

	-- castEffectId is optional (spells with no cast VFX omit it).
	-- Only validate when present.
	if payload.castEffectId ~= nil then
		if next(VfxConfig.EFFECTS) ~= nil and not VfxConfig.EFFECTS[payload.castEffectId] then
			return false
		end
	end

	-- impactEffectIds is an array of ids that must each resolve in EFFECTS.
	-- Missing array is fine (skills with empty onImpact, e.g. Stone Wall).
	if payload.impactEffectIds ~= nil then
		if type(payload.impactEffectIds) ~= "table" then
			return false
		end
		if #payload.impactEffectIds > MAX_IMPACT_EFFECT_IDS then
			return false
		end
		for _, id in payload.impactEffectIds do
			if type(id) ~= "string" or not VfxConfig.EFFECTS[id] then
				return false
			end
		end
	end

	if payload.impactTarget ~= nil then
		local ok, isDescendant = pcall(function(): boolean
			return (payload.impactTarget :: Instance):IsDescendantOf(Workspace)
		end)
		if not ok or not isDescendant then
			return false
		end
	end

	return true
end

Players.PlayerRemoving:Connect(function(player: Player)
	playerRates[player.UserId] = nil
end)

BroadcastSpellVfx.OnServerEvent:Connect(function(player: Player, payload: any)
	if not validatePayload(player, payload) then
		return
	end
	local outPayload: { [string]: any } = payload :: { [string]: any }
	outPayload.senderUserId = player.UserId
	SpellVfxEvent:FireAllClients(outPayload)
end)
