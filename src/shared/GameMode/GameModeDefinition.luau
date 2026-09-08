----------------------------------------------------------------------
-- GameModeDefinition
----------------------------------------------------------------------
-- Interface that all game modes must implement.
-- The RoundManager and GameModeService call these methods to drive
-- mode-specific behavior while keeping the core loop generic.
--
-- To create a new game mode:
--   1. Create a new module in src/shared/GameMode/Modes/
--   2. Return a table that satisfies this interface
--   3. Register it in GameModeService
----------------------------------------------------------------------

export type GameModeDefinition = {
	-- Display name for UI
	name: string,

	-- Returns the mode-specific configuration
	getConfig: () -> {
		scoreLimit: number,
		timeLimit: number,
		respawnTime: number,
		teamBased: boolean,
		-- CollectionService tag identifying this mode's spawn points.
		-- Team modes will typically return a per-team mapping via
		-- getTeamConfig instead; this is the FFA / single-pool default.
		spawnTag: string,

		-- Whether GameModeService should call `start()` on this mode's
		-- session. False for LobbyMode: the hub is a real session with a
		-- roster and spawn pads, it just has no round to run. Expressed
		-- here rather than as an arena-id check in GameModeService because
		-- "does this run rounds" is a property of the mode.
		--
		-- Optional; absent means true, so existing modes are unaffected.
		runsRounds: boolean?,

		-- Whether players in this mode may damage each other. HealthService
		-- asks through the *victim's* session, so a duellist is damageable
		-- by their opponent while a lobby player on the same server is not.
		-- This replaced the global PvP flag in GameConfig in the
		-- 2026-09 refactor (chunk 4). Optional; absent means false.
		allowsPvP: boolean?,
	},

	-- Called when a player joins the game. Modes apply team assignment
	-- or Neutral state here (e.g. FFA sets player.Neutral = true;
	-- TDM balance-assigns to a team).
	onPlayerJoin: (player: Player) -> (),

	-- Called when a player kills another player.
	-- Returns the score change for the killer (usually 1).
	-- Game modes like Gun Game can use this to switch weapons.
	onPlayerKill: (killer: Player, victim: Player, weaponName: string) -> number,

	-- Called each tick to check if the round should end.
	-- Receives the current scores table { [Player]: PlayerScore }.
	-- Returns (shouldEnd, winnerUserId, winnerTeamName). Modes set
	-- whichever fields they support; consumers prefer the team name
	-- for team-based modes and the user id for FFA.
	checkWinCondition: (scores: { [Player]: { kills: number, deaths: number, assists: number } }) -> (boolean, number?, string?),

	-- Determines the round leader on time-out. Same return shape as
	-- checkWinCondition's winner pair (userId, teamName); either or both
	-- may be nil for ties / no kills. RoundManager calls this when the
	-- timer expires before a score-limit win.
	getRoundLeader: (scores: { [Player]: { kills: number, deaths: number, assists: number } }) -> (number?, string?),

	-- Returns team configuration, or nil for FFA.
	-- Future modes (TDM, CTF) will return team definitions here.
	getTeamConfig: () -> nil,

	-- Called when a new round starts. Mode-specific setup (e.g., place flags for CTF).
	onRoundStart: () -> (),

	-- Called when a round ends. Mode-specific cleanup.
	onRoundEnd: () -> (),
}

return nil
