--!strict

----------------------------------------------------------------------
-- SpellCastController
----------------------------------------------------------------------
-- The client's cast path: turns a (color, tier) request from the spell
-- menu into a predicted cast and the relay that asks the server to run
-- the authoritative one.
--
--   1. Look the spell up — whether an enemy lock is needed depends on
--      the spell, not the colour (blue Shield is a self-buff).
--   2. Resolve the target, at release rather than at press: a 1.75 s T4
--      charge is long enough for the world to move.
--   3. CastAction.castSpecific — validates, drains the client reservoir,
--      runs the predicted executor pass and fires `SpellResolved`.
--   4. Relay every accepted cast over SpellCastServer. The server is the
--      only VM that applies damage, grants shields or places a wall; the
--      predicted run here draws the cast cue and nothing else.
--
-- The HUD (SpellMenuGui) owns the gesture, the charge orb and the
-- feedback (fired flash, fizzle sound). It hands the cast here through
-- the `RequestCast` BindableFunction and reads the result back, so the
-- coordinator never resolves a target or touches a remote itself.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger        = require(ReplicatedStorage.Shared.Core.Logger)
local CastAction    = require(ReplicatedStorage.Shared.CastAction)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local NPCConstants  = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local PlayerSession = require(script.Parent.PlayerSession)

local spellCastRemote = ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer :: RemoteEvent
local requestCast     = script:WaitForChild("RequestCast") :: BindableFunction

local log     = Logger.new("SpellCastController")
local player  = Players.LocalPlayer
local session = PlayerSession.get()

-- The Boss-system boss is named this in workspace and is not tagged NPC.
local BOSS_MODEL_NAME = "Boss"

-- What the menu gets back from a request. `name` is the spell that went
-- out; `reason` is why one didn't.
export type CastRequestResult = {
	ok: boolean,
	name: string?,
	reason: string?,
}

-- Nearest living enemy Model (NPC or the Boss-system boss) within
-- SpellRegistry.AUTO_TARGET_RANGE_STUDS of the character, or nil.
local function findAutoTarget(character: Model): Model?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return nil
	end
	local origin = (hrp :: BasePart).Position

	local nearest: Model? = nil
	local nearestDist = SpellRegistry.AUTO_TARGET_RANGE_STUDS

	local function consider(model: Instance)
		if not model:IsA("Model") or model == character then
			return
		end
		local h = model:FindFirstChildOfClass("Humanoid")
		if not h or h.Health <= 0 then
			return
		end
		local dist = (model:GetPivot().Position - origin).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = model :: Model
		end
	end

	for _, npc in CollectionService:GetTagged(NPCConstants.TAG_NPC) do
		consider(npc)
	end

	local boss = workspace:FindFirstChild(BOSS_MODEL_NAME)
	if boss then
		consider(boss)
	end

	return nearest
end

local function castSpell(color: string, tier: number): CastRequestResult
	local character = player.Character
	if not character then
		log:warn("cast requested but no character")
		return { ok = false, reason = "no character" }
	end

	local lookupOk, specOrErr = pcall(SpellRegistry.getSpell, color :: SpellRegistry.Color, tier)
	if not lookupOk then
		log:warn(string.format("cast fizzle (%s t%d) — %s", color, tier, tostring(specOrErr)))
		return { ok = false, reason = tostring(specOrErr) }
	end
	local spec = specOrErr :: SpellRegistry.Spec

	local target: Model? = nil
	if SpellRegistry.needsEnemyTarget(spec) then
		target = findAutoTarget(character)
		if not target then
			log:info(string.format("cast fizzle (%s) — no target in range", spec.name))
			return { ok = false, reason = "no target in range" }
		end
	end

	local result = CastAction.castSpecific(
		color :: CastAction.Color,
		tier,
		session.energyReservoirs,
		character,
		target
	)
	if not result.ok then
		log:info(string.format("cast fizzle: %s", result.reason or "?"))
		return { ok = false, reason = result.reason }
	end

	-- Relay every accepted cast. Offensive spells need it because the
	-- server owns every rig's Health; self-buffs because the shield pool
	-- is read by applyDamage server-side; Stone Wall because a
	-- client-spawned Part can't block the server-owned boss.
	if result.cast then
		spellCastRemote:FireServer(result.cast.color, result.cast.tier, target)
	end
	local name = if result.cast then result.cast.name else spec.name
	log:info(string.format("cast: %s (t%d) -> %s", name, tier, if target then target.Name else "self"))
	return { ok = true, name = name }
end

requestCast.OnInvoke = function(color: any, tier: any): CastRequestResult
	if typeof(color) ~= "string" or typeof(tier) ~= "number" then
		return { ok = false, reason = "malformed cast request" }
	end
	return castSpell(color, tier)
end

log:info("ready")
