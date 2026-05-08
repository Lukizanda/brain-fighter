local GameModeConstants = {
	----------------------------------------------------------------------
	-- Round Management
	----------------------------------------------------------------------
	MIN_PLAYERS = 1, -- minimum players to start (1 for solo testing, raise for production)
	COUNTDOWN_DURATION = 10, -- pre-round countdown seconds
	ROUND_TIME_LIMIT = 300, -- 5 minutes per round
	SCORE_LIMIT = 15, -- kill target to win (Step 5 tuning: was 25; tedious in 1v1/2v2 — raise back for 5v5 prod)
	INTERMISSION_DURATION = 10, -- seconds between rounds

	----------------------------------------------------------------------
	-- Respawn
	----------------------------------------------------------------------
	RESPAWN_TIME = 4, -- player respawn delay during active rounds (Step 5 tuning: was 5; 3-4s is arena-feel, 5 felt Halo-slow on this map)
	SPAWN_PROTECTION_DURATION = 3, -- invincibility after spawn
	SPAWN_MIN_ENEMY_DISTANCE = 50, -- minimum studs from nearest enemy when selecting spawn

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
