--!strict

----------------------------------------------------------------------
-- Ceremony (boss pose layer)
----------------------------------------------------------------------
-- Stage 11d (wiki/design/boss-movement.md). Three beats, all client-side:
--
--   Entrance  the boss is dropped onto its BossPoint. While it falls the
--             body holds still, lobes shut, eyes on the ground; on landing
--             it squashes on a spring, the core flares, and the eyes snap
--             up and look left, right, then at the room.
--   Ward      while WardUp is set the lobes clamp shut and shell plates
--             cover the brain; each time WardLettersLeft drops one plate
--             blows off, and when WardUp clears the rest go.
--   Death     deflates, spins faster, glares, then bursts into chunks, a
--             flash and a ring, and the body vanishes. The debris outlives
--             the model, so a model destroyed early still gets its burst.
--
-- See PoseTypes for the contract: write only into `pose`; own any
-- instances you make in attach/detach. Two writes go beyond the Pose
-- because it has no field for them, both client-only and only after the
-- burst: the body's LocalTransparencyModifier and its beams' / lights'
-- Enabled.
----------------------------------------------------------------------

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local C = require(script.Parent.CeremonyConstants)
local PoseTypes = require(script.Parent.PoseTypes)

local TAU = 2 * math.pi
local BRAIN_ROOT_NAME = "BrainRoot"
local CORE_NAME = "Core"
local LOBE_NAME = "LeftLobe"

type Plate = {
	part: Part,
	weld: Weld,
	offset: Vector3,
	phase: number,
}

type State = {
	model: Model,
	-- entrance
	entranceDone: boolean,
	attachedAt: number,
	airborne: boolean,
	maxFall: number,
	landedAt: number?,
	strength: number,
	spring: number,
	springVelocity: number,
	-- ward
	plates: { Plate },
	wardInitial: number,
	platesRaised: boolean,
	-- death
	deathAt: number?,
	spin: number,
	burst: boolean,
	lastPosition: Vector3,
}

local function brainRootOf(model: Model): BasePart?
	local part = model:FindFirstChild(BRAIN_ROOT_NAME)
	return if part and part:IsA("BasePart") then part else nil
end

local function easeOut(k: number): number
	return 1 - (1 - k) ^ 2
end

local function fxFolder(): Folder
	local folder = workspace:FindFirstChild(C.FX_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = C.FX_FOLDER_NAME
	made.Parent = workspace
	return made
end

local function newFxPart(size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Parent = parent
	return part
end

----------------------------------------------------------------------
-- Ward plates
----------------------------------------------------------------------

local function createPlate(state: State, brainRoot: BasePart, index: number)
	local spec = C.WARD_PLATES[index]
	local part = Instance.new("Part")
	part.Name = "WardPlate" .. index
	part.Size = spec.size
	part.Material = Enum.Material.Neon
	part.Color = C.WARD_PLATE_COLOR
	part.Transparency = C.WARD_PLATE_TRANSPARENCY
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.CFrame = brainRoot.CFrame * CFrame.new(spec.offset)
	local weld = Instance.new("Weld")
	weld.Part0 = brainRoot
	weld.Part1 = part
	weld.C0 = CFrame.new(spec.offset)
	weld.Parent = part
	part.Parent = state.model
	table.insert(state.plates, {
		part = part,
		weld = weld,
		offset = spec.offset,
		phase = index,
	})
end

-- Throws a plate off the brain: it is anchored where it hung, flies out
-- along its own direction, spins, fades and is destroyed. Independent of
-- the layer from here on.
local function blowOff(brainRoot: BasePart, plate: Plate)
	local part = plate.part
	local start = part.CFrame
	plate.weld:Destroy()
	part.Anchored = true
	part.Parent = fxFolder()
	local outward = brainRoot.CFrame:VectorToWorldSpace(plate.offset.Unit)
	local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	if axis.Magnitude < 0.1 then
		axis = Vector3.yAxis
	end
	local goal = (start + outward * C.PLATE_FLIGHT_DISTANCE + Vector3.new(0, C.PLATE_FLIGHT_LIFT, 0))
		* CFrame.fromAxisAngle(axis.Unit, C.PLATE_SPIN_RADIANS)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(C.PLATE_FLIGHT_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goal, Transparency = 1 }
	)
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	tween:Play()
end

-- Keeps `keep` plates; blows the rest off, last first.
local function trimPlates(state: State, keep: number)
	local brainRoot = brainRootOf(state.model)
	while #state.plates > keep do
		local plate = table.remove(state.plates) :: Plate
		if brainRoot then
			blowOff(brainRoot, plate)
		else
			plate.part:Destroy()
		end
	end
end

local function applyWard(state: State, ctx: PoseTypes.Context, pose: PoseTypes.Pose)
	local up = ctx.alive and ctx.model:GetAttribute(BossConstants.WARD_UP_ATTRIBUTE) == true
	if not up then
		if #state.plates > 0 then
			trimPlates(state, 0)
		end
		state.wardInitial = 0
		state.platesRaised = false
		return
	end

	local brainRoot = brainRootOf(state.model)
	if not brainRoot then
		return
	end
	local left = ctx.model:GetAttribute(BossConstants.WARD_LETTERS_LEFT_ATTRIBUTE)
	local count = if typeof(left) == "number" then left else state.wardInitial
	state.wardInitial = math.max(state.wardInitial, count)

	local total = #C.WARD_PLATES
	local keep = if count <= 0 or state.wardInitial <= 0
		then 0
		else math.min(total, math.ceil(count / state.wardInitial * total))
	-- The first frame of a ward raises every plate that is still due.
	if not state.platesRaised and keep > 0 then
		state.platesRaised = true
		for index = 1, keep do
			createPlate(state, brainRoot, index)
		end
	end
	trimPlates(state, keep)

	for _, plate in state.plates do
		plate.part.Transparency = C.WARD_PLATE_TRANSPARENCY
			+ math.sin(ctx.clock * C.WARD_PLATE_SHIMMER_HZ * TAU + plate.phase) * C.WARD_PLATE_SHIMMER
	end

	pose.lobeOpen = 0
	pose.coreLightScale *= C.WARD_CORE_LIGHT_SCALE
	pose.synapseGlow = math.max(pose.synapseGlow, C.WARD_SYNAPSE_GLOW)
	pose.neuronSpeedScale *= C.WARD_NEURON_SPEED_SCALE
end

----------------------------------------------------------------------
-- Entrance
----------------------------------------------------------------------

-- Distance from the root down to the ground, or nil when there is none in
-- reach (the boss is high above it).
local function groundGap(ctx: PoseTypes.Context): number?
	local ignore: { Instance } = { ctx.model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(ctx.root.Position, Vector3.new(0, -C.ENTRANCE_RAY_LENGTH, 0), params)
	return if hit then ctx.root.Position.Y - hit.Position.Y else nil
end

local function isGrounded(ctx: PoseTypes.Context): boolean
	local gap = groundGap(ctx)
	local hover = ctx.humanoid.HipHeight + ctx.root.Size.Y / 2
	return gap ~= nil and gap <= hover + C.ENTRANCE_GROUND_TOLERANCE
end

local function lookAt(ctx: PoseTypes.Context, side: number): Vector3
	local cf = ctx.root.CFrame
	return ctx.root.Position
		+ cf.LookVector * C.EYES_LOOK_DISTANCE * 0.3
		+ cf.RightVector * side * C.EYES_LOOK_DISTANCE
		+ Vector3.new(0, C.EYES_LOOK_HEIGHT, 0)
end

local function applyEntrance(state: State, ctx: PoseTypes.Context, pose: PoseTypes.Pose)
	if state.entranceDone or not ctx.alive then
		return
	end
	local dt = math.min(ctx.dt, 0.1)

	if state.landedAt == nil then
		state.maxFall = math.max(state.maxFall, -ctx.root.AssemblyLinearVelocity.Y)
		local grounded = isGrounded(ctx)
		if not grounded then
			state.airborne = true
		end
		if state.airborne and grounded then
			state.landedAt = ctx.clock
			state.strength = math.clamp(state.maxFall / C.ENTRANCE_FULL_FALL_SPEED, C.ENTRANCE_MIN_STRENGTH, 1)
			state.spring = state.strength
			state.springVelocity = 0
		elseif not state.airborne then
			if ctx.clock - state.attachedAt > C.ENTRANCE_GROUND_GRACE_SEC then
				state.entranceDone = true -- already standing: nothing to land
			end
			return
		else
			-- Still falling: hold still, shut, looking down.
			pose.motionScale = 0
			pose.lobeOpen = 0
			pose.eyeTarget = ctx.root.Position + C.ENTRANCE_FALL_LOOK_DOWN
			return
		end
	end

	local landedAt = state.landedAt :: number
	local since = ctx.clock - landedAt

	-- Squash and settle: x'' = -k x - c x'; x = 1 is fully squashed, a
	-- negative x is the rebound stretch.
	local accel = -C.LANDING_SPRING_STIFFNESS * state.spring - C.LANDING_SPRING_DAMPING * state.springVelocity
	state.springVelocity += accel * dt
	state.spring += state.springVelocity * dt
	local squash = state.spring * C.LANDING_SQUASH
	pose.lobeScale *= Vector3.new(1 + squash / 2, 1 - squash, 1 + squash / 2)
	pose.rootOffset *= CFrame.new(0, -state.spring * C.LANDING_DIP_STUDS, 0)
	pose.motionScale = math.clamp(since / C.LANDING_FLARE_SEC, 0, 1)

	local flare = math.max(1 - since / C.LANDING_FLARE_SEC, 0)
	pose.coreLightScale *= 1 + (C.LANDING_FLARE_SCALE - 1) * flare * state.strength

	-- Eyes: held on the ground, then snapped up to look around.
	local lookStart = C.EYES_HOLD_SEC
	local lookEnd = lookStart + #C.EYES_LOOK_ORDER * C.EYES_LOOK_SEC
	if since < lookStart then
		pose.eyeTarget = ctx.root.Position + C.ENTRANCE_FALL_LOOK_DOWN
	elseif since < lookEnd then
		local index = math.floor((since - lookStart) / C.EYES_LOOK_SEC) + 1
		pose.eyeTarget = lookAt(ctx, C.EYES_LOOK_ORDER[math.min(index, #C.EYES_LOOK_ORDER)])
		pose.eyeUnclamped = true
	end

	local settled = math.abs(state.spring) < C.LANDING_SPRING_SETTLE and math.abs(state.springVelocity) < C.LANDING_SPRING_SETTLE
	if since >= lookEnd and settled then
		state.entranceDone = true
	end
end

----------------------------------------------------------------------
-- Death
----------------------------------------------------------------------

local function emitBurst(state: State)
	if state.burst then
		return
	end
	state.burst = true
	local origin = state.lastPosition
	local model = state.model

	local bodyColor = Color3.new(1, 1, 1)
	local lobe = model:FindFirstChild(LOBE_NAME)
	if lobe and lobe:IsA("BasePart") then
		bodyColor = lobe.Color
	end
	local coreColor = C.BURST_FLASH_COLOR
	local core = model:FindFirstChild(CORE_NAME)
	if core and core:IsA("BasePart") then
		coreColor = core.Color
	end

	local folder = fxFolder()

	-- A flash and a spray of sparks, on one invisible part.
	local fx = newFxPart(Vector3.one, folder)
	fx.Transparency = 1
	fx.Position = origin
	local light = Instance.new("PointLight")
	light.Color = C.BURST_FLASH_COLOR
	light.Range = C.BURST_FLASH_RANGE
	light.Brightness = C.BURST_FLASH_BRIGHTNESS
	light.Parent = fx
	TweenService:Create(light, TweenInfo.new(C.BURST_RING_SEC, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Color = ColorSequence.new(coreColor)
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(C.BURST_PARTICLE_LIFETIME * 0.5, C.BURST_PARTICLE_LIFETIME)
	sparks.Speed = NumberRange.new(C.BURST_PARTICLE_SPEED * 0.4, C.BURST_PARTICLE_SPEED)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, C.BURST_PARTICLE_SIZE),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = fx
	sparks:Emit(C.BURST_PARTICLE_COUNT)
	Debris:AddItem(fx, C.BURST_FX_LIFETIME_SEC)

	-- The shock ring.
	local ring = newFxPart(Vector3.one * C.BURST_RING_DIAMETER_START, folder)
	ring.Shape = Enum.PartType.Ball
	ring.Color = C.BURST_FLASH_COLOR
	ring.Transparency = C.BURST_RING_TRANSPARENCY
	ring.Position = origin
	local ringTween = TweenService:Create(
		ring,
		TweenInfo.new(C.BURST_RING_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * C.BURST_RING_DIAMETER_END, Transparency = 1 }
	)
	ringTween.Completed:Connect(function()
		ring:Destroy()
	end)
	ringTween:Play()

	-- Chunks of the body, thrown out and falling.
	local chunks = {}
	for i = 1, C.BURST_CHUNK_COUNT do
		local size = C.BURST_CHUNK_MIN_SIZE + math.random() * (C.BURST_CHUNK_MAX_SIZE - C.BURST_CHUNK_MIN_SIZE)
		local part = newFxPart(Vector3.new(size, size * (0.5 + math.random()), size), folder)
		part.Material = if i % 2 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = if i % 2 == 0 then coreColor else bodyColor
		part.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * TAU, math.random() * TAU, 0)
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5)
		if direction.Magnitude < 0.1 then
			direction = Vector3.xAxis
		end
		table.insert(chunks, {
			part = part,
			velocity = direction.Unit * C.BURST_CHUNK_SPEED * (0.5 + math.random() * 0.5)
				+ Vector3.new(0, C.BURST_CHUNK_LIFT, 0),
			spin = CFrame.Angles(math.random() * 0.2, math.random() * 0.2, math.random() * 0.2),
		})
	end
	local age = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		age += dt
		local k = math.min(age / C.BURST_CHUNK_SEC, 1)
		for _, chunk in chunks do
			chunk.velocity -= Vector3.new(0, C.BURST_GRAVITY * dt, 0)
			chunk.part.CFrame = (chunk.part.CFrame + chunk.velocity * dt) * chunk.spin
			chunk.part.Transparency = k * k
		end
		if k >= 1 then
			connection:Disconnect()
			for _, chunk in chunks do
				chunk.part:Destroy()
			end
		end
	end)

	-- The body is gone: hide it (client-only) and switch off its light and beams.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Beam") or descendant:IsA("PointLight") then
			descendant.Enabled = false
		end
	end
end

local function applyDeath(state: State, ctx: PoseTypes.Context, pose: PoseTypes.Pose)
	local dt = math.min(ctx.dt, 0.1)
	if state.deathAt == nil then
		state.deathAt = ctx.clock
	end
	local t = ctx.clock - (state.deathAt :: number)

	if t >= C.DEATH_BURST_AT_SEC then
		emitBurst(state)
		pose.lobeScale = Vector3.one * 0.01
		pose.coreLightScale = 0
		pose.tintAlpha = 0
		return
	end

	local progress = t / C.DEATH_BURST_AT_SEC
	local spinRate = C.DEATH_SPIN_START + (C.DEATH_SPIN_END - C.DEATH_SPIN_START) * progress
	state.spin += spinRate * dt
	local deflate = easeOut(math.clamp(t / C.DEATH_DEFLATE_SEC, 0, 1))
	pose.lobeScale = Vector3.one:Lerp(C.DEATH_DEFLATE_SCALE, deflate)
	pose.rootOffset = CFrame.new(0, -C.DEATH_SINK_STUDS * deflate, 0) * CFrame.Angles(0, state.spin, 0)
	pose.eyeUnclamped = true

	local charge = math.clamp((t - C.DEATH_DEFLATE_SEC) / (C.DEATH_BURST_AT_SEC - C.DEATH_DEFLATE_SEC), 0, 1)
	pose.lobeOpen = C.DEATH_LOBE_OPEN * charge
	pose.coreLightScale = 1 + (C.DEATH_CORE_LIGHT_SCALE - 1) * charge
	pose.synapseGlow = C.DEATH_SYNAPSE_GLOW * charge
	pose.neuronRadiusScale = 1 + (C.DEATH_NEURON_RADIUS_END - 1) * progress
	pose.neuronSpeedScale = 1 + (C.DEATH_NEURON_SPEED_SCALE - 1) * progress
	pose.tint = C.BURST_FLASH_COLOR
	pose.tintAlpha = C.DEATH_TINT_ALPHA * charge
end

----------------------------------------------------------------------
-- The layer
----------------------------------------------------------------------

local layer: PoseTypes.Layer = {
	name = "Ceremony",

	attach = function(model: Model): any
		local state: State = {
			model = model,
			entranceDone = false,
			attachedAt = os.clock(),
			airborne = false,
			maxFall = 0,
			landedAt = nil,
			strength = 0,
			spring = 0,
			springVelocity = 0,
			plates = {},
			wardInitial = 0,
			platesRaised = false,
			deathAt = nil,
			spin = 0,
			burst = false,
			lastPosition = model:GetPivot().Position,
		}
		return state
	end,

	apply = function(stateAny: any, ctx: PoseTypes.Context, pose: PoseTypes.Pose)
		local state = stateAny :: State
		local brainRoot = brainRootOf(state.model)
		if brainRoot and not state.burst then
			state.lastPosition = brainRoot.Position
		end

		if not ctx.alive then
			applyWard(state, ctx, pose) -- blows any plates off
			applyDeath(state, ctx, pose)
			return
		end
		applyEntrance(state, ctx, pose)
		applyWard(state, ctx, pose)
	end,

	detach = function(stateAny: any)
		local state = stateAny :: State
		-- A boss that dies and is destroyed before its burst still bursts.
		if state.deathAt ~= nil then
			emitBurst(state)
		end
		for _, plate in state.plates do
			plate.part:Destroy()
		end
		table.clear(state.plates)
	end,
}

return layer
