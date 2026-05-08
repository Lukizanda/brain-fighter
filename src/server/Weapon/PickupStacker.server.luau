----------------------------------------------------------------------
-- PickupStacker
----------------------------------------------------------------------
-- When a player picks up a weapon they already have (same Tool.Name),
-- don't give them a duplicate Tool. Instead, top up the existing
-- weapon's reserve ammo by `pickupAmmoBonus`, clamped to
-- `maxReserveAmmo`, and destroy the fresh one.
--
-- Only triggers for weapons with the `pickupAmmoBonus` attribute
-- (i.e. ranged weapons). Melee weapons have no reserve and the player
-- simply can't pick up a duplicate (the first one stays).
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local Ammo = require(ReplicatedStorage.Shared.Weapon.Scripts.Ammo)

local log = Logger.new("PickupStacker")

-- Find another Tool with the same Name in either Backpack or Character,
-- excluding the newly-picked-up one itself.
local function findExistingDuplicate(player: Player, newTool: Tool): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, other in ipairs(backpack:GetChildren()) do
			if other ~= newTool and other:IsA("Tool") and other.Name == newTool.Name then
				return other
			end
		end
	end
	local character = player.Character
	if character then
		for _, other in ipairs(character:GetChildren()) do
			if other ~= newTool and other:IsA("Tool") and other.Name == newTool.Name then
				return other
			end
		end
	end
	return nil
end

local function onToolAdded(player: Player, newTool: Tool)
	if not newTool:IsA("Tool") then
		return
	end

	local bonus = newTool:GetAttribute(Constants.PICKUP_AMMO_BONUS_ATTRIBUTE)
	if typeof(bonus) ~= "number" or bonus <= 0 then
		return -- not a stackable weapon (e.g. melee)
	end

	local existing = findExistingDuplicate(player, newTool)
	if not existing then
		return -- first copy; keep it
	end

	local added = Ammo.addReserve(existing, bonus)
	log:info(string.format("%s: stacked '%s' pickup → +%d reserve (reserve=%d)",
		player.Name, newTool.Name, added,
		existing:GetAttribute(Constants.RESERVE_AMMO_ATTRIBUTE) or 0))

	-- Destroy the duplicate so the player doesn't end up with two Tools
	newTool:Destroy()
end

-- IMPORTANT: Roblox replaces the Player.Backpack instance on every
-- character load (verified empirically 2026-04-23, see comment in
-- LoadoutService.server.luau:235). Hooking only at PlayerAdded — which
-- this script used to do — binds to the original Backpack, which Roblox
-- then destroys when the first character spawns, silently disconnecting
-- the ChildAdded signal. Result: ammo-stacking stopped working after
-- the first death/respawn until D2 fixed it. The hookBackpack +
-- watchPlayer pattern below mirrors LoadoutService's solution: re-hook
-- on every CharacterAdded (and via Player.ChildAdded as a belt-and-
-- suspenders fallback). The hookedBackpacks set deduplicates so the
-- same container isn't wired twice.
local hookedBackpacks: { [Instance]: true } = {}

local function hookBackpack(player: Player, backpack: Instance)
	if hookedBackpacks[backpack] then
		return
	end
	hookedBackpacks[backpack] = true
	backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolAdded(player, child)
		end
	end)
	backpack.AncestryChanged:Connect(function()
		if not backpack.Parent then
			hookedBackpacks[backpack] = nil
		end
	end)
end

local function watchPlayer(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		hookBackpack(player, backpack)
	end
	player.CharacterAdded:Connect(function()
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			hookBackpack(player, bp)
		end
	end)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			hookBackpack(player, child)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(watchPlayer, player)
end
Players.PlayerAdded:Connect(watchPlayer)

log:info("Initialized")
