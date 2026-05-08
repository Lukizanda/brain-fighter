--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local bindSoundsToAnimationEvents = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.bindSoundsToAnimationEvents)

local WeaponAnimationController = {}
WeaponAnimationController.__index = WeaponAnimationController

function WeaponAnimationController.new(weapon: Tool, config: { ikChainRoot: string? }?)
	local sounds = weapon:WaitForChild("Sounds")
	local audioTarget = SoundService.Audio.Busses.World.AudioCompressor
	config = config or {}

	local self = {
		enabled = false,
		loadedAnimations = false,
		weapon = weapon,
		sounds = sounds,
		audioTarget = audioTarget,
		animationTracks = {},
		ikControl = nil,
		ikTarget = nil,
		ikConnection = nil,
		leftIkControl = nil,
		-- "RightLowerArm" = forearm only (handguns), "RightUpperArm" = full arm (rifles)
		ikChainRootName = config.ikChainRoot or "RightLowerArm",
	}
	setmetatable(self, WeaponAnimationController)

	return self
end

function WeaponAnimationController:playShootAnimation()
	local track = self.animationTracks.Shoot
	track:Play(0)

	if self.ikControl then
		self.ikControl.Weight = Constants.IK_ACTIVE_WEIGHT
		track.Stopped:Once(function()
			if self.ikControl then
				self.ikControl.Weight = Constants.IK_PASSIVE_WEIGHT
			end
		end)
	end
end

function WeaponAnimationController:stopShootAnimation()
	local track = self.animationTracks.Shoot
	if track and track.IsPlaying then
		track:Stop(0.1)
	end
	if self.ikControl then
		self.ikControl.Weight = Constants.IK_PASSIVE_WEIGHT
	end
end

function WeaponAnimationController:playReloadAnimation(reloadTime: number)
	if self.ikControl then
		self.ikControl.Weight = 0 -- fully disable IK during reload
	end
	if self.leftIkControl then
		self.leftIkControl.Weight = 0
	end
	local speed = self.animationTracks.Reload.Length / reloadTime
	local track = self.animationTracks.Reload
	track:Play(0.1, 1, speed)

	-- Restore left arm IK after reload finishes
	if self.leftIkControl then
		track.Stopped:Once(function()
			if self.leftIkControl then
				self.leftIkControl.Weight = 1
			end
		end)
	end
end

function WeaponAnimationController:loadAnimations()
	if self.loadedAnimations then
		return
	end

	self.loadedAnimations = true

	local animationsFolder = self.weapon.Animations
	local humanoid = self.weapon.Parent:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Weapon is not equipped")
	local animator = humanoid.Animator

	local animationTracks = {}
	for _, animation in animationsFolder:GetChildren() do
		local animationTrack = animator:LoadAnimation(animation)
		animationTrack.Priority = Enum.AnimationPriority.Action
		animationTracks[animation.Name] = animationTrack

		-- Bind sounds to animation events
		bindSoundsToAnimationEvents(animationTrack, self.sounds, self.audioTarget)
	end

	self.animationTracks = animationTracks
end

function WeaponAnimationController:setupIK()
	local character = self.weapon.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local chainRoot = character:FindFirstChild(self.ikChainRootName)
	local rightHand = character:FindFirstChild("RightHand")

	if not (humanoid and humanoidRootPart and chainRoot and rightHand) then
		warn("WeaponAnimationController: Could not find R15 limbs for IK setup")
		return
	end

	local ikTarget = Instance.new("Attachment")
	ikTarget.Name = "IKTarget"
	ikTarget.Parent = humanoidRootPart
	self.ikTarget = ikTarget

	local ikControl = Instance.new("IKControl")
	ikControl.Type = Enum.IKControlType.Position
	ikControl.ChainRoot = chainRoot
	ikControl.EndEffector = rightHand
	ikControl.Target = ikTarget
	ikControl.Weight = Constants.IK_PASSIVE_WEIGHT
	ikControl.Parent = humanoid
	self.ikControl = ikControl

	local camera = Workspace.CurrentCamera
	self.ikConnection = RunService.RenderStepped:Connect(function()
		ikTarget.WorldPosition = camera.CFrame.Position
			+ camera.CFrame.LookVector * Constants.IK_TARGET_DISTANCE
			+ camera.CFrame.RightVector * Constants.IK_AIM_OFFSET
	end)

	-- Left arm foregrip IK: if the weapon has a ForegripAttachment, lock the left hand to it
	local foregripAttachment = self.weapon:FindFirstChild("ForegripAttachment", true)
	if foregripAttachment then
		local leftUpperArm = character:FindFirstChild("LeftUpperArm")
		local leftHand = character:FindFirstChild("LeftHand")
		if leftUpperArm and leftHand then
			local leftIk = Instance.new("IKControl")
			leftIk.Type = Enum.IKControlType.Position
			leftIk.ChainRoot = leftUpperArm
			leftIk.EndEffector = leftHand
			leftIk.Target = foregripAttachment
			leftIk.Weight = 1
			leftIk.Parent = humanoid
			self.leftIkControl = leftIk
		end
	end
end

function WeaponAnimationController:teardownIK()
	if self.ikConnection then
		self.ikConnection:Disconnect()
		self.ikConnection = nil
	end
	if self.ikControl then
		self.ikControl:Destroy()
		self.ikControl = nil
	end
	if self.ikTarget then
		self.ikTarget:Destroy()
		self.ikTarget = nil
	end
	if self.leftIkControl then
		self.leftIkControl:Destroy()
		self.leftIkControl = nil
	end
end

function WeaponAnimationController:enable()
	if self.enabled then
		return
	end
	self.enabled = true

	if not self.loadedAnimations then
		self:loadAnimations()
	end

	self.animationTracks.Idle:Play()
	self:setupIK()
end

function WeaponAnimationController:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	self:teardownIK()

	for _, animation in self.animationTracks do
		animation:Stop()
	end
end

function WeaponAnimationController:destroy()
	self:disable()
	table.clear(self.animationTracks)
end

return WeaponAnimationController
