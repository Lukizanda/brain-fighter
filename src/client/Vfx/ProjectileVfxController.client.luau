--!strict

----------------------------------------------------------------------
-- ProjectileVfxController
----------------------------------------------------------------------
-- Draws the client's own copy of every shot the server fires.
--
-- The authoritative projectile is invisible and server-simulated, so
-- without this nothing would be visible for boss and NPC fire at all.
-- The reason for the split is in
-- wiki/systems/SkillPipeline.md § "Projectile visuals are client-local":
-- clients render server-owned parts behind the server, so the real shot
-- was vanishing ~12 studs short of a shield bubble instead of on it.
--
-- Skips the casting player's own shots. `SkillDelivery`'s client branch
-- already drew those on the frame they fired — replaying the broadcast
-- would stack a second projectile alongside the first. Boss and NPC fire
-- carries no `casterUserId`, so it is drawn by everyone.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticProjectile = require(ReplicatedStorage.Shared.Vfx.CosmeticProjectile)
local Logger             = require(ReplicatedStorage.Shared.Core.Logger)

local log         = Logger.new("ProjectileVfxController")
local LocalPlayer = Players.LocalPlayer

local Remotes             = ReplicatedStorage.Shared.Vfx.Remotes
local ProjectileVfxEvent  = Remotes:WaitForChild("ProjectileVfxEvent") :: RemoteEvent

-- The payload crosses a remote, so nothing in it is trustworthy shape-wise
-- even though only the server fires it. A malformed entry drops one
-- cosmetic rather than erroring inside a Heartbeat loop every frame.
local function isLaunchable(payload: any): boolean
	return typeof(payload) == "table"
		and typeof(payload.origin) == "Vector3"
		and typeof(payload.direction) == "Vector3"
		and typeof(payload.speed) == "number"
		and typeof(payload.size) == "Vector3"
		and typeof(payload.color) == "Color3"
		and typeof(payload.lifetimeSec) == "number"
		and payload.direction.Magnitude > 0
end

ProjectileVfxEvent.OnClientEvent:Connect(function(payload: any)
	if not isLaunchable(payload) then
		log:warnThrottled("bad_payload", 5, "dropped malformed projectile payload")
		return
	end
	if payload.casterUserId == LocalPlayer.UserId then return end

	CosmeticProjectile.launch({
		origin           = payload.origin,
		direction        = payload.direction,
		speed            = payload.speed,
		size             = payload.size,
		color            = payload.color,
		lifetimeSec      = payload.lifetimeSec,
		cosmeticEffectId = payload.cosmeticEffectId,
		source           = payload.source,
	})
end)

log:info("ready")
