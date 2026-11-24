--!strict

----------------------------------------------------------------------
-- SporeLetterVisuals
----------------------------------------------------------------------
-- Makes a spore letter read as dangerous and shows its fuse. A spore is an
-- ordinary letter block the boss lobbed; the server (BlockSpawner.spawnSpore)
-- marks it `SporeConstants.ATTRIBUTE` and publishes when it bursts as
-- `SporeConstants.EXPIRES_ATTRIBUTE` (`workspace:GetServerTimeNow()` seconds,
-- never os.clock). The server draws nothing; this script owns what a player
-- sees of the fuse (docs/agents/vfx-sfx.md): one Highlight per spore, an
-- outline plus a fill that pulses, drawn through walls, pulsing faster in the
-- last SporeConstants.FAST_WINDOW_SEC seconds. The burst itself and the
-- landing are world cues the server sends with VfxBroadcast.
--
-- A Highlight and not a tint on the block: LetterBlockAnimator owns the
-- block's transform and its intro fade, and a second writer on the same
-- parts would fight it (wiki/concepts/SingleOwnership.md). A spore is rare (a
-- lob of three, one lob in about two attacks), so the engine's cap on drawn
-- Highlights is not a worry here, unlike one per field block.
--
-- The same script draws the burst radius: a ground ring (CosmeticRing, outline
-- plus a fill) under the block for the whole fuse, in the fuse orange, filling
-- from the centre to the full radius exactly at the expiry time. The pool
-- publishes the radius, the ground height and the fuse's length next to the
-- expiry (SporeConstants), so the client does not raycast for the floor.
--
-- Everything is client-local and is removed with the block.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SporeConstants = require(ReplicatedStorage.Shared.BlockSpawner.SporeConstants)
local CosmeticRing = require(ReplicatedStorage.Shared.Vfx.CosmeticRing)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SporeLetterVisuals")

local TAU = math.pi * 2
local HALF = 0.5

type Fuse = {
	highlight: Highlight,
	-- The burst-radius ring on the ground. Made on the first frame the block's
	-- published radius and ground height are readable, so it may be nil for a
	-- frame or for good (a spore spawned without them).
	ring: CosmeticRing.Ring?,
	-- Pulse phase in radians, advanced by the current rate so a change of
	-- rate speeds the pulse up without a jump.
	phase: number,
	connection: RBXScriptConnection,
}

local fuses: { [Model]: Fuse } = {}

-- The ring under a spore, centred on the block horizontally and on the ground
-- height the pool published; nil until the block carries both it and the burst
-- radius.
local function makeRing(block: Model): CosmeticRing.Ring?
	local radius = block:GetAttribute(SporeConstants.BURST_RADIUS_ATTRIBUTE)
	local groundY = block:GetAttribute(SporeConstants.GROUND_Y_ATTRIBUTE)
	if type(radius) ~= "number" or radius <= 0 or type(groundY) ~= "number" then
		return nil
	end
	local centre = block:GetPivot().Position
	return CosmeticRing.new(Vector3.new(centre.X, groundY, centre.Z), {
		radius = radius,
		color = SporeConstants.FILL_COLOR,
		strokeStuds = SporeConstants.RING_STROKE_STUDS,
		outlineTransparency = SporeConstants.RING_OUTLINE_TRANSPARENCY,
		fillTransparency = SporeConstants.RING_FILL_TRANSPARENCY,
	})
end

local function removeFuse(block: Model)
	local fuse = fuses[block]
	if fuse == nil then
		return
	end
	fuses[block] = nil
	fuse.connection:Disconnect()
	fuse.highlight:Destroy()
	if fuse.ring ~= nil then
		fuse.ring.destroy()
	end
end

-- Adds the fuse look once the block is marked. The mark and the tag replicate
-- independently, so this is tried on both.
local function refresh(block: Model)
	local isSpore = block:GetAttribute(SporeConstants.ATTRIBUTE) == true
	if not isSpore then
		removeFuse(block)
		return
	end
	if fuses[block] ~= nil then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = SporeConstants.HIGHLIGHT_NAME
	highlight.Adornee = block
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = SporeConstants.FILL_COLOR
	highlight.OutlineColor = SporeConstants.OUTLINE_COLOR
	highlight.OutlineTransparency = SporeConstants.OUTLINE_TRANSPARENCY
	highlight.FillTransparency = SporeConstants.FILL_TRANSPARENCY_MAX
	highlight.Parent = block

	local connection = block.Destroying:Connect(function()
		removeFuse(block)
	end)
	fuses[block] = { highlight = highlight, ring = nil, phase = 0, connection = connection }
end

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local block: Model = instance
	block:GetAttributeChangedSignal(SporeConstants.ATTRIBUTE):Connect(function()
		refresh(block)
	end)
	refresh(block)
end

for _, block in ipairs(CollectionService:GetTagged(LetterBlocks.TAG)) do
	track(block)
end
CollectionService:GetInstanceAddedSignal(LetterBlocks.TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG):Connect(function(instance)
	if instance:IsA("Model") then
		removeFuse(instance)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	for block, fuse in pairs(fuses) do
		if block.Parent == nil then
			removeFuse(block)
			continue
		end
		local expiresAt = block:GetAttribute(SporeConstants.EXPIRES_ATTRIBUTE)
		local remaining = if type(expiresAt) == "number" then expiresAt - now else math.huge
		local rate = if remaining <= SporeConstants.FAST_WINDOW_SEC
			then SporeConstants.PULSE_FAST_HZ
			else SporeConstants.PULSE_BASE_HZ
		fuse.phase = (fuse.phase + rate * TAU * dt) % TAU
		-- 0 at the faintest, 1 at the strongest.
		local wave = (math.sin(fuse.phase) + 1) * HALF
		fuse.highlight.FillTransparency = SporeConstants.FILL_TRANSPARENCY_MAX
			- (SporeConstants.FILL_TRANSPARENCY_MAX - SporeConstants.FILL_TRANSPARENCY_MIN) * wave

		-- The burst radius on the ground, filling to the full radius exactly
		-- at the expiry time.
		local fuseSec = block:GetAttribute(SporeConstants.FUSE_SEC_ATTRIBUTE)
		if fuse.ring == nil then
			fuse.ring = makeRing(block)
		end
		if fuse.ring ~= nil and type(expiresAt) == "number" and type(fuseSec) == "number" and fuseSec > 0 then
			fuse.ring.setFill(1 - remaining / fuseSec)
		end
	end
end)

log:info("SporeLetterVisuals started")
