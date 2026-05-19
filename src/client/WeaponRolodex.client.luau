----------------------------------------------------------------------
-- WeaponRolodex (client entry)
----------------------------------------------------------------------
-- Single-card weapon display that cycles through held weapons via
-- Tab (keyboard) or swipe (mobile). Replaces the multi-tile
-- WeaponSlotStrip for better mobile readability.
--
-- Lifecycle:
--   1. Build the rolodex GUI once (persists across respawns)
--   2. On CharacterAdded: scan Backpack + Character for Tools,
--      wire up event listeners, show the equipped weapon
--   3. Tab/Shift+Tab or swipe left/right cycles weapons
--   4. Cycling auto-equips the selected weapon
----------------------------------------------------------------------

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
if not GameConfig.SHOW_WEAPON_ROLODEX then return end

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local WeaponConstants = require(ReplicatedStorage.Shared.Weapon.Constants)
local WeaponRolodexBuilder = require(ReplicatedStorage.Shared.Hud.WeaponRolodexBuilder)
local WeaponRolodexConfig = require(ReplicatedStorage.Shared.Hud.WeaponRolodexConfig)
local adjustListIndexAfterRemoval = require(ReplicatedStorage.Utility.adjustListIndexAfterRemoval)

type WeaponInfo = WeaponRolodexBuilder.WeaponInfo

local log = Logger.new("WeaponRolodex")

local player = Players.LocalPlayer

-- Build the GUI once
local rolodex = WeaponRolodexBuilder.build()
HudLayoutManager:register(HudConstants.WEAPON_PANEL_REGION, rolodex.gui)

-- ============================================================
-- State (rebuilt on each CharacterAdded)
-- ============================================================
-- Normals cycle through the main card; the current Special (0 or 1
-- per player per the loadout design) lives in the dedicated indicator.
local weapons: { WeaponInfo } = {}      -- ordered list of held Normals
local currentIndex: number = 0          -- 1-based index into weapons; 0 = none
local currentSpecial: WeaponInfo? = nil
local connections: { RBXScriptConnection } = {}

-- ============================================================
-- Helpers
-- ============================================================
local function teardown()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	table.clear(weapons)
	currentIndex = 0
	currentSpecial = nil
	ContextActionService:UnbindAction("WeaponRolodexNext")
	ContextActionService:UnbindAction("WeaponRolodexPrev")
end

local function findWeaponIndex(tool: Tool): number?
	for i, w in weapons do
		if w.tool == tool then
			return i
		end
	end
	return nil
end

local function buildInfo(tool: Tool): WeaponInfo?
	-- Only weapons with a category attribute participate in the Rolodex.
	-- Filters out random Tools a player might pick up.
	local category = tool:GetAttribute(WeaponConstants.CATEGORY_ATTRIBUTE)
	if not category then
		return nil
	end
	return {
		tool = tool,
		displayName = tool.Name,
		iconAssetId = tool:GetAttribute(WeaponConstants.ICON_ATTRIBUTE),
	}
end

-- Format the ammo line for the currently-displayed weapon. Returns nil
-- for weapons without a `magazineSize` (melee etc.) so the Rolodex can
-- hide the ammo label entirely.
-- Format: "30 / 90"  (current / reserve). Magazine capacity is implied
-- by how much the number jumps on reload — no need to show it explicitly.
local function ammoTextFor(tool: Tool): string?
	local mag = tool:GetAttribute(WeaponConstants.MAGAZINE_SIZE_ATTRIBUTE)
	if typeof(mag) ~= "number" then
		return nil -- melee / weapons without a magazine
	end
	local cur = tool:GetAttribute(WeaponConstants.AMMO_ATTRIBUTE) or 0
	local reserve = tool:GetAttribute(WeaponConstants.RESERVE_AMMO_ATTRIBUTE)
	if typeof(reserve) == "number" then
		return string.format("%d / %d", cur, reserve)
	end
	return tostring(cur)
end

local function refreshAmmo()
	if currentIndex >= 1 and currentIndex <= #weapons then
		rolodex:setAmmo(ammoTextFor(weapons[currentIndex].tool))
	else
		rolodex:setAmmo(nil)
	end
end

local function refreshDisplay(direction: number?)
	if currentIndex >= 1 and currentIndex <= #weapons then
		rolodex:showWeapon(weapons[currentIndex], direction)
	else
		rolodex:showWeapon(nil)
	end
	rolodex:setDots(#weapons, currentIndex)
	rolodex:setSpecial(currentSpecial)
	refreshAmmo()
end

-- ============================================================
-- Cycling
-- ============================================================
local function cycleNext()
	if #weapons <= 1 then return end -- nothing to cycle through
	local newIndex = currentIndex + 1
	if newIndex > #weapons then newIndex = 1 end
	currentIndex = newIndex
	refreshDisplay(1) -- slide from right

	-- Auto-equip
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and weapons[currentIndex] then
		humanoid:EquipTool(weapons[currentIndex].tool)
	end
end

local function cyclePrev()
	if #weapons <= 1 then return end -- nothing to cycle through
	local newIndex = currentIndex - 1
	if newIndex < 1 then newIndex = #weapons end
	currentIndex = newIndex
	refreshDisplay(-1) -- slide from left

	-- Auto-equip
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and weapons[currentIndex] then
		humanoid:EquipTool(weapons[currentIndex].tool)
	end
end

-- ============================================================
-- Tool tracking
-- ============================================================
local function watchToolDrop(tool: Tool, onDropped: () -> ())
	table.insert(connections, tool.AncestryChanged:Connect(function()
		-- Defer so we read the SETTLED parent. humanoid:EquipTool does an
		-- atomic unequip-then-equip swap that briefly transitions the
		-- previously-equipped tool through `Parent = nil` between Character
		-- and Backpack. Reading synchronously sees that nil window and
		-- false-positives a "dropped" event, removing the tool from the
		-- rolodex even though it's still in the player's possession. By
		-- the time task.defer fires the parent has settled to the new home.
		task.defer(function()
			if not tool.Parent then
				onDropped()
				return
			end
			local backpack = player:FindFirstChildOfClass("Backpack")
			local character = player.Character
			local isHeld = tool.Parent == character or tool.Parent == backpack
			if not isHeld then
				onDropped()
			end
		end)
	end))
end

local function addSpecial(tool: Tool, info: WeaponInfo)
	if currentSpecial and currentSpecial.tool == tool then
		return
	end
	currentSpecial = info

	-- Live-update the indicator if the special's icon changes.
	table.insert(connections, tool:GetAttributeChangedSignal(WeaponConstants.ICON_ATTRIBUTE):Connect(function()
		if currentSpecial and currentSpecial.tool == tool then
			currentSpecial.iconAssetId = tool:GetAttribute(WeaponConstants.ICON_ATTRIBUTE)
			refreshDisplay()
		end
	end))

	watchToolDrop(tool, function()
		if currentSpecial and currentSpecial.tool == tool then
			currentSpecial = nil
			refreshDisplay()
		end
	end)

	refreshDisplay()
	log:info("Added special:", info.displayName)
end

local function addNormal(tool: Tool, info: WeaponInfo)
	if findWeaponIndex(tool) then return end

	-- Append in pickup order — cycle follows the order weapons were picked up.
	table.insert(weapons, info)

	if #weapons == 1 then
		currentIndex = 1
	end

	local character = player.Character
	if tool.Parent == character then
		local idx = findWeaponIndex(tool)
		if idx then currentIndex = idx end
	end

	-- Watch for icon changes (skin swaps)
	table.insert(connections, tool:GetAttributeChangedSignal(WeaponConstants.ICON_ATTRIBUTE):Connect(function()
		local idx = findWeaponIndex(tool)
		if idx then
			weapons[idx].iconAssetId = tool:GetAttribute(WeaponConstants.ICON_ATTRIBUTE)
			if currentIndex == idx then
				refreshDisplay()
			end
		end
	end))

	-- Watch for ammo changes
	local function onAmmoChanged()
		if findWeaponIndex(tool) == currentIndex then
			refreshAmmo()
		end
	end
	table.insert(connections,
		tool:GetAttributeChangedSignal(WeaponConstants.AMMO_ATTRIBUTE):Connect(onAmmoChanged))
	table.insert(connections,
		tool:GetAttributeChangedSignal(WeaponConstants.RESERVE_AMMO_ATTRIBUTE):Connect(onAmmoChanged))

	watchToolDrop(tool, function()
		local idx = findWeaponIndex(tool)
		if idx then
			table.remove(weapons, idx)
			-- When a tool BEFORE the current one is removed (cap-eviction
			-- killing the oldest while the player holds the newer), the
			-- surviving entries shift left under the index. Without
			-- decrementing, currentIndex silently desyncs and the next
			-- Tab cycles from the wrong slot.
			currentIndex = adjustListIndexAfterRemoval(idx, currentIndex, #weapons)
			refreshDisplay()
		end
	end)

	-- Watch equip/unequip to track which Normal is active
	table.insert(connections, tool.Equipped:Connect(function()
		local idx = findWeaponIndex(tool)
		if idx then
			currentIndex = idx
			refreshDisplay()
		end
	end))

	refreshDisplay()
	log:info("Added normal:", info.displayName, "total:", #weapons)
end

local function addTool(tool: Tool)
	-- Defer so sibling Backpack.ChildAdded handlers (PickupStacker
	-- destroying same-name dupes for ammo stacking; LoadoutService
	-- evicting the oldest Normal when the cap is exceeded) get to
	-- run first. Without this, ordering of synchronous ChildAdded
	-- handlers can leave us inserting a Tool that's already had its
	-- Parent set to nil by a sibling handler — and AncestryChanged
	-- will never fire again on a Tool whose parent is already
	-- settled at nil, so our drop-cleanup listener never prunes it.
	-- The ghost entry sticks around until character respawn, and the
	-- next Tab calls EquipTool on a destroyed Tool — which throws
	-- "Parent property of X is locked" mid-swap, leaving the player
	-- in Unequipped (NIM-12).
	--
	-- This mirrors the pattern LoadoutService.onToolAdded uses
	-- server-side for the same race.
	task.defer(function()
		if not tool.Parent then
			return
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		local character = player.Character
		if tool.Parent ~= backpack and tool.Parent ~= character then
			return
		end

		local info = buildInfo(tool)
		if not info then return end -- no WeaponCategory attribute

		local category = tool:GetAttribute(WeaponConstants.CATEGORY_ATTRIBUTE)
		if category == WeaponConstants.Category.Special then
			addSpecial(tool, info)
		else
			addNormal(tool, info)
		end
	end)
end

local function scanForTools(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("Tool") then
			addTool(child)
		end
	end
end

-- ============================================================
-- Swipe detection
-- ============================================================
local swipeStartPos: Vector3? = nil

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		-- Only track swipes that start on the card
		swipeStartPos = input.Position
	end
end

local function onInputEnded(input: InputObject, gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	if not swipeStartPos then return end

	local delta = input.Position - swipeStartPos
	swipeStartPos = nil

	local horizontalDist = math.abs(delta.X)
	local verticalDist = math.abs(delta.Y)

	if horizontalDist < WeaponRolodexConfig.SWIPE_MIN_DISTANCE then return end
	if verticalDist > WeaponRolodexConfig.SWIPE_MAX_VERTICAL then return end

	if delta.X < 0 then
		cycleNext() -- swipe left = next
	else
		cyclePrev() -- swipe right = prev
	end
end

-- ============================================================
-- Character wiring
-- ============================================================
local function rewire(character: Model)
	teardown()

	local backpack = player:FindFirstChildOfClass("Backpack")

	-- Scan existing tools
	scanForTools(character)
	if backpack then
		scanForTools(backpack)
	end

	-- Watch for new tools
	if backpack then
		table.insert(connections, backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then addTool(child) end
		end))
	end
	table.insert(connections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then addTool(child) end
	end))

	-- Cooldown overlay watcher — Heartbeat reads _cooldownEnd on whichever
	-- Special the player currently holds. The attribute is a
	-- workspace:GetServerTimeNow() timestamp set by the special's server
	-- runtime when activation triggers cooldown; 0/nil = ready.
	table.insert(connections, RunService.Heartbeat:Connect(function()
		if not currentSpecial or not currentSpecial.tool.Parent then
			rolodex:setSpecialCooldown(nil)
			return
		end
		local cooldownEnd = currentSpecial.tool:GetAttribute(WeaponConstants.COOLDOWN_END_ATTRIBUTE) or 0
		if typeof(cooldownEnd) ~= "number" or cooldownEnd <= 0 then
			rolodex:setSpecialCooldown(nil)
			return
		end
		local remaining = cooldownEnd - Workspace:GetServerTimeNow()
		rolodex:setSpecialCooldown(if remaining > 0 then remaining else nil)
	end))

	-- Keyboard: Tab = next, Shift+Tab = prev
	ContextActionService:BindAction("WeaponRolodexNext", function(_, state)
		if state == Enum.UserInputState.Begin then
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				cyclePrev()
			else
				cycleNext()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab)

	-- Touch: swipe on the card frame
	local cardFrame = rolodex:getCardFrame()
	table.insert(connections, cardFrame.InputBegan:Connect(onInputBegan))
	table.insert(connections, cardFrame.InputEnded:Connect(onInputEnded))

	refreshDisplay()
	log:info("Rewired for character:", character.Name, "weapons:", #weapons)
end

if player.Character then
	rewire(player.Character)
end
player.CharacterAdded:Connect(rewire)

log:info("Initialized")
