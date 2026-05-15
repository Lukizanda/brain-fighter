--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local log = Logger.new("BlockSpawnerService")

-- Tag any Part in Workspace with "BlockSpawnVolume" to define a spawn
-- region. Multiple tagged parts are all used simultaneously — blocks are
-- distributed across them weighted by volume. Density is controlled via
-- GameConfig.BLOCK_SPAWN_DENSITY (blocks per 1000 cubic studs).
local SPAWN_VOLUME_TAG = "BlockSpawnVolume"

local function resolveSpawnOpts(): BlockSpawner.Opts
	local tagged = CollectionService:GetTagged(SPAWN_VOLUME_TAG)
	local boxes: { BlockSpawner.BoxDef } = {}

	for _, inst in ipairs(tagged) do
		if inst:IsA("BasePart") then
			local part = inst :: BasePart
			local pos = part.Position
			local half = part.Size * 0.5
			log:info(string.format(
				"BlockSpawnVolume at (%.1f, %.1f, %.1f), size (%.1f, %.1f, %.1f)",
				pos.X, pos.Y, pos.Z,
				part.Size.X, part.Size.Y, part.Size.Z
			))
			table.insert(boxes, { boxMin = pos - half, boxMax = pos + half })
		end
	end

	if #boxes == 0 then
		log:warn(string.format("No parts tagged '%s' found — using default spawn box", SPAWN_VOLUME_TAG))
	end

	return {
		boxes = if #boxes > 0 then boxes else nil,
		density = GameConfig.BLOCK_SPAWN_DENSITY,
		minSpacing = GameConfig.BLOCK_MIN_SPACING,
	}
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

hideVolumeParts()
BlockSpawner.start(resolveSpawnOpts())
log:info("BlockSpawnerService ready")
