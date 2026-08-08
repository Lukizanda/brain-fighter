--!strict

----------------------------------------------------------------------
-- InfernoVfxController
----------------------------------------------------------------------
-- Sets rigs alight and puts them out, driven purely by the `_burning`
-- character attribute, plus the screen-space punch on the frame a rig
-- catches fire.
--
-- Structurally a copy of FreezeVfxController, and intentionally so — the
-- binding problem is identical and its comments explain the shape:
-- attribute-driven because replication does the multiplayer work for
-- free, and watching both player characters and every rig carrying one of
-- SkillConstants.DAMAGEABLE_TAGS because Inferno is aimed at the boss far
-- more often than at anything else.
--
-- What it adds over its sibling is the screen layer. That fires once, on
-- the *rising* edge of the flag, and never on the falling edge or on the
-- initial value a late joiner reads — the difference between "an Inferno
-- just landed" and "an Inferno is currently burning", which look the same
-- to `refresh` and must not feel the same to the player. Someone walking
-- into the arena mid-burn should see a boss on fire, not get punched by a
-- detonation that happened before they arrived.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InfernoVfx     = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.InfernoVfx)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local ScreenImpact   = require(ReplicatedStorage.Shared.Vfx.ScreenImpact)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local VfxConfig      = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("InfernoVfxController")

local BURNING_ATTRIBUTE = SkillConstants.BURNING_ATTRIBUTE

type Watch = { conns: { RBXScriptConnection }, humanoid: Humanoid, lit: boolean }
local _watched: { [Model]: Watch } = {}

local function isBurning(character: Model): boolean
	return character:GetAttribute(BURNING_ATTRIBUTE) == true
end

-- Linear falloff from the camera to VfxConfig.FIRE.screenFalloffStuds.
-- Measured from the camera rather than from the local character because
-- the camera is what the effect is applied to — a player looking across
-- the arena at a blast should feel it at the distance they are *watching*
-- it from.
local function screenIntensityAt(position: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then return 0 end
	local distance = (camera.CFrame.Position - position).Magnitude
	return math.clamp(1 - distance / VfxConfig.FIRE.screenFalloffStuds, 0, 1)
end

local function punchScreen(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end
	ScreenImpact.play(VfxConfig.FIRE.screen, screenIntensityAt((hrp :: BasePart).Position))
end

local function unwatch(character: Model)
	local entry = _watched[character]
	if not entry then return end
	_watched[character] = nil
	for _, conn in entry.conns do
		conn:Disconnect()
	end
	InfernoVfx.stop(entry.humanoid)
end

local function watch(character: Model)
	-- Idempotent: a rig can carry several of the damageable tags, and the
	-- boss additionally arrives through its own tag signal.
	if _watched[character] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local conns: { RBXScriptConnection } = {}
	local entry: Watch = { conns = conns, humanoid = humanoid, lit = false }
	_watched[character] = entry

	-- `punch` is false for the first read so a late joiner inherits the
	-- flames without inheriting the blast. `entry.lit` makes the whole
	-- thing edge-triggered rather than level-triggered: the attribute
	-- signal fires on any write, including a server re-write of the same
	-- value, and re-igniting an already-burning rig would restart its
	-- ignition ramp and re-punch every watching screen.
	local function refresh(punch: boolean)
		local burning = isBurning(character)
		if burning == entry.lit then return end
		entry.lit = burning

		if burning then
			InfernoVfx.start(humanoid)
			if punch then punchScreen(character) end
		else
			InfernoVfx.stop(humanoid)
		end
	end

	table.insert(conns, character:GetAttributeChangedSignal(BURNING_ATTRIBUTE):Connect(function()
		refresh(true)
	end))

	-- Emitters are parented into the rig and go with it, but the Highlight
	-- is parented to the character Model and the CameraOffset is global, so
	-- both exits still need covering.
	table.insert(conns, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			unwatch(character)
		end
	end))

	-- A rig that dies mid-burn has its flag cleared by `purgeBurn`, which
	-- would route through refresh anyway. This is the backstop for a rig
	-- whose death and despawn race each other.
	table.insert(conns, humanoid.Died:Connect(function()
		InfernoVfx.stop(humanoid)
		entry.lit = false
	end))

	refresh(false)
end

----------------------------------------------------------------------
-- Binding
----------------------------------------------------------------------

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	player.CharacterRemoving:Connect(unwatch)
	if player.Character then
		watch(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	if player.Character then
		unwatch(player.Character)
	end
end)

-- The local player dying mid-shake would otherwise strand a non-zero
-- CameraOffset on the respawned character and a tint on the screen.
Players.LocalPlayer.CharacterRemoving:Connect(function()
	ScreenImpact.clear()
end)

for _, tag in SkillConstants.DAMAGEABLE_TAGS do
	for _, rig in CollectionService:GetTagged(tag) do
		if rig:IsA("Model") then
			watch(rig :: Model)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(rig: Instance)
		if not rig:IsA("Model") then return end
		-- A rig is routinely tagged before its Humanoid is parented, in
		-- which case `watch` bails and this rig would never be picked up.
		-- Retry once the Humanoid shows up.
		local model = rig :: Model
		if model:FindFirstChildOfClass("Humanoid") then
			watch(model)
			return
		end
		local conn: RBXScriptConnection
		conn = model.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Humanoid") then
				conn:Disconnect()
				watch(model)
			end
		end)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(rig: Instance)
		if rig:IsA("Model") then
			unwatch(rig :: Model)
		end
	end)
end

log:info("ready")
