--[[
	DummyBoss (Dev)
	----------------
	Spawns a static, high-HP boss dummy at the BossPoint part in Workspace.
	Uses the Patroller rig from ServerStorage so hitboxes and Humanoid are
	already correct for the damage pipeline.

	Scaled to 1.5×, coloured red, WalkSpeed = 0, MaxHealth = 500.
	Tagged "NPC" so the damage / death systems treat it the same as a live NPC.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("DummyBoss")

local BOSS_MAX_HEALTH = 500
local BOSS_SCALE = 1.5

local function spawnDummyBoss()
	local bossPoint = workspace:FindFirstChild("BossPoint")
	if not bossPoint or not bossPoint:IsA("BasePart") then
		log:warn("BossPoint part not found in Workspace — skipping dummy boss spawn")
		return
	end

	local aiWorldData = ServerStorage:FindFirstChild("AIWorldData")
	local rigs = aiWorldData and aiWorldData:FindFirstChild("Rigs")
	if not rigs then
		log:warn("ServerStorage.AIWorldData.Rigs not found — skipping dummy boss spawn")
		return
	end

	local template = rigs:FindFirstChild("Patroller")
	if not template or not template:IsA("Model") then
		log:warn("Patroller rig not found in AIWorldData.Rigs — skipping dummy boss spawn")
		return
	end

	local boss = template:Clone()
	boss.Name = "DummyBoss"

	-- Configure humanoid — static target, no movement
	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = BOSS_MAX_HEALTH
		humanoid.Health = BOSS_MAX_HEALTH
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0

		local scales = {
			BodyHeightScale = BOSS_SCALE,
			BodyWidthScale = BOSS_SCALE,
			BodyDepthScale = BOSS_SCALE,
		}
		for name, value in scales do
			local sv = humanoid:FindFirstChild(name)
			if sv and sv:IsA("NumberValue") then
				sv.Value = value
			end
		end
	end

	-- Tint all visible parts red so it reads as a boss
	for _, part in boss:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.BrickColor = BrickColor.new("Bright red")
			part.Material = Enum.Material.SmoothPlastic
		end
	end

	-- "BOSS" overhead label
	local head = boss:FindFirstChild("Head")
	if head then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "BossLabel"
		billboard.Size = UDim2.new(0, 120, 0, 40)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = false

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
		label.BackgroundTransparency = 0.2
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = "BOSS  500 HP"
		label.Parent = billboard

		billboard.Parent = head
	end

	-- Place 3 studs above the BossPoint surface
	local spawnPos = bossPoint.Position + Vector3.new(0, bossPoint.Size.Y / 2 + 3, 0)
	boss:PivotTo(CFrame.new(spawnPos))

	-- Tag so HealthService / DeathHandler treat it as an NPC
	CollectionService:AddTag(boss, NPCConstants.TAG_NPC)

	boss.Parent = workspace

	log:info(string.format("DummyBoss spawned at %s (HP=%d, scale=%.1f×)",
		tostring(spawnPos), BOSS_MAX_HEALTH, BOSS_SCALE))
end

spawnDummyBoss()
