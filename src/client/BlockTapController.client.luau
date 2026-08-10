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

	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
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

	local appended = session.wordBuffer:append(letter, color)
	if not appended then
		fizzleSound:Play()
		log:info(string.format("buffer rejected '%s' (%s)", letter, color))
		return
	end

	consumeRemote:FireServer(block)
	log:info(string.format("popped %s (%s)", letter, color))
end

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
	-- input.Position rather than UserInputService:GetMouseLocation():
	-- same value for a mouse click, and the only correct answer for a
	-- touch, which has no cursor to read.
	tryPop(Vector2.new(input.Position.X, input.Position.Y))
end)

log:info("BlockTapController started — tap a block to pop it")
