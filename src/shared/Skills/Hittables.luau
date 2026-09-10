--!strict

----------------------------------------------------------------------
-- Hittables
----------------------------------------------------------------------
-- The one definition of "a rig a skill can land on", and the seam that
-- scopes it to an arena (refactor chunk 9, audit F30).
--
-- Three modules used to keep their own copy of this list — SkillDelivery's
-- `collectHittables`, CosmeticProjectile's `collectRigs` and the NPC
-- Perception scan — each with a comment asking the reader to keep it in
-- step with the other two. They now all read this one, so the damage, the
-- picture of the shot and the AI cannot disagree about who is in a fight.
--
-- Pure and shared. CosmeticProjectile draws on the client, so nothing here
-- requires a server module; the caller passes the players it has — the
-- server passes an arena's roster, a client passes the whole player list
-- — and this module applies the arena filter to everything uniformly.
--
-- Arena membership is read the same way everywhere else in the place:
--   * a player — the `ArenaId` attribute SessionRegistry publishes on the
--     Player instance (replicated, so a client can read it too);
--   * a tagged rig (NPC, Boss, Damageable) — the `ArenaId` attribute the
--     spawning service stamped on the Model;
--   * an absent attribute means `Arena.DEFAULT_ID`, the reading `Arena.idOf`
--     gives every other authored part.
-- A `nil` arena id means "no filter" and is for callers that genuinely
-- want the whole server, not a default.
--
-- Candidates mirror the client auto-target in SpellCastController: the
-- NPC tag, the Damageable tag and the boss (tagged "Boss") — i.e.
-- `SkillConstants.DAMAGEABLE_TAGS` — plus player characters.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Arena          = require(ReplicatedStorage.Shared.GameMode.Arena)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)

export type Hittable = {
	model: Model,
	hum: Humanoid,
	hrp: BasePart,
	-- Set when the rig is a player's character; nil for NPCs, the boss
	-- and dummies. Lets a caller that only wants people (the NPC scan,
	-- an AoE aimed at the roster) select them without a second lookup.
	player: Player?,
}

-- Cache key for an unfiltered collect.
local ANY_ARENA_KEY = "*"

local Hittables = {}

-- Frame-level cache, one snapshot per arena id: rebuilt once per Heartbeat
-- and shared across every concurrent caller on this VM. Boss Volley puts
-- 30 projectiles in the air at once and every NPC scans every tick —
-- without this each of them would re-query CollectionService per frame.
--
-- The players list is *not* part of the key. It is taken to be that
-- arena's population, and every caller on one VM passes the same one for
-- the same id (the roster on the server, everyone on a client).
--
-- The Heartbeat that invalidates it connects on first use rather than at
-- module scope, so a VM that never collects never pays for the callback.
local cache: { [string]: { Hittable } } = {}
local invalidator: RBXScriptConnection? = nil

----------------------------------------------------------------------
-- Arena membership
----------------------------------------------------------------------

-- The arena a delivery's source lives in. A player's character answers
-- with its Player's attribute — the character carries none — and any
-- other rig with its own. nil only when there is no source at all.
function Hittables.arenaOfSource(source: Instance?): string?
	if not source then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(source)
	if player then
		return Arena.idOf(player)
	end
	return Arena.idOf(source)
end

----------------------------------------------------------------------
-- Collection
----------------------------------------------------------------------

-- Every living rig in `arenaId` (or everywhere, for nil): the given
-- players' characters, then every Model carrying one of the damageable
-- tags. Deduped by Humanoid so a rig carrying two tags is one entry.
function Hittables.collect(players: { Player }, arenaId: string?): { Hittable }
	local key = arenaId or ANY_ARENA_KEY
	local cached = cache[key]
	if cached then
		return cached
	end
	if not invalidator then
		invalidator = RunService.Heartbeat:Connect(function()
			table.clear(cache)
		end)
	end

	local results: { Hittable } = {}
	local seen: { [Humanoid]: true } = {}

	local function tryAdd(model: Instance?, player: Player?)
		if not model or not model:IsA("Model") then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or seen[hum] then
			return
		end
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			return
		end
		seen[hum] = true
		table.insert(results, { model = model, hum = hum, hrp = hrp, player = player })
	end

	for _, player in players do
		if arenaId == nil or Arena.idOf(player) == arenaId then
			tryAdd(player.Character, player)
		end
	end
	for _, tag in SkillConstants.DAMAGEABLE_TAGS do
		for _, inst in CollectionService:GetTagged(tag) do
			if arenaId == nil or Arena.idOf(inst) == arenaId then
				tryAdd(inst, nil)
			end
		end
	end

	cache[key] = results
	return results
end

return Hittables
