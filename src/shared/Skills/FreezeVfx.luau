--!strict

local TweenService = game:GetService("TweenService")

local TARGET_PARTS: { string } = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperLeg", "RightUpperLeg",
	"LeftUpperArm", "RightUpperArm",
}

local OVERSIZE       = 1.5
local ICE_COLOR      = Color3.fromRGB(128, 192, 255)
local TRANSPARENCY   = 0.35
local EXPAND_TIME    = 0.4
local COLLAPSE_TIME  = 0.2
local ROT_RANGE_XZ   = math.rad(35)

local _active: { [Humanoid]: { Part } } = {}

local function makeExpandTween(p: Part, targetSize: Vector3): Tween
	return TweenService:Create(
		p,
		TweenInfo.new(EXPAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
end

local function makeCollapseTween(p: Part): Tween
	return TweenService:Create(
		p,
		TweenInfo.new(COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0, 0, 0) }
	)
end

local FreezeVfx = {}

function FreezeVfx.start(humanoid: Humanoid, _durationSec: number)
	if _active[humanoid] then return end

	local character = humanoid.Parent
	if not character then return end

	local parts: { Part } = {}

	for _, name in TARGET_PARTS do
		local limb = character:FindFirstChild(name) :: BasePart?
		if not limb or not limb:IsA("BasePart") then continue end

		local rx = (math.random() * 2 - 1) * ROT_RANGE_XZ
		local ry = math.random() * math.pi * 2
		local rz = (math.random() * 2 - 1) * ROT_RANGE_XZ

		local icePart = Instance.new("Part")
		icePart.Name        = "IceShard"
		icePart.Material    = Enum.Material.Ice
		icePart.Color       = ICE_COLOR
		icePart.Transparency = TRANSPARENCY
		icePart.CanCollide  = false
		icePart.Anchored    = false
		icePart.CastShadow  = false
		icePart.Size        = Vector3.new(0.1, 0.1, 0.1)
		icePart.CFrame      = limb.CFrame * CFrame.Angles(rx, ry, rz)
		icePart.Parent      = workspace

		local weld = Instance.new("WeldConstraint")
		weld.Part0  = icePart
		weld.Part1  = limb
		weld.Parent = icePart

		makeExpandTween(icePart, limb.Size * OVERSIZE):Play()

		table.insert(parts, icePart)
	end

	_active[humanoid] = parts
end

function FreezeVfx.stop(humanoid: Humanoid)
	local parts = _active[humanoid]
	if not parts then return end
	_active[humanoid] = nil

	for _, p in parts do
		if not p.Parent then continue end
		makeCollapseTween(p):Play()
		task.delay(COLLAPSE_TIME, function()
			if p.Parent then p:Destroy() end
		end)
	end
end

return FreezeVfx
