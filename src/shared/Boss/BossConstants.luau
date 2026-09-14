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
	-- Attacks
	-- ============================================================
	-- Height above the root part that an attack is delivered from, so
	-- projectiles leave the body rather than the floor it stands on.
	ATTACK_ORIGIN_HEIGHT = 2, -- studs

	-- Fallback gap between attacks, used only when the active phase spec
	-- carries no attackCooldown of its own. Every shipped phase does, so
	-- this is the "a new phase forgot one" guard rather than a tuning dial.
	DEFAULT_ATTACK_COOLDOWN_SEC = 4,
}

return BossConstants
