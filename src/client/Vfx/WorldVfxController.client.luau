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
-- Skips a payload carrying `drawnLocallyBy == LocalPlayer.UserId`: the
-- dual-VM delivery handlers run on the predicting player's client too and
-- already drew it on the frame it fired. Same skip the VfxController and
-- ProjectileVfxController do with `senderUserId` / `predictedBy`.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger          = require(ReplicatedStorage.Shared.Core.Logger)
local SkillVisuals    = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local VfxConfig       = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
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
