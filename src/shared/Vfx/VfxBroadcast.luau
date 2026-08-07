--!strict

----------------------------------------------------------------------
-- VfxBroadcast
----------------------------------------------------------------------
-- The server's only legal way to make a player see or hear something.
--
-- The server has no screen and no speakers, and the engine does not
-- paper over that for you: `ParticleEmitter:Emit()` called on the server
-- does NOT replicate, so a server-spawned burst renders for nobody. What
-- *does* replicate — the anchor Part, the emitter instance, `Sound:Play()`,
-- and rate-based emitters driven by `Enabled = true` — is exactly enough
-- to make a broken effect look 80% correct in a playtest, and 100%
-- correct in Studio's server view. That combination is why this mistake
-- shipped three times before anyone caught it (see wiki/log.md 2026-08-04).
--
-- So: server code never draws. It describes, and every client draws.
--
--   VfxBroadcast.playAt(effectId, position)        — one-shot at a point
--   VfxBroadcast.playOn(effectId, target)          — one-shot on a Part
--   VfxBroadcast.shockwave(center, radius, opts)   — ground ring + burst
--   VfxBroadcast.beam(origin, endPoint)            — laser from A to B
--
-- Each takes an optional `drawnLocallyBy: number?` (a UserId): don't send
-- this to that player, they already have it. Exactly one situation earns
-- it — a client drew the cosmetic itself, immediately, as prediction, and
-- the server is now catching everyone else up. The LetterBlaster beam is
-- the case it exists for: the shooter's beam leaves the staff on the frame
-- they clicked, and a second copy a round trip later would be a visible
-- double-flash.
--
-- Omit it for anything the server originates alone (boss fire, Stone Wall).
-- And only pass it when the local draw is *unconditional* — if the client
-- might skip its own draw, excluding it means that player is the one
-- person who sees nothing, which is the exact bug class this module exists
-- to end (see wiki/design/client-server-boundary.md, Stage 4).
--
-- Calling any of these from a client is a no-op plus a warning: a client
-- cannot fire to other clients, and reaching for this from the client is
-- a sign the call belongs in the local-draw branch instead.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("VfxBroadcast")

export type BeamPayloadOpts = {
	soundParent: Instance?,
	soundName: string?,
	drawnLocallyBy: number?,
}

export type ShockwavePayloadOpts = {
	color: Color3?,
	transparency: number?,
	lifetimeSec: number?,
	cosmeticEffectId: string?,
	yOffset: number?,
	drawnLocallyBy: number?,
}

-- Resolved lazily rather than at module scope. This module is required
-- during server boot (SkillDelivery ← BossService), and a module-scope
-- WaitForChild would stall that boot indefinitely if the remote were ever
-- missing, instead of failing one effect. Same pattern as
-- SkillDelivery.projectileVfxRemote.
local _remote: RemoteEvent? = nil
local function remote(): RemoteEvent?
	if _remote then return _remote end
	local remotes = ReplicatedStorage.Shared.Vfx:FindFirstChild("Remotes")
	local found = remotes and remotes:FindFirstChild("WorldVfxEvent")
	if found and found:IsA("RemoteEvent") then
		_remote = found :: RemoteEvent
	end
	return _remote
end

local VfxBroadcast = {}

-- Shared guard. Returns the remote when this VM is allowed to broadcast,
-- nil otherwise. The client warning is deliberately loud and throttled
-- rather than silent: a silent no-op here would reproduce the exact
-- failure mode this module exists to kill.
local function outbound(caller: string): RemoteEvent?
	if not RunService:IsServer() then
		log:warnThrottled("client_call", 5, string.format(
			"%s called from a client — clients draw directly (SkillVisuals / spawnEffect), " ..
			"only the server broadcasts. Ignored.\n%s",
			caller, debug.traceback()
		))
		return nil
	end
	return remote()
end

-- One-shot effect at a bare world position — a shot dying on a shield
-- shell, a muzzle flash, an impact with no Part left to hang it on.
function VfxBroadcast.playAt(effectId: string, position: Vector3, drawnLocallyBy: number?)
	local r = outbound("playAt")
	if not r then return end
	r:FireAllClients({
		kind           = "point",
		effectId       = effectId,
		position       = position,
		drawnLocallyBy = drawnLocallyBy,
	})
end

-- One-shot effect parented to an existing replicated Instance — an impact
-- burst on a victim's HumanoidRootPart, a cosmetic overlay on a barrier.
--
-- `target` must ALREADY be replicated — an Instance argument the receiving
-- client hasn't seen yet arrives as nil, so this is only safe for things
-- that have existed for a while (a character's HumanoidRootPart, a tagged
-- rig). For a Part the server created this frame, use playAt with its
-- position instead; SkillVisuals.spawnBarrier does exactly that.
--
-- Each client attaches its own emitter to its own copy of the target,
-- which is what makes the burst actually render.
function VfxBroadcast.playOn(effectId: string, target: Instance, drawnLocallyBy: number?)
	local r = outbound("playOn")
	if not r then return end
	r:FireAllClients({
		kind           = "attached",
		effectId       = effectId,
		target         = target,
		drawnLocallyBy = drawnLocallyBy,
	})
end

-- A laser beam travelling from `origin` to `endPoint` — the LetterBlaster
-- shot, and anything else that wants a visible line between two points.
--
-- Positions rather than Instances on purpose. The endpoint is usually a
-- LetterBlock the server is about to destroy, and an Instance argument for
-- a thing that no longer exists by the time the payload lands arrives as
-- nil; a Vector3 still draws the shot that was actually taken.
--
-- `opts.soundParent` + `opts.soundName` name a Sound that already exists on
-- a long-lived replicated Instance — the staff's Handle — and each client
-- plays its own copy. Naming an existing Sound rather than shipping a
-- SoundId keeps its authored volume and rolloff intact, and the parent
-- being a BasePart is what makes the playback positional. Same
-- already-replicated requirement as playOn: don't point this at something
-- the server created this frame.
function VfxBroadcast.beam(origin: Vector3, endPoint: Vector3, opts: BeamPayloadOpts?)
	local r = outbound("beam")
	if not r then return end
	local o = opts or {}
	r:FireAllClients({
		kind           = "beam",
		origin         = origin,
		endPoint       = endPoint,
		soundParent    = o.soundParent,
		soundName      = o.soundName,
		drawnLocallyBy = o.drawnLocallyBy,
	})
end

-- Ground-plane ring plus its optional burst. Purely cosmetic — the ring
-- is CanCollide = false, so unlike a Stone Wall there is no reason for
-- the server to own one.
function VfxBroadcast.shockwave(center: Vector3, radius: number, opts: ShockwavePayloadOpts?)
	local r = outbound("shockwave")
	if not r then return end
	local o = opts or {}
	r:FireAllClients({
		kind             = "shockwave",
		center           = center,
		radius           = radius,
		color            = o.color,
		transparency     = o.transparency,
		lifetimeSec      = o.lifetimeSec,
		cosmeticEffectId = o.cosmeticEffectId,
		yOffset          = o.yOffset,
		drawnLocallyBy   = o.drawnLocallyBy,
	})
end

return VfxBroadcast
