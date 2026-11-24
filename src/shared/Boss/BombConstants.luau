--!strict

----------------------------------------------------------------------
-- BombConstants
----------------------------------------------------------------------
-- THE CONTRACT of the scramble bomb, delivered as a two-phase PUZZLE: the
-- letters first LAND near the player and REST as a tap-in-order puzzle on a
-- timer; only if the timer runs out do the unsolved letters HATCH into
-- seekers that chase. Names and shapes that more than one system must agree on
-- live here; boss tuning (flight, timer, speeds, damage, reach) lives in
-- BossConfig `bomb*` fields.
--
-- Words: "puzzle" = the resting phase, "seeker" = a chasing letter, "pop" =
-- tapping a letter, "burst" = a seeker reaching someone, "hatch" = a resting
-- letter becoming a seeker.
--
-- THE RULE IN ONE PARAGRAPH.
--   1. LOB. In the boss's SporeLob attack slot (never while the word ward is
--      up) the boss lobs ONE puzzle at its target: `bombFlightSec` in the air,
--      landing within `bombLandRadius` studs (horizontal) of where the target
--      stood, on a floor-like surface near the target's own ground and clear
--      of walls. The flight is drawn from VfxBroadcast.lob. The attack ends at
--      the landing.
--   2. REST. At landing the puzzle Model appears with one letter part per
--      letter of a scrambled key word (3 letters in phase 1, 4 after; a
--      puzzle keeps what it was thrown with), resting on a circle of
--      REST_RADIUS_STUDS around the centre at `bombHoverHeight`. (The client
--      redraws them as a camera-facing row.) The timer `bombFuseSecByLetters`
--      runs from landing. A player within reach `bombTapReach` of the CENTRE
--      taps letters: in an order that spells an allowed word
--      (BombRules.isAccepted) the letter LOCKS (its part stays, resting, until
--      the puzzle ends); out of order it is REFUSED: progress is kept and the
--      timer loses `bombWrongTapPenaltySec`. Tapping a locked letter is a
--      no-op. The last letter solves the puzzle: boss damage
--      `bombDefuseDamageByLetters`, BombDefused, the Model is removed.
--   3. HATCH. When the timer ends unsolved every letter NOT locked hatches
--      into a seeker, `bombHatchStaggerSec` apart in index order; locked
--      letters' parts are removed at once. The word can no longer be completed
--      (BombBroken = true). Each seeker follows a player (the nearest living
--      player of the arena to the puzzle at hatch time; if that player dies or
--      leaves, the nearest living one; nobody: it keeps its heading) at
--      `bombSeekerSpeed` ramping to `bombSeekerSpeedMax` over
--      `bombSeekerLifetimeSec`, `bombHoverHeight` over the ground beneath it.
--      A seeker BURSTS (`bombBurstDamage` to every player of the arena within
--      `bombBurstRadius` studs, horizontal) within `bombSeekerTriggerStuds` of
--      the player it follows, when it runs into world geometry, or when its
--      lifetime ends. A seeker can be popped from within `bombSeekerTapReach`
--      of THAT SEEKER: it is removed harmlessly (no reward, no reply). The
--      Model is removed when no seeker is left (and none is waiting to
--      hatch). Boss defeated / round end / destroy() removes everything
--      silently in any phase (and drops a lob still in the air).
--
-- Roles: W = writer, R = readers.
--   BossBombs  (src/server/Boss/Scripts)        the puzzle itself: the ONLY writer
--                                               of every attribute and part below
--                                               (it moves hatched parts from the
--                                               boss controller's tick).
--   BombTapService (src/server/Boss)            the tap remote's server handler.
--   BombRules  (src/shared/Boss)                accept / solved / hint, run by the
--                                               server and by every client.
--   Clients draw the puzzle and seekers and predict taps from the attributes;
--   Economy listens to BombDefused; the recorder listens to the events.
--
-- WORLD OBJECTS. ONE Model per puzzle (name MODEL_NAME, tag TAG, in the Folder
-- CONTAINER_NAME in workspace, stamped with the arena id attribute
-- Arena.ID_ATTRIBUTE, ModelStreamingMode Persistent), created at LANDING with
-- every model attribute already set before it is parented. No `Core` part, no
-- PrimaryPart. Its only parts are the letters `Tile1..TileN`
-- (TILE_PART_PREFIX .. index; N = #BombLetters), all created at landing,
-- anchored, CanCollide / CanTouch false, CanQuery true, each carrying
-- TILE_INDEX_ATTRIBUTE. A part rests (at its place on the circle) until the
-- puzzle is solved or it hatches; a locked part stays resting until the puzzle
-- ends or the hatch removes it. A hatched part is moved by the server every
-- Heartbeat (anchored, CFrame; no replication smoothing is promised: a client
-- may interpolate) and carries SEEKER_EXPIRES_ATTRIBUTE and HATCHED_ATTRIBUTE
-- from its hatch on. A part is destroyed when its seeker is popped or bursts,
-- or (locked ones) at the hatch; the model is destroyed when the puzzle is
-- solved, when no seeker is left after the hatch, or silently on boss death /
-- round end.
----------------------------------------------------------------------

local BombConstants = {
	-- ============================================================
	-- Identity
	-- ============================================================
	-- CollectionService tag on the puzzle Model. W: BossBombs. R: clients (find
	-- puzzles to draw), BombTapService (is this a puzzle).
	TAG = "ScrambleBomb",
	-- The puzzle Model's name, and the Folder in workspace the server keeps them
	-- in (raycasts that must ignore seekers ignore this folder).
	MODEL_NAME = "ScrambleBomb",
	CONTAINER_NAME = "ScrambleBombs",
	-- The letter parts are `Tile<i>`, i = 1..N, i = the letter's index in
	-- BombLetters (so part i carries letters:sub(i, i)).
	TILE_PART_PREFIX = "Tile",

	-- ============================================================
	-- Published attributes. W: BossBombs only.
	-- ============================================================
	-- ON THE MODEL (all set before it is parented, at landing):
	-- string. The letters by index, uppercase, e.g. "TAC". Part i (1-based) is
	-- letters:sub(i, i). Constant.
	LETTERS_ATTRIBUTE = "BombLetters",
	-- string. The letter colour, a LetterBlocks.COLOR_TINTS key ("red" / "blue").
	COLOR_ATTRIBUTE = "BombColor",
	-- string. The allowed solution words, uppercase, joined by LIST_SEPARATOR,
	-- the chosen word first ("CAT,ACT"). Feed to BombRules.decodeWords.
	WORDS_ATTRIBUTE = "BombWords",
	-- string. The locked letter indices in tap order, joined by LIST_SEPARATOR
	-- ("" when none, "2,1" after letters 2 then 1). Feed to
	-- BombRules.decodeIndices. Rewritten on every ACCEPTED tap (and only then).
	ACCEPTED_ATTRIBUTE = "BombAccepted",
	-- number. GetServerTimeNow() seconds after which the hint shows (landing +
	-- bombHintAfterSec). Clients compute the letter with BombRules.hintTile
	-- (index = BombTileIndex).
	HINT_AT_ATTRIBUTE = "BombHintAt",
	-- number. RESTING tap reach in studs, measured from the player's root to the
	-- puzzle CENTRE (BombCentre), not to a part (bombTapReach: 20).
	REACH_ATTRIBUTE = "BombReach",
	-- number. CHASING tap reach in studs, measured from the player's root to THAT
	-- SEEKER's part (bombSeekerTapReach: 45).
	SEEKER_REACH_ATTRIBUTE = "BombSeekerReach",
	-- number. Burst radius in studs (horizontal), for the burst ring.
	BURST_RADIUS_ATTRIBUTE = "BombBurstRadius",
	-- boolean. false from landing; set true, once and for good, at the HATCH
	-- (the timer ran out: the word can no longer be completed).
	BROKEN_ATTRIBUTE = "BombBroken",
	-- number. UserId of the player the lowest-index live seeker follows; 0 while
	-- the puzzle rests and whenever it follows nobody. Informational (a client
	-- may point an arrow); rewritten when it changes.
	TARGET_USER_ID_ATTRIBUTE = "BombTargetUserId",
	-- string, one of Phase below. Resting from landing; Chasing from the hatch.
	PHASE_ATTRIBUTE = "BombPhase",
	-- Vector3. The puzzle's centre at hover height (ground + bombHoverHeight).
	-- Constant. The resting letters sit on a circle of REST_RADIUS_STUDS round it.
	CENTRE_ATTRIBUTE = "BombCentre",
	-- number. World Y of the ground under the centre (the ring / marker height).
	-- Constant.
	GROUND_Y_ATTRIBUTE = "BombGroundY",
	-- number. GetServerTimeNow() seconds at which the timer ends and the unsolved
	-- letters hatch. Moves EARLIER by bombWrongTapPenaltySec on a refused tap.
	HATCH_AT_ATTRIBUTE = "BombHatchAt",
	-- number. The timer's full length in seconds (bombFuseSecByLetters[n]), so a
	-- client can draw BombHatchAt as a share of it. Constant.
	FUSE_SEC_ATTRIBUTE = "BombFuseSec",
	-- ON EACH LETTER PART (Tile<i>):
	-- number, 1-based index into BombLetters. Constant.
	TILE_INDEX_ATTRIBUTE = "BombTileIndex",
	-- number, workspace:GetServerTimeNow() seconds at which the seeker's
	-- lifetime ends and it bursts where it is. Set at ITS hatch (absent before),
	-- constant after.
	SEEKER_EXPIRES_ATTRIBUTE = "SeekerExpiresAt",
	-- boolean. Absent while the letter rests; true from ITS hatch on (so a
	-- client can tell a chasing part from a resting one during the hatch
	-- stagger, when the model is already Chasing).
	HATCHED_ATTRIBUTE = "Hatched",
	-- Separator for the list-valued attributes above.
	LIST_SEPARATOR = ",",
	-- Values of PHASE_ATTRIBUTE.
	Phase = {
		Resting = "Resting",
		Chasing = "Chasing",
	},

	-- ============================================================
	-- Remotes and events
	-- ============================================================
	-- RemoteEvent ReplicatedStorage.Shared.Boss.BossEvents.BombTap.
	--   client -> server: FireServer(puzzle: Model, tileIndex: number, requestId: number)
	--   server -> that client only: FireClient(player, requestId: number)
	--       a REJECTION, sent only when
	--         * a check failed (rate, payload, not a live puzzle, arena, dead
	--           character, out of reach: resting = from the centre, chasing =
	--           from that seeker, each plus BlockShootConstants.
	--           OWN_REACH_TOLERANCE_STUDS), or
	--         * the tap was REFUSED while resting (out of order), or
	--         * the tap was INVALID (the part is gone; a locked letter tapped
	--           while chasing; a not-yet-hatched letter tapped during the hatch
	--           stagger).
	--       The client rolls its prediction back.
	--   NO reply for an ACCEPTED tap, a LOCKED tap (resting, already locked: a
	--   no-op, no penalty) or a HARMLESS pop (a chasing seeker removed).
	TAP_REMOTE_NAME = "BombTap",
	-- BindableEvents under ServerScriptService.Server.Boss.Events (server only).
	-- Fired by BossBombs.
	--   BombLanded(arenaId: string, letterCount: number)
	--       the lob landed and the puzzle Model now exists. Once per puzzle.
	--   BombDefused(player: Player?, word: string, color: string, arenaId: string, letterCount: number, scale: number?)
	--       the puzzle was solved. player = the credited player (most accepted
	--       taps, ties -> earliest to reach that count), nil if they have left;
	--       word = the allowed word the taps spelled; scale = the boss type's
	--       `bombEnergyScale` (nil if the type has none). The Economy credits
	--       the word from this; BossBombs credits nothing.
	--   BombPopped(arenaId: string, accepted: boolean)
	--       a RESTING tap that was judged: true = accepted (letter locked),
	--       false = refused (out of order, timer penalised). Not fired for a
	--       locked-letter no-op, a chasing pop or an Invalid tap.
	--   BombBroken(arenaId: string)
	--       NAME KEPT, MEANING CHANGED: the timer ran out unsolved (the hatch).
	--       Once per puzzle, at the hatch, just before BombHatched.
	--   BombHatched(arenaId: string, seekerCount: number)
	--       the hatch: seekerCount = the letters that were not locked, which
	--       will hatch one after another. Once per puzzle.
	--   BombBurst(arenaId: string, hitCount: number)
	--       one seeker burst; hitCount = players hurt. Fired per burst.
	EVENTS_FOLDER_PATH = "Boss.Events",
	DEFUSED_EVENT = "BombDefused",
	BURST_EVENT = "BombBurst",
	LANDED_EVENT = "BombLanded",
	BROKEN_EVENT = "BombBroken",
	POPPED_EVENT = "BombPopped",
	HATCHED_EVENT = "BombHatched",

	-- What BossBombs.tap returns.
	--   Accepted  resting: the letter locked (the puzzle is solved if it was the
	--             last);
	--   Refused   resting, out of order: the progress is kept, the timer loses
	--             bombWrongTapPenaltySec;
	--   Locked    resting, that letter is already locked: nothing changes;
	--   Harmless  chasing: the seeker was removed, no reward;
	--   Invalid   no such live letter (part gone, a locked letter while chasing,
	--             a letter that has not hatched yet, bad index).
	TapResult = {
		Accepted = "Accepted",
		Refused = "Refused",
		Locked = "Locked",
		Harmless = "Harmless",
		Invalid = "Invalid",
	},

	-- ============================================================
	-- Server-side tap trust (BombTapService)
	-- ============================================================
	-- Token bucket per player: burst, then sustained taps per second.
	TAP_BURST_CAPACITY = 4,
	TAP_REFILL_PER_SEC = 4,
	REJECTION_LOG_THROTTLE_SEC = 10,

	-- ============================================================
	-- Cause strings on the damage requests
	-- ============================================================
	BURST_CAUSE = "BombBurst",
	DEFUSE_CAUSE = "BombDefuse",

	-- ============================================================
	-- Greybox look (what the server makes). A client that draws its own
	-- letters should hide these parts (LocalTransparencyModifier) and keep them
	-- as hit targets, or follow them.
	-- ============================================================
	TILE_SIZE = Vector3.new(1.6, 1.6, 0.4),
	TILE_TRANSPARENCY = 0.4,

	-- ============================================================
	-- Resting layout
	-- ============================================================
	-- The resting letters sit evenly spaced on a circle of this radius (studs)
	-- round the centre, in the horizontal plane at hover height.
	REST_RADIUS_STUDS = 3,

	-- ============================================================
	-- Lob landing (server-side, BossBombs)
	-- ============================================================
	-- Landing points tried (random, within bombLandRadius) before the fall-back
	-- to the target's own ground.
	LAND_MAX_ATTEMPTS = 8,
	-- The ground under a point is probed from this far above the target's root
	-- to this far below that start.
	LAND_PROBE_UP_STUDS = 20,
	LAND_PROBE_DOWN_STUDS = 80,
	-- A landing ground may differ from the target's own ground by at most this.
	LAND_HEIGHT_TOLERANCE_STUDS = 8,
	-- A floor-like surface: the hit's normal Y is at least this (1 = flat).
	LAND_MIN_NORMAL_Y = 0.7,
	-- "Not inside a wall": no colliding part overlaps a sphere of this radius at
	-- the centre (hover height). Smaller than the hover height so the floor
	-- itself is not counted.
	LAND_CLEARANCE_RADIUS_STUDS = 2,
	-- A target's root stands this far above its feet when no ground is found
	-- under it (a bare test arena).
	LAND_ROOT_TO_FEET_STUDS = 3,
	-- The lob leaves the boss this far above its root.
	LOB_ORIGIN_HEIGHT_STUDS = 6,

	-- ============================================================
	-- Seeker flight (server-side, BossBombs)
	-- ============================================================
	-- The ground under a seeker is probed from this far above it to this far
	-- below it; no ground there = it keeps its height. (Also read by the client.)
	GROUND_PROBE_UP_STUDS = 10,
	GROUND_PROBE_DOWN_STUDS = 80,
	-- A seeker changes height toward its hover height at most this fast, so a
	-- ledge is not a snap.
	VERTICAL_SPEED_STUDS = 14,
	-- The wall cast reaches this far past the step it is about to take.
	WALL_CAST_MARGIN_STUDS = 1.5,
	-- Steps shorter than this horizontal distance to the target are not
	-- normalised (no direction): the seeker keeps its heading.
	MIN_DIRECTION_STUDS = 0.01,
	-- Boolean on a seeker part, set by BossBombs when it starts its final
	-- approach (straight, fast, no tracking). Read by the client for the look.
	COMMITTED_ATTRIBUTE = "Committed",
	-- A burst, and the arrival that sets it off, only count for a player whose
	-- root is within this height of the seeker (it hovers about 2 studs over a
	-- standing player's root), so neither reaches a player on another level.
	BURST_HEIGHT_TOLERANCE_STUDS = 8,
	-- The longest dt one tick may move a seeker by, so a hitch cannot carry a
	-- seeker through a wall or a player (a long gap just moves it this far).
	MAX_STEP_DT_SEC = 0.25,

	-- ============================================================
	-- Cues (VfxConfig.EFFECTS ids through VfxBroadcast; reused stand-ins).
	-- The lob uses BossConstants.SPORE_LOB_VFX / SPORE_LOB_COLOR /
	-- SPORE_LOB_MARKER_RADIUS_STUDS; the burst ring uses
	-- BossConstants.SPORE_RING_COLOR / SPORE_BURST_RING_SEC /
	-- SPORE_BURST_RING_Y_OFFSET_STUDS.
	-- ============================================================
	LAND_VFX = "impact_wall", -- the puzzle lands (at its centre)
	POP_VFX = "impact_buff", -- accepted tap; a chasing pop
	REFUSED_VFX = "impact_damage", -- refused tap
	HATCH_VFX = "impact_wall", -- a letter hatches (per seeker)
	BURST_VFX = "impact_damage_t3", -- a seeker bursts
	DEFUSE_VFX = "impact_heal", -- the word is sent back at the boss

	-- ============================================================
	-- Scramble
	-- ============================================================
	-- Random shuffles tried before the exhaustive scan for a non-solution order.
	SCRAMBLE_MAX_ATTEMPTS = 20,
}

return BombConstants
