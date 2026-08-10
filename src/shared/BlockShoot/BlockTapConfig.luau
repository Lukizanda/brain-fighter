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

----------------------------------------------------------------------
-- Hover affordance
----------------------------------------------------------------------
-- Client-local presentation only. Nothing here is read by the server and
-- nothing here gates input — tryPop's own checks decide what happens on
-- click. If these two ever disagree the highlight is the one that is
-- wrong, so it derives its range from the same MAX_RAYCAST_DISTANCE the
-- tap does rather than carrying its own number.

-- The hover probe deliberately reaches further than a tap can.
--
-- If it stopped at reach, a block beyond it would return no hit and the
-- highlight would simply not appear — indistinguishable from pointing at
-- the sky. Probing past reach lets the affordance say the useful thing
-- instead: *that* is a block, and it is too far. Which is the whole
-- reason the affordance exists, given reach is now shorter than the
-- arena.
BlockTapConfig.HOVER_PROBE_MULTIPLIER = 4

-- Ready.
--
-- The fill takes the block's own tint so the highlight reads as "this
-- letter, this colour", but the **outline must not** — that was the
-- first attempt and it is invisible. A block's outline drawn in the
-- block's own colour has zero contrast against the thing it is
-- outlining, and it fails on all four tints at once because every tint
-- is by definition the colour of the block wearing it. Only a
-- screenshot catches this; every property assertion passes.
--
-- White is the one colour that separates from red, green, blue *and*
-- gold, and from the dark arena floor behind them.
BlockTapConfig.HOVER_READY_OUTLINE_COLOR = Color3.fromHex("#ffffff")
BlockTapConfig.HOVER_READY_FILL_TRANSPARENCY = 0.75
BlockTapConfig.HOVER_READY_OUTLINE_TRANSPARENCY = 0

-- Denied: out of reach, or the mind is full. Deliberately grey rather
-- than red — red reads as danger, and this is neither a threat nor an
-- error, just "not that one, not yet". Dimmer than ready in both
-- channels so the two are separable at a glance without reading colour,
-- which matters for the colour-blind case in a game already keying
-- three reservoirs to red/green/blue.
BlockTapConfig.HOVER_DENIED_COLOR = Color3.fromHex("#9ca3af")
BlockTapConfig.HOVER_DENIED_FILL_TRANSPARENCY = 0.92
BlockTapConfig.HOVER_DENIED_OUTLINE_TRANSPARENCY = 0.45

return BlockTapConfig
