--!strict

----------------------------------------------------------------------
-- BombTapService
----------------------------------------------------------------------
-- Server handler for the BombTap remote (a tap on a resting letter or a pop of
-- a chasing seeker, wiki/design/scramble-bomb.md). It owns trust and routing,
-- nothing else: BossBombs judges the tap (accepted, refused, locked, harmless)
-- and owns the puzzle.
--
-- A tap is `FireServer(puzzle: Model, tileIndex: number, requestId: number)`.
-- It must pass, in this order:
--   1. the player is inside a token budget (RateLimiter);
--   2. the payload is what it says: a Model, a finite integer index, a
--      number request id (validateInstance, not a table wearing a Model's name);
--   3. the Model is a live, tagged puzzle in workspace that a boss object owns
--      (BombRegistry);
--   4. it is in the arena the player's session is in (BlockShootValidation's
--      arena check, reused);
--   5. the player's character is alive;
--   6. its root is within reach of where BossBombs.reachOf measures from: while
--      the puzzle rests, its CENTRE (bombTapReach); once it chases, THAT SEEKER
--      (bombSeekerTapReach); plus the same tolerance the block tap allows
--      (BlockShootConstants.OWN_REACH_TOLERANCE_STUDS: the client measured from
--      where the character and the seeker were a moment ago). A letter with no
--      live part (gone, a locked letter once chasing, not hatched yet) has no
--      such point and is rejected here.
-- No line-of-sight check.
--
-- Every failure drops the request, logs (throttled) and tells only the sender
-- by firing the same remote back with their request id, so the client can roll
-- its prediction back. A tap BossBombs REFUSES (out of order, resting) or finds
-- INVALID (no such live letter) gets the same reply. An ACCEPTED tap, a LOCKED
-- one (resting, already locked) and a HARMLESS pop (a chasing seeker) get no
-- reply. The reason is never sent.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local BlockShootConstants = require(script.Parent.Parent.BlockShoot.BlockShootConstants)
local BlockShootValidation = require(script.Parent.Parent.BlockShoot.BlockShootValidation)
local SessionRegistry = require(script.Parent.Parent.GameMode.Scripts.SessionRegistry)
local RateLimiter = require(script.Parent.Parent.Utility.RateLimiter)
local validateInstance = require(script.Parent.Parent.Utility.TypeValidation.validateInstance)
local BombRegistry = require(script.Parent.Scripts.BombRegistry)

local log = Logger.new("BombTapService")

local tapRemote = ReplicatedStorage.Shared.Boss.BossEvents[BombConstants.TAP_REMOTE_NAME] :: RemoteEvent

local tapLimiter = RateLimiter.new(BombConstants.TAP_BURST_CAPACITY, BombConstants.TAP_REFILL_PER_SEC)
local rejectionLogBudget = RateLimiter.new(1, 1 / BombConstants.REJECTION_LOG_THROTTLE_SEC)

local function reject(player: Player, reason: string, requestId: any)
	local key = string.format("%d:%s", player.UserId, reason)
	if rejectionLogBudget:consume(key) then
		log:warn(string.format("rejected BombTap from %s — %s", player.Name, reason))
	end
	if typeof(requestId) == "number" then
		tapRemote:FireClient(player, requestId)
	end
end

tapRemote.OnServerEvent:Connect(function(player: Player, bomb: any, tileIndex: any, requestId: any)
	if not tapLimiter:consume(player) then
		reject(player, "rate limit", requestId)
		return
	end

	if typeof(requestId) ~= "number" or typeof(tileIndex) ~= "number" or tileIndex ~= math.floor(tileIndex)
		or tileIndex ~= tileIndex or math.abs(tileIndex) == math.huge
	then
		reject(player, "bad payload", requestId)
		return
	end
	if not validateInstance(bomb, "Model") then
		reject(player, "not a Model instance", requestId)
		return
	end
	local model = bomb :: Model
	if not model:IsDescendantOf(workspace) or not CollectionService:HasTag(model, BombConstants.TAG) then
		reject(player, "not a live puzzle", requestId)
		return
	end
	local owner = BombRegistry.ownerOf(model)
	if owner == nil then
		reject(player, "no boss owns this bomb", requestId)
		return
	end

	local inArena, arenaReason = BlockShootValidation.checkArena(SessionRegistry.arenaIdFor(player), model)
	if not inArena then
		reject(player, arenaReason or "arena mismatch", requestId)
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		reject(player, "no living character", requestId)
		return
	end
	-- Resting: reach is measured to the puzzle's centre. Chasing: to THAT
	-- seeker, wherever it is flying now.
	local center, reach = owner:reachOf(model, tileIndex)
	if center == nil then
		reject(player, "no live letter", requestId)
		return
	end
	local distance = ((root :: BasePart).Position - center).Magnitude
	local allowed = reach + BlockShootConstants.OWN_REACH_TOLERANCE_STUDS
	if distance ~= distance or distance > allowed then
		reject(player, string.format("out of reach (%.0f > %.0f studs)", distance, allowed), requestId)
		return
	end

	local result = owner:tap(player, model, tileIndex)
	-- Accepted, Locked and Harmless get no reply: the client's prediction stands.
	if result == BombConstants.TapResult.Refused or result == BombConstants.TapResult.Invalid then
		tapRemote:FireClient(player, requestId)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	tapLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info("BombTapService ready — payload, arena, range and rate validation active")
