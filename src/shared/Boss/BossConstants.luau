--!strict

----------------------------------------------------------------------
-- BossConstants
----------------------------------------------------------------------
-- Tunable values for boss *behaviour*, as opposed to boss *identity*.
--
-- The split against [[BossConfig]] is deliberate: BossConfig is a
-- registry of boss types, and every number in it (maxHealth, attackRange,
-- a skill's projectile count) describes one particular boss and is meant
-- to differ between entries. The numbers here hold for every boss and are
-- read by the shared machinery — the spawner, the state table — which has
-- no type spec to consult at the point it needs them.
----------------------------------------------------------------------

local BossConstants = {
	-- ============================================================
	-- Spawning
	-- ============================================================
	-- How far above the BossPoint's top surface a boss is placed. It is
	-- dropped rather than seated so the physics solver settles the rig on
	-- the floor itself; scaled rigs have hip heights that do not match
	-- their authored geometry and a seated spawn leaves them clipped in.
	SPAWN_Y_OFFSET = 12, -- studs

	-- Where the HP billboard sits. Two values because the anchor differs:
	-- a rig with a Head part gets the label just above it, and a rig
	-- without one (the custom BossBrain) is anchored at the root part and
	-- needs the extra height to clear the body.
	LABEL_OFFSET_HEAD = Vector3.new(0, 5, 0),
	LABEL_OFFSET_ROOT = Vector3.new(0, 9, 0),

	-- ============================================================
	-- Entrance (the beat between the first arrival and the boss appearing)
	-- ============================================================
	-- While the entrance runs, BossService tags the BossPoint with this and
	-- publishes the instant the boss appears on it as an attribute
	-- (`workspace:GetServerTimeNow()` time, never os.clock: the clock has to
	-- mean the same thing on the server and on every client). The client
	-- draws the countdown from those two; the tag coming off ends the tell.
	ENTRANCE_TAG = "BossEntranceTell",
	ENTRANCE_APPEAR_AT_ATTRIBUTE = "BossAppearAt",

	-- VfxConfig.EFFECTS ids played at the BossPoint through VfxBroadcast:
	-- a stone rumble as the countdown starts, a heavy thud as the boss lands.
	-- Reused stand-ins, not final art.
	ENTRANCE_START_VFX = "wall_rise_rumble",
	ENTRANCE_APPEAR_VFX = "aoe_boss_groundslam",

	-- The client countdown billboard over the BossPoint.
	ENTRANCE_LABEL_HEIGHT_STUDS = 40,
	ENTRANCE_LABEL_SIZE = UDim2.fromOffset(320, 90),
	ENTRANCE_LABEL_TEXT_COLOR = Color3.fromRGB(255, 90, 60),
	ENTRANCE_LABEL_HEADER = "BOSS INCOMING",
	-- How often the label redraws; the number only changes once a second.
	ENTRANCE_LABEL_REFRESH_SEC = 0.1,

	-- ============================================================
	-- Hunger (the boss eating letter blocks; numbers live in BossConfig)
	-- ============================================================
	-- Cause string on the heal request, for the Health log.
	HUNGER_HEAL_CAUSE = "BossHunger",
	-- VfxConfig.EFFECTS id played on the boss when a bite actually healed it.
	-- Reused stand-in (it carries its own sound); not final art.
	HUNGER_HEAL_VFX = "impact_heal",

	-- ============================================================
	-- Spore lob (Boss/Scripts/BossSpores; numbers live in BossConfig)
	-- ============================================================
	-- The attack name the boss's selection carries for a lob. It is not a
	-- skill in BossTypeSpec.skills: a lob delivers blocks, not a SkillSpec.
	-- The windup borrows the FireballVolley's telegraph and animation, so a
	-- player cannot tell the two apart until the throw.
	VOLLEY_ATTACK = "FireballVolley",
	SPORE_LOB_ATTACK = "SporeLob",
	-- Cause strings on the damage requests, for the Health log and kill feed.
	SPORE_BURST_CAUSE = "SporeBurst",
	SPORE_POP_CAUSE = "SporePop",
	-- VfxConfig.EFFECTS ids played through VfxBroadcast. Reused stand-ins, not
	-- final art: the throw (a sound-only launch cue at the boss), the landing
	-- (a thud with dust at the spore) and the burst (the big fire eruption).
	SPORE_LOB_VFX = "projectile_boss_fireball",
	SPORE_LAND_VFX = "impact_wall",
	SPORE_BURST_VFX = "impact_damage_t3",
	-- The ring drawn on the ground where a spore will land (for the flight)
	-- and where it burst (briefly): the burst radius, in this colour.
	SPORE_RING_COLOR = Color3.fromRGB(255, 70, 20),
	SPORE_BURST_RING_SEC = 0.4,
	-- Finding the ground under a landing point: probe down from this far above
	-- the target's root for this far. Without a hit (no floor, a test arena) the
	-- ground is taken to be this far below the target's root, a character's
	-- root-to-feet height.
	SPORE_GROUND_PROBE_UP_STUDS = 20,
	SPORE_GROUND_PROBE_DOWN_STUDS = 80,
	SPORE_ROOT_TO_FEET_STUDS = 3,
	-- The throw leaves the boss this far above its root.
	SPORE_LOB_ORIGIN_HEIGHT_STUDS = 6,

	-- ============================================================
	-- Word ward (Boss/Scripts/BossWard; numbers live in BossConfig)
	-- ============================================================
	-- VfxConfig.EFFECTS ids played at the boss through VfxBroadcast as the
	-- ward goes up and as it breaks. Reused stand-ins, not final art.
	WARD_UP_VFX = "wall_rise_rumble",
	WARD_DOWN_VFX = "impact_wall",
	-- While the ward holds, a ring at the orbit radius pulses round the boss
	-- this often, each lasting this long, in this colour.
	WARD_PULSE_EVERY_SEC = 1.5,
	WARD_RING_SEC = 0.6,
	WARD_RING_COLOR = Color3.fromRGB(120, 200, 255),
	-- The ward goes up when the boss's health is within this of the line
	-- (Humanoid.Health is a 32-bit float, so "exactly on it" is not safe).
	WARD_HEALTH_TOLERANCE = 0.01,

	-- ============================================================
	-- Attacks
	-- ============================================================
	-- Height above the root part that an attack is delivered from, so
	-- projectiles leave the body rather than the floor it stands on.
	ATTACK_ORIGIN_HEIGHT = 2, -- studs

	-- Fallback gap between attacks, used only when the active phase spec
	-- carries no attackCooldown of its own. Every shipped phase does, so
	-- this is the "a new phase forgot one" guard rather than a tuning dial.
	DEFAULT_ATTACK_COOLDOWN_SEC = 4,

	-- ============================================================
	-- Published intent (read by the client puppet, wiki/design/boss-movement.md)
	-- ============================================================
	-- The boss Model's current phase index, set at spawn and on every
	-- phase change.
	PHASE_ATTRIBUTE = "Phase",
}

return BossConstants
