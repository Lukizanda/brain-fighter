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

	-- Time-boxed invulnerability, owned by Health (`shared/Health/Protection`).
	-- The attribute holds the `workspace:GetServerTimeNow()` instant the
	-- window closes, never a flag plus a timer: it replicates as a plain
	-- value, so the client cue needs no remote, and an expired window cannot
	-- be left switched on by a timer that never ran.
	PROTECTED_UNTIL_ATTRIBUTE = "_protectedUntil",
	-- Seconds of protection a player gets on teleporting onto an arena's
	-- island (ArenaEntryService's `PlayerEntered`). Long enough to find
	-- footing, short enough that it cannot be camped in.
	ARRIVAL_PROTECTION_SEC = 2,
	-- The client cue: a gold bubble around the protected character. Cosmetic
	-- only (CanQuery off), so unlike the spell shield it deflects nothing.
	PROTECTION_BUBBLE_DIAMETER_STUDS = 7,
	PROTECTION_BUBBLE_TRANSPARENCY = 0.6,
	PROTECTION_BUBBLE_COLOR = Color3.fromRGB(255, 214, 90),

	HEAD_PARTS = { "Head" },
	TORSO_PARTS = { "UpperTorso", "LowerTorso" },

	DAMAGEABLE_TAG = "Damageable",
	-- A Damageable rig that is there to be hit rather than to fight back:
	-- it carries a world-space health readout so a player can read what a
	-- spell actually did. Opt-in per rig, so tagging Damageable does not
	-- put a bar over every NPC in the game.
	TRAINING_DUMMY_TAG = "TrainingDummy",
	MAX_HEALTH_ATTRIBUTE = "maxHealth",
	RESPAWN_TIME_ATTRIBUTE = "respawnTime",
}

return HealthConstants
