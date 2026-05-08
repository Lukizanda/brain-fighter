--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponScripts = ReplicatedStorage.Shared.Weapon.Scripts
local drawRayResults = require(weaponScripts.Utility.drawRayResults)
local castRays = require(weaponScripts.Utility.castRays)
local playRandomSoundFromSource = require(weaponScripts.Utility.playRandomSoundFromSource)

local effects = weaponScripts.Effects
local remotes = ReplicatedStorage.Shared.Weapon.Remotes
local replicateShotRemote = remotes.ReplicateShot

local function onReplicateShotEvent(blaster: Tool, position: Vector3, rayResults: { castRays.RayResult })
	-- Make sure that the blaster is currently streamed in
	if blaster and blaster:IsDescendantOf(game) then
		local handle = blaster:FindFirstChild("Handle")
		local sounds = blaster:FindFirstChild("Sounds")
		local emitter = handle and handle:FindFirstChild("AudioEmitter")
		local muzzle = blaster:FindFirstChild("MuzzleAttachment", true)

		-- If the blaster has a MuzzleAttachment, we'll use that as the laser starting point, otherwise
		-- default to the blaster's pivot position.
		if muzzle then
			position = muzzle.WorldPosition
			local flash = muzzle:FindFirstChild("FlashEmitter")
			if flash then
				flash:Emit(1)
			end
		else
			position = blaster:GetPivot().Position
		end

		if sounds and emitter then
			local shootSound = sounds:FindFirstChild("Shoot")
			if shootSound then
				playRandomSoundFromSource(shootSound, emitter)
			end
		end
	end

	local effectName = blaster and blaster:GetAttribute("ShotEffect")
	local effectModule = effects:FindFirstChild(effectName or "laserBeamEffect") or effects:FindFirstChild("laserBeamEffect")
	if not effectModule then
		return
	end

	local shotEffect = require(effectModule)
	drawRayResults(position, rayResults, shotEffect)
end

replicateShotRemote.OnClientEvent:Connect(onReplicateShotEvent)
