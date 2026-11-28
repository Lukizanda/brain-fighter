--!strict

----------------------------------------------------------------------
-- LoopSound — a looping sound that lasts as long as a status does.
----------------------------------------------------------------------
-- spawnEffect plays one-shots: it starts a Sound and destroys it when it
-- ends. A burning rig or a raised shield needs the other shape, a sound
-- that runs until someone says stop. The status visuals (InfernoVfx,
-- ShieldVfx) own when; this owns how, so the fades cannot drift apart.
--
-- CLIENT ONLY, like the visuals that call it: a server-side Sound would
-- replicate and play on top of each client's own.
----------------------------------------------------------------------

local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- A loop that starts or stops at full level clicks. Fading in is short so
-- the sound still arrives with the event that started it.
local FADE_IN_SEC = 0.15

local LoopSound = {}

-- Start `soundId` looping on `anchor`, fading up to `volume`. The file
-- must be built to loop (tools/sfx marks those `"loop": true`).
function LoopSound.start(anchor: BasePart | Attachment, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name    = "VfxLoopSound"
	sound.SoundId = soundId
	sound.Looped  = true
	sound.Volume  = 0
	sound.Parent  = anchor
	sound:Play()

	TweenService:Create(sound, TweenInfo.new(FADE_IN_SEC), { Volume = volume }):Play()
	return sound
end

-- Fade the loop out over `fadeSec` and destroy it. Safe on a sound whose
-- anchor has already been destroyed.
function LoopSound.stop(sound: Sound?, fadeSec: number)
	if not sound or not sound.Parent then return end
	TweenService:Create(sound, TweenInfo.new(fadeSec), { Volume = 0 }):Play()
	Debris:AddItem(sound, fadeSec)
end

return LoopSound
