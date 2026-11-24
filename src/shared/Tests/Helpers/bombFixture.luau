--!strict

----------------------------------------------------------------------
-- bombFixture
----------------------------------------------------------------------
-- Helpers for the scramble-puzzle tests (Arena suite, bomb_*). The stand-in boss
-- and the container are hungerFixture's, the throwaway arena is
-- bossEntranceFixture's; this adds only what is bomb-specific:
--
--   * `spec`: a copy of the Brain's boss-type spec (so it carries the shipped
--     puzzle numbers), `overrides` winning;
--   * `record`, which listens to BombDefused / BombBurst / BombLanded /
--     BombBroken / BombPopped / BombHatched and the Health damage event;
--   * a manual clock (`clock`, `advance`, `jump`) and `lob` / `land` /
--     `lobAndLand` / `expire` / `hatchAll`, which drive BossBombs.tick(dt, now)
--     with injected time, so a test never waits real seconds;
--   * `begin` / `finish`, which build and tear down the usual setup (a
--     throwaway arena with the harness player in it, a stand-in boss, a
--     BossBombs object on it);
--   * helpers to read what the puzzle published and to tap right or wrong
--     through BombRules (the rules themselves are tested in bomb_rules);
--   * `addFloor`, `placePlayer` / `releasePlayer`, which give the lob a ground
--     and park the harness player's root in the air (anchored).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local BombRules = require(ReplicatedStorage.Shared.Boss.BombRules)
local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)
local bossEntranceFixture = require(script.Parent.bossEntranceFixture)
local hungerFixture = require(script.Parent.hungerFixture)
local restoreToSafeSpawn = require(script.Parent.restoreToSafeSpawn)

local POLL_SEC = 0.05
-- BindableEvent handlers run deferred; one frame is enough, this is slack.
local SETTLE_SEC = 0.2
-- A tick step the tests use when they only need time to pass.
local STEP_SEC = 0.1
-- Most ticks `runUntil` and `hatchAll` spend before giving up.
local MAX_TICKS = 400
-- A far-off parking spot for a player a seeker must not reach in a test.
local FAR_STUDS = 400
-- A floor's size and how far under the stand-in boss's root its top lies.
local FLOOR_SIZE = Vector3.new(600, 2, 600)
local FLOOR_DROP_STUDS = 11

local brain = BossConfig.BOSS_TYPES.Brain

local fixture = {}

fixture.POLL_SEC = POLL_SEC
fixture.SETTLE_SEC = SETTLE_SEC
fixture.STEP_SEC = STEP_SEC
fixture.FAR_STUDS = FAR_STUDS
fixture.FLOOR_SIZE = FLOOR_SIZE
fixture.FLOOR_DROP_STUDS = FLOOR_DROP_STUDS
fixture.STAGGER_SEC = brain.bombHatchStaggerSec :: number
fixture.FLIGHT_SEC = brain.bombFlightSec :: number
-- Slack for a time comparison across attributes.
fixture.TIME_TOLERANCE_SEC = 0.001

-- A full boss-type spec: the Brain's. `overrides` wins.
function fixture.spec(overrides: { [string]: any }?): any
	local spec: any = table.clone(brain)
	-- The flight tests time a seeker from its hatch; the arming pause has its
	-- own place in the config and is switched off here.
	spec.bombSeekerArmSec = 0
	-- Likewise the limited turning: the flight tests expect exact tracking.
	spec.bombSeekerTurnDegPerSec = 0
	spec.bombSeekerCommitStuds = 0
	-- The reach tests expect the distance rule on, whatever the shipped switch says.
	spec.bombTapReachEnabled = true
	spec.bombDefuseDamageEnabled = true
	spec.bombSeekerLaunchStaggerSec = 0
	spec.bombSeekerArcHeight = 0
	if overrides then
		for key, value in overrides do
			spec[key] = value
		end
	end
	return spec
end

-- Listens to the bomb events and to Health's damage event; `ctx.defused`,
-- `ctx.bursts`, `ctx.landed`, `ctx.broken`, `ctx.popped`, `ctx.hatched` and
-- `ctx.damage` fill up. Disconnect with `fixture.disconnect(ctx)`.
function fixture.record(ctx: any)
	local events = ServerScriptService.Server.Boss.Events
	ctx.defused = {}
	ctx.bursts = {}
	ctx.landed = {}
	ctx.broken = {}
	ctx.popped = {}
	ctx.hatched = {}
	ctx.damage = {}
	ctx.connections = {
		(events[BombConstants.DEFUSED_EVENT] :: BindableEvent).Event:Connect(
			function(player: any, word: string, color: string, arenaId: string, letterCount: number, scale: any)
				table.insert(ctx.defused, {
					player = player,
					word = word,
					color = color,
					arenaId = arenaId,
					letterCount = letterCount,
					scale = scale,
				})
			end
		),
		(events[BombConstants.BURST_EVENT] :: BindableEvent).Event:Connect(function(arenaId: string, hitCount: number)
			table.insert(ctx.bursts, { arenaId = arenaId, hitCount = hitCount })
		end),
		(events[BombConstants.LANDED_EVENT] :: BindableEvent).Event:Connect(function(arenaId: string, letterCount: number)
			table.insert(ctx.landed, { arenaId = arenaId, letterCount = letterCount })
		end),
		(events[BombConstants.BROKEN_EVENT] :: BindableEvent).Event:Connect(function(arenaId: string)
			table.insert(ctx.broken, { arenaId = arenaId })
		end),
		(events[BombConstants.POPPED_EVENT] :: BindableEvent).Event:Connect(function(arenaId: string, accepted: boolean)
			table.insert(ctx.popped, { arenaId = arenaId, accepted = accepted })
		end),
		(events[BombConstants.HATCHED_EVENT] :: BindableEvent).Event:Connect(function(arenaId: string, seekerCount: number)
			table.insert(ctx.hatched, { arenaId = arenaId, seekerCount = seekerCount })
		end),
		(ServerScriptService.Server.Health.Events.PlayerDamaged :: BindableEvent).Event:Connect(
			function(source: any, humanoid: Humanoid, result: any)
				table.insert(ctx.damage, { source = source, humanoid = humanoid, cause = result and result.cause })
			end
		),
	}
end

function fixture.disconnect(ctx: any)
	if ctx.connections then
		for _, connection in ctx.connections do
			connection:Disconnect()
		end
		ctx.connections = nil
	end
end

----------------------------------------------------------------------
-- Setup and teardown
----------------------------------------------------------------------

-- The harness player in a throwaway arena, a stand-in boss in it and a
-- BossBombs on that boss. Fills `ctx.bf`, `ctx.hf`, `ctx.boss`, `ctx.humanoid`,
-- `ctx.root`, `ctx.bombs`, `ctx.spec`, `ctx.clock`; false (and the test should
-- return) when anything is missing. `maxHealth` is the boss's.
function fixture.begin(ctx: any, spec: any?, maxHealth: number?): boolean
	local player: Player? = ctx.player
	if not player then
		return false
	end
	local bf = bossEntranceFixture.new()
	ctx.bf = bf
	if not bf:build(player, { entranceDelaySec = nil, withPad = false }) then
		return false
	end
	local hf = hungerFixture.new(bf.arenaId)
	ctx.hf = hf
	local boss, humanoid, root = hf:fakeBoss(maxHealth)
	ctx.boss = boss
	ctx.humanoid = humanoid
	ctx.root = root
	ctx.spec = spec or fixture.spec()
	local bombs = BossBombs.new(boss, humanoid, root, ctx.spec)
	if not bombs then
		return false
	end
	ctx.bombs = bombs
	ctx.clock = fixture.clock()
	return true
end

-- The undo of `begin` (and of `placePlayer`).
function fixture.finish(ctx: any)
	fixture.disconnect(ctx)
	if ctx.bombs then
		ctx.bombs:destroy()
	end
	fixture.releasePlayer(ctx.player)
	if ctx.hf then
		ctx.hf:destroy()
	end
	if ctx.bf then
		ctx.bf:cleanup(ctx.player)
	end
	if ctx.bf and ctx.player then
		restoreToSafeSpawn.restoreToSafeSpawn(ctx.player)
	end
end

----------------------------------------------------------------------
-- Time
----------------------------------------------------------------------

-- A manual clock, starting at the real server time so attributes are sane.
function fixture.clock(): { now: number }
	return { now = workspace:GetServerTimeNow() }
end

-- Advance the clock by `dt` and tick `bombs` with it.
function fixture.advance(bombs: any, clock: { now: number }, dt: number)
	clock.now += dt
	bombs:tick(dt, clock.now)
end

-- Move the clock on by `seconds` and tick with dt 0: time passes (landing,
-- timer, staggers, ages, lifetimes) but nothing flies.
function fixture.jump(bombs: any, clock: { now: number }, seconds: number)
	clock.now += seconds
	bombs:tick(0, clock.now)
end

-- Tick in `dt` steps until `done()` or MAX_TICKS; returns whether it was done.
function fixture.runUntil(bombs: any, clock: { now: number }, dt: number, done: () -> boolean): boolean
	for _ = 1, MAX_TICKS do
		if done() then
			return true
		end
		fixture.advance(bombs, clock, dt)
	end
	return done()
end

-- Start a lob at `target` (thrown at the clock's `now`, nothing ticked).
-- `targetRoot` is the boss's target root (unused by the puzzle; nil = none).
-- Returns whether it started and a table whose `landed` turns true when
-- BossBombs calls the attack's callback.
function fixture.lob(bombs: any, clock: { now: number }, target: Vector3, targetRoot: BasePart?): (boolean, { landed: boolean })
	local state = { landed = false }
	local started = bombs:beginLob(target, function() state.landed = true end, targetRoot, clock.now)
	return started, state
end

-- Move the clock on by the flight time and tick once with no time passing in
-- the tick (dt 0): the puzzle lands. Returns its Model (nil if none appeared).
function fixture.land(bombs: any, clock: { now: number }): Model?
	fixture.jump(bombs, clock, fixture.FLIGHT_SEC)
	local models = bombs:liveModels()
	return models[#models]
end

-- `lob` then `land`: the landed puzzle's Model (nil if none) and the state.
function fixture.lobAndLand(bombs: any, clock: { now: number }, target: Vector3, targetRoot: BasePart?): (Model?, { landed: boolean })
	local started, state = fixture.lob(bombs, clock, target, targetRoot)
	if not started then
		return nil, state
	end
	return fixture.land(bombs, clock), state
end

-- Move the clock to the moment the puzzle's timer ends (its BombHatchAt) and
-- tick with dt 0: the hatch happens, the first seeker is out.
function fixture.expire(bombs: any, clock: { now: number }, model: Model)
	local hatchAt = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE)
	if type(hatchAt) == "number" and hatchAt > clock.now then
		clock.now = hatchAt
	end
	bombs:tick(0, clock.now)
end

----------------------------------------------------------------------
-- Reading and tapping
----------------------------------------------------------------------

-- What the puzzle published, decoded.
function fixture.letters(model: Model): { string }
	return BombRules.lettersOf(model:GetAttribute(BombConstants.LETTERS_ATTRIBUTE) :: string)
end

function fixture.allowed(model: Model): { string }
	return BombRules.decodeWords(model:GetAttribute(BombConstants.WORDS_ATTRIBUTE) :: string)
end

function fixture.accepted(model: Model): { number }
	return BombRules.decodeIndices(model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE) :: string)
end

-- The letter part with that index, nil if it is not (or no longer) in the world.
function fixture.part(model: Model, index: number): BasePart?
	local part = model:FindFirstChild(BombConstants.TILE_PART_PREFIX .. tostring(index))
	return if part and part:IsA("BasePart") then part else nil
end

local function isHatched(part: BasePart): boolean
	return part:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) == true
end

-- The part with that index when it has hatched (it is a chasing seeker), else nil.
function fixture.seeker(model: Model, index: number): BasePart?
	local part = fixture.part(model, index)
	return if part and isHatched(part) then part else nil
end

-- How many letter parts the puzzle has now (resting, locked and hatched).
function fixture.partCount(model: Model): number
	local count = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- How many of them have hatched (are seekers).
function fixture.seekerCount(model: Model): number
	local count = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and isHatched(child) then
			count += 1
		end
	end
	return count
end

-- How many have not hatched (resting or locked).
function fixture.restingCount(model: Model): number
	return fixture.partCount(model) - fixture.seekerCount(model)
end

-- Move the clock to the timer's end and one stagger at a time (no flight: dt 0)
-- until every unlocked letter has hatched. Returns the staggers it took after
-- the first hatch.
function fixture.hatchAll(bombs: any, clock: { now: number }, model: Model): number
	fixture.expire(bombs, clock, model)
	local steps = 0
	-- Locked letters' parts went at the hatch, so what still rests is waiting.
	while model.Parent ~= nil and fixture.restingCount(model) > 0 and steps < MAX_TICKS do
		fixture.jump(bombs, clock, fixture.STAGGER_SEC)
		steps += 1
	end
	return steps
end

-- The letter that is right to tap now, nil when solved.
function fixture.rightTile(model: Model): number?
	return BombRules.hintTile(fixture.letters(model), fixture.allowed(model), fixture.accepted(model))
end

-- A letter that is wrong to tap now (not locked, refused), nil if none.
function fixture.wrongTile(model: Model): number?
	local letters = fixture.letters(model)
	local allowed = fixture.allowed(model)
	local accepted = fixture.accepted(model)
	for index = 1, #letters do
		if fixture.part(model, index) ~= nil and not BombRules.isLockedTile(accepted, index)
			and not BombRules.isAccepted(letters, allowed, accepted, index)
		then
			return index
		end
	end
	return nil
end

-- `player` taps the right letter; returns the tap result, or nil if solved.
function fixture.tapRight(bombs: any, player: any, model: Model): string?
	local tile = fixture.rightTile(model)
	if tile == nil then
		return nil
	end
	return bombs:tap(player, model, tile)
end

-- A big collidable floor whose top is FLOOR_DROP_STUDS under the stand-in
-- boss's root; returns its top Y. Parented to the fixture's container.
function fixture.addFloor(ctx: any): number
	local root: BasePart = ctx.root
	local floor = Instance.new("Part")
	floor.Name = "BombTestFloor"
	floor.Anchored = true
	floor.CanCollide = true
	floor.Size = FLOOR_SIZE
	floor.Position = root.Position - Vector3.new(0, FLOOR_DROP_STUDS + FLOOR_SIZE.Y / 2, 0)
	floor.Parent = ctx.hf.container
	return floor.Position.Y + FLOOR_SIZE.Y / 2
end

----------------------------------------------------------------------
-- The harness player
----------------------------------------------------------------------

-- The player's root, anchored at `position`; false when there is no character.
function fixture.placePlayer(player: Player, position: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	if character then
		character:SetAttribute(HealthConstants.PROTECTED_UNTIL_ATTRIBUTE, nil)
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(position)
	return true
end

function fixture.releasePlayer(player: Player?)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
end

-- The player's root part, nil when there is none.
function fixture.rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A stand-in for a second player: BossBombs keys taps by the value and reads
-- only `.Parent` (nil = has left). Never handed to Roblox APIs unless it is
-- the credited player, so keep it from winning unless the test wants nil.
function fixture.standIn(left: boolean): any
	return { Parent = if left then nil else workspace, Name = "StandIn" }
end

return fixture
