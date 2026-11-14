--!strict

----------------------------------------------------------------------
-- BreakableWallConstants
----------------------------------------------------------------------
-- The vocabulary and tuning of the BreakableWalls system. Shared rather
-- than server-only because the client reads the tag, the attribute names
-- and the state names to draw a wall; only the server reads the damage and
-- timing numbers. See wiki/design/boss-arena.md § Contract between the
-- three pieces — the names here ARE that contract.
----------------------------------------------------------------------

local BreakableWallConstants = {}

-- A wall is one anchored BasePart carrying this tag.
BreakableWallConstants.TAG = "BreakableWall"

-- An invisible, non-colliding BasePart that covers the ground beyond a gate.
-- A regenerating wall whose `GateId` matches the zone's (same arena) does not
-- re-seal while a living player's character is inside it.
BreakableWallConstants.ZONE_TAG = "GateHoldZone"

-- Attributes the level author sets on the part (all optional).
BreakableWallConstants.Authored = {
	MaxHealth = "MaxHealth", -- number; absent = DEFAULT_MAX_HEALTH
	RegenSec  = "RegenSec",  -- number; absent or 0 = gone for the round
	-- string; names the gate. Also set on a GateHoldZone part to pair it with
	-- the walls of the same id in the same arena, and read by the word-kit
	-- watcher (a kit's `KitGate` refers to it). Absent or "" = no gate.
	GateId    = "GateId",
	-- The arena id attribute is `Arena.ID_ATTRIBUTE` ("ArenaId"), read with
	-- `Arena.idOf` so absence means the Default arena, as everywhere else.
}

-- Attributes the server publishes on the part; the client reads them.
BreakableWallConstants.Published = {
	Health = "WallHealth",
	State  = "WallState",
}

BreakableWallConstants.State = {
	Intact   = "intact",
	Cracked  = "cracked",
	Critical = "critical",
	Broken   = "broken",
}

----------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------
-- Health is counted in fireball hits: one boss fireball is one unit, so
-- every other number below reads as "how many fireballs is this".
BreakableWallConstants.FIREBALL_WALL_DAMAGE = 1

-- A Ground Slam is worth ten fireballs: three slams take a default wall
-- down, and a slam that lands beside cover is a real event rather than a
-- scratch. Applies to every wall whose nearest point is inside the radius.
BreakableWallConstants.SLAM_WALL_DAMAGE = 10

-- Brain's FireballVolley is 20 shots (BossConfig, `count = 20`). A wall
-- that cannot outlast one volley is no cover at all, so the default is a
-- volley and a half: it survives one full volley even if every shot lands
-- on it, and the second volley finishes it. The `breakable_wall_*` suite
-- asserts this against the live BossConfig so a retune of the volley
-- cannot silently turn cover into paper.
BreakableWallConstants.DEFAULT_MAX_HEALTH_IN_VOLLEYS = 1.5
BreakableWallConstants.VOLLEY_SHOTS = 20 -- mirrors BossConfig Brain FireballVolley.count; checked by the suite
BreakableWallConstants.DEFAULT_MAX_HEALTH =
	BreakableWallConstants.VOLLEY_SHOTS * BreakableWallConstants.DEFAULT_MAX_HEALTH_IN_VOLLEYS
		* BreakableWallConstants.FIREBALL_WALL_DAMAGE

----------------------------------------------------------------------
-- State thresholds
----------------------------------------------------------------------
-- Fractions of max health at or below which a wall is in the named stage.
-- Thirds, so a default 30-health wall is cracked after 10 hits and critical
-- after 20, with the last 10 to go.
BreakableWallConstants.CRACKED_AT_FRACTION  = 2 / 3
BreakableWallConstants.CRITICAL_AT_FRACTION = 1 / 3

----------------------------------------------------------------------
-- Regeneration
----------------------------------------------------------------------
-- A wall due to re-seal waits while any character overlaps it, or a living
-- player is inside a hold zone paired with it, and asks again on this interval. Short enough that a player stepping clear sees
-- the wall close almost at once; long enough that the overlap query is not
-- a per-frame cost.
BreakableWallConstants.REGEN_RETRY_SEC = 0.5

----------------------------------------------------------------------
-- Client look (greybox)
----------------------------------------------------------------------
-- Colour the part is pushed toward at each damaged stage, as a fraction of
-- the way from its authored colour. The authored colour is whatever the
-- level designer gave the part; the client remembers it and restores it.
BreakableWallConstants.CRACKED_TINT_FRACTION  = 0.30
BreakableWallConstants.CRITICAL_TINT_FRACTION = 0.60
BreakableWallConstants.DAMAGE_TINT_COLOR = Color3.fromRGB(46, 38, 32)

-- Critical walls also go slightly see-through so the last hit reads as
-- "about to give", without letting a player see through cover early.
BreakableWallConstants.CRITICAL_TRANSPARENCY = 0.15

-- How the regen is told. After a wall breaks the client waits out
-- RegenSec minus this lead, then shows a faint ghost of the wall pulsing
-- until it re-seals. Estimated from the client's own clock: the server
-- publishes no regen timestamp (that would widen the design contract).
BreakableWallConstants.REGEN_TELEGRAPH_LEAD_SEC = 2
BreakableWallConstants.GHOST_TRANSPARENCY = 0.82
BreakableWallConstants.GHOST_PULSE_SEC = 0.5
BreakableWallConstants.GHOST_PULSE_DEPTH = 0.12 -- transparency swing either side of GHOST_TRANSPARENCY
BreakableWallConstants.RESEAL_FADE_SEC = 0.35

-- VfxConfig.EFFECTS keys the client plays at the wall's centre.
BreakableWallConstants.Vfx = {
	Crack  = "wall_crack", -- one fracture opening (sound only; reused from the Stone Wall)
	Break  = "wall_break", -- the wall giving way
	Reseal = "wall_rise_dust", -- dust as the wall closes (reused from the Stone Wall)
}

return BreakableWallConstants
