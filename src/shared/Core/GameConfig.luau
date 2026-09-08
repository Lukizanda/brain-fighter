----------------------------------------------------------------------
-- GameConfig
----------------------------------------------------------------------
-- Game-wide configuration for default Roblox systems.
-- Change these values to toggle built-in Roblox UI and behaviors.
-- These are applied once at startup by CharacterSystemsLoader.
----------------------------------------------------------------------

local GameConfig = {
	----------------------------------------------------------------------
	-- Default Roblox UI Visibility
	----------------------------------------------------------------------
	-- Set to false to hide the corresponding built-in Roblox UI.
	-- Useful when replacing with custom UI (e.g., custom health bar,
	-- custom backpack, custom player list).
	----------------------------------------------------------------------
	SHOW_BACKPACK = false,         -- Default tool hotbar (bottom center)
	SHOW_HEALTH = false,           -- Default health bar (replaced by HealthGui)
	SHOW_PLAYER_LIST = false,      -- Leaderboard (top right) — replaced by custom ScoreboardGui
	SHOW_CHAT = true,              -- Chat window
	SHOW_EMOTES = true,            -- Emote menu

	----------------------------------------------------------------------
	-- Combat feature gates
	----------------------------------------------------------------------
	-- Brain Fighter is being repurposed as an educational shooter. The
	-- inherited Archon team/PvP template (TeamService, FFADeathmatch,
	-- TeamDeathmatch, camera/locomotion/loadout stack) was deleted in
	-- 6610291 — flipping these flags no longer restores anything; a
	-- future PvP mode would need to be rebuilt, not un-gated. The flags
	-- remain because consumers across the damage, mode-registry, spawn,
	-- UI, and nametag layers still read them directly via
	-- require(...).TEAMS_ENABLED / .PLAYER_VS_PLAYER_ENABLED.
	----------------------------------------------------------------------
	TEAMS_ENABLED = false,            -- Set true to restore Team Deathmatch mode + team UI + team-aware spawn/nametag/score logic.
	PLAYER_VS_PLAYER_ENABLED = false, -- Set true to restore PvP damage. When false, players cannot damage other players; NPCs remain valid targets.
	ROUND_TIMER_ENABLED = false,      -- When false, rounds have no time limit; win by score only. Set true to re-enable the 5-minute cap.
	ROUND_COUNTDOWN_ENABLED = false,  -- When false, the pre-round 10-s countdown is skipped; round starts immediately. Set true to restore.

	----------------------------------------------------------------------
	-- Dev-only helpers (leave off in shipped builds)
	----------------------------------------------------------------------
	DEV_SMOKE_KILLFEED = false, -- when true, loop-fires 3 synthetic KillFeed events (normal kill / self-elim / env kill) so the UI can be verified without real combat
	DEV_COUNT_POP_VFX = false, -- when true, each client logs one line per block pop counting the burst and ribbon instances it actually built. Turns the "is the popper's burst drawn twice?" question into a number — a doubled burst reads only as slightly brighter and slightly louder, which is not something anyone should be asked to eyeball. Multi-client: every line is prefixed with the player name

	----------------------------------------------------------------------
	-- Block Spawner
	----------------------------------------------------------------------
	-- Blocks per 1000 cubic studs of spawn volume. All BlockSpawnVolume
	-- parts are summed; total count = density × total_volume / 1000.
	-- Default 2 ≈ 26 blocks in the 40×8×40 reference arena.
	----------------------------------------------------------------------
	BLOCK_SPAWN_DENSITY = 0.1,
	BLOCK_SCALE = 1.5,                -- uniform scale multiplier on the 4×4×4 template (e.g. 0.5 = 2 studs, 2 = 8 studs)

	----------------------------------------------------------------------
	-- Minimum spacing between block centres, as a multiple of the sphere
	-- a block sweeps while it tumbles (LetterBlocks.tumbleDiameter).
	--
	-- 1.0 = two blocks can never visibly intersect at any orientation.
	-- Below 1.0 they may clip while turning; below ~0.58 they overlap
	-- even sitting still. 0 disables the spacing check entirely.
	--
	-- Expressed as a multiplier rather than in studs on purpose. This was
	-- a literal 4 studs while BLOCK_SCALE made the blocks 6 studs wide,
	-- so the check passed on pairs that were plainly interpenetrating —
	-- a hand-maintained coupling that broke the first time BLOCK_SCALE
	-- moved. A multiplier cannot drift out of step with the block size.
	----------------------------------------------------------------------
	BLOCK_SPACING_CLEARANCE = 1,
	BLOCK_RESPAWN_DELAY = 3,          -- seconds between a block being consumed and its replacement spawning; 0 refills on the next frame. Each consumed block is replaced independently, so N rapid kills come back staggered the same way they went out. Raising this thins the arena under sustained fire — steady-state missing blocks ≈ delay × kills-per-second.

	----------------------------------------------------------------------
	-- Default camera behavior
	----------------------------------------------------------------------
	-- When false: right-click toggles between mouse-locked and free-cursor
	--   (Roblox CameraToggle mode). When true: right-click held to rotate only
	--   (Classic mode).
	CAMERA_TOGGLE_DISABLED = true,

	----------------------------------------------------------------------
	-- Dash / Roll
	----------------------------------------------------------------------
	DASH = {
		KEY           = Enum.KeyCode.LeftShift,
		DASH_SPEED    = 60,   -- studs/sec (airborne dash)
		DASH_DURATION = 0.2,  -- seconds
		ROLL_SPEED    = 60,   -- studs/sec (grounded roll, decelerates to 0)
		ROLL_DURATION = 0.35, -- seconds
		ROLL_COOLDOWN = 0.2,  -- seconds (wait after roll ends before next roll)
		ANIM_FADE_TIME = 0.1,
		VFX_DURATION  = 0.3,
	},
}

return GameConfig
