--!strict

----------------------------------------------------------------------
-- BlockSpawnerService
----------------------------------------------------------------------
-- Reads the authored spawn volumes out of the workspace and starts one
-- BlockSpawner pool per arena.
--
-- Tag any Part in Workspace with "BlockSpawnVolume" to define a spawn
-- region, and give it an "ArenaId" attribute to say which arena it belongs
-- to. Volumes sharing an id are one pool: blocks are distributed across
-- them weighted by volume, and the pool's target count is
-- GameConfig.BLOCK_SPAWN_DENSITY × that arena's volume / 1000. How long a
-- consumed block takes to come back is GameConfig.BLOCK_RESPAWN_DELAY.
--
-- A volume with no ArenaId belongs to Arena.DEFAULT_ID — the shipped
-- arena's eight volumes are all in that state, so the attribute is how you
-- opt a volume OUT of the default arena, never how you opt one in.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

local log = Logger.new("BlockSpawnerService")

local SPAWN_VOLUME_TAG = "BlockSpawnVolume"

-- Boxes grouped by the arena that owns them, keyed by arena id.
type ArenaBoxes = { [string]: { BlockSpawner.BoxDef } }

local function collectVolumesByArena(): ArenaBoxes
	local byArena: ArenaBoxes = {}

	for _, inst in ipairs(CollectionService:GetTagged(SPAWN_VOLUME_TAG)) do
		if inst:IsA("BasePart") then
			local part = inst :: BasePart
			local arenaId = Arena.idOf(part)
			local pos = part.Position
			local half = part.Size * 0.5

			log:info(string.format(
				"[%s] BlockSpawnVolume at (%.1f, %.1f, %.1f), size (%.1f, %.1f, %.1f)",
				arenaId, pos.X, pos.Y, pos.Z,
				part.Size.X, part.Size.Y, part.Size.Z
			))

			local boxes = byArena[arenaId]
			if not boxes then
				boxes = {}
				byArena[arenaId] = boxes
			end
			table.insert(boxes, { boxMin = pos - half, boxMax = pos + half })
		end
	end

	return byArena
end

-- Derived from the prefab's real geometry rather than configured in
-- studs, so it can never fall out of step with GameConfig.BLOCK_SCALE
-- the way the old BLOCK_MIN_SPACING literal did.
local function resolveMinSpacing(): number
	local minSpacing = LetterBlocks.tumbleDiameter() * GameConfig.BLOCK_SPACING_CLEARANCE
	log:info(string.format(
		"block spacing: %.2f studs (tumble diameter %.2f x clearance %.2f)",
		minSpacing, LetterBlocks.tumbleDiameter(), GameConfig.BLOCK_SPACING_CLEARANCE
	))
	return minSpacing
end

local function hideVolumeParts()
	for _, inst in ipairs(CollectionService:GetTagged(SPAWN_VOLUME_TAG)) do
		if inst:IsA("BasePart") then
			local part = inst :: BasePart
			part.Transparency = 1
			part.CanQuery = false
		end
	end
end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

hideVolumeParts()

local minSpacing = resolveMinSpacing()
local byArena = collectVolumesByArena()

-- Pools by arena id. Held so a later stage can disable or destroy one
-- arena's blocks without touching another's; nothing tears them down yet.
local pools: { [string]: BlockSpawner.BlockSpawner } = {}

for arenaId, boxes in byArena do
	local pool = BlockSpawner.new({
		arenaId = arenaId,
		boxes = boxes,
		density = GameConfig.BLOCK_SPAWN_DENSITY,
		minSpacing = minSpacing,
		respawnDelay = GameConfig.BLOCK_RESPAWN_DELAY,
	})
	pool:start()
	pools[arenaId] = pool
end

if next(pools) == nil then
	-- No tagged volumes at all. One default pool on BlockSpawner's own
	-- fallback box keeps a bare test place populated rather than silently
	-- empty, which is what the singleton did too.
	log:warn(string.format("No parts tagged '%s' found — using default spawn box", SPAWN_VOLUME_TAG))
	local pool = BlockSpawner.new({
		arenaId = Arena.DEFAULT_ID,
		density = GameConfig.BLOCK_SPAWN_DENSITY,
		minSpacing = minSpacing,
		respawnDelay = GameConfig.BLOCK_RESPAWN_DELAY,
	})
	pool:start()
	pools[Arena.DEFAULT_ID] = pool
end

local summary: { string } = {}
for arenaId, pool in pools do
	table.insert(summary, string.format("%s=%d", arenaId, pool:getTargetCount()))
end
table.sort(summary)
log:info(string.format("BlockSpawnerService ready — %d arena(s): %s",
	#summary, table.concat(summary, ", ")))
