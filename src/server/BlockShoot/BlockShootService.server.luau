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
--   3. it is within a sane radius of the popping player's character;
--   4. the player is inside a token budget matched to the client's
--      tap cooldown.
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
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local RateLimiter = require(script.Parent.Parent.Utility.RateLimiter)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

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

-- Show the pop for everyone who isn't the player who made it.
--
-- Two cosmetics, one round trip: the burst where the block stood, and the
-- stream carrying its mana onto the popper. The server describes both and
-- each client draws its own — `ParticleEmitter:Emit()` does not replicate,
-- and a Beam the server built would be anchored to a Part the receiving
-- client may not have yet.
--
-- The stream is the PvP attribution cue. It replaces the blaster beam,
-- which was the only thing linking a taker to a block for other players,
-- and it says more: who got it, and which colour they banked.
--
-- `drawnLocallyBy` excludes the popper, who drew both on the frame they
-- clicked and must not get a second copy a round trip later. That is only
-- safe because the client's draw is unconditional on the same branch that
-- fires this remote.
local function broadcastPop(player: Player, blockPos: Vector3, blockColor: string?)
	VfxBroadcast.playAt(
		VfxConfig.resolveBlockPopId(blockColor),
		blockPos,
		player.UserId
	)
	VfxBroadcast.collect(blockPos, player.UserId, {
		color          = if blockColor then LetterBlocks.COLOR_TINTS[blockColor] else nil,
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

	-- Read both before the block stops existing. The burst needs the
	-- position it stood at, and the stream needs its colour — neither is
	-- recoverable from a destroyed Model, and an Instance reference for a
	-- thing that no longer exists arrives as nil on the receiving client.
	local blockPos = model:GetPivot().Position
	local _, blockColor = BlockShoot.readBlock(model)

	model:Destroy()

	broadcastPop(player, blockPos, blockColor)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	consumeLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info("BlockShootService ready — payload, range and rate validation active")
