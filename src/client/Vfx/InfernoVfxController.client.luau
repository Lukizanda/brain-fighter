--!strict

----------------------------------------------------------------------
-- InfernoVfxController
----------------------------------------------------------------------
-- Sets rigs alight and puts them out, driven purely by the `_burning`
-- character attribute, plus the screen-space punch on the frame a rig
-- catches fire.
--
-- Sibling of FreezeVfxController: same watcher, same tag coverage (Inferno
-- is aimed at the boss far more often than at anything else), and
-- CharacterAttributeWatcher's header explains the binding both share.
--
-- What it adds over its sibling is the screen layer, and that is why this
-- one is **edge-triggered**. The punch fires on the rising edge of the
-- flag only — never on the falling edge, never on the initial value a late
-- joiner reads, and never on a server re-write of a value that did not
-- change. "An Inferno just landed" and "an Inferno is currently burning"
-- look the same to a refresh and must not feel the same to the player:
-- someone walking into the arena mid-burn should see a boss on fire, not
-- get punched by a detonation that happened before they arrived. Re-
-- igniting an already-burning rig would also restart its ignition ramp.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAttributeWatcher = require(ReplicatedStorage.Shared.Vfx.CharacterAttributeWatcher)
local InfernoVfx     = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.InfernoVfx)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local ScreenImpact   = require(ReplicatedStorage.Shared.Vfx.ScreenImpact)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local VfxConfig      = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("InfernoVfxController")

local BURNING_ATTRIBUTE = SkillConstants.BURNING_ATTRIBUTE

-- Which rigs this client currently has alight. The edge flag: the
-- attribute signal fires on any write, including one that does not change
-- the value.
local _lit: { [Model]: boolean } = {}

local function isBurning(rig: Model): boolean
	return rig:GetAttribute(BURNING_ATTRIBUTE) == true
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

local function punchScreen(rig: Model)
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end
	ScreenImpact.play(VfxConfig.FIRE.screen, screenIntensityAt((hrp :: BasePart).Position))
end

local watcher = CharacterAttributeWatcher.new({
	label              = "InfernoVfxController",
	attributes         = { BURNING_ATTRIBUTE },
	includeTaggedRigs  = true,
	includeLocalPlayer = true,

	handlers = {
		onRefresh = function(rig: Model, humanoid: Humanoid, initial: boolean)
			local burning = isBurning(rig)
			if burning == (_lit[rig] == true) then return end
			_lit[rig] = burning

			if burning then
				InfernoVfx.start(humanoid)
				-- The one line that makes this controller differ from Freeze's.
				if not initial then punchScreen(rig) end
			else
				InfernoVfx.stop(humanoid)
			end
		end,

		-- Emitters are parented into the rig and go with it, but the
		-- Highlight hangs off the character Model and the CameraOffset is
		-- global, so both still need taking off by hand.
		onDetach = function(rig: Model, humanoid: Humanoid)
			_lit[rig] = nil
			InfernoVfx.stop(humanoid)
		end,

		-- Backstop for a rig whose death and despawn race each other: a rig
		-- that dies mid-burn normally has its flag cleared by `purgeBurn`,
		-- which would route through onRefresh.
		onDied = function(rig: Model, humanoid: Humanoid)
			InfernoVfx.stop(humanoid)
			_lit[rig] = false
		end,
	},
})

watcher:enable()

-- The local player dying mid-shake would otherwise strand a non-zero
-- CameraOffset on the respawned character and a tint on the screen.
local localCharacterRemoving = Players.LocalPlayer.CharacterRemoving:Connect(function()
	ScreenImpact.clear()
end)

-- Rojo replaces this script on every sync; see FreezeVfxController.
script.Destroying:Connect(function()
	localCharacterRemoving:Disconnect()
	watcher:destroy()
	table.clear(_lit)
	ScreenImpact.clear()
end)

log:info("ready")
