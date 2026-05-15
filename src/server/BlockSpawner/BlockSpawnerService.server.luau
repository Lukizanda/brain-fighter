--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local log = Logger.new("BlockSpawnerService")

-- Optional spawn-volume Part in Workspace. If present, its CFrame + Size
-- define the bounding box for block placement. Create a Part named
-- "BlockSpawnVolume" anywhere in the workspace hierarchy and resize it
-- in Studio to cover the play area. If absent, BlockSpawner falls back
-- to its hardcoded defaults (origin-centered 40×8×40 box).
local function resolveSpawnOpts(): BlockSpawner.Opts
	local volumePart = workspace:FindFirstChild("BlockSpawnVolume", true) :: BasePart?
	if not volumePart or not volumePart:IsA("BasePart") then
		log:warn("BlockSpawnVolume Part not found in Workspace — using default spawn box")
		return {}
	end

	local pos  = volumePart.Position
	local half = volumePart.Size * 0.5
	log:info(string.format(
		"BlockSpawnVolume found at (%.1f, %.1f, %.1f), size (%.1f, %.1f, %.1f)",
		pos.X, pos.Y, pos.Z,
		volumePart.Size.X, volumePart.Size.Y, volumePart.Size.Z
	))

	return {
		boxMin = pos - half,
		boxMax = pos + half,
	}
end

BlockSpawner.start(resolveSpawnOpts())
log:info("BlockSpawnerService ready")
