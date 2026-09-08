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

-- Enforcing. While false the ledger computed every verdict and logged
-- the failures but refused nothing, so a bug there could not cost a real
-- player a cast they earned.
--
-- The flip criterion was a measurement, not a judgement call: zero
-- rejections against honest play. Measured 2026-09-08 (chunk 6) once the
-- round-reset hook below it existed — before that the ceiling carried
-- across rounds and the check could never have refused anything, so the
-- reading would have been worthless. Four memorized words and three
-- casts driven through the real client modules and the real remotes
-- produced zero "would reject" lines, and three round starts each logged
-- their reset. See wiki/design/refactor-plan-2026-09.md § Chunk 6 for
-- the sample's limits — one player, no discards, no wildcards.
--
-- Back to false is the correct first response to a player reporting a
-- cast they earned being refused; the log line says which check fired.
EconomyConstants.ENFORCE = true

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

-- The hard ceiling on a single memorize payload, as opposed to the
-- reporting threshold above. The client's buffer physically cannot hold
-- more than its cap, so a report naming more tiles than that did not
-- come from a buffer — it is the one memorize shape that is impossible
-- rather than merely suspicious, which is why it is refused in shadow
-- mode too. Reads the buffer's own cap so the two cannot drift.
EconomyConstants.MEMORIZE_TILE_CAP = WordBuffer.DEFAULT_CAP

-- Seconds between repeats of the same player+reason rejection log, so a
-- looping client cannot bury everyone else's output. Matches the
-- throttle both hardened remotes already use (BlockShootConstants,
-- SpellCastConstants) — this was drifted to 5 despite the comment
-- claiming the match; restored to 10.
EconomyConstants.REJECTION_LOG_THROTTLE_SEC = 10

-- Memorize report flood guard. Every letter in a memorized word costs
-- one block, and blocks are already rate-limited, so honest memorizes
-- cannot arrive faster than the shortest word a player can collect.
-- Both figures are far above that: this exists so a looping client
-- cannot make the ledger do dictionary work in a tight loop, not to
-- price anything.
EconomyConstants.REPORT_BURST_CAPACITY = 5
EconomyConstants.REPORT_REFILL_PER_SEC = 4

return EconomyConstants
