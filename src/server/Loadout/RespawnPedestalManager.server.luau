----------------------------------------------------------------------
-- RespawnPedestalManager
----------------------------------------------------------------------
-- Phase 3B server-side counterpart to the user-placed RespawnPedestal
-- markers in Workspace. Scans markers → clones templates → respawns
-- at round-start. The authoritative weapon-spawner for active modes;
-- the legacy `WeaponSpawnerManager` it replaced was retired in B2
-- (see wiki/decisions/TechDebtRoadmap.md). This adds:
--
--   1. Per-claim respawn: after a player picks up a pedestal's weapon,
--      we wait RESPAWN_DELAY seconds and re-clone the weapon onto
--      that same pedestal. Each pedestal regenerates independently.
--
--   2. RespawnAfterClaim attribute: pedestals can opt out (false) to
--      behave as one-shot spawns until the next round-start cycle.
--
-- Pedestal contract (see docs/loadout-system-plan.md):
--   - BasePart named "RespawnPedestal" anywhere in Workspace
--   - WeaponName: string — template folder under Shared.Weapon.Templates
--   - Team: string?           — for team-scoping (currently unused —
--                                LoadoutService still gates by claim)
--   - SpawnerMesh: string?    — pedestal mesh from Spawner.Meshes
--   - RespawnAfterClaim: bool — default true
--
-- Known limitation flagged in the design doc Phase 6:
--   This manager doesn't yet consult LoadoutService team claims for
--   specials. If team A's shield-holder still has the shield when a
--   teammate walks past the pedestal, the spawned shield will be
--   destroyed by LoadoutService's "team already holds it" rejection,
--   and we'll respawn it after the delay → blink loop. Acceptable for
--   first cut; pedestal-aware claim checks come with Phase 6 visuals.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("RespawnPedestalManager")

local RESPAWN_DELAY = 3 -- seconds before a claimed pedestal regenerates
local WEAPON_VERTICAL_OFFSET = 1.0 -- studs above the pedestal/mesh top

local templates = ReplicatedStorage.Shared.Weapon.Templates
local spawnerMeshes = ReplicatedStorage:FindFirstChild("Spawner")
	and ReplicatedStorage.Spawner:FindFirstChild("Meshes")

type Pedestal = {
	part: BasePart,
	weaponName: string,
	team: string?,
	spawnerMesh: string?,
	respawnAfterClaim: boolean,
	currentWeapon: Tool?,
	meshInstance: Instance?,
	pickupConn: RBXScriptConnection?,
}

local pedestals: { Pedestal } = {}

-- The pedestals carry "Label" BillboardGuis as editor affordances so the
-- placer can identify each weapon at a glance in Studio. Hide them at
-- runtime so they don't intrude on the actual game view; edit mode keeps
-- them visible because this script doesn't run there.
local function hideEditorLabels(part: BasePart)
	for _, c in part:GetChildren() do
		if c:IsA("BillboardGui") and c.Name == "Label" then
			c.Enabled = false
		end
	end
end

local function collectPedestals()
	table.clear(pedestals)
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "RespawnPedestal" then
			local weaponName = d:GetAttribute("WeaponName")
			if typeof(weaponName) ~= "string" or weaponName == "" then
				log:warn(string.format("%s has no WeaponName attribute; skipping", d:GetFullName()))
				continue
			end
			hideEditorLabels(d)
			table.insert(pedestals, {
				part = d,
				weaponName = weaponName,
				team = d:GetAttribute("Team"),
				spawnerMesh = d:GetAttribute("SpawnerMesh"),
				respawnAfterClaim = d:GetAttribute("RespawnAfterClaim") ~= false,
				currentWeapon = nil,
				meshInstance = nil,
				pickupConn = nil,
			})
		end
	end
	log:info(string.format("Collected %d RespawnPedestal markers", #pedestals))
end

-- Spawn the weapon (and optional pedestal mesh) for one pedestal.
-- Idempotent: if the pedestal already has a live weapon, no-op.
local function spawnAt(p: Pedestal)
	if p.currentWeapon and p.currentWeapon.Parent then
		return
	end
	local template = templates:FindFirstChild(p.weaponName)
	if not template then
		-- Pedestals can be marked `Stub = true` (BasePart attribute) when
		-- their target weapon has been intentionally retired but the
		-- pedestal is left as a level-intent marker for a future revisit
		-- (e.g. ShieldPrototype, Phase 5). Skip silently to avoid warn
		-- spam every round-start. Without the Stub flag, missing
		-- templates are still warned as a configuration error.
		if not p.part:GetAttribute("Stub") then
			log:warn(string.format("Template '%s' not found for pedestal at %s",
				p.weaponName, p.part:GetFullName()))
		end
		return
	end

	-- Optional pedestal mesh: spawn once, persists across weapon respawns.
	-- We re-anchor it under the manager's tracking each cycle so cleanup
	-- doesn't leave orphans if the marker is moved.
	local pedestalTop = p.part.Position.Y + p.part.Size.Y / 2
	if p.spawnerMesh and spawnerMeshes and not p.meshInstance then
		local meshTpl = spawnerMeshes:FindFirstChild(p.spawnerMesh)
		if meshTpl then
			local mesh = meshTpl:Clone()
			mesh:PivotTo(p.part.CFrame)
			mesh.Parent = Workspace
			pedestalTop = p.part.Position.Y + (mesh:GetExtentsSize().Y / 2)
			p.meshInstance = mesh
		end
	end

	local weapon = template:Clone()
	weapon:PivotTo(CFrame.new(p.part.Position.X, pedestalTop + WEAPON_VERTICAL_OFFSET, p.part.Position.Z))
	weapon.Parent = Workspace
	p.currentWeapon = weapon

	-- Pickup detection: when the cloned Tool leaves Workspace (engine
	-- auto-pickup parents it to Backpack/Character), trigger respawn.
	-- Disconnects itself once handled so spawnAll's destroy doesn't
	-- double-fire.
	if p.pickupConn then
		p.pickupConn:Disconnect()
	end
	p.pickupConn = weapon.AncestryChanged:Connect(function()
		if weapon.Parent == Workspace then
			return
		end
		p.currentWeapon = nil
		if p.pickupConn then
			p.pickupConn:Disconnect()
			p.pickupConn = nil
		end
		if p.respawnAfterClaim then
			task.delay(RESPAWN_DELAY, function()
				spawnAt(p)
			end)
		end
	end)
end

-- Tear down everything spawned by this manager. Used at round-start to
-- restore a clean slate before re-spawning. Disconnects pickup signals
-- first so the destroy doesn't trigger spurious respawn timers.
local function despawnAll()
	for _, p in pedestals do
		if p.pickupConn then
			p.pickupConn:Disconnect()
			p.pickupConn = nil
		end
		if p.currentWeapon and p.currentWeapon.Parent == Workspace then
			p.currentWeapon:Destroy()
		end
		p.currentWeapon = nil
		if p.meshInstance and p.meshInstance.Parent then
			p.meshInstance:Destroy()
		end
		p.meshInstance = nil
	end
end

local function spawnAll()
	despawnAll()
	for _, p in pedestals do
		spawnAt(p)
	end
end

collectPedestals()
spawnAll()

local gameModeEvents = ServerScriptService:FindFirstChild("Server")
	and ServerScriptService.Server:FindFirstChild("GameMode")
	and ServerScriptService.Server.GameMode:FindFirstChild("Events")
if gameModeEvents then
	local roundStarted = gameModeEvents:FindFirstChild("RoundStarted")
	if roundStarted then
		roundStarted.Event:Connect(function()
			log:info("Round started — respawning pedestal weapons")
			spawnAll()
		end)
	end
end

log:info("Initialized")
