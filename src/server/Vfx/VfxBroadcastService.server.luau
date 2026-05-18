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
local MAX_TIER = 3

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

	-- Skip effectId check while VfxConfig.EFFECTS is empty (Phase A).
	-- Once Phase C populates EFFECTS, this becomes a real gate.
	if next(VfxConfig.EFFECTS) ~= nil and not VfxConfig.EFFECTS[payload.castEffectId] then
		return false
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
