--!strict

----------------------------------------------------------------------
-- BlockShootConstants
----------------------------------------------------------------------
-- Server-side trust thresholds for the ConsumeBlock remote (Phase 5.4).
-- Every value here is derived from a client-side number rather than
-- picked, so the two stay in step when tuning moves.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local LetterBlasterConfig = require(ReplicatedStorage.Shared.LetterBlaster.LetterBlasterConfig)

local BlockShootConstants = {}

-- The client raycasts from the *camera*, which in this game's default
-- third-person rig sits behind the character. The server can only
-- measure character→block, so the camera-to-character gap has to be
-- added back or a legitimate long shot would be rejected. 100 studs
-- covers any sane zoom-out; the reference arena is 40×40, so this is
-- pure headroom rather than a real gameplay limit.
local CAMERA_ZOOM_ALLOWANCE_STUDS = 100

BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS =
	BlockShoot.MAX_RAYCAST_DISTANCE + CAMERA_ZOOM_ALLOWANCE_STUDS

-- Sustained ceiling is exactly the LetterBlaster's fire cooldown, so a
-- player firing as fast as the weapon allows is never throttled. The
-- burst allowance absorbs network jitter bunching consecutive fires
-- into one frame — see RateLimiter for why a flat interval is wrong.
BlockShootConstants.CONSUME_BURST_CAPACITY = 3
BlockShootConstants.CONSUME_REFILL_PER_SEC = 1 / LetterBlasterConfig.COOLDOWN

-- A rejected client is usually a broken client or an exploiter looping
-- the remote; either way the log must not become the DoS. Each
-- (player, reason) pair gets one warning immediately and then at most
-- one per this window, so a single probe is never silent and a loop
-- can't bury other players' warnings.
BlockShootConstants.REJECTION_LOG_THROTTLE_SEC = 10

return BlockShootConstants
