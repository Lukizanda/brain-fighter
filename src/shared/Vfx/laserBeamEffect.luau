local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LASER_BEAM_VISUAL_SPEED = 200 -- studs/sec; beam travels from muzzle to hit point

local laserBeamTemplate = ReplicatedStorage.Shared.Weapon.Objects.LaserBeam

local function laserBeamEffect(startPosition: Vector3, endPosition: Vector3)
	local distance = (startPosition - endPosition).Magnitude
	if distance < 0.01 then
		return
	end

	local tweenTime = distance / LASER_BEAM_VISUAL_SPEED
	local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

	local laser = laserBeamTemplate:Clone()
	laser.CFrame = CFrame.lookAt(startPosition, endPosition)
	laser.StartAttachment.Position = Vector3.zero
	laser.EndAttachment.Position = Vector3.zero -- start at muzzle, grow outward
	laser.CoreBeam.Attachment0 = laser.StartAttachment
	laser.CoreBeam.Attachment1 = laser.EndAttachment
	laser.OtherBeam.Attachment0 = laser.StartAttachment
	laser.OtherBeam.Attachment1 = laser.EndAttachment
	laser.Parent = Workspace

	local tween = TweenService:Create(laser.EndAttachment, tweenInfo, { Position = Vector3.new(0, 0, -distance) })
	tween:Play()
	tween.Completed:Once(function()
		laser:Destroy()
	end)
end

return laserBeamEffect
