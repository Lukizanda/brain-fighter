--!strict

----------------------------------------------------------------------
-- WorldVfxController
----------------------------------------------------------------------
-- Draws the world cosmetics the server asked for over WorldVfxEvent.
--
-- The receiving half of VfxBroadcast — see that module for why the
-- server can't just draw these itself. Every payload lands here and is
-- turned into the same SkillVisuals / spawnEffect call the server used
-- to make directly, except now it happens on a VM that has a renderer.
--
-- Skips a payload carrying `drawnLocallyBy == LocalPlayer.UserId`: that
-- client's prediction layer (VfxController, off `SpellResolved`) already
-- drew it on the frame it fired. Today only the cast cue carries the
-- exclusion; every impact, shockwave and projectile goes to everyone.
--
-- `projectile` payloads draw this client's own copy of every shot the
-- server fires. The authoritative projectile is invisible and
-- server-simulated, so without this nothing would be visible for boss and
-- NPC fire at all — see wiki/systems/SkillPipeline.md § "Projectile
-- visuals are client-local" for why the seen shot is client-local.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena           = require(ReplicatedStorage.Shared.GameMode.Arena)
local CosmeticProjectile = require(ReplicatedStorage.Shared.Vfx.CosmeticProjectile)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Hittables       = require(ReplicatedStorage.Shared.Skills.Hittables)
local Logger          = require(ReplicatedStorage.Shared.Core.Logger)
local SkillBuffs      = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local SkillVisuals    = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local VfxConfig       = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local collectStream   = require(ReplicatedStorage.Shared.Vfx.collectStream)
local laserBeamEffect = require(ReplicatedStorage.Shared.Weapon.Scripts.Effects.laserBeamEffect)
local spawnEffect     = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

local log         = Logger.new("WorldVfxController")
local LocalPlayer = Players.LocalPlayer

local Remotes       = ReplicatedStorage.Shared.Vfx.Remotes
local WorldVfxEvent = Remotes:WaitForChild("WorldVfxEvent") :: RemoteEvent

-- Play a Sound that already exists on a replicated Instance, on this
-- client only.
--
-- We play the authored instance rather than building one from a SoundId:
-- its volume, pitch and rolloff were tuned where the designer can see
-- them, and a second Sound built here would drift from that silently.
-- Positional playback comes free from the parent being a BasePart, which
-- is the whole reason the staff's Sounds hang off the Handle.
--
-- Restarting a Sound already playing is deliberate — that is what a weapon
-- fired twice inside one sample's length should do.
local function playNamedSound(parent: any, name: any)
	if typeof(parent) ~= "Instance" or typeof(name) ~= "string" then return end
	-- The character may have been destroyed, or the Tool unequipped,
	-- between the server firing and this arriving.
	if not parent:IsDescendantOf(workspace) then return end
	local sound = parent:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

----------------------------------------------------------------------
-- Gameplay seams for the drawn shot
----------------------------------------------------------------------
-- CosmeticProjectile draws and knows nothing else (refactor chunk 10): the
-- three questions its flight loop has to ask about the *game* are answered
-- here, where requiring the Skills layer is the right way round. Each one
-- is the same question the server asks about the authoritative shot, asked
-- against the same modules, so the picture and the damage agree.

-- Every player currently carrying a live absorb pool. Players only,
-- deliberately: shields come from selfTarget spells, so no NPC or boss can
-- hold one today. If that changes, this, ShieldVfxController's
-- `includeTaggedRigs` and SkillDelivery's shell scan change together, or
-- the visual stops matching the block.
local function shieldedRoots(source: Instance?): { BasePart }
	local roots: { BasePart } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or character == source then continue end
		local pool = character:GetAttribute(HealthConstants.SHIELD_ATTRIBUTE)
		if typeof(pool) ~= "number" or (pool :: number) <= 0 then continue end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			table.insert(roots, hrp :: BasePart)
		end
	end
	return roots
end

-- Where a step first meets the nearest shield shell, or nil for none.
--
-- `SkillBuffs.shellEntry` is the one copy of this maths, shared with
-- SkillDelivery's authoritative block: the bubble has no Part behind it
-- (ShieldVfx draws a per-client cosmetic), so both sides have to agree
-- analytically about the same sphere or a shot dies in two different places.
local function shellContactFor(source: Instance?)
	return function(from: Vector3, step: Vector3, padding: number): Vector3?
		local length = step.Magnitude
		if length <= 0 then return nil end
		local direction = step / length

		local nearest: number? = nil
		for _, root in shieldedRoots(source) do
			local entry = SkillBuffs.shellEntry(from, step, root.Position, padding)
			if entry and (nearest == nil or entry < (nearest :: number)) then
				nearest = entry
			end
		end
		if not nearest then return nil end
		return from + direction * (nearest :: number)
	end
end

-- Is a rig within `radius` of this point — the server's proximity rule,
-- measured against exactly the set the server measures against.
--
-- This runs on a client, so the candidate players are everyone on the
-- server and `Hittables` keeps only those whose ArenaId matches the
-- shooter's. It frame-caches per arena, which matters: a Brain volley puts
-- 30 cosmetics in the air at once and each of them asks this every frame.
local function rigWithinFor(source: Instance?)
	local arenaId = Hittables.arenaOfSource(source) or Arena.DEFAULT_ID
	return function(point: Vector3, radius: number): boolean
		for _, rig in Hittables.collect(Players:GetPlayers(), arenaId) do
			if rig.model == source then continue end
			if (rig.hrp.Position - point).Magnitude <= radius then
				return true
			end
		end
		return false
	end
end

-- A projectile payload drives a per-frame distance test inside a
-- Heartbeat loop, so every numeric field is checked before launch: a
-- malformed entry drops one cosmetic rather than erroring every frame.
local function isLaunchable(payload: any): boolean
	return typeof(payload.origin) == "Vector3"
		and typeof(payload.direction) == "Vector3"
		and typeof(payload.speed) == "number"
		and typeof(payload.size) == "Vector3"
		and typeof(payload.color) == "Color3"
		and typeof(payload.lifetimeSec) == "number"
		and payload.direction.Magnitude > 0
end

-- Only the server fires this, so the payload isn't a trust boundary — but
-- it is still a wire boundary. A malformed entry should drop one cosmetic,
-- not throw inside the event handler.
local handlers: { [string]: (payload: any) -> () } = {
	point = function(payload: any)
		if typeof(payload.effectId) ~= "string" then return end
		if typeof(payload.position) ~= "Vector3" then return end
		SkillVisuals.spawnEffectAtPoint(payload.position, payload.effectId)
	end,

	attached = function(payload: any)
		if typeof(payload.effectId) ~= "string" then return end
		local target = payload.target
		if typeof(target) ~= "Instance" then return end
		-- The Part may have been destroyed between the server firing and
		-- this arriving — a victim who died, a barrier that expired.
		if not target:IsDescendantOf(workspace) then return end
		if not (target:IsA("BasePart") or target:IsA("Attachment")) then return end
		local effect = VfxConfig.EFFECTS[payload.effectId]
		if not effect then return end
		spawnEffect(effect, target :: BasePart | Attachment)
	end,

	beam = function(payload: any)
		if typeof(payload.origin) ~= "Vector3" then return end
		if typeof(payload.endPoint) ~= "Vector3" then return end
		laserBeamEffect(payload.origin, payload.endPoint)
		playNamedSound(payload.soundParent, payload.soundName)
	end,

	-- A block's mana streaming onto the player who popped it. Drawn by
	-- everyone except the popper, who drew their own on the frame they
	-- clicked — see VfxBroadcast.collect.
	collect = function(payload: any)
		if typeof(payload.origin) ~= "Vector3" then return end
		if typeof(payload.collectorUserId) ~= "number" then return end
		collectStream.play(
			payload.origin,
			payload.collectorUserId,
			if typeof(payload.color) == "Color3" then payload.color else nil
		)
	end,

	shockwave = function(payload: any)
		if typeof(payload.center) ~= "Vector3" then return end
		if typeof(payload.radius) ~= "number" then return end
		SkillVisuals.spawnShockwave(payload.center, payload.radius, {
			color            = if typeof(payload.color) == "Color3" then payload.color else nil,
			transparency     = if typeof(payload.transparency) == "number" then payload.transparency else nil,
			lifetimeSec      = if typeof(payload.lifetimeSec) == "number" then payload.lifetimeSec else nil,
			cosmeticEffectId = if typeof(payload.cosmeticEffectId) == "string" then payload.cosmeticEffectId else nil,
			yOffset          = if typeof(payload.yOffset) == "number" then payload.yOffset else nil,
		})
	end,

	projectile = function(payload: any)
		if not isLaunchable(payload) then
			log:warnThrottled("bad_projectile", 5, "dropped malformed projectile payload")
			return
		end
		CosmeticProjectile.launch({
			origin           = payload.origin,
			direction        = payload.direction,
			speed            = payload.speed,
			size             = payload.size,
			color            = payload.color,
			lifetimeSec      = payload.lifetimeSec,
			cosmeticEffectId = payload.cosmeticEffectId,
			launchEffectId   = if typeof(payload.launchEffectId) == "string"
				then payload.launchEffectId
				else nil,
			proximityRadius  = if typeof(payload.proximityRadius) == "number"
				then payload.proximityRadius
				else nil,
			-- Defaults to consuming, matching SkillDelivery: only an explicit
			-- `false` over the wire makes the drawn shot pierce.
			consumeOnHit     = payload.consumeOnHit ~= false,
			-- Both optional and both only ever read as "is it set" / "is it
			-- true", so a malformed value degrades to a missing death cue
			-- rather than anything that can error mid-Heartbeat.
			destroyEffectId  = if typeof(payload.destroyEffectId) == "string"
				then payload.destroyEffectId
				else nil,
			hasImpactCue     = payload.hasImpactCue == true,
			source           = payload.source,
			-- The three seams above. `drawAt` is this VM's local draw:
			-- SkillVisuals routes on which VM it is, and we are a client.
			drawAt           = SkillVisuals.spawnEffectAtPoint,
			shellContactFor  = shellContactFor(payload.source),
			rigWithin        = rigWithinFor(payload.source),
		})
	end,

	-- A rig's windup warning. Drawn by everyone: it is a warning about
	-- someone else's attack and nothing predicts it.
	telegraph = function(payload: any)
		if typeof(payload.style) ~= "string" then return end
		if typeof(payload.durationSec) ~= "number" or payload.durationSec <= 0 then return end
		local rig = payload.rig
		-- The rig may have died between the server describing the windup and
		-- this arriving, in which case there is nothing left to warn about.
		if typeof(rig) ~= "Instance" or not rig:IsA("Model") then return end
		if not rig:IsDescendantOf(workspace) then return end
		SkillVisuals.spawnTelegraph(
			payload.style,
			rig :: Model,
			payload.durationSec,
			if typeof(payload.radiusStuds) == "number" then payload.radiusStuds else nil
		)
	end,
}

WorldVfxEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		log:warnThrottled("bad_payload", 5, "dropped non-table payload")
		return
	end
	if payload.drawnLocallyBy == LocalPlayer.UserId then return end

	local handler = handlers[payload.kind]
	if not handler then
		log:warnThrottled("bad_kind", 5, ("dropped payload with unknown kind %q"):format(
			tostring(payload.kind)
		))
		return
	end
	handler(payload)
end)

log:info("ready")
