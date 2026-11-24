--!strict

----------------------------------------------------------------------
-- Exposed (boss pose layer)
----------------------------------------------------------------------
-- Stage 11c — the vulnerability windows (wiki/design/boss-movement.md
-- § Vulnerability windows), from ExposedUntil / StunnedUntil on the boss
-- Model (workspace:GetServerTimeNow() time, written by the server's
-- BossExposure). See PoseTypes for the contract: write only into `pose`.
--
-- The one unmistakable "hit me now" signal: while exposed the lobes swing
-- wide to bare the core, the core blazes white-gold and throbs, the synapses
-- light up, a gold wash pulses over the body and the eyes circle dizzily.
-- Stunned (after a Ground Slam) it also sinks and stops its idle motion;
-- exposed without a stun (the ward breaking) it sinks less and reels.
--
-- Each window eases in and eases out over its last CLOSE_SEC, so the body
-- is shut again as the window ends. The layer remembers the last instants it
-- was told, so the server clearing the attributes cannot snap it shut early.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local PoseTypes = require(script.Parent.PoseTypes)
local C = require(script.Parent.ExposedConstants)

local TAU = 2 * math.pi

type State = {
	model: Model,
	exposedUntil: number,
	stunnedUntil: number,
	exposedWeight: number,
	stunWeight: number,
	spinPhase: number,
}

local function readInstant(model: Model, attribute: string): number?
	local value = model:GetAttribute(attribute)
	if typeof(value) == "number" then
		return value :: number
	end
	return nil
end

-- Toward `goal`: up at OPEN_RATE, down at once (the goal itself ramps down
-- over the window's last CLOSE_SEC).
local function ease(weight: number, goal: number, dt: number): number
	if goal <= weight then
		return goal
	end
	return math.min(goal, weight + C.OPEN_RATE_PER_SEC * dt)
end

local function goalFor(untilAt: number, serverNow: number): number
	return math.clamp((untilAt - serverNow) / C.CLOSE_SEC, 0, 1)
end

local layer: PoseTypes.Layer = {
	name = "Exposed",

	attach = function(model: Model): any
		local state: State = {
			model = model,
			exposedUntil = 0,
			stunnedUntil = 0,
			exposedWeight = 0,
			stunWeight = 0,
			spinPhase = 0,
		}
		return state
	end,

	apply = function(rawState: any, ctx: PoseTypes.Context, pose: PoseTypes.Pose)
		local state = rawState :: State
		-- Keep the latest instants; a cleared attribute leaves the last one.
		local exposedUntil = readInstant(state.model, BossConstants.EXPOSED_UNTIL_ATTRIBUTE)
		if exposedUntil then
			state.exposedUntil = exposedUntil
		end
		local stunnedUntil = readInstant(state.model, BossConstants.STUNNED_UNTIL_ATTRIBUTE)
		if stunnedUntil then
			state.stunnedUntil = stunnedUntil
		end

		-- A dead boss belongs to the death ceremony.
		local alive = ctx.alive
		local exposedGoal = if alive then goalFor(state.exposedUntil, ctx.serverNow) else 0
		local stunGoal = if alive then goalFor(state.stunnedUntil, ctx.serverNow) else 0
		state.exposedWeight = ease(state.exposedWeight, exposedGoal, ctx.dt)
		state.stunWeight = ease(state.stunWeight, stunGoal, ctx.dt)

		local w = state.exposedWeight
		local stun = state.stunWeight
		if w < C.MIN_WEIGHT and stun < C.MIN_WEIGHT then
			state.spinPhase = 0
			return
		end
		state.spinPhase += C.EYE_SPIN_HZ * TAU * ctx.dt
		local t = ctx.clock

		-- Body: stuck and sunk when stunned; reeling and half-sunk when only exposed.
		local stagger = w * (1 - stun)
		local sink = C.STUN_SINK_STUDS * stun + C.STAGGER_SINK_STUDS * stagger
		local reel = math.sin(t * C.STAGGER_HZ * TAU) * C.STAGGER_ROLL_RADIANS * stagger
		pose.rootOffset = pose.rootOffset * CFrame.new(0, -sink, 0) * CFrame.Angles(0, 0, reel)
		pose.motionScale = math.min(pose.motionScale, 1 - stun)

		if w < C.MIN_WEIGHT then
			return
		end

		-- Lobes wide, fluttering: the core bared.
		local flutter = math.sin(t * C.LOBE_FLUTTER_HZ * TAU) * C.LOBE_FLUTTER_RADIANS
		pose.lobeOpen = math.max(pose.lobeOpen, (C.LOBE_OPEN_RADIANS + flutter) * w)

		-- Dizzy eyes: the gaze circles its target.
		local spin = C.EYE_SPIN_RADIANS * w
		pose.eyeUnclamped = true
		pose.eyeOffset = pose.eyeOffset
			* CFrame.Angles(math.cos(state.spinPhase) * spin, math.sin(state.spinPhase) * spin, 0)

		-- The core blazes and throbs.
		local throb = 1 + math.sin(t * C.CORE_THROB_HZ * TAU) * C.CORE_THROB_SHARE
		pose.coreLightScale = pose.coreLightScale * (1 + C.CORE_LIGHT_BOOST * w * throb)
		if w >= C.CORE_COLOR_FROM_WEIGHT then
			pose.coreLightColor = C.CORE_LIGHT_COLOR
		end
		pose.synapseGlow = math.max(pose.synapseGlow, C.SYNAPSE_GLOW * w)

		-- A gold wash pulsing over the body.
		local pulse = (math.sin(t * C.TINT_PULSE_HZ * TAU) + 1) / 2
		pose.tint = C.TINT_COLOR
		pose.tintAlpha = (C.TINT_ALPHA_MIN + (C.TINT_ALPHA_MAX - C.TINT_ALPHA_MIN) * pulse) * w
	end,

	detach = function(_state: any) end,
}

return layer
