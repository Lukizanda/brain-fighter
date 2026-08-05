--!strict

local LetterBlasterConfig = {}

LetterBlasterConfig.COOLDOWN          = 0.25   -- seconds between shots
LetterBlasterConfig.FIRE_SOUND_NAME   = "FireSound"
LetterBlasterConfig.HIT_SOUND_NAME    = "HitSound"
LetterBlasterConfig.FIZZLE_SOUND_NAME = "FizzleSound"

-- Where the beam leaves the staff. Both VMs resolve this: the client to
-- draw its own shot immediately, the server to tell everyone else where
-- the shot came from. See BlockShoot.muzzlePosition.
LetterBlasterConfig.HANDLE_NAME            = "Handle"
LetterBlasterConfig.MUZZLE_ATTACHMENT_NAME = "Muzzle"

return LetterBlasterConfig
