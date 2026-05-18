--!strict

----------------------------------------------------------------------
-- BossSpawner
----------------------------------------------------------------------
-- Builds the Boss Model from the Patroller rig template:
--   - typeSpec.bodyScale× body scale
--   - Phase 1 color / walk speed from typeSpec
--   - ShieldPart + LeftArmCore visual placeholders (welded)
--   - BillboardGui above head
--   - Tagged "Boss" so SpellMenuGui auto-targets it
--
-- BossService.server.luau owns the lifecycle (death / respawn).
-- This module only constructs the model.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local Logger    = require(ReplicatedStorage.Shared.Core.Logger)

type BossTypeSpec = BossTypes.BossTypeSpec

local log = Logger.new("BossSpawner")

local BOSS_TAG       = "Boss"
local SPAWN_Y_OFFSET = 12   -- studs above BossPoint surface; boss falls to ground on spawn

local BossSpawner = {}

-- ---------------------------------------------------------------
-- Internal: add a welded visual part to the boss model.
-- The part's CFrame is set relative to `anchorPart` before the
-- WeldConstraint is created, so the offset is captured correctly.
-- ---------------------------------------------------------------
local function addWeldedPart(boss: Model, anchorPart: BasePart, opts: {
	name: string,
	size: Vector3,
	shape: Enum.PartType?,
	color: BrickColor,
	material: Enum.Material,
	transparency: number,
	localOffset: CFrame,
	partName: string, -- value for BossPartName attribute
}): Part
	local part = Instance.new("Part")
	part.Name = opts.name
	part.Size = opts.size
	if opts.shape then
		part.Shape = opts.shape
	end
	part.BrickColor   = opts.color
	part.Material     = opts.material
	part.Transparency = opts.transparency
	part.Anchored     = false
	part.CanCollide   = false
	part.CanQuery     = false
	part.CastShadow   = false
	part.CFrame       = anchorPart.CFrame * opts.localOffset
	part:SetAttribute("BossPartName", opts.partName)
	part.Parent = boss

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = part
	weld.Part1  = anchorPart
	weld.Parent = boss

	return part
end

-- ---------------------------------------------------------------
-- Internal: add billboard HP label above the boss head.
-- Falls back to HumanoidRootPart with a taller offset when the
-- rig has no "Head" part (e.g. BossBrain custom rigs).
-- ---------------------------------------------------------------
local function addBillboard(boss: Model)
	local anchor = boss:FindFirstChild("Head")
	local offset = Vector3.new(0, 5, 0)
	if not anchor or not anchor:IsA("BasePart") then
		anchor = boss:FindFirstChild("HumanoidRootPart")
		offset = Vector3.new(0, 9, 0)
	end
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	local head = anchor

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "BossLabel"
	billboard.Size        = UDim2.new(0, 220, 0, 55)
	billboard.StudsOffset = offset
	billboard.AlwaysOnTop = false

	local bg = Instance.new("Frame")
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = Color3.fromRGB(120, 0, 0)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel        = 0
	bg.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3            = Color3.new(1, 1, 1)
	label.TextScaled            = true
	label.Font                  = Enum.Font.GothamBold
	label.Text                  = "BOSS"
	label.Parent                = bg

	billboard.Parent = head
end

-- ---------------------------------------------------------------
-- Public: spawn boss at bossPoint using typeSpec. Returns Model or nil.
-- ---------------------------------------------------------------
function BossSpawner.spawn(bossPoint: BasePart, typeSpec: BossTypeSpec): Model?
	local aiWorldData = ServerStorage:FindFirstChild("AIWorldData")
	local rigs = aiWorldData and aiWorldData:FindFirstChild("Rigs")
	if not rigs then
		log:warn("ServerStorage.AIWorldData.Rigs not found")
		return nil
	end

	local rigName = typeSpec.rigName or "Patroller"
	local template = rigs:FindFirstChild(rigName)
	if not template or not template:IsA("Model") then
		log:warn("Rig '" .. rigName .. "' not found in AIWorldData.Rigs")
		return nil
	end

	local boss: Model = template:Clone()
	boss.Name = "Boss"

	-- ── Humanoid setup ──────────────────────────────────────────
	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:warn(rigName .. " rig has no Humanoid")
		boss:Destroy()
		return nil
	end

	local phase1 = typeSpec.phases[1]

	humanoid.MaxHealth           = typeSpec.maxHealth
	humanoid.Health              = typeSpec.maxHealth
	humanoid.WalkSpeed           = phase1.walkSpeed
	humanoid.JumpPower           = 0
	humanoid.BreakJointsOnDeath  = false

	-- Apply scale then destroy the NumberValues immediately. Roblox's character
	-- scaling system keeps HipHeight = scale × baseHipHeight (e.g. 6 at 3×), but the
	-- rig's physical foot geometry doesn't match that height, so the physics engine
	-- fights a large vertical error that absorbs all motor force and prevents movement.
	-- Destroying the NumberValues after the scale is baked in lets HipHeight settle at
	-- the rig's natural value (~2) rather than being locked at 6.
	local allScaleNames = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "BodyProportionScale", "HeadScale" }
	for _, scaleName in allScaleNames do
		local sv = humanoid:FindFirstChild(scaleName)
		if sv and sv:IsA("NumberValue") then
			if scaleName == "BodyHeightScale" or scaleName == "BodyWidthScale" or scaleName == "BodyDepthScale" then
				sv.Value = typeSpec.bodyScale
			end
			sv:Destroy()
		end
	end

	-- Override HipHeight after scale bake-in (custom rigs set this to control hover height)
	if typeSpec.hipHeight then
		humanoid.HipHeight = typeSpec.hipHeight
	end

	-- ── Color all visible parts (skip HRP and KeepColor-marked parts) ─
	for _, desc in boss:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart"
			and not desc:GetAttribute("KeepColor") then
			desc.BrickColor = phase1.bodyColor
			desc.Material   = Enum.Material.SmoothPlastic
		end
	end

	-- ── Welded visual parts — only for Patroller-based rigs ─────────
	-- Custom rigs (e.g. BossBrain) define their own visual parts in the template.
	local hrp = boss:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") and not typeSpec.rigName then
		addWeldedPart(boss, hrp :: BasePart, {
			name         = "ShieldPart",
			size         = Vector3.new(8, 10, 0.5),
			color        = BrickColor.new("Bright blue"),
			material     = Enum.Material.Neon,
			transparency = 0.55,
			localOffset  = CFrame.new(0, 0, -5),
			partName     = "Shield",
		})

		addWeldedPart(boss, hrp :: BasePart, {
			name         = "LeftArmCore",
			size         = Vector3.new(2.5, 2.5, 2.5),
			shape        = Enum.PartType.Ball,
			color        = BrickColor.new("Bright orange"),
			material     = Enum.Material.Neon,
			transparency = 0.3,
			localOffset  = CFrame.new(-5, 1.5, 0),
			partName     = "LeftArm",
		})
	end

	-- ── Billboard ───────────────────────────────────────────────
	addBillboard(boss)

	-- ── CollectionService tag (SpellMenuGui targets "Boss"-named models) ─
	CollectionService:AddTag(boss, BOSS_TAG)

	-- ── Position above BossPoint ────────────────────────────────
	local spawnY = bossPoint.Position.Y + bossPoint.Size.Y / 2 + SPAWN_Y_OFFSET
	boss:PivotTo(CFrame.new(bossPoint.Position.X, spawnY, bossPoint.Position.Z))
	boss.Parent = workspace

	log:info(string.format(
		"Boss '%s' spawned at (%.1f, %.1f, %.1f) HP=%d scale=%.1f×",
		typeSpec.name,
		bossPoint.Position.X, spawnY, bossPoint.Position.Z,
		typeSpec.maxHealth, typeSpec.bodyScale
	))

	return boss
end

return BossSpawner
