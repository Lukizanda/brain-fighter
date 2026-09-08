local GameModeConstants = {
	----------------------------------------------------------------------
	-- Round Management
	----------------------------------------------------------------------
	MIN_PLAYERS = 1, -- minimum players to start (1 for solo testing, raise for production)
	COUNTDOWN_DURATION = 10, -- pre-round countdown seconds
	INTERMISSION_DURATION = 10, -- seconds between rounds

	----------------------------------------------------------------------
	-- Respawn
	----------------------------------------------------------------------
	-- Player auto-respawn delay (Step 5 tuning: was 5; 3-4s is arena-feel, 5
	-- felt Halo-slow on this map). Every mode config's `respawnTime` reads
	-- this, and RoundManager broadcasts that value in GameStateChanged —
	-- DeathScreenGui reads it from there rather than this constant directly,
	-- so client and server agree on one number. See HealthConstants.RESPAWN_TIME
	-- for the unrelated Damageable/manual-respawn-gate constant.
	RESPAWN_TIME = 4,
	SPAWN_PROTECTION_DURATION = 3, -- invincibility after spawn

	----------------------------------------------------------------------
	-- Round States
	----------------------------------------------------------------------
	RoundState = {
		WaitingForPlayers = "WaitingForPlayers",
		Countdown = "Countdown",
		Active = "Active",
		PostRound = "PostRound",
	},

}

return GameModeConstants
