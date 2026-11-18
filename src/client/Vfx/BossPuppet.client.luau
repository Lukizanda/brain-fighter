--!strict

----------------------------------------------------------------------
-- BossPuppet
----------------------------------------------------------------------
-- Animates a boss's body on this client (wiki/design/boss-movement.md).
-- The server owns where the boss is and which way it faces; this script
-- only writes the body's Motor6D.Transform values, the lobes' mesh Scale,
-- the core light and synapse beams, and its own hit-flash Highlight. None
-- of that replicates, so the motion costs nothing on the network and
-- cannot fight the server.
--
-- Single ownership (wiki/concepts/SingleOwnership.md): nothing else writes
-- any of those.
--
-- Base motion (stage 11a):
--   idle    hover bob, breathing lobes, pulsing core, orbiting neurons,
--           eyes on the nearest player
--   moving  leans into its travel, bobs faster, the stem trails behind
--   hit     a wobble that grows with the damage, a white flash, the lobes
--           flinch open
--   frozen  every joint holds its pose
--
-- Pose layers (BossPoses/): Telegraph (11b), Exposed (11c), Ceremony (11d)
-- each add to a neutral Pose every frame (see BossPoses/PoseTypes); the
-- puppet draws the base motion plus that Pose.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BrainBody = require(ReplicatedStorage.Shared.Boss.BrainBody)
local C = require(ReplicatedStorage.Shared.Boss.BossPuppetConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local PoseTypes = require(script.Parent.BossPoses.PoseTypes)

-- Applied in this order; a later layer may override an earlier one.
local LAYERS: { PoseTypes.Layer } = {
	require(script.Parent.BossPoses.Telegraph) :: PoseTypes.Layer,
	require(script.Parent.BossPoses.Exposed) :: PoseTypes.Layer,
	require(script.Parent.BossPoses.Ceremony) :: PoseTypes.Layer,
}

local log = Logger.new("BossPuppet")

local TAU = 2 * math.pi
local J = BrainBody.Joint

type Puppet = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	joints: { [string]: Motor6D },
	neurons: { Motor6D },
	lobeMeshes: { { mesh: SpecialMesh, base: Vector3 } },
	coreLight: PointLight?,
	coreLightColor: Color3,
	synapses: { { beam: Beam, width: number } },
	layerStates: { any },
	pose: PoseTypes.Pose,
	flash: Highlight?,
	flashUntil: number,
	seed: number,
	bobPhase: number,
	neuronPhase: number,
	pitch: number,
	roll: number,
	wobble: number,
	wobbleVelocity: number,
	lastHealth: number,
	eyeLook: { [string]: CFrame },
	connections: { RBXScriptConnection },
}

local puppets: { [Model]: Puppet } = {}

-- Exponential approach of `current` toward `goal` over `dt`.
local function approach(current: number, goal: number, dt: number): number
	return goal + (current - goal) * math.exp(-C.SMOOTHING_RATE * dt)
end

local function findJoints(model: Model): ({ [string]: Motor6D }, { Motor6D })
	local joints: { [string]: Motor6D } = {}
	local neurons: { Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			if string.sub(d.Name, 1, #BrainBody.NEURON_JOINT_PREFIX) == BrainBody.NEURON_JOINT_PREFIX then
				table.insert(neurons, d)
			else
				joints[d.Name] = d
			end
		end
	end
	table.sort(neurons, function(a, b)
		return a.Name < b.Name
	end)
	return joints, neurons
end

-- Every joint the puppet drives must be there before it starts: with
-- streaming the body can arrive a part at a time.
local function hasAllJoints(joints: { [string]: Motor6D }, neurons: { Motor6D }): boolean
	for _, name in J do
		if not joints[name] then
			return false
		end
	end
	return #neurons == BrainBody.NEURON_COUNT
end

local function onHealthChanged(puppet: Puppet, health: number)
	local lost = puppet.lastHealth - health
	puppet.lastHealth = health
	if lost <= 0 then
		return
	end
	local strength = math.min(lost / C.WOBBLE_FULL_DAMAGE, 1)
	puppet.wobbleVelocity += C.WOBBLE_KICK * C.WOBBLE_STIFFNESS ^ 0.5 * strength
	puppet.flashUntil = os.clock() + C.HIT_FLASH_SEC
end

local function untrack(model: Model)
	local puppet = puppets[model]
	if not puppet then
		return
	end
	puppets[model] = nil
	for _, connection in puppet.connections do
		connection:Disconnect()
	end
	if puppet.flash then
		puppet.flash:Destroy()
	end
	for i, layer in LAYERS do
		local ok, err = pcall(layer.detach, puppet.layerStates[i])
		if not ok then
			log:warn("Pose layer " .. layer.name .. " failed to detach: " .. tostring(err))
		end
	end
end

local function track(model: Model)
	if puppets[model] or not model:IsA("Model") then
		return
	end
	if model:GetAttribute(BrainBody.BODY_ATTRIBUTE) ~= BrainBody.BODY_NAME then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local joints, neurons = findJoints(model)
	if not hasAllJoints(joints, neurons) then
		return
	end

	local lobeMeshes = {}
	for _, lobeName in BrainBody.LOBE_PARTS do
		local lobe = model:FindFirstChild(lobeName)
		local mesh = lobe and lobe:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			table.insert(lobeMeshes, { mesh = mesh, base = mesh.Scale })
		end
	end
	local core = model:FindFirstChild("Core")
	local found = core and core:FindFirstChild(BrainBody.CORE_LIGHT_NAME)
	local coreLight: PointLight? = if found and found:IsA("PointLight") then found else nil
	local synapses = {}
	for _, motor in neurons do
		local neuron = motor.Part1
		local beam = neuron and neuron:FindFirstChildOfClass("Beam")
		if beam then
			table.insert(synapses, { beam = beam, width = beam.Width0 })
		end
	end

	local flash = Instance.new("Highlight")
	flash.Name = "BossHitFlash"
	flash.FillColor = C.HIT_FLASH_COLOR
	flash.OutlineTransparency = 1
	flash.FillTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Adornee = model
	flash.Parent = model

	local puppet: Puppet = {
		model = model,
		humanoid = humanoid,
		root = root,
		joints = joints,
		neurons = neurons,
		lobeMeshes = lobeMeshes,
		coreLight = coreLight,
		coreLightColor = if coreLight then coreLight.Color else Color3.new(1, 1, 1),
		synapses = synapses,
		layerStates = {},
		pose = PoseTypes.neutral(),
		flash = flash,
		flashUntil = 0,
		seed = math.random() * TAU,
		bobPhase = 0,
		neuronPhase = 0,
		pitch = 0,
		roll = 0,
		wobble = 0,
		wobbleVelocity = 0,
		lastHealth = humanoid.Health,
		eyeLook = {},
		connections = {},
	}
	table.insert(puppet.connections, humanoid.HealthChanged:Connect(function(health)
		onHealthChanged(puppet, health)
	end))
	table.insert(puppet.connections, model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			untrack(model)
		end
	end))
	for i, layer in LAYERS do
		local ok, result = pcall(layer.attach, model)
		puppet.layerStates[i] = if ok then result else {}
		if not ok then
			log:warn("Pose layer " .. layer.name .. " failed to attach: " .. tostring(result))
		end
	end
	puppets[model] = puppet
	log:info("Animating boss body on " .. model:GetFullName())
end

-- The nearest living player character to `from`, within range.
local function nearestCharacter(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = C.EYE_LOOK_RANGE
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if hrp and hrp:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local distance = (hrp.Position - from).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = hrp.Position
			end
		end
	end
	return best
end

-- Turns an eye toward `target` (world space), clamped unless told not to,
-- smoothed, then turned by `offset`.
local function aimEye(puppet: Puppet, jointName: string, target: Vector3?, unclamped: boolean, offset: CFrame, dt: number)
	local motor = puppet.joints[jointName]
	local goal = CFrame.identity
	local eye = motor.Part1
	local brain = motor.Part0
	if target and eye and brain then
		local direction = brain.CFrame:VectorToObjectSpace(target - eye.Position)
		if direction.Magnitude > 0 then
			local look = CFrame.lookAt(Vector3.zero, direction.Unit)
			local angle = math.acos(math.clamp(-direction.Unit.Z, -1, 1))
			local fraction = if not unclamped and angle > C.EYE_MAX_RADIANS then C.EYE_MAX_RADIANS / angle else 1
			goal = CFrame.identity:Lerp(look, fraction)
		end
	end
	local current = puppet.eyeLook[jointName] or CFrame.identity
	local alpha = 1 - math.exp(-C.SMOOTHING_RATE * dt)
	local nextLook = current:Lerp(goal, alpha)
	puppet.eyeLook[jointName] = nextLook
	motor.Transform = nextLook * offset
end

local function resetPose(pose: PoseTypes.Pose)
	local neutral = PoseTypes.neutral() :: any
	local target = pose :: any
	for key in target do
		target[key] = nil
	end
	for key, value in neutral do
		target[key] = value
	end
end

local function step(puppet: Puppet, dt: number, now: number, serverNow: number, camera: Camera?)
	local model = puppet.model
	if model:GetAttribute(SkillConstants.FROZEN_ATTRIBUTE) then
		return -- every joint holds its pose
	end
	local root = puppet.root
	if camera and (camera.CFrame.Position - root.Position).Magnitude > C.MAX_ANIMATE_DISTANCE then
		return
	end
	local alive = puppet.humanoid.Health > 0

	-- Travel, in the boss's own frame (-Z is forward).
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local localVelocity = root.CFrame:VectorToObjectSpace(flat)
	local speed = flat.Magnitude

	-- Let the layers pose the body for this frame.
	local pose = puppet.pose
	resetPose(pose)
	local state = model:GetAttribute("CurrentState")
	local ctx: PoseTypes.Context = {
		model = model,
		root = root,
		humanoid = puppet.humanoid,
		dt = dt,
		clock = now,
		serverNow = serverNow,
		speed = speed,
		state = if typeof(state) == "string" then state else nil,
		alive = alive,
	}
	for i, layer in LAYERS do
		local ok, err = pcall(layer.apply, puppet.layerStates[i], ctx, pose)
		if not ok then
			log:warnThrottled("layer:" .. layer.name, C.LAYER_ERROR_LOG_SEC, "Pose layer " .. layer.name .. " failed: " .. tostring(err))
		end
	end
	-- A dead boss does no idle motion; only the layers move it.
	local motion = if alive then pose.motionScale else 0

	local pitchGoal = math.clamp(localVelocity.Z * C.LEAN_RADIANS_PER_SPEED, -C.LEAN_MAX_RADIANS, C.LEAN_MAX_RADIANS)
	local rollGoal = math.clamp(-localVelocity.X * C.LEAN_RADIANS_PER_SPEED, -C.LEAN_MAX_RADIANS, C.LEAN_MAX_RADIANS)
	puppet.pitch = approach(puppet.pitch, pitchGoal * motion, dt)
	puppet.roll = approach(puppet.roll, rollGoal * motion, dt)

	-- Hit spring: x'' = -k x - c x'.
	local accel = -C.WOBBLE_STIFFNESS * puppet.wobble - C.WOBBLE_DAMPING * puppet.wobbleVelocity
	puppet.wobbleVelocity += accel * dt
	puppet.wobble += puppet.wobbleVelocity * dt
	local w = puppet.wobble

	puppet.bobPhase += (C.HOVER_BOB_HZ + speed * C.HOVER_BOB_HZ_PER_SPEED) * TAU * dt
	local hover = C.HOVER_LIFT + math.sin(puppet.bobPhase) * C.HOVER_BOB_AMPLITUDE * motion
	local t = now + puppet.seed

	local j = puppet.joints
	j[J.Root].Transform = CFrame.new(0, hover, 0)
		* CFrame.Angles(puppet.pitch + w * C.WOBBLE_TILT_RADIANS, 0, puppet.roll)
		* pose.rootOffset

	-- Lobes: the layers' opening plus a flinch on a hit (outward half only).
	local open = pose.lobeOpen + math.max(w, 0) * C.WOBBLE_LOBE_FLINCH_RADIANS
	j[J.LeftLobe].Transform = CFrame.Angles(0, 0, open)
	j[J.RightLobe].Transform = CFrame.Angles(0, 0, -open)

	-- Breathing plus the squash of a hit, times the layers' scale.
	local breath = 1 + math.sin(t * C.BREATH_HZ * TAU) * C.BREATH_SCALE * motion
	local squash = w * C.WOBBLE_SQUASH
	local scale = Vector3.new(breath * (1 + squash / 2), breath * (1 - squash), breath * (1 + squash / 2)) * pose.lobeScale
	for _, entry in puppet.lobeMeshes do
		entry.mesh.Scale = entry.base * scale
	end

	-- The stem trails the lean and sways.
	local sway = math.sin(t * C.STEM_SWAY_HZ * TAU) * C.STEM_SWAY_RADIANS * motion
	j[J.Stem].Transform = CFrame.Angles(-puppet.pitch * C.STEM_TRAIL, 0, -puppet.roll * C.STEM_TRAIL + sway) * pose.stemOffset

	local target = pose.eyeTarget or nearestCharacter(root.Position)
	aimEye(puppet, J.LeftEye, target, pose.eyeUnclamped, pose.eyeOffset, dt)
	aimEye(puppet, J.RightEye, target, pose.eyeUnclamped, pose.eyeOffset, dt)

	puppet.neuronPhase += C.NEURON_ORBIT_HZ * TAU * pose.neuronSpeedScale * dt
	local radius = C.NEURON_ORBIT_RADIUS * pose.neuronRadiusScale
	for i, motor in puppet.neurons do
		local angle = puppet.neuronPhase + (i - 1) * TAU / #puppet.neurons
		local y = C.NEURON_HEIGHT + pose.neuronHeightOffset + math.sin(t * C.NEURON_BOB_HZ * TAU + i) * C.NEURON_BOB_STUDS
		motor.Transform = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
	end
	local glow = math.clamp(pose.synapseGlow, 0, 1)
	for _, synapse in puppet.synapses do
		local width = synapse.width * (1 + glow * C.SYNAPSE_GLOW_WIDTH)
		synapse.beam.Width0 = width
		synapse.beam.Width1 = width
		synapse.beam.Transparency = NumberSequence.new(C.SYNAPSE_REST_TRANSPARENCY * (1 - glow))
	end

	local light = puppet.coreLight
	if light then
		local pulse = (math.sin(t * C.CORE_PULSE_HZ * TAU) + 1) / 2
		light.Brightness = (C.CORE_LIGHT_MIN + (C.CORE_LIGHT_MAX - C.CORE_LIGHT_MIN) * pulse) * pose.coreLightScale
		light.Color = pose.coreLightColor or puppet.coreLightColor
	end

	local flash = puppet.flash
	if flash then
		local left = puppet.flashUntil - os.clock()
		if left > 0 then
			local fade = 1 - left / C.HIT_FLASH_SEC
			flash.FillColor = C.HIT_FLASH_COLOR
			flash.FillTransparency = C.HIT_FLASH_TRANSPARENCY + (1 - C.HIT_FLASH_TRANSPARENCY) * fade
		elseif pose.tint and pose.tintAlpha > 0 then
			flash.FillColor = pose.tint
			flash.FillTransparency = 1 - math.clamp(pose.tintAlpha, 0, 1)
		else
			flash.FillTransparency = 1
		end
	end
end

-- A boss is tagged before its body has streamed in, and BrainBody's
-- attribute may land after the tag; retry until it is complete.
local pending: { [Model]: boolean } = {}

local function consider(instance: Instance)
	if instance:IsA("Model") then
		pending[instance] = true
	end
end

CollectionService:GetInstanceAddedSignal(SkillConstants.BOSS_TAG):Connect(consider)
CollectionService:GetInstanceRemovedSignal(SkillConstants.BOSS_TAG):Connect(function(instance)
	pending[instance :: Model] = nil
	untrack(instance :: Model)
end)
for _, instance in CollectionService:GetTagged(SkillConstants.BOSS_TAG) do
	consider(instance)
end

RunService.PreSimulation:Connect(function(dt: number)
	for model in pending do
		if not model.Parent then
			pending[model] = nil
		else
			track(model)
			if puppets[model] then
				pending[model] = nil
			end
		end
	end
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	for _, puppet in puppets do
		step(puppet, dt, now, serverNow, camera)
	end
end)
