----------------------------------------------------------------------
-- SpawnManager
----------------------------------------------------------------------
-- Intelligent spawn point selection, per arena.
-- Uses CollectionService tags to find spawn points in the workspace.
-- Scores each spawn by distance to nearest living enemy and picks
-- the safest one.
--
-- Each session registers its arena's spawn tag; a spawn candidate is a
-- part carrying that tag whose `ArenaId` resolves to the same arena. Two
-- arenas can therefore share a tag name (the two duel pads of stage 6 are
-- both `PvPArenaSpawn`) and still keep their pads apart. See
-- `wiki/design/lobby.md` § Session model.
--
-- Extensible:
--   - Tag name comes from the mode definition's `spawnTag`
--   - Team-aware: pass a team filter to exclude friendly spawns
--   - Falls back to default SpawnLocations if no tagged spawns exist
--
-- Usage:
--   SpawnManager.initialize()
--   SpawnManager.registerArena("Default", "FFASpawn")
--   local cf = SpawnManager.getBestSpawn(player, "Default")
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SpawnManager")

local SpawnManager = {}

-- Spawn tag per arena id, populated by registerArena(). An arena with no
-- registered tag, or whose tag matches nothing in the workspace, falls
-- back to any SpawnLocation.
local arenaSpawnTags: { [string]: string } = {}
local initialized = false

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------

local function getLivingEnemyPositions(excludePlayer: Player?, teamFilter: string?): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		if player == excludePlayer then
			continue
		end

		-- Team filtering for future TDM support
		if teamFilter and player.Team and player.Team.Name ~= teamFilter then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			table.insert(positions, hrp.Position)
		end
	end
	return positions
end

local function getSpawnPoints(arenaId: string): { BasePart }
	local spawns = {}

	local spawnTag = arenaSpawnTags[arenaId]
	if spawnTag then
		for _, obj in CollectionService:GetTagged(spawnTag) do
			if obj:IsA("BasePart") and obj:IsDescendantOf(workspace) and Arena.idOf(obj) == arenaId then
				table.insert(spawns, obj)
			end
		end
	end

	-- Fallback: use any SpawnLocation in workspace.
	--
	-- Deliberately NOT filtered by arena. It is the misconfigured-scene
	-- path — nothing is tagged for this arena — and its whole job is to
	-- put the player somewhere rather than at origin. Narrowing it by
	-- arena would make the empty case empty again. The shipped place
	-- reaches this path today: nothing carries the FFASpawn tag, so every
	-- player lands on Arena.SpawnZone.SpawnLocation.
	if #spawns == 0 then
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("SpawnLocation") then
				table.insert(spawns, descendant)
			end
		end
	end

	return spawns
end

-- Restrict the candidate set to spawns the player can use given their
-- Team. SpawnLocations honour their TeamColor / Neutral flags; tagged
-- BaseParts can carry a "Team" attribute to opt into the same filter.
-- Returns the original set unchanged when the player has no team
-- (FFA / pre-assignment) or when TEAMS_ENABLED is off (educational
-- shooter build — every player draws from the neutral spawn pool).
local function filterSpawnsForPlayer(spawns: { BasePart }, player: Player): { BasePart }
	if not GameConfig.TEAMS_ENABLED then
		return spawns
	end
	if not player.Team then
		return spawns
	end
	local filtered = {}
	for _, spawn in spawns do
		if spawn:IsA("SpawnLocation") then
			if spawn.Neutral or spawn.TeamColor == player.Team.TeamColor then
				table.insert(filtered, spawn)
			end
		else
			local teamAttr = spawn:GetAttribute("Team")
			if teamAttr == nil or teamAttr == player.Team.Name then
				table.insert(filtered, spawn)
			end
		end
	end
	-- If the filter wiped out every candidate (misconfigured scene),
	-- fall back to the unfiltered list rather than spawning at origin.
	if #filtered == 0 then
		log:warn(string.format(
			"No team-matching spawns for %s (team %s); falling back to all spawns",
			player.Name, player.Team.Name
		))
		return spawns
	end
	return filtered
end

local function scoreSpawn(spawnPart: BasePart, enemyPositions: { Vector3 }): number
	-- Score = minimum distance to any enemy. Higher = safer.
	-- If no enemies, all spawns score equally (infinity).
	if #enemyPositions == 0 then
		return math.huge
	end

	local minDist = math.huge
	local spawnPos = spawnPart.Position

	for _, enemyPos in enemyPositions do
		local dist = (spawnPos - enemyPos).Magnitude
		if dist < minDist then
			minDist = dist
		end
	end

	return minDist
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function SpawnManager.initialize()
	if initialized then
		log:warn("Already initialized")
		return
	end

	initialized = true
	log:info("Initialized — awaiting arena registrations")
end

-- Binds an arena to the spawn tag its mode authors pads with. Called by
-- GameModeService as each session is created.
function SpawnManager.registerArena(arenaId: string, spawnTag: string?)
	if spawnTag then
		arenaSpawnTags[arenaId] = spawnTag
	else
		arenaSpawnTags[arenaId] = nil
	end

	local spawns = getSpawnPoints(arenaId)
	log:info(string.format("[%s] registered with %d spawn points (tag: %s)",
		arenaId, #spawns, spawnTag or "<none — SpawnLocation fallback>"))
end

function SpawnManager.unregisterArena(arenaId: string)
	arenaSpawnTags[arenaId] = nil
end

-- Returns the best CFrame to spawn at, avoiding nearby enemies.
-- arenaId: which arena's pads to draw from; defaults to the default arena.
-- teamFilter: optional team name to only consider enemies from that team.
function SpawnManager.getBestSpawn(player: Player, arenaId: string?, teamFilter: string?): CFrame
	local resolvedArenaId = arenaId or Arena.DEFAULT_ID
	local spawns = filterSpawnsForPlayer(getSpawnPoints(resolvedArenaId), player)

	if #spawns == 0 then
		log:warn(string.format("[%s] No spawn points found, using origin", resolvedArenaId))
		return CFrame.new(0, 10, 0)
	end

	local enemyPositions = getLivingEnemyPositions(player, teamFilter)

	-- Score each spawn and pick the best
	local bestSpawn = spawns[1]
	local bestScore = -1

	for _, spawn in spawns do
		local score = scoreSpawn(spawn, enemyPositions)
		if score > bestScore then
			bestScore = score
			bestSpawn = spawn
		end
	end

	-- Spawn slightly above the spawn point to avoid clipping
	local spawnCFrame = bestSpawn.CFrame + Vector3.new(0, 3, 0)

	log:info(string.format(
		"[%s] Best spawn for %s: %s (dist to nearest enemy: %s)",
		resolvedArenaId,
		player.Name,
		bestSpawn.Name,
		bestScore == math.huge and "no enemies" or string.format("%.0f studs", bestScore)
	))

	return spawnCFrame
end

-- Returns all spawn points for an arena (for debug/visualization)
function SpawnManager.getSpawnPoints(arenaId: string?): { BasePart }
	return getSpawnPoints(arenaId or Arena.DEFAULT_ID)
end

return SpawnManager
