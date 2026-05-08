----------------------------------------------------------------------
-- SpawnManager
----------------------------------------------------------------------
-- Intelligent spawn point selection for game modes.
-- Uses CollectionService tags to find spawn points in the workspace.
-- Scores each spawn by distance to nearest living enemy and picks
-- the safest one.
--
-- Extensible:
--   - Tag name is configurable (default: GameModeConstants.SPAWN_TAG)
--   - Team-aware: pass a team filter to exclude friendly spawns
--   - Falls back to default SpawnLocations if no tagged spawns exist
--
-- Usage:
--   SpawnManager.initialize()
--   local cf = SpawnManager.getBestSpawn(player)
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SpawnManager")

local SpawnManager = {}

-- Set by initialize({ spawnTag = ... }). If no tag is provided or no
-- tagged spawns exist in workspace, falls back to any SpawnLocation.
local spawnTag: string? = nil
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

local function getSpawnPoints(): { BasePart }
	local spawns = {}

	if spawnTag then
		for _, obj in CollectionService:GetTagged(spawnTag) do
			if obj:IsA("BasePart") and obj:IsDescendantOf(workspace) then
				table.insert(spawns, obj)
			end
		end
	end

	-- Fallback: use any SpawnLocation in workspace
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
-- (FFA / pre-assignment).
local function filterSpawnsForPlayer(spawns: { BasePart }, player: Player): { BasePart }
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

function SpawnManager.initialize(config: { spawnTag: string? }?)
	if initialized then
		log:warn("Already initialized")
		return
	end

	if config and config.spawnTag then
		spawnTag = config.spawnTag
	end

	initialized = true
	local spawns = getSpawnPoints()
	log:info(string.format("Initialized with %d spawn points (tag: %s)",
		#spawns, spawnTag or "<none — SpawnLocation fallback>"))
end

-- Returns the best CFrame to spawn at, avoiding nearby enemies.
-- teamFilter: optional team name to only consider enemies from that team.
function SpawnManager.getBestSpawn(player: Player, teamFilter: string?): CFrame
	local spawns = filterSpawnsForPlayer(getSpawnPoints(), player)

	if #spawns == 0 then
		log:warn("No spawn points found, using origin")
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
		"Best spawn for %s: %s (dist to nearest enemy: %s)",
		player.Name,
		bestSpawn.Name,
		bestScore == math.huge and "no enemies" or string.format("%.0f studs", bestScore)
	))

	return spawnCFrame
end

-- Returns all spawn points (for debug/visualization)
function SpawnManager.getSpawnPoints(): { BasePart }
	return getSpawnPoints()
end

return SpawnManager
