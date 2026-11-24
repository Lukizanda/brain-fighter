--!strict

----------------------------------------------------------------------
-- SporeConstants
----------------------------------------------------------------------
-- The published state of a spore letter: an ordinary letter block the boss
-- lobbed that bursts when its fuse runs out (wiki/design/ai-playtest.md,
-- the spore decision). The pool (BlockSpawner.spawnSpore) writes the mark
-- and the fuse time on the block; BlockShoot reads the mark before it
-- destroys a popped block and passes it on; the client script
-- SporeLetterVisuals reads both to draw the fuse. What a spore DOES (the
-- burst, the damage to the boss when popped) belongs to the Boss system and
-- its numbers are in BossConfig, not here.
--
-- Shared so the writer and the readers agree on the names without any of
-- them requiring the other.
----------------------------------------------------------------------

local SporeConstants = {
	-- Boolean on the block model: this block is a spore.
	ATTRIBUTE = "Block.Spore",
	-- Number on the block model: when the fuse runs out, in
	-- `workspace:GetServerTimeNow()` seconds (never os.clock(), which differs
	-- per VM). The client counts down to it; the boss bursts the spore then.
	EXPIRES_ATTRIBUTE = "SporeExpiresAt",
	-- Numbers on the block model, published with the fuse time so the client can
	-- draw the burst radius for the whole fuse: the fuse's total length (seconds,
	-- how full the fill is), the burst radius (studs) and the ground height under
	-- the block (world Y). The boss already knows all three; the client would
	-- otherwise have to guess the ground with a raycast. Optional: a spore
	-- spawned without them simply shows no ring.
	FUSE_SEC_ATTRIBUTE = "SporeFuseSec",
	BURST_RADIUS_ATTRIBUTE = "SporeBurstRadius",
	GROUND_Y_ATTRIBUTE = "SporeGroundY",

	-- The pool removes a spore this long after its fuse as a safety net, so a
	-- spore whose boss is gone cannot float forever. The boss normally bursts
	-- and removes it first.
	REMOVAL_GRACE_SEC = 2,

	-- ============================================================
	-- Fuse look (client, SporeLetterVisuals). Greybox.
	-- ============================================================
	HIGHLIGHT_NAME = "SporeFuse",
	-- A pulsing red-orange fill and a hot outline, drawn through walls so a
	-- spore lands as a warning even behind cover.
	FILL_COLOR = Color3.fromRGB(255, 70, 20),
	OUTLINE_COLOR = Color3.fromRGB(255, 220, 80),
	-- Fill transparency swings between these as the pulse goes round.
	FILL_TRANSPARENCY_MIN = 0.25,
	FILL_TRANSPARENCY_MAX = 0.85,
	OUTLINE_TRANSPARENCY = 0,
	-- Pulses a second while the fuse is long, and in its last FAST_WINDOW_SEC.
	-- The burst-radius ring on the ground under a live spore: outline plus a
	-- fill (in FILL_COLOR) that grows to the full radius as the fuse runs out.
	-- Up to three overlap, so the fill is light and the outline does the work.
	RING_STROKE_STUDS = 0.6,
	RING_FILL_TRANSPARENCY = 0.7,
	RING_OUTLINE_TRANSPARENCY = 0.05,
	PULSE_BASE_HZ = 1.5,
	PULSE_FAST_HZ = 6,
	FAST_WINDOW_SEC = 2,
}

return SporeConstants
