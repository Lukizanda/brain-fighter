--!strict

----------------------------------------------------------------------
-- EconomyConstants
----------------------------------------------------------------------
-- Tuning for the server-side energy ledger (Phase 5.4, validated
-- memorize). See wiki/systems/SpellCastService.md § Validated memorize.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)

local EconomyConstants = {}

-- Shadow mode. While false the ledger computes every verdict and logs
-- the failures but refuses nothing, so a bug here cannot cost a real
-- player a cast they earned.
--
-- Flip to true only once a playtest has shown zero rejections against
-- honest play — the point of shipping this dark first is to turn "is
-- the coverage check generous enough?" into a measurement rather than
-- the judgement call that left the cast rate limit standing in for a
-- price check in the first place.
EconomyConstants.ENFORCE = false

-- A player's held letters are the ones consumed since their last
-- memorize, so in honest play the count tracks the word buffer and
-- cannot exceed its capacity by much — discards are the only way to
-- legitimately consume more blocks than the buffer holds.
--
-- Deliberately a reporting threshold and NOT a cap. Refusing consumes
-- past a limit would reject a real player who discards aggressively,
-- and rejecting real play is the one thing this design may not do.
-- Log the outliers, tune against what they say.
EconomyConstants.HELD_BANKING_LOG_THRESHOLD = WordBuffer.DEFAULT_CAP * 2

-- Seconds between repeats of the same player+reason rejection log, so a
-- looping client cannot bury everyone else's output. Matches the
-- throttle both hardened remotes already use.
EconomyConstants.REJECTION_LOG_THROTTLE_SEC = 5

-- Memorize report flood guard. Every letter in a memorized word costs
-- one block, and blocks are already rate-limited, so honest memorizes
-- cannot arrive faster than the shortest word a player can collect.
-- Both figures are far above that: this exists so a looping client
-- cannot make the ledger do dictionary work in a tight loop, not to
-- price anything.
EconomyConstants.REPORT_BURST_CAPACITY = 5
EconomyConstants.REPORT_REFILL_PER_SEC = 4

return EconomyConstants
