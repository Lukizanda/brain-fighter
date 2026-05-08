----!nocheck
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("CameraController")

local CameraController = {}
CameraController.__index = CameraController

-- Camera mode types
export type CameraMode = {
	-- The unique identifier name for this camera mode (e.g. "Default", "Handgun")
	name: string,
	-- Spring arm settings
	-- The length of the spring arm, controlling how far the camera is from the character
	armLength: number,
	-- The positional offset of the camera socket relative to the character's root position
	socketOffset: Vector3,
	-- Rotation inheritance (true = inherit, false = don't inherit)
	-- Whether the camera should inherit the character's pitch (up/down tilt)
	inheritPitch: boolean,
	-- Whether the camera should inherit the character's yaw (left/right rotation)
	inheritYaw: boolean,
	-- Whether the camera should inherit the character's roll (side tilt)
	inheritRoll: boolean,
	-- Spring physics
	-- Controls how quickly the spring arm snaps toward the target position; higher = snappier
	stiffness: number,
	-- Controls how much the spring arm resists oscillation; higher = less bouncy
	damping: number,
	-- Camera settings
	-- The camera's field of view in degrees; nil defaults to 70
	fieldOfView: number?,
	-- The duration in seconds for transitioning to this camera mode; nil means instant
	transitionTime: number?,
}

-- Camera constants
local MOUSE_SENSITIVITY = 0.003
local PITCH_CLAMP = math.rad(80)

-- Dev-only: when workspace:GetAttribute("DevDisableCameraInput") is true,
-- the controller keeps running but ignores mouse input and leaves the
-- cursor free. Intended for automated playtests where the test driver
-- (MCP / another script) needs an unlocked mouse to interact with Studio.
local DEV_DISABLE_CAMERA_INPUT_ATTRIBUTE = "DevDisableCameraInput"

-- Spring mode enum
local SpringMode = {
	Spring = "Spring", -- Full spring physics with lag and bounce
	Rigid = "Rigid", -- Instant snap, no rubber banding
}

-- Default camera modes
local CameraModes = {
	Default = {
		name = "Default",
		armLength = 8,
		socketOffset = Vector3.new(1.0, 1.5, 0), -- Above character center
		inheritPitch = false, -- Don't follow character's up/down look
		inheritYaw = false, -- Follow character's left/right rotation
		inheritRoll = false,
		stiffness = 200,
		damping = 20,
		fieldOfView = 70,
		transitionTime = 0.3,
	},
	-- Handgun modes (one-handed weapons)
	Handgun = {
		name = "Handgun",
		armLength = 10,
		socketOffset = Vector3.new(3.0, 3.0, 0),
		inheritPitch = false,
		inheritYaw = false,
		inheritRoll = false,
		stiffness = 200,
		damping = 20,
		fieldOfView = 70,
		transitionTime = 0.3,
	},
	HandgunAiming = {
		name = "HandgunAiming",
		armLength = 8,
		socketOffset = Vector3.new(2.0, 2.5, 0),
		inheritPitch = false,
		inheritYaw = false,
		inheritRoll = false,
		stiffness = 300,
		damping = 25,
		fieldOfView = 50,
		transitionTime = 0.2,
	},
	HandgunSprinting = {
		name = "HandgunSprinting",
		armLength = 12,
		socketOffset = Vector3.new(2.0, 2.0, 0),
		inheritPitch = false,
		inheritYaw = false,
		inheritRoll = false,
		stiffness = 150,
		damping = 15,
		fieldOfView = 75,
		transitionTime = 0.3,
	},
	-- Rifle modes (two-handed weapons)
	Rifle = {
		name = "Rifle",
		armLength = 10,
		socketOffset = Vector3.new(3.5, 3.0, 0),
		inheritPitch = false,
		inheritYaw = false,
		inheritRoll = false,
		stiffness = 200,
		damping = 20,
		fieldOfView = 70,
		transitionTime = 0.3,
	},
	RifleAiming = {
		name = "RifleAiming",
		armLength = 6,
		socketOffset = Vector3.new(1.5, 2.5, 0),
		inheritPitch = false,
		inheritYaw = false,
		inheritRoll = false,
		stiffness = 300,
		damping = 25,
		fieldOfView = 45,
		transitionTime = 0.2,
	},
	RifleSprinting = {
		name = "RifleSprinting",
		armLength = 14,
		socketOffset = Vector3.new(2.5, 2.0, 0),
		inheritPitch = false,
		inheritYaw = false,
		inheritRoll = false,
		stiffness = 150,
		damping = 15,
		fieldOfView = 80,
		transitionTime = 0.3,
	},
}

function CameraController.new()
	local self = {
		enabled = false,
		connections = {},
		camera = Workspace.CurrentCamera,
		character = nil,
		humanoidRootPart = nil,
		currentMode = CameraModes.Default,
		targetMode = CameraModes.Default,

		-- Spring arm state
		armPosition = Vector3.new(0, 0, 0),
		armVelocity = Vector3.new(0, 0, 0),

		-- Interpolated mode values (lerped during transitions)
		currentSocketOffset = CameraModes.Default.socketOffset,
		currentArmLength = CameraModes.Default.armLength,
		fromSocketOffset = CameraModes.Default.socketOffset,
		fromArmLength = CameraModes.Default.armLength,
		offsetTransitionAlpha = 1, -- 1 = fully at target, no lerp in progress
		offsetTransitionDuration = 0,

		-- Camera rotation state (controlled by mouse)
		cameraYaw = 0,
		cameraPitch = 0,

		-- Spring mode: SpringMode.Spring or SpringMode.Rigid
		springMode = SpringMode.Rigid,

		-- Camera state
		currentFieldOfView = 70,
		targetFieldOfView = 70,
		transitioning = false,
		transitionTween = nil,
	}
	setmetatable(self, CameraController)

	return self
end

function CameraController:enable(character: Model)
	log:info("Enabling with character:", character.Name)

	if self.enabled then
		log:warn("Already enabled, skipping")
		return
	end

	self.character = character
	self.humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if not self.humanoidRootPart then
		log:error("HumanoidRootPart not found")
		return
	end

	log:info("HumanoidRootPart found:", self.humanoidRootPart.Name)

	-- Initialize camera rotation from the character's facing (set by the
	-- SpawnLocation orientation), not the engine's default camera. The engine
	-- camera often hasn't repositioned to the new character at this moment,
	-- so reading its CFrame gave a stale yaw and ignored the spawn marker.
	--
	-- Yaw convention here matches the rest of the controller: the camera's
	-- world-space orientation is built as CFrame.Angles(0, yaw, 0), whose
	-- LookVector is (-sin(yaw), 0, -cos(yaw)). Inverting gives:
	--   yaw = atan2(-LookVector.X, -LookVector.Z)
	local hrpLook = self.humanoidRootPart.CFrame.LookVector
	self.cameraYaw = math.atan2(-hrpLook.X, -hrpLook.Z)
	self.cameraPitch = math.asin(hrpLook.Y)

	log:info("Initial camera rotation - Yaw:", self.cameraYaw, "Pitch:", self.cameraPitch)

	-- Initialize arm position to current camera position
	self.armPosition = self.camera.CFrame.Position
	self.currentFieldOfView = self.camera.FieldOfView
	self.targetFieldOfView = self.currentMode.fieldOfView or 70

	-- Set camera to scriptable mode
	self.camera.CameraType = Enum.CameraType.Scriptable
	log:info("Enabled - Camera type set to Scriptable")

	if Workspace:GetAttribute(DEV_DISABLE_CAMERA_INPUT_ATTRIBUTE) then
		log:info("DevDisableCameraInput set — skipping mouse lock + input wiring")
	else
		-- Lock mouse to center of screen and hide cursor
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false

		-- Accumulate mouse delta via InputChanged for reliable per-event delta capture
		table.insert(
			self.connections,
			UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end
				local mouseDelta = UserInputService:GetMouseDelta()
				self.cameraYaw = self.cameraYaw - (mouseDelta.X * MOUSE_SENSITIVITY)
				-- Wrap yaw to [-pi, pi] to prevent unbounded growth
				self.cameraYaw = math.atan2(math.sin(self.cameraYaw), math.cos(self.cameraYaw))
				self.cameraPitch = math.clamp(self.cameraPitch - (mouseDelta.Y * MOUSE_SENSITIVITY), -PITCH_CLAMP, PITCH_CLAMP)
			end)
		)
	end

	-- Start camera update loop after Roblox's own camera step so spring physics are applied last
	RunService:BindToRenderStep("CameraController", Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
		self:update(deltaTime)
	end)

	self.enabled = true
end

function CameraController:disable()
	if not self.enabled then
		return
	end

	-- Cancel any ongoing transition
	if self.transitionTween then
		self.transitionTween:Cancel()
		self.transitionTween = nil
	end

	-- Clear connections
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)

	RunService:UnbindFromRenderStep("CameraController")

	-- Reset camera type
	self.camera.CameraType = Enum.CameraType.Custom

	-- Unlock mouse and restore cursor
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	self.enabled = false
	self.character = nil
	self.humanoidRootPart = nil
end

function CameraController:setMode(modeName: string)
	local mode = CameraModes[modeName]
	if not mode then
		warn("CameraController: Unknown mode '" .. modeName .. "'")
		return
	end

	-- Snapshot current interpolated values as the lerp start point
	self.fromSocketOffset = self.currentSocketOffset
	self.fromArmLength = self.currentArmLength

	self.targetMode = mode
	self.targetFieldOfView = mode.fieldOfView or 70

	local duration = mode.transitionTime or 0
	if duration > 0 then
		-- Begin offset lerp
		self.offsetTransitionAlpha = 0
		self.offsetTransitionDuration = duration
		self:transition(duration)
	else
		-- Instant change
		self.currentSocketOffset = mode.socketOffset
		self.currentArmLength = mode.armLength
		self.offsetTransitionAlpha = 1
		self.camera.FieldOfView = self.targetFieldOfView
	end
end

function CameraController:setSpringMode(mode: string)
	if mode ~= SpringMode.Spring and mode ~= SpringMode.Rigid then
		warn("CameraController: Unknown spring mode '" .. mode .. "'")
		return
	end
	self.springMode = mode
	-- Reset velocity so there's no leftover momentum when switching
	self.armVelocity = Vector3.new(0, 0, 0)
end

function CameraController:registerMode(modeName: string, mode: CameraMode)
	CameraModes[modeName] = mode
end

function CameraController:transition(duration: number)
	if self.transitionTween then
		self.transitionTween:Cancel()
	end

	self.transitioning = true

	-- Tween field of view
	self.transitionTween =
		TweenService:Create(self.camera, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = self.targetFieldOfView,
		})
	self.transitionTween:Play()

	task.delay(duration, function()
		self.transitioning = false
		self.transitionTween = nil
	end)
end

-- Calculate the target position for the spring arm
function CameraController:calculateArmTarget(): (Vector3, CFrame)
	if not self.humanoidRootPart then
		return Vector3.new(0, 0, 0), CFrame.new()
	end

	local characterPosition = self.humanoidRootPart.CFrame.Position

	-- Create rotation from camera yaw and pitch
	local yawCFrame = CFrame.Angles(0, self.cameraYaw, 0)
	local pitchCFrame = CFrame.Angles(self.cameraPitch, 0, 0)
	local rotationCFrame = yawCFrame * pitchCFrame

	-- Calculate socket position using the currently interpolated offset and arm length
	local cameraRight = yawCFrame.RightVector
	local cameraUp = Vector3.new(0, 1, 0) -- world up, avoids pitch affecting height
	local rotatedOffset = (cameraRight * self.currentSocketOffset.X) + (cameraUp * self.currentSocketOffset.Y)
	local socketPosition = characterPosition + rotatedOffset

	-- Calculate arm end position (where camera should be)
	local armEndPosition = socketPosition + (rotationCFrame.LookVector * -self.currentArmLength)

	return armEndPosition, rotationCFrame
end

-- Spring physics update
function CameraController:updateSpringPhysics(deltaTime: number)
	local targetPosition, _ = self:calculateArmTarget()
	local mode = self.targetMode

	-- Spring physics: F = -kx - cv
	-- acceleration = (target - current) * stiffness - velocity * damping
	local displacement = targetPosition - self.armPosition
	local acceleration = (displacement * mode.stiffness) - (self.armVelocity * mode.damping)

	-- Update velocity and position
	self.armVelocity = self.armVelocity + (acceleration * deltaTime)
	self.armPosition = self.armPosition + (self.armVelocity * deltaTime)
end

function CameraController:update(deltaTime: number)
	if not self.humanoidRootPart then
		return
	end

	-- Advance offset/armLength lerp if a transition is in progress
	if self.offsetTransitionAlpha < 1 then
		self.offsetTransitionAlpha =
			math.min(self.offsetTransitionAlpha + (deltaTime / self.offsetTransitionDuration), 1)
		-- Use Quad Out easing to match the FOV tween curve and avoid snap at the end
		local t = self.offsetTransitionAlpha
		local easedT = 1 - (1 - t) * (1 - t) -- Quad Out: matches TweenService Quad Out
		self.currentSocketOffset = self.fromSocketOffset:Lerp(self.targetMode.socketOffset, easedT)
		self.currentArmLength = self.fromArmLength + (self.targetMode.armLength - self.fromArmLength) * easedT
	end

	-- Update arm position based on spring mode
	if self.springMode == SpringMode.Rigid then
		-- Instant snap: bypass spring, set position directly
		local targetPosition = self:calculateArmTarget()
		self.armPosition = targetPosition
		self.armVelocity = Vector3.new(0, 0, 0)
	else
		-- Full spring physics with lag and bounce
		self:updateSpringPhysics(deltaTime)
	end

	-- Create rotation from camera yaw and pitch
	local yawCFrame = CFrame.Angles(0, self.cameraYaw, 0)
	local pitchCFrame = CFrame.Angles(self.cameraPitch, 0, 0)
	local rotationCFrame = yawCFrame * pitchCFrame

	-- Set camera CFrame - position from spring arm, rotation from mouse input
	local cameraCFrame = CFrame.new(self.armPosition) * rotationCFrame

	self.camera.CFrame = cameraCFrame

	-- Debug: print camera position and rotation every 60 frames (approx 1 second)
	--if math.random(1, 60) == 1 then
	--	print("Camera update - Yaw:", self.cameraYaw, "Pitch:", self.cameraPitch, "Position:", self.armPosition)
	--end
end

function CameraController:destroy()
	self:disable()
end

-- Export CameraModes and SpringMode for external use
CameraController.CameraModes = CameraModes
CameraController.SpringMode = SpringMode

return CameraController
