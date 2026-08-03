--!strict

----------------------------------------------------------------------
-- SpellCastConstants
----------------------------------------------------------------------
-- Server-side trust thresholds for the SpellCastServer remote
-- (Phase 5.4).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlasterConfig = require(ReplicatedStorage.Shared.LetterBlaster.LetterBlasterConfig)

local SpellCastConstants = {}

-- Mirrors AUTO_TARGET_RANGE_STUDS in client/UI/SpellMenuGui — the range
-- the client's auto-targeter will lock within. It has to be duplicated
-- because a server script cannot require a LocalScript; the two must be
-- changed together. (Hoisting it into SpellRegistry so both sides read
-- one number is the right fix and is filed as follow-up — see
-- wiki/systems/SpellCastService.md § Trust model.)
local CLIENT_AUTO_TARGET_RANGE_STUDS = 150

-- Both caster and target keep moving during the client→server hop, so
-- a target locked at exactly the client's limit can be measurably
-- further away by the time the server reads it. 50 studs covers a
-- round trip at full sprint without meaningfully widening the bound.
local TARGET_DRIFT_ALLOWANCE_STUDS = 50

SpellCastConstants.MAX_TARGET_DISTANCE_STUDS =
	CLIENT_AUTO_TARGET_RANGE_STUDS + TARGET_DRIFT_ALLOWANCE_STUDS

-- Flood guard, NOT an affordability check — the server cannot price a
-- cast today (see the service header). The floor is derived from what
-- the economy physically permits: energy only enters a reservoir by
-- memorizing a word, every letter in that word costs one LetterBlaster
-- shot, and the weapon gates shots at COOLDOWN. One block per cast is
-- the most generous possible reading (a one-letter dictionary word
-- carrying a high-value tile), so this can never reject real play while
-- still stopping a remote loop dead.
local MIN_BLOCKS_PER_CAST = 1

SpellCastConstants.CAST_BURST_CAPACITY = 3
SpellCastConstants.CAST_REFILL_PER_SEC = 1 / (MIN_BLOCKS_PER_CAST * LetterBlasterConfig.COOLDOWN)

-- Each (player, reason) pair gets one warning immediately and then at
-- most one per this window: a single probe is never silent, a loop
-- can't flood the output.
SpellCastConstants.REJECTION_LOG_THROTTLE_SEC = 10

return SpellCastConstants
