--!strict

----------------------------------------------------------------------
-- Telegraph (boss pose layer)
----------------------------------------------------------------------
-- Stage 11b — a body tell per attack from PendingAttack / WindupEndsAt, and
-- leaning toward EatingAt (wiki/design/boss-movement.md). See PoseTypes for
-- the contract: write only into `pose`; own any instances you make in
-- attach/detach (here, the slam's ground shadow).
--
-- Every tell is a function of `r`, the seconds left until WindupEndsAt
-- (workspace:GetServerTimeNow() time): it builds before r = 0, peaks at it,
-- and releases after it. The layer remembers the last attack it was told
-- about, so the release still plays after the server clears PendingAttack on
-- entering Cooldown.
--
--   FireballVolley  draws back and up, lobes glow red, recoils on each shot
--   GroundSlam      rises, hangs trembling, drops with stretch, lands in a
--                   squash; a shadow grows on the ground meanwhile
--   SporeLob        swells, gulps twice, then spits (violet, never the
--                   volley's red: run TO the spores, do not dodge)
--   Eating          leans toward EatingAt, the stem reaches out
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local PoseTypes = require(script.Parent.PoseTypes)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect = require(ReplicatedStorage.Shared.Vfx.spawnEffect)
local C = require(script.Parent.TelegraphConstants)

local TAU = 2 * math.pi

type Remembered = {
	attack: string?,
	endsAt: number,
	-- Where the slam's shadow lies, found once when a slam is first seen.
	groundY: number?,
}

type State = {
	model: Model,
	shadow: Part,
	remembered: Remembered,
	-- Eating lean, smoothed 0..1, and the last letter position it leaned at.
	eatWeight: number,
	eatPoint: Vector3?,
}

-- ── Timing, read from the config the server runs on ──────────────────

local function brainSpec(): any
	return (BossConfig.BOSS_TYPES :: any)[BossConfig.DEFAULT_TYPE]
end

local function volleyTiming(): (number, number)
	local skill: any = brainSpec().skills[BossConstants.VOLLEY_ATTACK]
	local params: any = skill and skill.deliveryParams
	local count = if params and params.count then params.count else C.FALLBACK_VOLLEY_SHOT_COUNT
	local interval = if params and params.staggerSec then params.staggerSec else C.FALLBACK_VOLLEY_SHOT_INTERVAL_SEC
	return count, interval
end

-- Total warning of a slam (the boss's prep plus the slam's own windup) and
-- its radius.
local function slamTiming(): (number, number)
	local spec = brainSpec()
	local skill: any = spec.skills.GroundSlam
	local params: any = skill and skill.deliveryParams
	local prep: any = spec.attackPrepSec and spec.attackPrepSec.GroundSlam
	local total = C.FALLBACK_SLAM_TOTAL_WARNING_SEC
	if prep and params and params.windupSec then
		total = prep + params.windupSec
	end
	local radius = if params and params.radius then params.radius else C.FALLBACK_SLAM_RADIUS_STUDS
	return total, radius
end

-- ── Easing ───────────────────────────────────────────────────────────

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function easeOut(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

local function easeIn(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x
end

-- ── Tells ────────────────────────────────────────────────────────────
-- Each takes `r` (seconds until WindupEndsAt; negative once it has landed)
-- and writes into `pose`.

local function volleyTell(pose: PoseTypes.Pose, r: number)
	local count, interval = volleyTiming()
	local firingSec = count * interval
	local t = -r
	local draw: number
	local kick = 0
	if r > 0 then
		draw = smooth(1 - r / C.VOLLEY_DRAW_SEC)
	elseif t < firingSec then
		draw = C.VOLLEY_HOLD
		local u = (t % interval) / interval
		kick = (1 - u) ^ 2
	else
		draw = C.VOLLEY_HOLD * (1 - smooth((t - firingSec) / C.RELEASE_SEC))
	end
	if draw <= 0 then
		return
	end

	pose.rootOffset = pose.rootOffset
		* CFrame.new(0, C.VOLLEY_RISE_STUDS * draw, C.VOLLEY_BACK_STUDS * draw + C.VOLLEY_RECOIL_STUDS * kick)
		* CFrame.Angles(C.VOLLEY_TILT_RADIANS * draw + C.VOLLEY_RECOIL_TILT_RADIANS * kick, 0, 0)
	pose.motionScale *= 1 - (1 - C.VOLLEY_IDLE_MOTION_LEFT) * draw
	pose.synapseGlow = math.max(pose.synapseGlow, draw)
	pose.coreLightScale *= 1 + C.VOLLEY_CORE_LIGHT_BOOST * draw
	pose.coreLightColor = C.VOLLEY_GLOW_COLOR
	pose.tint = C.VOLLEY_GLOW_COLOR
	pose.tintAlpha = math.max(pose.tintAlpha, C.VOLLEY_TINT_ALPHA * draw)
	pose.neuronSpeedScale *= 1 + C.VOLLEY_NEURON_SPEED_BOOST * draw
	pose.neuronRadiusScale *= 1 - (1 - C.VOLLEY_NEURON_RADIUS_SCALE) * draw
end

-- The slam warning's sound, started so that it ends on the landing.
-- `left` is the seconds until WindupEndsAt when this client first sees
-- the slam. Seen early, the sound waits; seen late (replication lag, or a
-- player walking in mid-warning), it starts part-way through its file.
local function playSlamRise(root: BasePart, left: number)
	local effect = VfxConfig.EFFECTS[C.SLAM_RISE_EFFECT_ID]
	if not effect or left < C.SLAM_RISE_SOUND_MIN_LEFT_SEC then return end
	local early = left - C.SLAM_RISE_SOUND_SEC
	if early > 0 then
		task.delay(early, function()
			if root.Parent then
				spawnEffect(effect, root)
			end
		end)
	else
		spawnEffect(effect, root, -early)
	end
end

-- Returns how far the slam is through its warning (0..1) for the shadow.
local function slamTell(pose: PoseTypes.Pose, r: number, clock: number): number
	local total = slamTiming()
	local t = -r
	local riseP = easeOut((total - r) / C.SLAM_RISE_SEC)
	local dropP = if r > 0 then easeIn(1 - r / C.SLAM_DROP_SEC) else 1
	local lift = C.SLAM_LIFT_STUDS * riseP * (1 - dropP)
	-- Hanging: risen, not yet dropping.
	local hang = riseP * (1 - dropP)

	local scale = Vector3.one:Lerp(C.SLAM_RISE_SCALE, riseP * (1 - dropP))
	scale = scale:Lerp(C.SLAM_DROP_SCALE, dropP)
	local sink = 0
	local neuron = 1 - (1 - C.SLAM_NEURON_RADIUS_SCALE) * riseP
	if r <= 0 then
		-- Landed: squash, sink, and the neurons burst out, all settling.
		local settle = math.clamp(t / C.SLAM_LAND_RECOVER_SEC, 0, 1)
		local impact = (1 - settle) ^ 2
		scale = Vector3.one:Lerp(C.SLAM_LAND_SCALE, impact)
		sink = C.SLAM_LAND_SINK_STUDS * impact
		neuron = 1 + (C.SLAM_LAND_NEURON_RADIUS_SCALE - 1) * impact
		lift = 0
		hang = 0
	end

	local quiver = math.sin(clock * C.SLAM_QUIVER_HZ * TAU) * C.SLAM_QUIVER_STUDS * hang
	pose.rootOffset = pose.rootOffset * CFrame.new(quiver, lift - sink, 0)
	pose.lobeScale = pose.lobeScale * scale
	pose.motionScale *= 1 - riseP * (r > 0 and 1 or 0)
	pose.neuronRadiusScale *= neuron
	local glow = if r > 0 then C.SLAM_GLOW * riseP else 0
	pose.synapseGlow = math.max(pose.synapseGlow, glow)
	pose.tint = C.SLAM_TINT
	pose.tintAlpha = math.max(pose.tintAlpha, C.SLAM_TINT_ALPHA * glow / C.SLAM_GLOW)
	return math.clamp((total - r) / total, 0, 1)
end

local function sporeTell(pose: PoseTypes.Pose, r: number)
	local t = -r
	local swell: number
	local pulse = 0
	if r > 0 then
		local x = math.clamp(1 - r / C.SPORE_GULP_SEC, 0, 1)
		swell = smooth(x)
		-- Gulps: a pulse train that grows with the swell.
		pulse = (1 - math.cos(TAU * C.SPORE_GULP_COUNT * x)) / 2 * x
	else
		swell = 1 - smooth(t / C.SPORE_SPIT_SEC)
	end

	local scale = Vector3.one * (1 + C.SPORE_SWELL_FRACTION * swell + C.SPORE_GULP_PULSE_FRACTION * pulse)
	local offset = CFrame.new(0, -C.SPORE_SINK_STUDS * swell, C.SPORE_HUNCH_BACK_STUDS * swell)
		* CFrame.Angles(C.SPORE_HUNCH_TILT_RADIANS * swell, 0, 0)
	local coreBoost = 1 + C.SPORE_SWELL_FRACTION * swell
	if r <= 0 and t < C.SPORE_SPIT_SEC then
		-- The spit: a lurch forward and a flattening, easing back.
		local spit = (1 - t / C.SPORE_SPIT_SEC) ^ 2
		offset = offset
			* CFrame.new(0, 0, -C.SPORE_SPIT_FORWARD_STUDS * spit)
			* CFrame.Angles(C.SPORE_SPIT_TILT_RADIANS * spit, 0, 0)
		scale = scale * Vector3.one:Lerp(C.SPORE_SPIT_SCALE, spit)
		coreBoost += C.SPORE_SPIT_CORE_LIGHT_BOOST * spit
	end

	pose.rootOffset = pose.rootOffset * offset
	pose.lobeScale = pose.lobeScale * scale
	-- The stem throbs down and out with each gulp (stemOffset can move the
	-- stem but not swell it).
	pose.stemOffset = pose.stemOffset
		* CFrame.new(0, -C.SPORE_STEM_THROB_STUDS * pulse, -C.SPORE_STEM_THROB_STUDS * pulse)
		* CFrame.Angles(-C.SPORE_STEM_THROB_TILT_RADIANS * pulse, 0, 0)
	pose.motionScale *= 1 - swell
	pose.synapseGlow = math.max(pose.synapseGlow, C.SPORE_GLOW * swell)
	pose.coreLightScale *= coreBoost
	pose.coreLightColor = C.SPORE_TINT
	pose.tint = C.SPORE_TINT
	pose.tintAlpha = math.max(pose.tintAlpha, C.SPORE_TINT_ALPHA * swell)
end

-- Leans toward the letter being eaten and reaches the stem out. `weight` is
-- the smoothed 0..1 blend; `point` the letter's world position.
-- `whip` (0..1) is how far the yank has pulled the stem back: 0 reaching out
-- toward the letter, 1 whipped back past its rest.
local function eatTell(pose: PoseTypes.Pose, ctx: PoseTypes.Context, weight: number, point: Vector3, whip: number)
	local local3 = ctx.root.CFrame:PointToObjectSpace(point)
	local flat = Vector3.new(local3.X, 0, local3.Z)
	if flat.Magnitude < C.EAT_MIN_FLAT_DISTANCE_STUDS then
		return
	end
	local dir = flat.Unit -- (x, z) in the boss's frame; -Z is forward
	-- Top toward +Z needs +X rotation; top toward +X needs -Z rotation.
	pose.rootOffset = pose.rootOffset
		* CFrame.new(dir.X * C.EAT_LEAN_FORWARD_STUDS * weight, 0, dir.Z * C.EAT_LEAN_FORWARD_STUDS * weight)
		* CFrame.Angles(dir.Z * C.EAT_LEAN_RADIANS * weight, 0, -dir.X * C.EAT_LEAN_RADIANS * weight)
	-- The stem hangs below its hinge: tip toward +X needs +Z rotation; toward
	-- -Z (forward) needs +X rotation.
	local flick = 1 - C.EAT_REACH_FLICK_FRACTION
		+ C.EAT_REACH_FLICK_FRACTION * math.sin(ctx.clock * C.EAT_REACH_HZ * TAU)
	local reach = C.EAT_STEM_REACH_RADIANS * weight * flick * (1 - whip) - C.EAT_WHIP_BACK_RADIANS * whip
	pose.stemOffset = pose.stemOffset * CFrame.Angles(-dir.Z * reach, 0, dir.X * reach)
	if weight > C.EAT_EYE_LOCK_WEIGHT then
		pose.eyeTarget = point
	end
end

-- The gulp as the letter lands. `x` is 0..1 through EAT_GULP_SEC: a quick
-- swell, then a settle.
local function gulpTell(pose: PoseTypes.Pose, x: number)
	local swell: number
	if x < C.EAT_GULP_ATTACK_FRACTION then
		swell = easeOut(x / C.EAT_GULP_ATTACK_FRACTION)
	else
		swell = 1 - smooth((x - C.EAT_GULP_ATTACK_FRACTION) / (1 - C.EAT_GULP_ATTACK_FRACTION))
	end
	pose.rootOffset = pose.rootOffset * CFrame.new(0, -C.EAT_GULP_SINK_STUDS * swell, 0)
	pose.lobeScale = pose.lobeScale * (1 + C.EAT_GULP_SWELL_FRACTION * swell)
	pose.synapseGlow = math.max(pose.synapseGlow, C.EAT_GULP_GLOW * swell)
end

-- ── Ground shadow ────────────────────────────────────────────────────

local function groundBelow(root: BasePart, model: Model): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local start = root.Position + Vector3.new(0, C.SHADOW_RAY_START_STUDS, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -C.SHADOW_RAY_DISTANCE, 0), params)
	if hit then
		return hit.Position.Y
	end
	return root.Position.Y - C.SHADOW_RAY_DISTANCE
end

local function hideShadow(shadow: Part)
	shadow.Transparency = 1
end

local function showShadow(state: State, ctx: PoseTypes.Context, grow: number, fade: number)
	local _, radius = slamTiming()
	local groundY = state.remembered.groundY
	if groundY == nil then
		groundY = groundBelow(ctx.root, ctx.model)
		state.remembered.groundY = groundY
	end
	local diameter = C.SHADOW_START_DIAMETER
		+ (radius * 2 * C.SHADOW_FULL_RADIUS_FRACTION - C.SHADOW_START_DIAMETER) * easeIn(grow)
	local shadow = state.shadow
	shadow.Size = Vector3.new(C.SHADOW_HEIGHT_STUDS, diameter, diameter)
	shadow.CFrame = CFrame.new(ctx.root.Position.X, groundY + C.SHADOW_GROUND_CLEARANCE_STUDS, ctx.root.Position.Z)
		* CFrame.Angles(0, 0, math.pi / 2)
	local dark = C.SHADOW_MAX_TRANSPARENCY + (C.SHADOW_MIN_TRANSPARENCY - C.SHADOW_MAX_TRANSPARENCY) * grow
	shadow.Transparency = dark + (1 - dark) * fade
end

-- ── The layer ────────────────────────────────────────────────────────

local function numberAttr(model: Model, name: string): number?
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

-- Seconds after WindupEndsAt that an attack's tell is still playing.
local function tailSec(attack: string): number
	if attack == BossConstants.VOLLEY_ATTACK then
		local count, interval = volleyTiming()
		return count * interval + C.RELEASE_SEC
	elseif attack == BossConstants.SPORE_LOB_ATTACK then
		return C.SPORE_SPIT_SEC
	end
	return math.max(C.SLAM_LAND_RECOVER_SEC, C.SHADOW_FADE_SEC)
end

local layer: PoseTypes.Layer = {
	name = "Telegraph",

	attach = function(model: Model): any
		local shadow = Instance.new("Part")
		shadow.Name = C.SHADOW_NAME
		shadow.Shape = Enum.PartType.Cylinder
		shadow.Anchored = true
		shadow.CanCollide = false
		shadow.CanQuery = false
		shadow.CanTouch = false
		shadow.CastShadow = false
		shadow.Material = Enum.Material.SmoothPlastic
		shadow.Color = C.SHADOW_COLOR
		shadow.Transparency = 1
		shadow.Parent = model
		local state: State = {
			model = model,
			shadow = shadow,
			remembered = { attack = nil, endsAt = 0, groundY = nil },
			eatWeight = 0,
			eatPoint = nil,
		}
		return state
	end,

	apply = function(raw: any, ctx: PoseTypes.Context, pose: PoseTypes.Pose)
		local state = raw :: State
		local model = ctx.model
		local memory = state.remembered

		-- What the server last said is coming.
		local pending = model:GetAttribute(BossConstants.PENDING_ATTACK_ATTRIBUTE)
		local endsAt = numberAttr(model, BossConstants.WINDUP_ENDS_AT_ATTRIBUTE)
		if typeof(pending) == "string" and endsAt then
			if memory.attack ~= pending or memory.endsAt ~= endsAt then
				memory.attack = pending
				memory.endsAt = endsAt
				memory.groundY = nil
				-- Once per slam: this branch runs only when a new windup is
				-- first seen.
				if pending == C.SLAM_ATTACK and ctx.alive then
					playSlamRise(ctx.root, endsAt - ctx.serverNow)
				end
			end
		end
		local attack = memory.attack
		if attack and ctx.serverNow > memory.endsAt + tailSec(attack) then
			memory.attack = nil
			attack = nil
		end

		-- A dead boss is posed by the death sequence (stage 11d), not by tells.
		local shadowShown = false
		if attack and ctx.alive then
			local r = memory.endsAt - ctx.serverNow
			if attack == BossConstants.VOLLEY_ATTACK then
				volleyTell(pose, r)
			elseif attack == BossConstants.SPORE_LOB_ATTACK then
				sporeTell(pose, r)
			elseif attack == C.SLAM_ATTACK then
				local grow = slamTell(pose, r, ctx.clock)
				local fade = if r > 0 then 0 else math.clamp(-r / C.SHADOW_FADE_SEC, 0, 1)
				if fade < 1 then
					showShadow(state, ctx, grow, fade)
					shadowShown = true
				end
			end
		end
		if not shadowShown then
			hideShadow(state.shadow)
		end

		-- Eating runs whatever else the boss is doing.
		local eating = model:GetAttribute(BossConstants.EATING_AT_ATTRIBUTE)
		if typeof(eating) == "Vector3" and ctx.alive then
			state.eatPoint = eating
		end
		local goal = if typeof(eating) == "Vector3" and ctx.alive then 1 else 0
		state.eatWeight += (goal - state.eatWeight) * (1 - math.exp(-C.EAT_BLEND_RATE * ctx.dt))
		local point = state.eatPoint
		-- The yank and the landing, from the times the server published. The
		-- times survive an eaten letter (see EAT_SNAP_AT_ATTRIBUTE), so the
		-- gulp can play after EatingAt is gone.
		local snapAt = numberAttr(model, BossConstants.EAT_SNAP_AT_ATTRIBUTE)
		local landsAt = numberAttr(model, BossConstants.EAT_LANDS_AT_ATTRIBUTE)
		local whip = 0
		if ctx.alive and snapAt and landsAt and landsAt > snapAt then
			if ctx.serverNow >= landsAt then
				local x = (ctx.serverNow - landsAt) / C.EAT_GULP_SEC
				if x < 1 then
					whip = 1 - smooth(x)
					gulpTell(pose, x)
				end
			elseif ctx.serverNow >= snapAt then
				whip = easeOut((ctx.serverNow - snapAt) / (landsAt - snapAt))
			end
		end
		if point and state.eatWeight > C.EAT_MIN_WEIGHT then
			eatTell(pose, ctx, state.eatWeight, point, whip)
		end
	end,

	detach = function(raw: any)
		local state = raw :: State
		if state.shadow then
			state.shadow:Destroy()
		end
	end,
}

return layer
