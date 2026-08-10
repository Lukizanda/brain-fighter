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
local EnergyLedger = require(script.Parent.Parent.Economy.EnergyLedger)
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

-- Drop the request, log it, and — new in 5.7 stage 4 — tell the client.
--
-- The client appended the letter to its WordBuffer *before* firing this
-- remote, and until now nothing ever told it the consume had failed. In
-- solo play that was safe: nobody else can take your block, so the only
-- rejections were exploit attempts by a client that would ignore the
-- reply anyway. PvP makes it reachable by honest players — two people
-- tapping one block on the same frame, where exactly one can win — and
-- the loser would otherwise keep a phantom letter for the rest of the
-- round, occupying a slot and eventually paying out energy on Memorize.
--
-- Reused `ConsumeBlock` rather than adding a sibling remote: the
-- rejection *is* the response to that request, and one wire object is
-- one thing to keep in step. Firing back to the requesting player only,
-- so this stays off the broadcast path entirely.
--
-- What comes back is the client's own opaque request id, NOT the block.
-- Echoing the block looks natural and fails exactly where it matters:
-- the rejection that matters most is losing a race, and by then the
-- winner has already destroyed that block — an Instance reference for a
-- destroyed object is the same nil-arrival trap `VfxBroadcast.playOn`
-- documents, so the rollback would no-op in the one case it exists for.
-- A number always survives the trip.
--
-- The id is never trusted: it is type-checked, nothing is looked up with
-- it, and it goes back only to the player who sent it. A client that
-- lies about its own id can only fail to roll back its own buffer.
--
-- The reason string is deliberately NOT sent. It is server-log detail
-- (it names which check tripped and at what threshold), and the client
-- needs exactly one bit: the letter did not land.
local function reject(player: Player, reason: string, requestId: any)
	local key = string.format("%d:%s", player.UserId, reason)
	if rejectionLogBudget:consume(key) then
		log:warn(string.format("rejected ConsumeBlock from %s — %s", player.Name, reason))
	end
	if typeof(requestId) == "number" then
		consumeRemote:FireClient(player, requestId)
	end
end

-- Describe the pop for the clients. Two cosmetics, and they are broadcast
-- differently on purpose.
--
-- The server describes rather than draws — `ParticleEmitter:Emit()` does
-- not replicate, and a Beam the server built would be anchored to a Part
-- the receiving client may not have yet.
--
-- **Burst — excludes the popper.** They drew it on the frame they clicked,
-- as prediction, and a second copy a round trip later would be a visible
-- double-flash. Safe to predict because it stays true even if they lose a
-- race for the block: the block popped either way.
--
-- **Stream — goes to everyone, popper included.** It is the attribution
-- cue, and attribution is a claim only the server can make. The popper
-- deliberately does *not* predict it (see BlockTapController), so there is
-- nothing to exclude them from — and a player who loses a race never sees
-- a stream flow into them for a letter they did not get, because the only
-- thing that draws one is this line, on the branch where the consume
-- actually succeeded.
local function broadcastPop(player: Player, blockPos: Vector3, blockColor: string?)
	VfxBroadcast.playAt(
		VfxConfig.resolveBlockPopId(blockColor),
		blockPos,
		player.UserId
	)
	VfxBroadcast.collect(blockPos, player.UserId, {
		color = if blockColor then LetterBlocks.COLOR_TINTS[blockColor] else nil,
	})
end

consumeRemote.OnServerEvent:Connect(function(player: Player, block: any, requestId: any)
	-- Rate first: it is the cheapest check and the one an exploiter is
	-- most likely to be hammering.
	if not consumeLimiter:consume(player) then
		reject(player, "rate limit", requestId)
		return
	end

	local model, blockReason = BlockShootValidation.checkBlock(block)
	if not model then
		reject(player, blockReason or "invalid block", requestId)
		return
	end

	local character = player.Character
	local inRange, rangeReason = BlockShootValidation.checkRange(character, model)
	if not inRange then
		reject(player, rangeReason or "out of range", requestId)
		return
	end

	-- Read both before the block stops existing. The burst needs the
	-- position it stood at, and the stream needs its colour — neither is
	-- recoverable from a destroyed Model, and an Instance reference for a
	-- thing that no longer exists arrives as nil on the receiving client.
	local blockPos = model:GetPivot().Position
	local blockLetter, blockColor = BlockShoot.readBlock(model)

	model:Destroy()

	-- Credit sits on this branch deliberately. A consume the server
	-- refused is rolled back out of the client's buffer by
	-- BlockTapController.onRejected, so crediting any earlier would put
	-- the ledger's held set and that buffer out of step in the one
	-- direction that can reject honest play.
	-- See wiki/systems/SpellCastService.md § Validated memorize.
	if blockLetter and blockColor then
		EnergyLedger.creditBlock(player.UserId, blockLetter, blockColor)
	end

	broadcastPop(player, blockPos, blockColor)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	consumeLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info("BlockShootService ready — payload, range and rate validation active")
