--!strict

----------------------------------------------------------------------
-- BlockTapController
----------------------------------------------------------------------
-- Click or tap a letter block and it pops. The whole input half of the
-- block-consume loop (Phase 5.7).
--
-- Replaces LetterBlaster, which did exactly this behind the Spelling
-- Staff's Tool.Activated. The staff gave the input a home and a laser
-- beam; it did not give the weapon a reason to exist — no reticle (by
-- design), no ammo, no alternate fire, and nothing else in the game is
-- shot. What it cost was a boot chain no other input has: StarterPack →
-- Backpack → Tool.Equipped → mount. See wiki/design/tap-to-pop.md.
--
-- The server contract is untouched: ConsumeBlock still takes exactly one
-- argument and BlockShootValidation still runs the same three checks.
-- This is an input-layer migration, not an authority change.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")

local BlockShoot     = require(ReplicatedStorage.Shared.BlockShoot)
local BlockTapConfig = require(ReplicatedStorage.Shared.BlockShoot.BlockTapConfig)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillVisuals   = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local VfxConfig      = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local PlayerSession  = require(script.Parent.PlayerSession)

local log = Logger.new("BlockTapController")

local consumeRemote = ReplicatedStorage.Shared.BlockShoot.Remotes.ConsumeBlock :: RemoteEvent

local LocalPlayer = Players.LocalPlayer
local session     = PlayerSession.get()

-- Matches GameplayHudGui and SpellMenuGui: same asset, same pitch drop,
-- so a refused action sounds identical wherever it was triggered from.
-- The staff's FizzleSound was a .model.json on the Handle carrying a
-- duplicate of this id; with no Handle to hang it off, the client-local
-- Sound the rest of the HUD already uses is the whole answer.
local FIZZLE_PLAYBACK_SPEED = 0.55

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId       = VfxConfig.SFX.fizzle
fizzleSound.Volume        = 1
fizzleSound.PlaybackSpeed = FIZZLE_PLAYBACK_SPEED
fizzleSound.Parent        = SoundService

local lastPopped: number = -math.huge

-- Letters appended optimistically and not yet settled, keyed by a
-- client-minted request id.
--
-- **Not keyed by the block**, which was the obvious first choice and is
-- wrong. The server would have to echo the block back to say which
-- consume failed, and the single most important rejection — losing a race
-- for a block — is precisely the case where that block has *already been
-- destroyed* by the winner. An Instance reference for a destroyed object
-- is exactly the kind of thing VfxBroadcast.playOn warns arrives as nil,
-- so the rollback would silently no-op in the one situation it exists
-- for. A number always survives the trip.
--
-- The id is opaque to the server: it type-checks it and echoes it, never
-- looks anything up with it, so this adds no trust surface.
--
-- The server only replies when it *refuses*, so a success leaves its
-- entry behind — hence the sweep below rather than an ack on the hot
-- path, which would double this remote's traffic on the most frequent
-- action in the game to carry one bit that is almost always "fine".
type PendingAppend = { letter: string, color: string, firedAt: number }
local pending: { [number]: PendingAppend } = {}
local requestSeq = 0

-- How long an unanswered append waits before it is assumed to have
-- succeeded. A rejection travels one round trip; this is orders of
-- magnitude more than that, because the cost of the two mistakes is not
-- symmetric. Expiring too early means a late rejection finds no entry and
-- the phantom letter survives — the exact bug this stage exists to close.
-- Expiring late costs a table entry.
local PENDING_TTL_SEC = 10

local PENDING_SWEEP_SEC = 5

-- Alive-and-embodied check.
--
-- New with this migration, and required by it. Holding the staff was an
-- implicit gate: a corpse has no equipped Tool, so Tool.Activated could
-- not fire. A global InputBegan handler has no such gate, and without
-- this a dead player clicking around would fire consumes that the server
-- can only reject (checkRange needs a HumanoidRootPart), spending rate
-- limit budget and filling the log with warnings for input that was
-- never legitimate.
local function livingCharacter(): Model?
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character
end

local function tryPop(screenPosition: Vector2)
	local now = os.clock()
	if now - lastPopped < BlockTapConfig.COOLDOWN then
		log:infoThrottled("cooldown", 1, "on cooldown — skipping")
		return
	end
	lastPopped = now

	if session.mindFullManager:isMindFull() then
		fizzleSound:Play()
		log:info("blocked: mind is full")
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		log:warn("no CurrentCamera")
		return
	end

	local character = livingCharacter()
	if not character then
		log:infoThrottled("no_character", 5, "no living character — ignoring tap")
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	-- ScreenPointToRay, *not* ViewportPointToRay — the two take different
	-- coordinate spaces and the caller has to match the one its point came
	-- from. `input.Position` (and Mouse.X/Y) are inset-adjusted: measured
	-- from below the topbar. GetMouseLocation() is not; it is raw viewport
	-- space. ScreenPointToRay adds the inset back, ViewportPointToRay does
	-- not, so the correct pairs are ScreenPointToRay+input.Position and
	-- ViewportPointToRay+GetMouseLocation().
	--
	-- LetterBlaster used the second pair and was right. This controller
	-- inherited its ViewportPointToRay line but changed where the point
	-- came from, which silently tilted every ray up by the inset — 58px,
	-- or 7.7 degrees at a 601px/70-degree viewport. That is an *angular*
	-- error, so the miss grows with range: 0.135 studs per stud, meaning
	-- ~4 studs off at 30 studs and 43 off at 320. A letter block is about
	-- 4 studs wide, so taps landed only within ~30 studs and it read as a
	-- hard range limit that raising MAX_RAYCAST_DISTANCE could not budge.
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * BlockShoot.MAX_RAYCAST_DISTANCE, params)

	if not result then
		log:info("tap missed — nothing within range")
		return
	end

	local block = BlockShoot.findLetterBlock(result.Instance)
	if not block then
		log:info(string.format("'%s' has no LetterBlock ancestor", result.Instance.Name))
		return
	end

	local letter, color = BlockShoot.readBlock(block)
	if not letter or not color then
		log:warn(string.format("block '%s' missing Letter/Color attrs", block.Name))
		return
	end

	-- Read before firing: the server destroys the block, and the burst
	-- needs to start from where it stood, not from a Model mid-teardown.
	local blockPos = block:GetPivot().Position

	local appended = session.wordBuffer:append(letter, color)
	if not appended then
		fizzleSound:Play()
		log:info(string.format("buffer rejected '%s' (%s)", letter, color))
		return
	end

	-- The append above is optimistic — the server has not agreed yet. Record
	-- what we owe back so a rejection can undo exactly this letter.
	requestSeq += 1
	local requestId = requestSeq
	pending[requestId] = { letter = letter, color = color, firedAt = os.clock() }

	consumeRemote:FireServer(block, requestId)
	log:info(string.format("popped %s (%s)", letter, color))

	-- Predict the burst, but NOT the stream. The split is the point.
	--
	-- The burst is a spark: it says a block came apart here. That stays
	-- true even when we lose a race for it, because the block really did
	-- pop — the winner popped it — so drawing it immediately is honest and
	-- the tap feels instant.
	--
	-- The stream is an attribution claim: "that letter came to *me*". That
	-- is the same class of thing as a hit marker, which CastAction's
	-- prediction contract explicitly forbids this layer from asserting. So
	-- it is drawn only once the server has confirmed the consume — which is
	-- why BlockShootService broadcasts `collect` to everyone *including*
	-- the popper, with no drawnLocallyBy exclusion. A stream you did not
	-- earn is never drawn rather than drawn and retracted.
	SkillVisuals.spawnEffectAtPoint(blockPos, VfxConfig.resolveBlockPopId(color))
end

-- The consume was refused. Give the letter back.
--
-- Every rejection rolls back identically. The client does not need to
-- know whether it lost a race, tripped the rate limiter or sent something
-- malformed — it needs one bit, that the letter did not land.
local function onRejected(requestId: any)
	if typeof(requestId) ~= "number" then return end
	local entry = pending[requestId]
	if not entry then
		-- Already expired, or a reply for something we never sent. Doing
		-- nothing is right: with no record of an optimistic append there is
		-- nothing owed back, and guessing would confiscate an earned letter.
		--
		-- Logged rather than silent. This branch is indistinguishable from
		-- "the rollback is broken" when you are looking at a buffer that
		-- still has a phantom letter in it, and a silent return cost a
		-- diagnostic cycle during 5.7 stage 4. If this ever fires in real
		-- play it means PENDING_TTL_SEC is too short for the round trip.
		log:warn(string.format(
			"rejection for request %d had no pending entry — expired (TTL %ds) or never sent",
			requestId, PENDING_TTL_SEC))
		return
	end
	pending[requestId] = nil

	local removed = session.wordBuffer:removeLastMatching(entry.letter, entry.color)
	fizzleSound:Play()
	log:info(string.format(
		"consume rejected — rolled back '%s' (%s), tile found: %s",
		entry.letter, entry.color, tostring(removed)
	))
end

consumeRemote.OnClientEvent:Connect(onRejected)

-- Retire entries the server never refused, so the table cannot grow
-- across a long round. Every successful pop leaves one behind by design.
task.spawn(function()
	while true do
		task.wait(PENDING_SWEEP_SEC)
		local now = os.clock()
		for requestId, entry in pending do
			if now - entry.firedAt > PENDING_TTL_SEC then
				pending[requestId] = nil
			end
		end
	end
end)

-- gameProcessedEvent is load-bearing, not defensive.
--
-- Tool.Activated used to suppress clicks that landed on GUI for free.
-- A raw InputBegan handler does not, and this game's mouse is unlocked
-- during play with a click-driven HUD — SpellMenuGui's spell buttons,
-- DashButtonGui, the buffer's tap-to-swap slots. Without this guard
-- every spell cast would also pop whatever block happened to be behind
-- the button, on every press.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	-- input.Position rather than UserInputService:GetMouseLocation(): the
	-- only correct answer for a touch, which has no cursor to read.
	--
	-- These are NOT the same value for a mouse click — they differ by the
	-- GUI inset — and assuming they were is what broke aim when this
	-- replaced LetterBlaster. tryPop pairs this with ScreenPointToRay;
	-- see the note there before changing either.
	tryPop(Vector2.new(input.Position.X, input.Position.Y))
end)

log:info("BlockTapController started — tap a block to pop it")
