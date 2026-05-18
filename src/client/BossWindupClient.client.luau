--!strict

----------------------------------------------------------------------
-- BossWindupClient
----------------------------------------------------------------------
-- Renders telegraph VFX for incoming boss attacks so players have
-- warning before a skill fires. Listens to BossWindupEvent
-- (fired by BossStates.AttackPrepState).
--
-- VFX kinds:
--   aoe_indicator  — pulsing ground disc showing the danger zone radius
--   charge_glow    — growing neon sphere tracking the boss during windup
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local BossWindupEvent: RemoteEvent =
	ReplicatedStorage.Shared.Boss.BossEvents:WaitForChild("BossWindupEvent") :: RemoteEvent

----------------------------------------------------------------------
-- VFX renderers
----------------------------------------------------------------------

local function renderAoeIndicator(boss: Model, durationSec: number, aoeRadius: number?)
	local radius = aoeRadius or 12
	local hrp = boss:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	local center = (hrp :: BasePart).Position

	local disc = Instance.new("Part")
	disc.Name         = "WindupAoeIndicator"
	disc.Shape        = Enum.PartType.Cylinder
	disc.Size         = Vector3.new(0.25, radius * 2, radius * 2)
	disc.CFrame       = CFrame.new(center.X, center.Y - 2.5, center.Z)
		* CFrame.Angles(0, 0, math.pi / 2)
	disc.Anchored     = true
	disc.CanCollide   = false
	disc.CanQuery     = false
	disc.CastShadow   = false
	disc.Color        = Color3.fromRGB(255, 55, 0)
	disc.Material     = Enum.Material.Neon
	disc.Transparency = 0.55
	disc.Parent       = workspace
	Debris:AddItem(disc, durationSec + 0.1)

	-- Pulse faster as the windup nears its end
	local startTime = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not disc.Parent then
			conn:Disconnect()
			return
		end
		local t = (os.clock() - startTime) / durationSec
		if t >= 1 then
			conn:Disconnect()
			if disc.Parent then disc:Destroy() end
			return
		end
		local freq = 4 + t * 10
		disc.Transparency = 0.45 + 0.3 * math.abs(math.sin(os.clock() * freq))
	end)
end

local function renderChargeGlow(boss: Model, durationSec: number, _aoeRadius: number?)
	local hrp = boss:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	local glow = Instance.new("Part")
	glow.Name         = "WindupChargeGlow"
	glow.Shape        = Enum.PartType.Ball
	glow.Size         = Vector3.new(3, 3, 3)
	glow.Anchored     = true
	glow.CanCollide   = false
	glow.CanQuery     = false
	glow.CastShadow   = false
	glow.Material     = Enum.Material.Neon
	glow.Color        = Color3.fromRGB(255, 210, 0)
	glow.Transparency = 0.35
	glow.CFrame       = (hrp :: BasePart).CFrame + Vector3.new(0, 2, 0)
	glow.Parent       = workspace
	Debris:AddItem(glow, durationSec + 0.1)

	local startTime = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not glow.Parent or not hrp.Parent then
			conn:Disconnect()
			return
		end
		local t = (os.clock() - startTime) / durationSec
		if t >= 1 then
			conn:Disconnect()
			if glow.Parent then glow:Destroy() end
			return
		end
		-- Track boss and grow 3→6 studs over the windup
		glow.CFrame = (hrp :: BasePart).CFrame + Vector3.new(0, 2, 0)
		local scale = 3 + t * 3 + 0.4 * math.sin(os.clock() * 7)
		glow.Size         = Vector3.new(scale, scale, scale)
		glow.Transparency = 0.25 + 0.2 * math.sin(os.clock() * 5)
	end)
end

----------------------------------------------------------------------
-- Dispatch table
----------------------------------------------------------------------

type WindupHandler = (boss: Model, durationSec: number, aoeRadius: number?) -> ()

local HANDLERS: { [string]: WindupHandler } = {
	aoe_indicator = renderAoeIndicator,
	charge_glow   = renderChargeGlow,
}

----------------------------------------------------------------------
-- Event listener
----------------------------------------------------------------------

BossWindupEvent.OnClientEvent:Connect(function(
	boss: any,
	windupVfxKind: any,
	durationSec: any,
	aoeRadius: any
)
	local handler = HANDLERS[windupVfxKind :: string]
	if handler then
		handler(boss :: Model, durationSec :: number, aoeRadius :: number?)
	end
end)
