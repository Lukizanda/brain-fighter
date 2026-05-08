local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local log = Logger.new("Locomotion")

local LocomotionController = {}
LocomotionController.__index = LocomotionController

export type MovementState = "Idle" | "Forward" | "Backward" | "StrafeLeft" | "StrafeRight"

-- Movement direction thresholds (dot product with camera forward)
-- BACKWARD_THRESHOLD: dot < this = backward. -0.5 ≈ 120° from forward, -0.25 ≈ 105°, -0.7 ≈ 135°
-- FORWARD_THRESHOLD:  dot > this = forward.  0.5 ≈ 60° from forward
local BACKWARD_THRESHOLD = -0.5
local FORWARD_THRESHOLD = 0.5
local MOVE_MAGNITUDE_THRESHOLD = 0.1
local UPPER_BODY_MAX_YAW = math.rad(90) -- max upper body twist from center
local UPPER_BODY_FIRE_MAX_YAW = math.rad(120) -- wider range when firing, but not full 180
local UPPER_BODY_LERP_SPEED = 10 -- how fast the upper body tracks the camera
local ANIMATION_FADE_TIME = 0.2 -- seconds to crossfade between locomotion animations
local LOG_INTERVAL = 60 -- log every N frames


function LocomotionController.new()
	local self = {
		enabled = false,
		character = nil,
		humanoid = nil,
		humanoidRootPart = nil,

		-- External dependency: provides camera yaw for direction calculation
		cameraController = nil,

		-- Current movement state
		movementState = "Idle" :: MovementState,

		-- Animation tracks keyed by MovementState
		animationTracks = {} :: { [MovementState]: AnimationTrack },

		-- Orientation control: AlignOrientation + Attachment for physics-safe rotation
		alignOrientation = nil :: AlignOrientation?,
		orientationAttachment = nil :: Attachment?,

		-- Upper body tracking — single owner of Waist/Neck/Shoulder Motor6Ds
		upperBodyMotors = {} :: { { motor: Motor6D, originalC0: CFrame } },
		currentUpperBodyYaw = 0, -- smoothed current yaw offset
		currentUpperBodyPitch = 0, -- smoothed current pitch offset

		-- Speed control
		baseWalkSpeed = 16, -- captured on enable, restored on disable

		-- Firing state (merged from FireRotation)
		isFiring = false,
		toolConnections = {} :: { [Tool]: { activated: RBXScriptConnection, deactivated: RBXScriptConnection } },
		characterConnections = {} :: { RBXScriptConnection },
	}
	setmetatable(self, LocomotionController)
	return self
end

function LocomotionController:enable(character: Model, cameraController: any)
	if self.enabled then
		return
	end

	self.character = character
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	self.cameraController = cameraController

	if not (self.humanoid and self.humanoidRootPart) then
		log:warn("Missing Humanoid or HumanoidRootPart")
		return
	end

	self:cacheUpperBodyMotors()
	self:setupToolFireListeners()
	self.baseWalkSpeed = self.humanoid.WalkSpeed
	self.currentUpperBodyYaw = 0

	self:loadAnimations()
	self:createOrientationConstraint()

	-- Start locked to camera (will toggle per-state based on available animations)
	self.humanoid.AutoRotate = false
	self.alignOrientation.Enabled = true

	log:info("Enabled — orientation lock active")
	log:info("Upper body motors cached:", #self.upperBodyMotors)

	local animNames = {}
	for name, _ in self.animationTracks do
		table.insert(animNames, name)
	end
	log:info("Loaded animations:", if #animNames > 0 then table.concat(animNames, ", ") else "(none)")

	-- Bind AFTER the character controller (priority > 300) so we override
	-- the Humanoid's auto-rotation
	RunService:BindToRenderStep("LocomotionController", Enum.RenderPriority.Character.Value + 1, function(dt)
		self:update(dt)
	end)

	self.enabled = true
end

function LocomotionController:disable()
	if not self.enabled then
		return
	end

	RunService:UnbindFromRenderStep("LocomotionController")

	-- Restore auto-rotate and base walk speed
	if self.humanoid then
		self.humanoid.AutoRotate = true
		self.humanoid.WalkSpeed = self.baseWalkSpeed
	end

	-- Reset all upper body motors to original orientation
	for _, entry in self.upperBodyMotors do
		entry.motor.C0 = entry.originalC0
	end
	table.clear(self.upperBodyMotors)

	-- Clean up tool fire listeners
	self:cleanupToolFireListeners()
	self.isFiring = false

	self:destroyOrientationConstraint()
	self:stopAllAnimations()
	self.movementState = "Idle"
	self.currentUpperBodyYaw = 0
	self.currentUpperBodyPitch = 0
	self.enabled = false
	self.character = nil
	self.humanoid = nil
	self.humanoidRootPart = nil
	self.cameraController = nil

	log:info("Disabled")
end

-- Cache the Motor6Ds we rotate for upper body tracking (R15)
-- Searches by Motor6D name across all descendants to handle different rig layouts
function LocomotionController:cacheUpperBodyMotors()
	table.clear(self.upperBodyMotors)

	-- Only rotate the Waist for yaw tracking. The Neck/Head/Shoulders are children
	-- of UpperTorso and naturally follow the Waist rotation. Rotating Shoulders
	-- independently on yaw swings the arms into the body causing clipping.
	for _, desc in self.character:GetDescendants() do
		if desc:IsA("Motor6D") and desc.Name == "Waist" then
			table.insert(self.upperBodyMotors, { motor = desc, originalC0 = desc.C0 })
			log:info("Cached motor:", desc.Name, "parent:", desc.Parent.Name)
		end
	end
end

-- Listen for tools with EnableFireRotation attribute
function LocomotionController:setupToolFireListeners()
	local character = self.character
	if not character then
		return
	end

	-- Wire up any tool already in the character
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("EnableFireRotation") then
			self:connectToolFire(child)
		end
	end

	-- Wire up tools as they get equipped
	table.insert(self.characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("EnableFireRotation") then
			self:connectToolFire(child)
		end
	end))

	-- Clean up when tools are unequipped
	table.insert(self.characterConnections, character.ChildRemoved:Connect(function(child)
		self:disconnectToolFire(child)
	end))
end

function LocomotionController:connectToolFire(tool: Tool)
	if self.toolConnections[tool] then
		return
	end
	log:info("Connected fire rotation for tool:", tool.Name)
	self.toolConnections[tool] = {
		activated = tool.Activated:Connect(function()
			self.isFiring = true
		end),
		deactivated = tool.Deactivated:Connect(function()
			self.isFiring = false
		end),
	}
end

function LocomotionController:disconnectToolFire(tool: Tool)
	local conns = self.toolConnections[tool]
	if conns then
		conns.activated:Disconnect()
		conns.deactivated:Disconnect()
		self.toolConnections[tool] = nil
		-- If no active tools remain, stop firing
		if not next(self.toolConnections) then
			self.isFiring = false
		end
	end
end

function LocomotionController:cleanupToolFireListeners()
	for tool, _ in self.toolConnections do
		self:disconnectToolFire(tool)
	end
	for _, conn in self.characterConnections do
		conn:Disconnect()
	end
	table.clear(self.characterConnections)
end

function LocomotionController:createOrientationConstraint()
	local hrp = self.humanoidRootPart

	-- Attachment that we rotate to set the desired orientation
	local attachment = Instance.new("Attachment")
	attachment.Name = "LocomotionOrientAttachment"
	attachment.Parent = hrp
	self.orientationAttachment = attachment

	-- AlignOrientation that forces HRP to match our attachment's world CFrame
	local align = Instance.new("AlignOrientation")
	align.Name = "LocomotionAlignOrientation"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true -- snap, no spring wobble
	align.Enabled = false -- enabled in :enable(), always active while locomotion is on
	align.Parent = hrp
	self.alignOrientation = align
end

function LocomotionController:destroyOrientationConstraint()
	if self.alignOrientation then
		self.alignOrientation:Destroy()
		self.alignOrientation = nil
	end
	if self.orientationAttachment then
		self.orientationAttachment:Destroy()
		self.orientationAttachment = nil
	end
end

function LocomotionController:loadAnimations()
	local humanoid = self.humanoid
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		log:warn("No Animator found on Humanoid")
		return
	end

	-- Look for locomotion animations in ReplicatedStorage.Shared.LocomotionAnimations
	local animationsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	animationsFolder = animationsFolder and animationsFolder:FindFirstChild("LocomotionAnimations")

	if not animationsFolder then
		log:info("No LocomotionAnimations folder found — state tracking only, no custom anims")
		return
	end

	for _, animation in animationsFolder:GetChildren() do
		if animation:IsA("Animation") then
			local track = animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Movement
			track.Looped = true
			self.animationTracks[animation.Name] = track
			log:info("Loaded animation:", animation.Name, "id:", animation.AnimationId)
		end
	end
end

function LocomotionController:getMovementState(): MovementState
	return self.movementState
end

-- Toggle between locked orientation (animation handles legs) and free rotation (tank style).
-- When locked: AlignOrientation forces HRP to face cameraYaw, AutoRotate off.
-- When unlocked: AutoRotate on, lower body rotates toward movement direction naturally.
function LocomotionController:setOrientationLocked(locked: boolean, cameraYaw: number)
	if not self.humanoid then
		return
	end

	if locked then
		self.humanoid.AutoRotate = false
		if self.alignOrientation then
			self.alignOrientation.Enabled = true
			self.orientationAttachment.CFrame = CFrame.Angles(0, -cameraYaw, 0)
		end
	else
		self.humanoid.AutoRotate = true
		if self.alignOrientation then
			self.alignOrientation.Enabled = false
		end
	end
end

function LocomotionController:update(dt: number)
	local humanoid = self.humanoid
	if not humanoid or not self.cameraController then
		return
	end

	local cameraYaw = self.cameraController.cameraYaw

	-- Determine movement state for animation selection
	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude < MOVE_MAGNITUDE_THRESHOLD then
		self:setMovementState("Idle")
		humanoid.WalkSpeed = self.baseWalkSpeed -- restore full speed when idle
		-- Idle: lock to camera so character faces forward when standing still
		self:setOrientationLocked(true, cameraYaw)
		self:updateUpperBodyRotation(cameraYaw, dt)
		log:infoThrottled("frame", LOG_INTERVAL,
			"State=Idle",
			"| cameraYaw=", string.format("%.1f°", math.deg(cameraYaw)),
			"| firing=", self.isFiring,
			"| locked=true",
			"| upperBodyYaw=", string.format("%.1f°", math.deg(self.currentUpperBodyYaw))
		)
		return
	end

	-- Use the actual camera LookVector to match what Roblox uses for MoveDirection.
	-- Computing from cameraYaw via trig can have sign mismatches with the camera CFrame.
	local camLook = workspace.CurrentCamera.CFrame.LookVector
	local cameraForward = Vector3.new(camLook.X, 0, camLook.Z)
	if cameraForward.Magnitude < MOVE_MAGNITUDE_THRESHOLD then
		cameraForward = Vector3.new(math.sin(cameraYaw), 0, math.cos(cameraYaw))
	end
	cameraForward = cameraForward.Unit
	local cameraRight = Vector3.new(cameraForward.Z, 0, -cameraForward.X)

	-- Flatten move direction to XZ plane
	local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flatMove.Magnitude < MOVE_MAGNITUDE_THRESHOLD then
		self:setMovementState("Idle")
		self:setOrientationLocked(true, cameraYaw)
		self:updateUpperBodyRotation(cameraYaw, dt)
		return
	end
	flatMove = flatMove.Unit

	local forwardDot = flatMove:Dot(cameraForward)
	local rightDot = flatMove:Dot(cameraRight)

	-- Determine primary movement direction relative to camera
	local newState: MovementState
	if forwardDot < BACKWARD_THRESHOLD then
		newState = "Backward"
	elseif forwardDot > FORWARD_THRESHOLD then
		newState = "Forward"
	elseif rightDot > 0 then
		newState = "StrafeRight"
	else
		newState = "StrafeLeft"
	end

	self:setMovementState(newState)

	-- Apply speed modifier based on movement state and firing
	local speedMul = 1
	if newState == "Backward" and self.isFiring then
		speedMul = GameConfig.BACKWARD_FIRING_SPEED_MULTIPLIER
	elseif newState == "Backward" then
		speedMul = GameConfig.BACKWARD_SPEED_MULTIPLIER
	elseif self.isFiring then
		speedMul = GameConfig.FIRING_SPEED_MULTIPLIER
	end
	humanoid.WalkSpeed = self.baseWalkSpeed * speedMul

	-- Lock the lower body (HRP) to camera yaw when:
	-- 1. Backward: ALWAYS lock — releasing would spin the body 180°.
	--    If a backward-walk animation exists it handles legs; if not, we slide.
	-- 2. Other states: lock only if we have an animation for natural leg movement,
	--    otherwise release so the lower body rotates toward movement direction.
	-- Note: while firing we deliberately do NOT force HRP lock here.
	-- updateUpperBodyRotation pins the upper body to camera via an instant
	-- Waist write while firing, which lets the legs continue to autorotate
	-- toward MoveDirection (visible strafe motion) without dragging the
	-- firing pose with them.
	-- Note on camera-locking animations (e.g. sword swing): we also do NOT
	-- force HRP lock for those. That would stop the legs mid-strafe and
	-- read as the lower body teleporting to face camera. Instead, the
	-- upper body Waist write yields entirely (see isCameraLockingAnimationPlaying).
	local hasAnim = self.animationTracks[newState] ~= nil
	local shouldLock = hasAnim or newState == "Backward"
	self:setOrientationLocked(shouldLock, cameraYaw)

	self:updateUpperBodyRotation(cameraYaw, dt)

	log:infoThrottled("frame", LOG_INTERVAL,
		"State=", newState,
		"| fwdDot=", string.format("%.2f", forwardDot),
		"| rightDot=", string.format("%.2f", rightDot),
		"| cameraYaw=", string.format("%.1f°", math.deg(cameraYaw)),
		"| firing=", self.isFiring,
		"| locked=", shouldLock,
		"| upperBodyYaw=", string.format("%.1f°", math.deg(self.currentUpperBodyYaw)),
		"| anim=", hasAnim and "playing" or "MISSING"
	)
end

function LocomotionController:updateUpperBodyRotation(cameraYaw: number, dt: number)
	if #self.upperBodyMotors == 0 or not self.humanoidRootPart then
		return
	end

	-- Skip upper-body manipulation entirely while a camera-locking
	-- animation (sword swing) is playing. Pre-swing the body is already
	-- tracking camera direction via this same function, so the swing
	-- starts in the right orientation. Trying to maintain the rotation
	-- through the swing fights the Animator's blender — it triggers
	-- Roblox's "frozen pose" behavior on Motor.Transform that we have
	-- no clean way to undo. Letting the animation play unmolested keeps
	-- code simple at the cost of the body slightly drifting with HRP
	-- during the ~0.5s swing if the player is strafing.
	if self:isCameraLockingAnimationPlaying() then
		return
	end

	-- Get HRP yaw and the raw delta to camera. Read once so both branches
	-- below can use it.
	local _, characterYaw, _ = self.humanoidRootPart.CFrame:ToEulerAnglesYXZ()
	local rawDeltaYaw = math.atan2(math.sin(cameraYaw - characterYaw), math.cos(cameraYaw - characterYaw))

	-- Firing: pin the upper body to camera with an INSTANT write — no lerp.
	-- The lerp is what made the arms visibly swing and spring back when
	-- strafing without an animation: HRP autorotates toward MoveDirection,
	-- the lerp races to catch up at ~10 rad/sec, and any change in HRP yaw
	-- (strafe start/stop, physics-step jitter) shows up as a ~10°/frame
	-- counter-rotation. With an instant write, HRP_yaw + Waist_yaw stays
	-- equal to cameraYaw every frame, so the upper body is mathematically
	-- pinned regardless of how the legs are moving. Clamp at the firing
	-- limit so extreme camera/movement angles don't snap arms through the
	-- torso (rare with strafe states, possible with bad combinations).
	if self.isFiring then
		local target = math.clamp(rawDeltaYaw, -UPPER_BODY_FIRE_MAX_YAW, UPPER_BODY_FIRE_MAX_YAW)
		if self.currentUpperBodyYaw ~= target then
			self.currentUpperBodyYaw = target
			local rotationCFrame = CFrame.Angles(0, target, 0)
			for _, entry in self.upperBodyMotors do
				entry.motor.C0 = entry.originalC0 * rotationCFrame
			end
		end
		return
	end

	-- Non-firing: smooth look-around tracking via lerp.
	local clampedDelta = math.clamp(rawDeltaYaw, -UPPER_BODY_MAX_YAW, UPPER_BODY_MAX_YAW)
	local diff = clampedDelta - self.currentUpperBodyYaw
	-- Normalize diff to [-pi, pi] so the lerp always takes the short way around
	diff = math.atan2(math.sin(diff), math.cos(diff))
	self.currentUpperBodyYaw = self.currentUpperBodyYaw
		+ diff * math.min(1, UPPER_BODY_LERP_SPEED * dt)
	-- Normalize to prevent drift when the body rotates freely (AutoRotate on)
	self.currentUpperBodyYaw = math.atan2(math.sin(self.currentUpperBodyYaw), math.cos(self.currentUpperBodyYaw))

	local rotationCFrame = CFrame.Angles(0, self.currentUpperBodyYaw, 0)
	for _, entry in self.upperBodyMotors do
		entry.motor.C0 = entry.originalC0 * rotationCFrame
	end
end

-- True if any currently-playing track is flagged as requiring an HRP
-- lock to camera yaw — used to keep combat animations (e.g. sword
-- swings) cutting toward where the player is aiming, even when the
-- normal locomotion logic would leave the body tracking MoveDirection.
-- Animations opt in via a Bool attribute `LocksOrientationToCamera =
-- true` on the Animation instance (e.g. Sword.SwingAnimation). Cheap:
-- GetPlayingAnimationTracks returns a small list (typically 0-3
-- entries) and we early-exit on first hit.
function LocomotionController:isCameraLockingAnimationPlaying(): boolean
	local humanoid = self.humanoid
	if not humanoid then
		return false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation and track.Animation:GetAttribute("LocksOrientationToCamera") then
			return true
		end
	end
	return false
end

function LocomotionController:setMovementState(newState: MovementState)
	if self.movementState == newState then
		return
	end

	local oldState = self.movementState
	self.movementState = newState

	log:info("State changed:", oldState, "->", newState)

	-- Stop old animation
	local oldTrack = self.animationTracks[oldState]
	if oldTrack and oldTrack.IsPlaying then
		oldTrack:Stop(ANIMATION_FADE_TIME)
		log:info("  Stopped anim:", oldState)
	end

	-- Play new animation
	local newTrack = self.animationTracks[newState]
	if newTrack and not newTrack.IsPlaying then
		newTrack:Play(ANIMATION_FADE_TIME)
		log:info("  Playing anim:", newState)
	elseif not newTrack and newState ~= "Idle" and newState ~= "Forward" then
		log:info("  WARNING: No animation loaded for state:", newState)
	end
end

function LocomotionController:stopAllAnimations()
	for _, track in self.animationTracks do
		if track.IsPlaying then
			track:Stop(ANIMATION_FADE_TIME)
		end
	end
end

function LocomotionController:destroy()
	self:disable()
	table.clear(self.animationTracks)
end

return LocomotionController
