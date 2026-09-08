local HealthConstants = {
	DEFAULT_MAX_HEALTH = 100,
	-- Generic Damageable respawn timer (DeathHandler, non-player rigs) and
	-- the RequestRespawn server-side gate fallback (HealthService). NOT the
	-- player active-round auto-respawn delay — that's
	-- GameModeConstants.RESPAWN_TIME, which DeathScreenGui now reads via
	-- the GameState broadcast instead of guessing between the two.
	RESPAWN_TIME = 5,

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
