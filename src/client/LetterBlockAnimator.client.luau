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

-- Was 6 deg/s, which is a full turn per minute -- slow enough that the
-- eye does not register it as motion at all, so a field of blocks read
-- as static scenery.
local ROTATION_DEGREES_PER_SECOND = 28

-- ...and about a tilted axis rather than straight Y. A vertical spin
-- sweeps the same four side faces past the camera forever and keeps the
-- top and bottom permanently hidden; tilting it tumbles the block, so
-- every face takes a turn and the lighting changes across them as it
-- goes. The azimuth of the tilt is rolled per block, for the same
-- reason the bob phase is: a field turning on one shared axis reads as
-- a mechanism.
local SPIN_TILT_DEGREES = 20

local TAU = math.pi * 2
local BOB_FREQUENCY = TAU / BOB_PERIOD_SECONDS
local ROTATION_RADIANS_PER_SECOND = math.rad(ROTATION_DEGREES_PER_SECOND)
local SPIN_TILT_RADIANS = math.rad(SPIN_TILT_DEGREES)

----------------------------------------------------------------------
-- Spawn-in intro tunables
----------------------------------------------------------------------

local INTRO_DURATION_SECONDS = 0.45

-- ±fraction of jitter on the duration. A consumed block triggers one
-- refill, but a joining player can receive a whole arena at once —
-- jittered durations keep that from reading as a single synchronised
-- inflate.
local INTRO_DURATION_JITTER = 0.15

-- Model:ScaleTo rejects zero, and a hair of starting size reads as
-- "materialising" rather than "growing from nothing".
local INTRO_START_SCALE_FRACTION = 0.08

-- Opacity resolves just past the spring's first peak, so the block is
-- solid by the time it is at its biggest and the ring-down reads as
-- weight rather than as the block still arriving.
local INTRO_FADE_FRACTION = 0.45

-- Scale rides a damped harmonic — the spring:
--     y(t) = 1 - e^(-decay*t) * cos(omega*t)
-- y(0) = 0 and y(1) settles on 1, with the first peak overshooting the
-- final scale by INTRO_SPRING_OVERSHOOT before ringing back down.
--
-- Enum.EasingStyle.Back overshoots too, but its magnitude is a fixed
-- engine constant (~10%) and it only crosses the settle point once.
-- Springiness wants both of those as dials, hence the explicit curve.
local INTRO_SPRING_OVERSHOOT = 0.20

-- Half-cycles of the cosine across the intro. 3 gives the shape you
-- want from a spring: overshoot, a shallow dip under, then settle.
-- 1 degenerates to a Back-style single overshoot; 5+ starts to read as
-- rubber rather than weight.
local INTRO_SPRING_HALF_CYCLES = 3

local SPRING_OMEGA = math.pi * INTRO_SPRING_HALF_CYCLES
-- The first peak lands at omega*t = pi, where the envelope has decayed
-- to e^(-decay*pi/omega). Solving that for decay puts the peak exactly
-- on the requested overshoot instead of wherever the math happens to
-- land.
local SPRING_DECAY = -math.log(INTRO_SPRING_OVERSHOOT) * SPRING_OMEGA / math.pi

-- Quad/Out on opacity, which must not overshoot — transparency clamps.
local INTRO_FADE_EASING_STYLE = Enum.EasingStyle.Quad
local INTRO_FADE_EASING_DIRECTION = Enum.EasingDirection.Out

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
	spinAxis: Vector3,
	bucket: number,
	intro: Intro?,
}

-- Unit vector SPIN_TILT_DEGREES off vertical, at a random compass
-- bearing. Rolled once at track time so a block's tumble is a stable
-- trait rather than something that rerolls mid-life.
local function randomSpinAxis(): Vector3
	local azimuth = math.random() * TAU
	return Vector3.new(
		math.sin(SPIN_TILT_RADIANS) * math.cos(azimuth),
		math.cos(SPIN_TILT_RADIANS),
		math.sin(SPIN_TILT_RADIANS) * math.sin(azimuth)
	)
end

local trackedBlocks: { [Model]: State } = {}

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

-- Damped harmonic on [0, 1]. Rises past 1, rings back through it, and
-- lands on ~1. Slightly overshoots 1 at t = 1 by the residual envelope
-- (well under a percent), which settleIntro snaps away.
local function springAlpha(alpha: number): number
	return 1 - math.exp(-SPRING_DECAY * alpha) * math.cos(SPRING_OMEGA * alpha)
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
	--
	-- The face border (a UIStroke per SurfaceGui, see LetterBlocks) has
	-- the same failure at block scale: it is not a Transparency the
	-- Cube fade reaches, so an unfaded one draws a full-opacity dark
	-- wireframe box around a block that has not arrived yet.
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
		elseif descendant:IsA("UIStroke") then
			table.insert(fades, {
				instance = descendant,
				property = "Transparency",
				finalValue = descendant.Transparency,
			})
		elseif descendant:IsA("Frame") then
			-- The face panel is an opaque plate and would otherwise hang
			-- in the air through the whole intro. Captured rather than
			-- assumed: the border Frame is also a Frame and is authored
			-- fully transparent, so it lerps 1 -> 1 and stays a no-op.
			table.insert(fades, {
				instance = descendant,
				property = "BackgroundTransparency",
				finalValue = descendant.BackgroundTransparency,
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

	-- The spring exceeds 1 by design; clamp only the low end so a
	-- negative sample can never reach ScaleTo, which rejects it.
	local scale = math.max(intro.startScale, lerp(intro.startScale, intro.finalScale, springAlpha(alpha)))
	block:ScaleTo(scale)

	local fadeAlpha = TweenService:GetValue(
		math.min(alpha / INTRO_FADE_FRACTION, 1),
		INTRO_FADE_EASING_STYLE,
		INTRO_FADE_EASING_DIRECTION
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
		spinAxis = randomSpinAxis(),
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
					* CFrame.fromAxisAngle(state.spinAxis, state.rotation)
				)
			end
		else
			trackedBlocks[block] = nil
		end
	end
end)

log:info("LetterBlockAnimator started")
