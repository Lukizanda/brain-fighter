--!strict

----------------------------------------------------------------------
-- BombTapController
----------------------------------------------------------------------
-- The input half of the scramble puzzle (BombConstants is the contract): click
-- or tap a letter and the server is asked to lock it (resting) or pop it
-- (chasing). BombVisuals draws the letters; this script only reads them and
-- sends the tap.
--
-- Prediction. The accept/refuse rule is the shared BombRules, run here on what
-- the server published (letters, allowed words, accepted letters), so the same
-- inputs give the same answer as the server (wiki/concepts/
-- ClientServerPredictionParity.md). The server replies ONLY to a failure:
--   * RESTING (BombPhase Resting): reach is local root to BombCentre, strictly
--     BombReach. A locked letter sends nothing. Predicted accept: the letter
--     shows locked at once, the tap is sent, and the lock is taken back if the
--     server's reply for that request id arrives or if BombAccepted has not
--     confirmed it within PREDICTION_TIMEOUT_SEC. Predicted refuse (out of
--     order): the refused cue plays and the glyph shakes, and the tap is STILL
--     sent, because the server owns the rule (and the time penalty);
--   * CHASING: only a part with Hatched = true can be popped. Reach is local
--     root to THAT seeker, strictly BombSeekerReach. A harmless removal: the
--     seeker is hidden at once and the tap is sent; it is shown again on a reply
--     or if the part is still there after PREDICTION_TIMEOUT_SEC.
-- The word buffer is never touched.
--
-- Which clicks are ours: one whose first ray hit is a letter's client-only
-- tap proxy, or, when the first hit is cover (a wall, the floor), one whose
-- ray meets a tap proxy behind it. A letter block in front of a letter is hit
-- first, so it pops through BlockTapController as usual.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local BombRules = require(ReplicatedStorage.Shared.Boss.BombRules)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local BombClientConstants = require(script.Parent.Vfx.BombClientConstants)
local BombClientState = require(script.Parent.Vfx.BombClientState)

local log = Logger.new("BombTapController")
local K = BombClientConstants

local LocalPlayer = Players.LocalPlayer
local tapRemote = ReplicatedStorage.Shared.Boss.BossEvents:WaitForChild(BombConstants.TAP_REMOTE_NAME) :: RemoteEvent

-- The server's token bucket refills this fast; sending faster only gets taps
-- refused, so a tap sooner than this after the last is dropped here.
local MIN_SEND_GAP_SEC = 1 / BombConstants.TAP_REFILL_PER_SEC

-- Same asset and pitch as BlockTapController's refused-pop cue, so a refused
-- action sounds the same wherever it comes from.
local refusedSound = Instance.new("Sound")
refusedSound.Name = "BombRefusedSound"
refusedSound.SoundId = VfxConfig.SFX.fizzle
refusedSound.Volume = 1
refusedSound.PlaybackSpeed = VfxConfig.SFX.FIZZLE_PLAYBACK_SPEED
refusedSound.Parent = SoundService

type Kind = "accept" | "harmless" | "refuse"
type Pending = { bomb: Model, tile: number, kind: Kind, part: BasePart }

-- Taps sent and not yet settled, keyed by a client-minted request id (a number
-- survives the trip when the puzzle itself would not).
local pending: { [number]: Pending } = {}
local requestSeq = 0
local lastSent: number = -math.huge

local function livingRoot(): BasePart?
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function refuse(bomb: Model, tile: number)
	refusedSound:Play()
	BombClientState.markRefused(bomb, tile)
end

-- Take a predicted tap back (a failure reply, or a timeout without the server's
-- confirmation): show the letter as it was.
local function rollBack(entry: Pending, why: string)
	local wasPredicted = false
	if entry.kind == "accept" then
		wasPredicted = BombClientState.removePrediction(entry.bomb, entry.tile)
	elseif entry.kind == "harmless" then
		wasPredicted = BombClientState.isHidden(entry.bomb, entry.tile)
		BombClientState.setHidden(entry.bomb, entry.tile, false)
	end
	if wasPredicted then
		refuse(entry.bomb, entry.tile)
		log:info(string.format("letter %d tap rolled back (%s)", entry.tile, why))
	end
end

-- The part of letter `tile`, if it is still there.
local function letterPart(bomb: Model, tile: number): BasePart?
	local part = bomb:FindFirstChild(BombConstants.TILE_PART_PREFIX .. tostring(tile))
	if part ~= nil and part:IsA("BasePart") and part:GetAttribute(BombConstants.TILE_INDEX_ATTRIBUTE) == tile then
		return part
	end
	return nil
end

-- Every tap, click or bot, goes through here. Returns true if a tap was sent.
local function tapLetter(bomb: Model, tile: number): boolean
	if not bomb:IsDescendantOf(workspace) or not CollectionService:HasTag(bomb, BombConstants.TAG) then
		return false
	end
	local root = livingRoot()
	if root == nil then
		log:infoThrottled("no_character", 5, "no living character - ignoring letter tap")
		return false
	end
	local lettersText = bomb:GetAttribute(BombConstants.LETTERS_ATTRIBUTE)
	local wordsText = bomb:GetAttribute(BombConstants.WORDS_ATTRIBUTE)
	if type(lettersText) ~= "string" or type(wordsText) ~= "string" then
		return false
	end
	local letters = BombRules.lettersOf(lettersText)
	if tile ~= math.floor(tile) or tile < 1 or tile > #letters then
		return false
	end

	-- A letter whose part is already gone (popped, burst, puzzle over) is ignored.
	local part = letterPart(bomb, tile)
	if part == nil then
		return false
	end
	local accepted = BombClientState.effectiveAccepted(bomb)
	local chasing = bomb:GetAttribute(BombConstants.PHASE_ATTRIBUTE) == BombConstants.Phase.Chasing

	-- Where reach is measured to, and how far it goes.
	local distance: number
	local reach: any
	if chasing then
		-- Only a hatched seeker can be popped; a letter still waiting to hatch,
		-- or one already popped here, is not a target.
		if part:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) ~= true or BombClientState.isHidden(bomb, tile) then
			return false
		end
		distance = (root.Position - part.Position).Magnitude
		reach = bomb:GetAttribute(BombConstants.SEEKER_REACH_ATTRIBUTE)
	else
		-- A locked letter is a no-op: nothing is sent.
		if BombRules.isLockedTile(accepted, tile) then
			return false
		end
		local centre = bomb:GetAttribute(BombConstants.CENTRE_ATTRIBUTE)
		if typeof(centre) ~= "Vector3" then
			return false
		end
		distance = (root.Position - centre).Magnitude
		reach = bomb:GetAttribute(BombConstants.REACH_ATTRIBUTE)
	end

	-- Out of reach: refused here, nothing sent (the server would refuse it too).
	if type(reach) == "number" and distance > reach then
		refuse(bomb, tile)
		log:info(string.format("letter %d is out of reach - walk closer", tile))
		return false
	end

	local now = os.clock()
	if now - lastSent < MIN_SEND_GAP_SEC then
		return false
	end
	lastSent = now

	local kind: Kind
	if chasing then
		kind = "harmless"
		BombClientState.setHidden(bomb, tile, true)
	elseif BombRules.isAccepted(letters, BombRules.decodeWords(wordsText), accepted, tile) then
		kind = "accept"
		BombClientState.addPrediction(bomb, tile)
	else
		kind = "refuse"
		-- Still sent: the server owns the rule and the time penalty.
		refuse(bomb, tile)
	end

	requestSeq += 1
	local requestId = requestSeq
	pending[requestId] = { bomb = bomb, tile = tile, kind = kind, part = part }
	tapRemote:FireServer(bomb, tile, requestId)
	log:info(string.format("tapped letter %d (%s)", tile, kind))

	task.delay(K.PREDICTION_TIMEOUT_SEC, function()
		local entry = pending[requestId]
		if entry == nil then
			return
		end
		pending[requestId] = nil
		if entry.kind == "accept" then
			-- Rolls back only if BombAccepted never confirmed the lock.
			rollBack(entry, "not confirmed in time")
		elseif entry.kind == "harmless" and entry.part.Parent ~= nil then
			-- A seeker that is gone was popped as predicted; one still there was not.
			rollBack(entry, "not confirmed in time")
		end
	end)
	return true
end

-- The server failed a tap (a check, or it was refused or invalid). It sends
-- nothing for an accepted, locked or harmless tap.
tapRemote.OnClientEvent:Connect(function(requestId: any)
	if typeof(requestId) ~= "number" then
		return
	end
	local entry = pending[requestId]
	if entry == nil then
		log:info(string.format("reply for request %d had no pending entry (settled already)", requestId))
		return
	end
	pending[requestId] = nil
	rollBack(entry, "server rejected")
end)

----------------------------------------------------------------------
-- Click and touch
----------------------------------------------------------------------

-- The puzzle and letter a ray hit stands for: a client tap proxy only. The
-- server's own letter parts are excluded from the ray.
local function targetOf(hit: Instance): (Model?, number?)
	local index = hit:GetAttribute(BombConstants.TILE_INDEX_ATTRIBUTE)
	if type(index) ~= "number" or hit.Name ~= K.PROXY_NAME then
		return nil, nil
	end
	local ref = hit:FindFirstChild(K.PROXY_BOMB_VALUE_NAME)
	if ref ~= nil and ref:IsA("ObjectValue") and ref.Value ~= nil and ref.Value:IsA("Model") then
		return ref.Value, index
	end
	return nil, nil
end

local function tryTap(screenPosition: Vector2)
	local camera = workspace.CurrentCamera
	local character = LocalPlayer.Character
	if camera == nil or character == nil then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- The server's letter parts must not stand between the pointer and a proxy.
	local ignore: { Instance } = { character }
	local serverBombs = workspace:FindFirstChild(BombConstants.CONTAINER_NAME)
	if serverBombs ~= nil then
		table.insert(ignore, serverBombs)
	end
	params.FilterDescendantsInstances = ignore
	-- ScreenPointToRay pairs with input.Position (see BlockTapController.tryPop).
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local reachVector = ray.Direction * BlockShoot.MAX_RAYCAST_DISTANCE
	local result = workspace:Raycast(ray.Origin, reachVector, params)
	if result ~= nil then
		local bomb, tile = targetOf(result.Instance)
		if bomb ~= nil and tile ~= nil then
			tapLetter(bomb, tile)
			return
		end
		-- A letter block in front of a puzzle letter is BlockTapController's pop.
		if BlockShoot.findLetterBlock(result.Instance) ~= nil then
			return
		end
	end

	-- The glyphs draw through walls (AlwaysOnTop) and the design solves a puzzle
	-- behind cover, so a wall or the floor between the camera and a letter must
	-- not swallow the tap: look again at the client's tap proxies only.
	local clientFolder = workspace:FindFirstChild(K.CLIENT_FOLDER_NAME)
	if clientFolder == nil then
		return
	end
	local proxyParams = RaycastParams.new()
	proxyParams.FilterType = Enum.RaycastFilterType.Include
	proxyParams.FilterDescendantsInstances = { clientFolder }
	local proxyHit = workspace:Raycast(ray.Origin, reachVector, proxyParams)
	if proxyHit == nil then
		return
	end
	local bomb, tile = targetOf(proxyHit.Instance)
	if bomb ~= nil and tile ~= nil then
		log:info(string.format("letter %d tapped through cover", tile))
		tapLetter(bomb, tile)
	end
end

-- gameProcessedEvent keeps a press on a HUD button from also tapping a letter.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	tryTap(Vector2.new(input.Position.X, input.Position.Y))
end)

-- Automation hook for the Studio playtest bot (src/client/Playtest):
-- Invoke(puzzleModel, tileIndex) -> boolean, true only if a tap was sent.
-- Created at runtime and only in Studio. Same checks and send path as a real tap.
if RunService:IsStudio() then
	local requestBombTap = Instance.new("BindableFunction")
	requestBombTap.Name = "RequestBombTap"
	requestBombTap.OnInvoke = function(bomb: any, tileIndex: any): boolean
		if typeof(bomb) ~= "Instance" or not bomb:IsA("Model") or typeof(tileIndex) ~= "number" then
			return false
		end
		return tapLetter(bomb, tileIndex)
	end
	requestBombTap.Parent = script
end

log:info("BombTapController started - tap a puzzle letter")
