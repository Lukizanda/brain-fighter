--!strict

----------------------------------------------------------------------
-- ArrivalProtectionVfxController
----------------------------------------------------------------------
-- Draws a gold bubble around any player character inside a protection
-- window, so a player who just teleported onto the island can see they are
-- safe for a moment (and others can see why a shot did nothing).
--
-- Driven purely by the `_protectedUntil` character attribute, the instant the
-- window closes in `workspace:GetServerTimeNow()` time. Health owns the
-- window (shared/Health/Protection); this only reads it. The bubble is its
-- own Part, not ShieldVfx's: that one is the spell shield's, keyed to the
-- `_shield` pool and the shell that deflects projectiles, and sharing it
-- would let one status tear down the other. This bubble is cosmetic only
-- (CanQuery off) and deflects nothing; the block is in `applyDamage`.
--
-- Nothing counts the window down here beyond one `task.delay` to the close
-- time: when it fires, the attribute is read again, so a window that was
-- extended meanwhile keeps its bubble.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CharacterAttributeWatcher = require(ReplicatedStorage.Shared.Vfx.CharacterAttributeWatcher)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Protection = require(ReplicatedStorage.Shared.Health.Protection)

local log = Logger.new("ArrivalProtectionVfxController")

local BUBBLE_NAME = "ArrivalProtectionBubble"
local SPAWN_DIAMETER_STUDS = 0.2
local EXPAND_SEC = 0.25
local COLLAPSE_SEC = 0.2

type Active = {
	bubble: Part,
	closeThread: thread?,
}

local active: { [Model]: Active } = {}

local function resolveRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function raise(character: Model): Active?
	local root = resolveRoot(character)
	if not root then
		return nil
	end
	local bubble = Instance.new("Part")
	bubble.Name = BUBBLE_NAME
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Color = HealthConstants.PROTECTION_BUBBLE_COLOR
	bubble.Transparency = HealthConstants.PROTECTION_BUBBLE_TRANSPARENCY
	bubble.Size = Vector3.new(SPAWN_DIAMETER_STUDS, SPAWN_DIAMETER_STUDS, SPAWN_DIAMETER_STUDS)
	bubble.CFrame = root.CFrame
	bubble.Anchored = false
	bubble.CanCollide = false
	-- Load-bearing: spell targeting and projectile raycasts sweep the
	-- workspace, and a body-sized ball would swallow them.
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.CastShadow = false
	bubble.Massless = true
	-- In workspace rather than the character, so nothing that walks the
	-- character's parts (FreezeVfx) picks it up.
	bubble.Parent = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bubble
	weld.Part1 = root
	weld.Parent = bubble

	local diameter = HealthConstants.PROTECTION_BUBBLE_DIAMETER_STUDS
	TweenService:Create(
		bubble,
		TweenInfo.new(EXPAND_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.new(diameter, diameter, diameter) }
	):Play()

	local entry: Active = { bubble = bubble, closeThread = nil }
	active[character] = entry
	return entry
end

local function drop(character: Model)
	local entry = active[character]
	if not entry then
		return
	end
	active[character] = nil
	if entry.closeThread then
		pcall(task.cancel, entry.closeThread)
		entry.closeThread = nil
	end
	local bubble = entry.bubble
	if not bubble.Parent then
		return
	end
	TweenService:Create(
		bubble,
		TweenInfo.new(COLLAPSE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0, 0, 0), Transparency = 1 }
	):Play()
	task.delay(COLLAPSE_SEC, function()
		if bubble.Parent then
			bubble:Destroy()
		end
	end)
end

-- Bring the bubble in line with the attribute as it reads now.
local function refresh(character: Model)
	local closesAt = Protection.closesAt(character)
	local now = workspace:GetServerTimeNow()
	if closesAt == nil or closesAt <= now then
		drop(character)
		return
	end

	local entry = active[character] or raise(character)
	if not entry then
		return
	end
	if entry.closeThread then
		pcall(task.cancel, entry.closeThread)
	end
	entry.closeThread = task.delay(closesAt - now, function()
		entry.closeThread = nil
		refresh(character)
	end)
end

local watcher = CharacterAttributeWatcher.new({
	label = "ArrivalProtectionVfxController",
	attributes = { HealthConstants.PROTECTED_UNTIL_ATTRIBUTE },
	includeTaggedRigs = false,
	includeLocalPlayer = true,

	handlers = {
		onRefresh = function(character: Model, _humanoid: Humanoid, _initial: boolean)
			refresh(character)
		end,
		onDetach = function(character: Model, _humanoid: Humanoid)
			drop(character)
		end,
		onDied = function(character: Model, _humanoid: Humanoid)
			drop(character)
		end,
	},
})

watcher:enable()

-- Rojo replaces this script on every sync; see FreezeVfxController.
script.Destroying:Connect(function()
	watcher:destroy()
	for character in active do
		drop(character)
	end
end)

log:info("ready")
