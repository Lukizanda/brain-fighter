--!strict

----------------------------------------------------------------------
-- BlockShootService
----------------------------------------------------------------------
-- Server handler for the ConsumeBlock remote. Validates the payload,
-- then destroys the block. The BlockSpawner's CollectionService
-- removed-signal handler auto-refills the arena.
--
-- Phase 5.4 hardening — the remote used to destroy whatever Model the
-- client named, as fast as the client asked. It now enforces:
--   1. the payload is a real Instance, not a table wearing a Model's
--      property names (see Utility/TypeValidation/validateInstance);
--   2. the block is a live, tagged LetterBlock still parented to
--      workspace — not the ReplicatedStorage template, not an already
--      destroyed block, not an arbitrary world Model;
--   3. it is within a sane radius of the firing player's character;
--   4. the player is inside a token budget matched to the
--      LetterBlaster's fire cooldown.
--
-- Every rejection drops the request and logs; nothing throws, so one
-- malformed payload can never take the handler down for other players.
-- Thresholds live in BlockShootConstants; checks in BlockShootValidation.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local BlockShootConstants = require(script.Parent.BlockShootConstants)
local BlockShootValidation = require(script.Parent.BlockShootValidation)
local LetterBlasterConfig = require(ReplicatedStorage.Shared.LetterBlaster.LetterBlasterConfig)
local RateLimiter = require(script.Parent.Parent.Utility.RateLimiter)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)

local log = Logger.new("BlockShootService")

local consumeRemote = ReplicatedStorage.Shared.BlockShoot.Remotes.ConsumeBlock :: RemoteEvent

local consumeLimiter = RateLimiter.new(
	BlockShootConstants.CONSUME_BURST_CAPACITY,
	BlockShootConstants.CONSUME_REFILL_PER_SEC
)

-- One log budget token per player+reason, so the first instance of each
-- rejection is always reported and a client looping the remote can't
-- bury everyone else's warnings in the output window.
--
-- Deliberately not Logger:warnThrottled — its interval is a call count
-- (`count % interval == 0`), so it would swallow the first N-1 hits and
-- a single probe would leave no trace at all.
local rejectionLogBudget = RateLimiter.new(1, 1 / BlockShootConstants.REJECTION_LOG_THROTTLE_SEC)

local function reject(player: Player, reason: string)
	local key = string.format("%d:%s", player.UserId, reason)
	if rejectionLogBudget:consume(key) then
		log:warn(string.format("rejected ConsumeBlock from %s — %s", player.Name, reason))
	end
end

-- Show and sound the shot for everyone who isn't the shooter.
--
-- The blaster's laser used to be drawn only by the client that fired it,
-- into its own Workspace, where it stayed: client-created instances never
-- replicate upward, so every other player watched blocks vanish in silence
-- with nothing connecting them to the player who shot them. `Sound:Play()`
-- on a client is local in exactly the same way. The beam is cosmetic, so
-- the server does not draw it either — it describes it, and each client
-- draws its own (see VfxBroadcast).
--
-- The sound is named, not shipped: every client already has this Sound
-- replicated on the shooter's Handle with its authored volume and rolloff,
-- and playing that instance is what makes a distant blaster sound distant.
--
-- `drawnLocallyBy` excludes the shooter, who drew the beam and played the
-- fire sound on the frame they clicked and must not get a second of each a
-- round trip later. That exclusion is only safe because the client's draw
-- is unconditional on the same branch that fires this remote.
local function broadcastShot(player: Player, character: Model, blockPos: Vector3)
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then return end
	local origin = BlockShoot.muzzlePosition(tool)
	if not origin then return end
	VfxBroadcast.beam(origin, blockPos, {
		soundParent    = BlockShoot.resolveHandle(tool),
		soundName      = LetterBlasterConfig.FIRE_SOUND_NAME,
		drawnLocallyBy = player.UserId,
	})
end

consumeRemote.OnServerEvent:Connect(function(player: Player, block: any)
	-- Rate first: it is the cheapest check and the one an exploiter is
	-- most likely to be hammering.
	if not consumeLimiter:consume(player) then
		reject(player, "rate limit")
		return
	end

	local model, blockReason = BlockShootValidation.checkBlock(block)
	if not model then
		reject(player, blockReason or "invalid block")
		return
	end

	local character = player.Character
	local inRange, rangeReason = BlockShootValidation.checkRange(character, model)
	if not inRange then
		reject(player, rangeReason or "out of range")
		return
	end

	-- Read the endpoint before the block stops existing.
	local blockPos = model:GetPivot().Position
	model:Destroy()
	broadcastShot(player, character :: Model, blockPos)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	consumeLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info("BlockShootService ready — payload, range and rate validation active")
