--!strict

----------------------------------------------------------------------
-- ArenaEntryService
----------------------------------------------------------------------
-- The one-way teleporter from an arena's ready room onto its island. Every
-- BasePart tagged `ArenaEntryPad` is watched; a living player of the pad's
-- arena who touches it is moved to a random `ArenaArrivalPoint` of the same
-- arena (matched by `Arena.idOf`), standing on top of it and facing the way
-- the part faces. Nothing leads back: the player leaves the island by dying
-- (the respawn already returns them to the ready room).
--
-- "Which arena is this player in" is the session registry's answer, the same
-- one BlockShoot asks (`SessionRegistry.forPlayer(...):getArenaId()`); this
-- service keeps no arena bookkeeping of its own. A player with no session
-- is refused rather than defaulted to `Default`.
--
-- The server draws nothing: the depart and arrive cues go out through
-- VfxBroadcast and every client draws them.
--
-- A successful teleport is announced on the `PlayerEntered` BindableEvent
-- (`player, arenaId`). The service only announces; the boss entrance
-- (BossService) and arrival protection (HealthService) listen.
--
-- A ModuleScript so the test suite can drive `handleTouch` directly;
-- `ArenaEntryBoot.server.luau` starts it.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local log = Logger.new("ArenaEntryService")

-- Server-side fact: `(player, arenaId)` for each successful teleport. It
-- lives in the Arena domain's shared folder, beside where BossDefeated sits
-- for the Boss domain.
local playerEnteredEvent = ReplicatedStorage.Shared.Arena.ArenaEvents.PlayerEntered :: BindableEvent

local C = ArenaEntryConstants
local Result = C.Result

local padConns: { [BasePart]: RBXScriptConnection } = {}
local tagConns: { RBXScriptConnection } = {}
-- Pads that already warned about having no arrival point. Cleared for an
-- arena when an arrival point of it appears, so a later miss warns again.
local warnedPads: { [BasePart]: boolean } = {}
local lastTeleport: { [Player]: number } = {}
local playerRemovingConn: RBXScriptConnection? = nil
local enabled = false

local ArenaEntryService = {}

----------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------

-- Every live arrival point of the arena. Read from CollectionService on each
-- call rather than cached, so a point tagged (or removed) after boot is
-- honoured with no bookkeeping.
function ArenaEntryService.arrivalsFor(arenaId: string): { BasePart }
	local found: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(C.ARRIVAL_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) and Arena.idOf(instance) == arenaId then
			table.insert(found, instance)
		end
	end
	return found
end

-- Does the arena have an entry pad, i.e. do players reach its island by
-- teleporting rather than by walking in? Asked by whoever needs to know
-- whether an arrival is coming (the boss entrance), so the definition of
-- "a pad of this arena" stays here.
function ArenaEntryService.hasPadFor(arenaId: string): boolean
	for _, instance in CollectionService:GetTagged(C.PAD_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) and Arena.idOf(instance) == arenaId then
			return true
		end
	end
	return false
end

-- One arrival point of the arena, chosen at random; nil when there is none.
-- `random` is injectable so a test can pin the choice.
function ArenaEntryService.pickArrival(arenaId: string, random: Random?): BasePart?
	local arrivals = ArenaEntryService.arrivalsFor(arenaId)
	if #arrivals == 0 then
		return nil
	end
	local generator = random or Random.new()
	return arrivals[generator:NextInteger(1, #arrivals)]
end

-- Where the character's HumanoidRootPart goes: standing on the arrival
-- part's top surface, heading along the part's look vector flattened to the
-- ground plane.
function ArenaEntryService.standingCFrame(arrival: BasePart): CFrame
	local up = arrival.CFrame.UpVector
	local position = arrival.Position + up * (arrival.Size.Y / 2 + C.STAND_OFFSET_STUDS)
	local look = arrival.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < C.MIN_HEADING_LENGTH then
		flat = Vector3.zAxis
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

----------------------------------------------------------------------
-- Touch
----------------------------------------------------------------------

local function characterOf(hit: Instance): (Model?, Player?)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end
	return model, Players:GetPlayerFromCharacter(model)
end

-- The whole decision for one touch, returning what happened. Public so the
-- suite can drive it with a real character; the engine's Touched event adds
-- nothing but the `hit` part.
function ArenaEntryService.handleTouch(pad: BasePart, hit: Instance): string
	local character, player = characterOf(hit)
	if not character or not player then
		return Result.NotAPlayer
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return Result.Dead
	end
	local rootPart: BasePart = root

	local session = SessionRegistry.forPlayer(player)
	if not session or session:getArenaId() ~= Arena.idOf(pad) then
		return Result.WrongArena
	end

	local now = os.clock()
	local last = lastTeleport[player]
	if last and now - last < C.COOLDOWN_SEC then
		return Result.Cooldown
	end

	local arenaId = Arena.idOf(pad)
	local arrival = ArenaEntryService.pickArrival(arenaId)
	if not arrival then
		if not warnedPads[pad] then
			warnedPads[pad] = true
			log:warn(string.format("%s has no ArenaArrivalPoint for arena '%s'", pad:GetFullName(), arenaId))
		end
		return Result.NoArrival
	end

	lastTeleport[player] = now
	local target = ArenaEntryService.standingCFrame(arrival)
	VfxBroadcast.playAt(C.Vfx.Depart, rootPart.Position)
	character:PivotTo(target)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	VfxBroadcast.playAt(C.Vfx.Arrive, target.Position)
	log:info(string.format("%s: %s -> %s", player.Name, pad:GetFullName(), arrival:GetFullName()))
	-- Announce only. Who reacts (the boss entrance, arrival protection) is
	-- their business; this service knows nothing about bosses or health.
	playerEnteredEvent:Fire(player, arenaId)
	return Result.Teleported
end

-- Has this pad already logged its no-arrival warning? Read by the suite.
function ArenaEntryService.hasWarned(pad: BasePart): boolean
	return warnedPads[pad] == true
end

-- Forget cooldowns and warnings. For the suite's fixtures.
function ArenaEntryService.resetState()
	table.clear(lastTeleport)
	table.clear(warnedPads)
end

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

local function watchPad(instance: Instance)
	if not instance:IsA("BasePart") or padConns[instance] then
		return
	end
	padConns[instance] = instance.Touched:Connect(function(hit)
		ArenaEntryService.handleTouch(instance, hit)
	end)
end

local function unwatchPad(instance: Instance)
	local conn = padConns[instance :: BasePart]
	if conn then
		conn:Disconnect()
		padConns[instance :: BasePart] = nil
	end
	warnedPads[instance :: BasePart] = nil
end

-- An arrival point that appears may fix a pad that warned; let it warn again
-- if it is still unmatched later.
local function onArrivalAdded(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local arenaId = Arena.idOf(instance)
	for pad in warnedPads do
		if Arena.idOf(pad) == arenaId then
			warnedPads[pad] = nil
		end
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

-- Pause: stop watching pads. Reversible via enable().
function ArenaEntryService.disable()
	enabled = false
	for _, conn in padConns do
		conn:Disconnect()
	end
	table.clear(padConns)
	for _, conn in tagConns do
		conn:Disconnect()
	end
	table.clear(tagConns)
	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end
	log:info("Disabled")
end

function ArenaEntryService.enable()
	if enabled then
		return
	end
	enabled = true
	-- Listen first, then take what exists, so a pad tagged between the two
	-- is not missed.
	table.insert(tagConns, CollectionService:GetInstanceAddedSignal(C.PAD_TAG):Connect(watchPad))
	table.insert(tagConns, CollectionService:GetInstanceRemovedSignal(C.PAD_TAG):Connect(unwatchPad))
	table.insert(tagConns, CollectionService:GetInstanceAddedSignal(C.ARRIVAL_TAG):Connect(onArrivalAdded))
	for _, pad in CollectionService:GetTagged(C.PAD_TAG) do
		watchPad(pad)
	end
	playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)
	log:info("Enabled")
end

-- Permanent teardown: disable, then drop all state.
function ArenaEntryService.destroy()
	ArenaEntryService.disable()
	table.clear(warnedPads)
	table.clear(lastTeleport)
	log:info("Destroyed")
end

return ArenaEntryService
