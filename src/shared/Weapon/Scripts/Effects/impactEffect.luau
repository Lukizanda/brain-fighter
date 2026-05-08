local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local environmentImpactTemplate = ReplicatedStorage.Shared.Weapon.Objects.EnvironmentImpact
local characterImpactTemplate = ReplicatedStorage.Shared.Weapon.Objects.CharacterImpact

local function impactEffect(position: Vector3, normal: Vector3, isCharacter: boolean)
	local impact
	if isCharacter then
		impact = characterImpactTemplate:Clone()
		impact.CFrame = CFrame.lookAlong(position, normal)
		impact.Parent = Workspace

		impact.SparkEmitter:Emit(10)
		impact.CircleEmitter:Emit(2)
	else
		impact = environmentImpactTemplate:Clone()
		impact.CFrame = CFrame.lookAlong(position, normal)
		impact.Parent = Workspace

		impact.SparkEmitter:Emit(10)
		impact.CircleEmitter:Emit(2)
	end

	task.delay(0.5, function()
		impact:Destroy()
	end)
end

return impactEffect
