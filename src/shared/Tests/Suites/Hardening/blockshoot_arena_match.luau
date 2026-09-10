--!strict

----------------------------------------------------------------------
-- blockshoot_arena_match — ConsumeBlock refuses another arena's block
----------------------------------------------------------------------
-- Refactor chunk 9. Two halves, both asserted in both directions:
--
--   1. A BlockSpawner pool stamps every block it spawns with its own
--      ArenaId — the attribute the check reads, so an unstamped pool
--      would make every block look like the Default arena's.
--   2. BlockShootValidation.checkArena passes a block for the arena it
--      belongs to and refuses it for any other, including the hub; an
--      unstamped block is the Default arena's, per Arena.idOf.
--
-- Drives checkArena directly rather than the remote: the interesting
-- input is "which session is the player in", and the harness has one
-- real player in one session. The service's only job is to resolve that
-- id via SessionRegistry.arenaIdFor and pass it in.
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena                = require(ReplicatedStorage.Shared.GameMode.Arena)
local BlockSpawner         = require(ReplicatedStorage.Shared.BlockSpawner)
local BlockShootValidation = require(ServerScriptService.Server.BlockShoot.BlockShootValidation)

local TEST_ARENA_ID  = "HardeningArenaA"
local OTHER_ARENA_ID = "HardeningArenaB"
local TEST_TARGET    = 3
local CONTAINER_NAME = "HardeningArenaContainer"

-- Its own box, well above the shipped arena so nothing else's spacing
-- rule sees these blocks.
local BOX_MIN = Vector3.new(-10, 400, -10)
local BOX_MAX = Vector3.new(10, 408, 10)

type Ctx = {
	container: Folder,
	spawner: BlockSpawner.BlockSpawner,
	unstamped: Model,
}

return {
	name = "blockshoot_arena_match",

	setup = function(ctx: Ctx)
		local container = Instance.new("Folder")
		container.Name = CONTAINER_NAME
		container.Parent = workspace
		ctx.container = container

		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			targetCount = TEST_TARGET,
			boxMin = BOX_MIN,
			boxMax = BOX_MAX,
			parent = container,
		})
		ctx.spawner:start()

		-- A block nothing stamped: what a hand-placed or pre-chunk-9 block
		-- looks like.
		local unstamped = Instance.new("Model")
		unstamped.Name = "HardeningUnstampedBlock"
		unstamped.Parent = container
		ctx.unstamped = unstamped
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local blocks = ctx.spawner:getActiveBlocks()
		if #blocks == 0 then
			return false, "pool spawned no blocks to check"
		end

		for _, block in blocks do
			-- 1. The stamp.
			local stamped = block:GetAttribute(Arena.ID_ATTRIBUTE)
			if stamped ~= TEST_ARENA_ID then
				return false, string.format(
					"pool block %s carries ArenaId %s, expected %s",
					block.Name, tostring(stamped), TEST_ARENA_ID
				)
			end

			-- 2. Own arena passes.
			local ok, reason = BlockShootValidation.checkArena(TEST_ARENA_ID, block)
			if not ok then
				return false, string.format("refused a block in the player's own arena: %s", tostring(reason))
			end

			-- 2. Another arena is refused, and so is the hub.
			local otherOk = BlockShootValidation.checkArena(OTHER_ARENA_ID, block)
			if otherOk then
				return false, string.format("accepted a %s block for a player in %s", TEST_ARENA_ID, OTHER_ARENA_ID)
			end
			local lobbyOk, lobbyReason = BlockShootValidation.checkArena(Arena.LOBBY_ID, block)
			if lobbyOk then
				return false, string.format("accepted a %s block for a hub player", TEST_ARENA_ID)
			end
			if not lobbyReason or not string.find(lobbyReason, "arena", 1, true) then
				return false, string.format("refusal reason does not name the arena rule: %s", tostring(lobbyReason))
			end
		end

		-- An unstamped block is the Default arena's — never the hub's.
		local defaultOk, defaultReason = BlockShootValidation.checkArena(Arena.DEFAULT_ID, ctx.unstamped)
		if not defaultOk then
			return false, string.format("refused an unstamped block for a Default player: %s", tostring(defaultReason))
		end
		if BlockShootValidation.checkArena(Arena.LOBBY_ID, ctx.unstamped) then
			return false, "accepted an unstamped block for a hub player"
		end

		return true, string.format(
			"%d pool blocks stamped %s; own arena passes, %s and %s refused; unstamped = %s",
			#blocks, TEST_ARENA_ID, OTHER_ARENA_ID, Arena.LOBBY_ID, Arena.DEFAULT_ID
		)
	end,

	teardown = function(ctx: Ctx)
		if ctx.spawner then
			ctx.spawner:destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
