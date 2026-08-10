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
local BlockTapConfig = require(ReplicatedStorage.Shared.BlockShoot.BlockTapConfig)

local BlockShootConstants = {}

-- The client raycasts from the *camera*, which in this game's default
-- third-person rig sits behind the character. The server can only
-- measure character→block, so the camera-to-character gap has to be
-- added back or a legitimate long tap would be rejected. 100 studs
-- covers any sane zoom-out. It does not scale with reach — it is a
-- property of the camera rig, not of how far you can tap.
local CAMERA_ZOOM_ALLOWANCE_STUDS = 100

-- NOTE on what this bound is worth now (2026-08-10). At the old 200-stud
-- reach this capped a client at 300 studs, which was a real anti-grief
-- bound: an exploiter could clear blocks near themselves but not across
-- the map. With reach at 1400 it is 1500, comfortably more than the
-- ~353-stud arena diagonal, so it no longer bounds griefing at all — it
-- is a sanity check against absurd coordinates, and nothing more. If
-- cross-map block denial ever needs stopping in PvP, it needs a
-- different mechanism (per-block claim, or a much tighter reach).

BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS =
	BlockShoot.MAX_RAYCAST_DISTANCE + CAMERA_ZOOM_ALLOWANCE_STUDS

-- Sustained ceiling is exactly the client's tap cooldown, so a player
-- popping as fast as the input allows is never throttled. The burst
-- allowance absorbs network jitter bunching consecutive pops into one
-- frame — see RateLimiter for why a flat interval is wrong.
BlockShootConstants.CONSUME_BURST_CAPACITY = 3
BlockShootConstants.CONSUME_REFILL_PER_SEC = 1 / BlockTapConfig.COOLDOWN

-- A rejected client is usually a broken client or an exploiter looping
-- the remote; either way the log must not become the DoS. Each
-- (player, reason) pair gets one warning immediately and then at most
-- one per this window, so a single probe is never silent and a loop
-- can't bury other players' warnings.
BlockShootConstants.REJECTION_LOG_THROTTLE_SEC = 10

return BlockShootConstants
