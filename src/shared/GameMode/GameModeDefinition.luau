----------------------------------------------------------------------
-- GameModeDefinition
----------------------------------------------------------------------
-- Interface that all game modes must implement.
-- RoundManager and GameModeService call these methods to drive
-- mode-specific behavior while keeping the core loop generic.
--
-- To create a new game mode:
--   1. Create a new module in src/shared/GameMode/Modes/
--   2. Return a table that satisfies this interface
--   3. Register it in Modes/init.luau
--
-- Everything that used to be a global flag in GameConfig — PvP, the round
-- timer, the pre-round countdown — is a field of `getConfig()` (refactor
-- chunk 8, Q7). Two sessions can run different rules on one server, so a
-- server-wide boolean could only ever be right for one of them.
----------------------------------------------------------------------

export type PlayerScore = { kills: number, deaths: number, assists: number }
export type Scores = { [Player]: PlayerScore }

export type ModeConfig = {
	-- Kills that end the round. `math.huge` for a round nobody wins.
	scoreLimit: number,

	-- Seconds of Active play before the round ends on time and the mode is
	-- asked for its leader. Absent means unlimited: the round runs until
	-- the score limit is hit or the session is disabled.
	timeLimit: number?,

	-- Seconds of pre-round countdown. Absent or 0 skips the Countdown
	-- state; the round goes live the moment MIN_PLAYERS is met.
	countdownSec: number?,

	-- Seconds a dead player waits before GameModeService respawns them.
	respawnTime: number,

	-- CollectionService tag identifying this mode's spawn points, one of
	-- `Arena.SpawnTags`. SpawnManager resolves the pads carrying it that
	-- also belong to the session's arena.
	spawnTag: string,

	-- Whether GameModeService should call `start()` on this mode's
	-- session. False for LobbyMode: the hub is a real session with a
	-- roster and spawn pads, it just has no round to run. Expressed
	-- here rather than as an arena-id check because "does this run
	-- rounds" is a property of the mode.
	--
	-- Optional; absent means true.
	runsRounds: boolean?,

	-- Whether players in this mode may damage each other. HealthService
	-- asks through the *victim's* session, so a duellist is damageable
	-- by their opponent while a lobby player on the same server is not.
	-- Optional; absent means false.
	allowsPvP: boolean?,
}

export type GameModeDefinition = {
	-- Display name for UI
	name: string,

	-- Returns the mode-specific configuration
	getConfig: () -> ModeConfig,

	-- Called when a player joins the game.
	onPlayerJoin: (player: Player) -> (),

	-- Called when a player is killed. `killer` is nil for an environment
	-- kill; `cause` is the id the kill feed credits (a skill name, a
	-- DamageTypes.Cause). Returns the score change for the killer
	-- (usually 1). Game modes like Gun Game can use this to switch weapons.
	onPlayerKill: (killer: Player?, victim: Player, cause: string) -> number,

	-- Called each tick to check if the round should end.
	-- Receives the session's current scores, keyed by Player.
	-- Returns (shouldEnd, winnerUserId).
	checkWinCondition: (scores: Scores) -> (boolean, number?),

	-- Determines the round leader on time-out. Returns the leading
	-- user id, or nil for a tie / no kills. RoundManager calls this when
	-- the timer expires before a score-limit win.
	getRoundLeader: (scores: Scores) -> number?,

	-- Called when a new round starts. Mode-specific setup (e.g., place flags for CTF).
	onRoundStart: () -> (),

	-- Called when a round ends. Mode-specific cleanup.
	onRoundEnd: () -> (),
}

return nil
