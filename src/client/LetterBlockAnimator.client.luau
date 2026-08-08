----------------------------------------------------------------------
-- LetterBlockAnimator
----------------------------------------------------------------------
-- Client-only visual animator for floating letter blocks. Bobs the
-- block on a vertical sine and slowly rotates it around its Y axis,
-- per the LetterBlock design (see wiki/systems/LetterBlock.md).
--
-- Hooked to CollectionService tag = LetterBlocks.TAG. Each block
-- gets a random phase offset on track so the arena doesn't bob in
-- unison.
--
-- Also owns the spawn-in intro. The spawner refills the arena the
-- instant a block is consumed, so without an intro a replacement
-- block snaps into existence at full size next to the one the player
-- just shot. The intro scales it up on a Back/Out curve (overshoot,
-- then settle) while fading it in, so a refill reads as arriving
-- rather than teleporting.
--
-- The intro lives here rather than in its own controller because this
-- module already owns each block's transform every frame — a second
-- system writing scale/transparency would fight it (see
-- wiki/concepts/SingleOwnership.md).
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

local NEAR_THRESHOLD_STUDS = 60
local FAR_THRESHOLD_STUDS  = 150
local N_BUCKETS             = 4

local BOB_AMPLITUDE_STUDS = 0.5
local BOB_PERIOD_SECONDS = 1.5
local ROTATION_DEGREES_PER_SECOND = 6

local TAU = math.pi * 2
local BOB_FREQUENCY = TAU / BOB_PERIOD_SECONDS
local ROTATION_RADIANS_PER_SECOND = math.rad(ROTATION_DEGREES_PER_SECOND)

----------------------------------------------------------------------
-- Spawn-in intro tunables
----------------------------------------------------------------------

local INTRO_DURATION_SECONDS = 0.35

-- ±fraction of jitter on the duration. A consumed block triggers one
-- refill, but a joining player can receive a whole arena at once —
-- jittered durations keep that from reading as a single synchronised
-- inflate.
local INTRO_DURATION_JITTER = 0.15

-- Model:ScaleTo rejects zero, and a hair of starting size reads as
-- "materialising" rather than "growing from nothing".
local INTRO_START_SCALE_FRACTION = 0.08

-- Opacity resolves partway through so the block is legible while the
-- tail of the scale curve is still settling.
local INTRO_FADE_FRACTION = 0.55

-- Back/Out overshoots past the final scale and eases back — the pop.
-- Quad/Out on opacity, which must not overshoot (transparency clamps).
local INTRO_SCALE_EASING_STYLE = Enum.EasingStyle.Back
local INTRO_FADE_EASING_STYLE = Enum.EasingStyle.Quad
local INTRO_EASING_DIRECTION = Enum.EasingDirection.Out

local FULLY_TRANSPARENT = 1
local CUBE_CHILD_NAME = "Cube"

local log = Logger.new("LetterBlockAnimator")

-- One numeric property to drive from fully transparent back to the
-- value the block replicated in with. Captured per instance so the
-- intro restores authored values instead of assuming zero.
type FadeTarget = {
	instance: Instance,
	property: string,
	finalValue: number,
}

type Intro = {
	elapsed: number,
	duration: number,
	startScale: number,
	finalScale: number,
	fades: { FadeTarget },
	emitters: { ParticleEmitter },
}

type State = {
	basePosition: Vector3,
	phaseOffset: number,
	rotation: number,
	bucket: number,
	intro: Intro?,
}

local trackedBlocks: { [Model]: State } = {}

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

----------------------------------------------------------------------
-- Intro construction
----------------------------------------------------------------------

local function collectFades(block: Model): { FadeTarget }
	local fades: { FadeTarget } = {}

	local cube = block:FindFirstChild(CUBE_CHILD_NAME)
	if cube and cube:IsA("BasePart") then
		table.insert(fades, {
			instance = cube,
			property = "Transparency",
			finalValue = cube.Transparency,
		})
	end

	-- The letter glyph is a TextLabel per cube face. Stroke fades with
	-- the text; leaving it opaque would draw a black outline around an
	-- invisible letter.
	for _, descendant in ipairs(block:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			table.insert(fades, {
				instance = descendant,
				property = "TextTransparency",
				finalValue = descendant.TextTransparency,
			})
			table.insert(fades, {
				instance = descendant,
				property = "TextStrokeTransparency",
				finalValue = descendant.TextStrokeTransparency,
			})
		end
	end

	return fades
end

-- The ambient mana emitter is rate-based, so at intro scale it would
-- spit sparkles out of a near-point volume before the block exists.
-- Silence it for the intro and switch it back on at the end.
local function collectEmitters(block: Model): { ParticleEmitter }
	local emitters: { ParticleEmitter } = {}
	for _, descendant in ipairs(block:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") and descendant.Enabled then
			table.insert(emitters, descendant)
			descendant.Enabled = false
		end
	end
	return emitters
end

local function buildIntro(block: Model): Intro?
	-- No cube means no visual to fade; let the block appear as-is
	-- rather than half-animating a malformed prefab.
	local cube = block:FindFirstChild(CUBE_CHILD_NAME)
	if not (cube and cube:IsA("BasePart")) then
		return nil
	end

	local finalScale = block:GetScale()
	local jitter = 1 + (math.random() * 2 - 1) * INTRO_DURATION_JITTER

	return {
		elapsed = 0,
		duration = INTRO_DURATION_SECONDS * jitter,
		startScale = finalScale * INTRO_START_SCALE_FRACTION,
		finalScale = finalScale,
		fades = collectFades(block),
		emitters = collectEmitters(block),
	}
end

local function settleIntro(block: Model, intro: Intro)
	block:ScaleTo(intro.finalScale)
	for _, target in ipairs(intro.fades) do
		(target.instance :: any)[target.property] = target.finalValue
	end
	for _, emitter in ipairs(intro.emitters) do
		emitter.Enabled = true
	end
end

local function applyIntro(block: Model, intro: Intro, alpha: number)
	if alpha >= 1 then
		settleIntro(block, intro)
		return
	end

	local scaleAlpha = TweenService:GetValue(alpha, INTRO_SCALE_EASING_STYLE, INTRO_EASING_DIRECTION)
	-- Back/Out overshoots above 1 by design; clamp only the low end so
	-- a negative sample can never reach ScaleTo, which rejects it.
	local scale = math.max(intro.startScale, lerp(intro.startScale, intro.finalScale, scaleAlpha))
	block:ScaleTo(scale)

	local fadeAlpha = TweenService:GetValue(
		math.min(alpha / INTRO_FADE_FRACTION, 1),
		INTRO_FADE_EASING_STYLE,
		INTRO_EASING_DIRECTION
	)
	for _, target in ipairs(intro.fades) do
		(target.instance :: any)[target.property] =
			lerp(FULLY_TRANSPARENT, target.finalValue, fadeAlpha)
	end
end

----------------------------------------------------------------------
-- Tracking
----------------------------------------------------------------------

local function track(block: Instance, withIntro: boolean)
	if not block:IsA("Model") then return end
	if trackedBlocks[block] then return end

	local intro = if withIntro then buildIntro(block) else nil

	trackedBlocks[block] = {
		basePosition = block:GetPivot().Position,
		phaseOffset = math.random() * BOB_PERIOD_SECONDS,
		rotation = 0,
		bucket = math.random(0, N_BUCKETS - 1),
		intro = intro,
	}

	-- Apply frame zero here rather than waiting for the next Heartbeat.
	-- One frame at full size and full opacity is exactly the snap this
	-- intro exists to remove.
	if intro then
		applyIntro(block, intro, 0)
	end
end

local function onRemoved(block: Instance)
	if not block:IsA("Model") then return end
	local state = trackedBlocks[block]
	if not state then return end
	-- Phase C: spawn collect-pop emitter at state.basePosition here.
	trackedBlocks[block] = nil
end

-- Blocks already present when this script starts are part of a settled
-- arena, not an arrival — introing them would inflate the whole field
-- in the player's face on join.
for _, block in ipairs(CollectionService:GetTagged(LetterBlocks.TAG)) do
	track(block, false)
end

CollectionService:GetInstanceAddedSignal(LetterBlocks.TAG):Connect(function(block: Instance)
	track(block, true)
end)
CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG):Connect(onRemoved)

local frameCount = 0

RunService.Heartbeat:Connect(function(dt)
	frameCount = (frameCount + 1) % N_BUCKETS

	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local playerPos: Vector3? = if hrp then (hrp :: BasePart).Position else nil

	local now = os.clock()
	for block, state in pairs(trackedBlocks) do
		if block.Parent then
			state.rotation = (state.rotation + ROTATION_RADIANS_PER_SECOND * dt) % TAU

			local intro = state.intro
			if intro then
				intro.elapsed += dt
				local alpha = math.min(intro.elapsed / intro.duration, 1)
				applyIntro(block, intro, alpha)
				if alpha >= 1 then
					state.intro = nil
				end
			end

			local shouldUpdate: boolean
			if intro then
				-- Distance culling holds a block's pivot still for whole
				-- frames. That is invisible on a settled block and very
				-- visible on one mid-pop, so the intro opts out.
				shouldUpdate = true
			elseif playerPos then
				local dist = (state.basePosition - playerPos).Magnitude
				if dist > FAR_THRESHOLD_STUDS then
					shouldUpdate = false
				elseif dist > NEAR_THRESHOLD_STUDS then
					shouldUpdate = state.bucket == frameCount
				else
					shouldUpdate = true
				end
			else
				shouldUpdate = true
			end

			if shouldUpdate then
				local bobOffset = math.sin((now + state.phaseOffset) * BOB_FREQUENCY) * BOB_AMPLITUDE_STUDS
				block:PivotTo(
					CFrame.new(state.basePosition + Vector3.new(0, bobOffset, 0))
					* CFrame.Angles(0, state.rotation, 0)
				)
			end
		else
			trackedBlocks[block] = nil
		end
	end
end)

log:info("LetterBlockAnimator started")
