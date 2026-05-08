----------------------------------------------------------------------
-- MeleeHitReplication (client)
----------------------------------------------------------------------
-- Listens for server-broadcast melee hits and plays a spatial impact
-- sound at the victim's position. Each weapon carries its own Sounds/Hit
-- folder (either a single AudioPlayer or a folder of variants Hit1/2/3)
-- so different melee weapons can have different impact audio.
--
-- Server-authoritative: only fires when MeleeSwingService confirms a
-- damage-landing hit, so the sound is always consistent with the
-- gameplay result.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playSoundFromSource = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.playSoundFromSource)
local playRandomSoundFromSource = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.playRandomSoundFromSource)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("MeleeHitReplication")

local hitRemote = ReplicatedStorage.Shared.Weapon.Remotes:WaitForChild("MeleeHitReplication")

-- Finds or lazily creates a spatial output target on the victim's RootPart.
-- Same pattern as the weapon's Handle.AudioEmitter.
local function ensureAudioEmitter(part: BasePart): AudioEmitter
	local existing = part:FindFirstChildOfClass("AudioEmitter")
	if existing then
		return existing
	end
	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "HitAudioEmitter"
	emitter.Parent = part
	return emitter
end

hitRemote.OnClientEvent:Connect(function(weapon: Tool, targetPart: BasePart)
	if not (weapon and weapon:IsA("Tool")) or not (targetPart and targetPart:IsA("BasePart")) then
		return
	end
	local sounds = weapon:FindFirstChild("Sounds")
	local hit = sounds and sounds:FindFirstChild("Hit")
	if not hit then
		return
	end
	local target = ensureAudioEmitter(targetPart)

	-- Hit can be either a single AudioPlayer or a folder of variants (Hit1, Hit2, ...).
	if hit:IsA("AudioPlayer") then
		playSoundFromSource(hit, target)
	elseif hit:IsA("Folder") and #hit:GetChildren() > 0 then
		playRandomSoundFromSource(hit, target)
	end
end)

log:info("Initialized")
