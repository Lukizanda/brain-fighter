local castRays = require(script.Parent.castRays)
local impactEffect = require(script.Parent.Parent.Effects.impactEffect)

-- Debug visualization toggle
local DEBUG = false
local DEBUG_LIFETIME = 2 -- seconds before debug parts are removed

local function debugSphere(position: Vector3, color: Color3, size: number)
	local part = Instance.new("Part")
	part.Name = "DEBUG_Sphere"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = workspace
	task.delay(DEBUG_LIFETIME, function()
		part.Parent = nil
	end)
end

local function debugBeam(startPos: Vector3, endPos: Vector3, color: Color3)
	local midpoint = (startPos + endPos) / 2
	local distance = (startPos - endPos).Magnitude
	local part = Instance.new("Part")
	part.Name = "DEBUG_Beam"
	part.Size = Vector3.new(0.1, 0.1, distance)
	part.CFrame = CFrame.lookAt(midpoint, endPos)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = workspace
	task.delay(DEBUG_LIFETIME, function()
		part.Parent = nil
	end)
end

local function drawRayResults(
	position: Vector3,
	rayResults: { castRays.RayResult },
	shotEffect: (Vector3, Vector3) -> ()
)
	for _, rayResult in rayResults do
		shotEffect(position, rayResult.position)
		if rayResult.instance then
			impactEffect(rayResult.position, rayResult.normal, rayResult.taggedHumanoid ~= nil)
		else
			impactEffect(rayResult.position, rayResult.normal, false)
		end

		if DEBUG then
			-- Green sphere = origin, Red sphere = end point
			debugSphere(position, Color3.fromRGB(0, 255, 0), 0.4)
			debugSphere(rayResult.position, Color3.fromRGB(255, 0, 0), 0.4)
			-- Yellow beam connecting origin to end point
			debugBeam(position, rayResult.position, Color3.fromRGB(255, 255, 0))
		end
	end
end

return drawRayResults
