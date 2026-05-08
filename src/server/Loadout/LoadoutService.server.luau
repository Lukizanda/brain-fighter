----------------------------------------------------------------------
-- LoadoutService
----------------------------------------------------------------------
-- Enforces loadout rules for the hero-shooter loadout system (see
-- docs/loadout-system-plan.md). Runs alongside PickupStacker — which
-- handles same-name ammo stacking — and adds:
--
--   1. Special uniqueness: only one player per team may hold a given
--      SpecialId at a time. If the team has already claimed that
--      special, an incoming pickup of the same special is destroyed.
--   2. Normal 2-slot cap with oldest-evicts-first: when a player
--      picks up a 3rd Normal weapon, their oldest-held Normal is
--      destroyed and the new one lands. The evict-to-pedestal
--      refinement is Phase 3B scene work.
--   3. Voluntary drop via the LoadoutRequestDrop RemoteEvent: when a
--      client fires it, the player's currently-equipped Tool is
--      destroyed. Claim release + pickup-order list update happens
--      automatically through the tool's AncestryChanged hook.
--
-- Team scope:
--   When the player has a Team assigned, the claim is keyed on that
--   Team. When they don't, the claim is keyed on the player itself —
--   effectively "each player is their own team", which is correct for
--   team-less test sessions.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local WeaponConstants = require(ReplicatedStorage.Shared.Weapon.Constants)

local log = Logger.new("LoadoutService")

local NORMAL_SLOT_CAP = 2

-- Nested map: teamKey -> specialId -> Player
local teamClaims: { [any]: { [string]: Player } } = {}

-- Which specials each player currently holds, indexed by Tool so
-- AncestryChanged can release the right claim when that tool is dropped.
local playerSpecials: { [Player]: { [Tool]: string } } = {}

-- Per-player pickup order of Normal weapons. Oldest first.
local normalPickupOrder: { [Player]: { Tool } } = {}

local function teamKeyFor(player: Player): any
	return player.Team or player
end

local function getClaim(player: Player, specialId: string): Player?
	local bucket = teamClaims[teamKeyFor(player)]
	return bucket and bucket[specialId] or nil
end

local function setClaim(player: Player, specialId: string)
	local key = teamKeyFor(player)
	local bucket = teamClaims[key]
	if not bucket then
		bucket = {}
		teamClaims[key] = bucket
	end
	bucket[specialId] = player
end

local function clearClaim(player: Player, specialId: string)
	local bucket = teamClaims[teamKeyFor(player)]
	if bucket and bucket[specialId] == player then
		bucket[specialId] = nil
	end
end

local function isHeldBy(player: Player, tool: Tool): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	return tool.Parent == backpack or tool.Parent == character
end

-- When a held Special tool leaves Backpack + Character (drop / destroy /
-- character reset), release its claim.
--
-- The synchronous `isHeldBy` check is safe here even though it's a
-- multi-target (Backpack ∪ Character) parent check. The
-- `feedback_ancestrychanged_race.md` race that bit WeaponRolodex is
-- CLIENT-side only: client-side AncestryChanged sees the
-- replicated parent change in two stages (briefly transitioning through
-- `Parent = nil`), but server-side AncestryChanged fires once with the
-- final settled parent. Verified empirically 2026-05-06 via the
-- SimulateLoadoutCycling harness's eviction-order probe — the race
-- doesn't fire on the server.
local function watchSpecialDrop(player: Player, tool: Tool, specialId: string)
	playerSpecials[player] = playerSpecials[player] or {}
	playerSpecials[player][tool] = specialId

	tool.AncestryChanged:Connect(function()
		if isHeldBy(player, tool) then
			return
		end
		local map = playerSpecials[player]
		if map then
			map[tool] = nil
		end
		clearClaim(player, specialId)
		log:info(string.format("%s: released '%s' claim", player.Name, specialId))
	end)
end

-- When a Normal tool leaves the player's inventory, prune it from the
-- pickup-order list so the next overflow eviction targets the true
-- oldest remaining Normal. Same server-side AncestryChanged guarantee
-- as watchSpecialDrop above — no defer needed.
local function watchNormalDrop(player: Player, tool: Tool)
	tool.AncestryChanged:Connect(function()
		if isHeldBy(player, tool) then
			return
		end
		local order = normalPickupOrder[player]
		if not order then
			return
		end
		local idx = table.find(order, tool)
		if idx then
			table.remove(order, idx)
		end
	end)
end

-- Evict the oldest Normal tool(s) until the player is under the cap.
-- Destroys the evictees. When Phase 3B's respawn-zone pedestals land,
-- this will instead route the evicted tool back to its source pedestal.
local function evictToNormalCap(player: Player)
	local order = normalPickupOrder[player]
	if not order then
		return
	end
	while #order >= NORMAL_SLOT_CAP do
		local oldest = table.remove(order, 1)
		if oldest and oldest.Parent then
			log:info(string.format("%s: evicting oldest Normal '%s' (cap=%d)",
				player.Name, oldest.Name, NORMAL_SLOT_CAP))
			oldest:Destroy()
		end
	end
end

-- Register a newly-picked-up Normal tool with the pickup-order tracker.
-- Idempotent: this fires from `Backpack.ChildAdded`, which Roblox raises
-- every time a tool re-enters the backpack — including each Tab-cycle's
-- unequip swap. Re-registering a tool we already track would (a) re-run
-- evictToNormalCap and destroy a sibling, and (b) leak a duplicate
-- AncestryChanged connection. The early-return below makes the function
-- safe to call on every ChildAdded.
local function registerNormal(player: Player, tool: Tool)
	local order = normalPickupOrder[player]
	if order and table.find(order, tool) then
		return
	end

	evictToNormalCap(player)
	if not order then
		order = {}
		normalPickupOrder[player] = order
	end
	table.insert(order, tool)
	watchNormalDrop(player, tool)
end

local function onToolAdded(player: Player, tool: Tool)
	-- Deferred so PickupStacker — which hooks the same ChildAdded signal
	-- and stacks ammo onto an existing same-name tool by destroying the
	-- duplicate — gets to run first. If it destroyed the tool, our
	-- Parent-nil check below short-circuits us.
	task.defer(function()
		if not tool.Parent then
			return
		end

		local category = tool:GetAttribute(WeaponConstants.CATEGORY_ATTRIBUTE)
		if category == WeaponConstants.Category.Normal then
			registerNormal(player, tool)
			return
		end
		if category ~= WeaponConstants.Category.Special then
			return
		end

		local specialId = tool:GetAttribute(WeaponConstants.SPECIAL_ID_ATTRIBUTE)
		if typeof(specialId) ~= "string" or specialId == "" then
			log:warn(string.format("%s: special tool '%s' has no SpecialId; ignoring",
				player.Name, tool.Name))
			return
		end

		-- Idempotent re-entry guard: ChildAdded fires every Tab-cycle when
		-- the previously-equipped Special re-enters the backpack. If we
		-- already track THIS exact Tool for this player, it's not a fresh
		-- pickup attempt — skip the duplicate-claim rejection (which would
		-- otherwise destroy the player's own Special on every Tab press).
		local heldByPlayer = playerSpecials[player]
		if heldByPlayer and heldByPlayer[tool] then
			return
		end

		-- Reject if any holder (even self) already has the claim with a
		-- DIFFERENT tool instance: a single player cannot carry two of the
		-- same special, and a teammate cannot take one already held on
		-- the team.
		local holder = getClaim(player, specialId)
		if holder then
			local reason = if holder == player
				then "you already hold it"
				else ("team already holds it (held by " .. holder.Name .. ")")
			log:info(string.format("%s: rejecting '%s' pickup — %s",
				player.Name, specialId, reason))
			tool:Destroy()
			return
		end

		setClaim(player, specialId)
		watchSpecialDrop(player, tool, specialId)
		log:info(string.format("%s: claimed '%s'", player.Name, specialId))
	end)
end

-- Tracks which Backpack/Character instances we've already hooked, so a
-- repeat character-added doesn't double-wire the same container.
local hookedBackpacks: { [Instance]: true } = {}
local hookedCharacters: { [Instance]: true } = {}

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

-- IMPORTANT: pedestal pickups go Workspace → Character via Roblox's
-- engine-side Tool auto-equip (when the player has nothing equipped,
-- or when the new Tool replaces the equipped one). That path NEVER
-- fires `Backpack.ChildAdded`, so a Backpack-only hook misses every
-- pedestal pickup until the player Tab-cycles and the engine moves
-- the previously-equipped tool back to Backpack — by which point a
-- single `registerNormal` call evicts the freshly-equipped weapon
-- the player just tabbed to. (NIM-12 root cause.) Hooking
-- `Character.ChildAdded` in addition closes the gap: every Tool
-- entering the player's possession registers immediately, and the
-- cap is enforced at the moment of pickup. registerNormal's
-- `table.find` early-return makes the duplicate fire from
-- Backpack.ChildAdded → Character.ChildAdded swap path a no-op.
local function hookCharacter(player: Player, character: Instance)
	if hookedCharacters[character] then
		return
	end
	hookedCharacters[character] = true
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolAdded(player, child)
		end
	end)
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			hookedCharacters[character] = nil
		end
	end)
end

-- IMPORTANT: Roblox replaces the Player.Backpack instance on every
-- character load (verified empirically 2026-04-23). Hooking only at
-- PlayerAdded — which is what the neighbouring PickupStacker still does
-- — binds to the original Backpack, which Roblox then destroys when
-- the first character spawns, silently disconnecting the signal.
-- Re-hook on every CharacterAdded (and also via Player.ChildAdded in
-- case a Backpack appears outside that path). The hookedBackpacks set
-- deduplicates so the same container isn't wired twice.
local function watchPlayer(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		hookBackpack(player, backpack)
	end
	if player.Character then
		hookCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			hookBackpack(player, bp)
		end
		hookCharacter(player, character)
	end)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			hookBackpack(player, child)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local map = playerSpecials[player]
	if map then
		for _, specialId in map do
			clearClaim(player, specialId)
		end
		playerSpecials[player] = nil
	end
	normalPickupOrder[player] = nil
end

-- Voluntary drop: client signals they want to get rid of whatever Tool
-- they're currently holding. We only destroy the equipped Tool (the one
-- parented to Character). Backpack-only tools are ignored — the player
-- should equip one before dropping.
--
-- Downstream cleanup (special claim release, normal pickup-order prune)
-- rides the Tool's AncestryChanged handler, so this is intentionally
-- a one-liner.
local RespawnZoneService = require(script.Parent.RespawnZoneService)
RespawnZoneService.initialize()

local requestDrop = ReplicatedStorage.Shared.Loadout.Remotes.LoadoutRequestDrop
local dropRejected = ReplicatedStorage.Shared.Loadout.Remotes.LoadoutDropRejected

-- Phase 3C drop UX. Server-authoritative drop validation. Returns
-- (success, reason): on success the equipped Tool was destroyed; on
-- rejection the reason is also sent to the client via dropRejected
-- so it can show a toast (when the rejection is user-actionable).
-- Exposed as `_G.LoadoutService_tryDrop` for the multiplayer test
-- suite — `RemoteEvent:FireServer` is client-only, so a server-side
-- test can't fire the OnServerEvent handler indirectly.
local function tryDrop(player: Player): (boolean, string?)
	local character = player.Character
	if not character then
		dropRejected:FireClient(player, "no character")
		return false, "no character"
	end
	local equipped = character:FindFirstChildOfClass("Tool")
	if not equipped then
		dropRejected:FireClient(player, "no equipped weapon")
		return false, "no equipped weapon"
	end
	if not equipped:GetAttribute(WeaponConstants.CATEGORY_ATTRIBUTE) then
		return false, "non-loadout tool" -- silent; no client UI needed
	end
	-- Voluntary drops are only honoured when the player is standing in
	-- their team's respawn zone. Keeps the playable space clear of
	-- weapon spam and anchors the drop loop at the spawn rooms (where
	-- pedestals can re-collect via RespawnAfterClaim).
	if not RespawnZoneService.isPlayerInZone(player, player.Team) then
		log:info(string.format("%s: drop request rejected — not in respawn zone", player.Name))
		dropRejected:FireClient(player, "Drop only in your spawn room")
		return false, "Drop only in your spawn room"
	end
	log:info(string.format("%s: drop request — destroying '%s'", player.Name, equipped.Name))
	equipped:Destroy()
	return true, nil
end
_G.LoadoutService_tryDrop = tryDrop

requestDrop.OnServerEvent:Connect(tryDrop)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(watchPlayer, player)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(onPlayerRemoving)

log:info("Initialized")
