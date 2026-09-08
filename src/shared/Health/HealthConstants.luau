local HealthConstants = {
	DEFAULT_MAX_HEALTH = 100,
	-- Default respawn timer for a Damageable **non-player rig** — the
	-- `respawnTime` attribute HealthService stamps on a tagged Model and
	-- DeathHandler counts down. Players never read this: their delay is the
	-- mode's `respawnTime` (GameModeConstants.RESPAWN_TIME), owned by
	-- GameModeService and broadcast to DeathScreenGui in GameStateChanged.
	-- Named NPC_ so the two can no longer be confused (chunk 5).
	NPC_RESPAWN_TIME = 5,

	HEADSHOT_MULTIPLIER = 2.0,
	LIMB_MULTIPLIER = 0.75,

	-- Lethal through any armor or shield in one request. For callers that
	-- mean "dead now" (the DeathZone) but still go through the one damage
	-- path rather than writing Health — so a big number, not a special case
	-- in applyDamage.
	INSTANT_KILL_DAMAGE = 1e9,

	ARMOR_ATTRIBUTE = "_armor",
	SHIELD_ATTRIBUTE = "_shield",

	HEAD_PARTS = { "Head" },
	TORSO_PARTS = { "UpperTorso", "LowerTorso" },

	DAMAGEABLE_TAG = "Damageable",
	MAX_HEALTH_ATTRIBUTE = "maxHealth",
	RESPAWN_TIME_ATTRIBUTE = "respawnTime",
}

return HealthConstants
