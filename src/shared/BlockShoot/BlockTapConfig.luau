--!strict

----------------------------------------------------------------------
-- BlockTapConfig
----------------------------------------------------------------------
-- Tuning for the tap-to-pop input loop (Phase 5.7). Replaces
-- LetterBlasterConfig, which tuned the same numbers back when the input
-- lived behind the Spelling Staff Tool.
--
-- Read on both VMs: the client gates its own input on COOLDOWN, and
-- BlockShootConstants derives the server's rate-limit refill from it so
-- a player tapping as fast as the client allows is never throttled.
-- They must not drift, which is why this is one constant and not two.
--
-- See wiki/design/tap-to-pop.md.
----------------------------------------------------------------------

local BlockTapConfig = {}

-- Minimum time between pops. Unchanged from the staff's fire cooldown —
-- the input moved, the pacing did not.
BlockTapConfig.COOLDOWN = 0.25

return BlockTapConfig
