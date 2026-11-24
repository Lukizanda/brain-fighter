--!strict

----------------------------------------------------------------------
-- BombVisuals
----------------------------------------------------------------------
-- Draws the scramble puzzle and its seekers (BombConstants is the contract).
-- The server makes one Model per puzzle whose parts Tile1..TileN are the
-- letters: they rest on a small circle until the puzzle is solved or hatches,
-- and from its hatch on a letter's part is moved by the server every tick
-- (Hatched = true) until popped or burst. The server draws no glyph, ring or
-- label. This script owns what a player sees (docs/agents/vfx-sfx.md):
--   * RESTING: the letters are drawn, and their client-only tap proxies are
--     placed, in a ROW above BombCentre that always faces this client's camera
--     (left to right in tile order along the camera's flattened right vector),
--     so they never overlap or hide each other. Big glyphs: palette tint, white
--     letter, dark outline and border. A locked letter is greyed with its order
--     badge. A countdown number (a pixel-sized billboard) and a ground ring
--     that fills as the timer runs out show how long is left; a refused tap
--     (BombHatchAt jumping earlier) flashes it with a "-1.0s" note. After
--     BombHintAt the next correct letter pulses with a marker. Too far from
--     the centre: the row is grey with a "get closer" note. A refused tap
--     shakes that letter with a red border.
--   * HATCHED: a hatched letter's glyph and proxy leave the row and follow the
--     server part (eased), with a warning border, a "!" badge and a fast pulse,
--     and a burst-radius ring on the ground under it (one downward raycast per
--     seeker per frame, the same probe the server uses). Out of seeker reach:
--     grey. Locked letters' visuals go with their parts. No hint, no countdown.
--   * the word progress as a small strip at the top centre of the screen
--     ("C A _"; struck through with a "Pop them or hide!" note once hatched).
-- Progress strip: a minimal self-contained ScreenGui built here, with its
-- numbers in BombClientConstants.
-- It never moves, reparents or destroys a server instance. The server parts
-- stay where they are, hidden locally (LocalTransparencyModifier); everything
-- drawn here is client-only and removed with its letter, and a puzzle's with
-- the puzzle. Every value is re-read each frame. Runs on Heartbeat on purpose:
-- RenderStepped does not fire on the automated test client. Reduced effects
-- (Settings) drops the pulsing, shaking and flashing.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local BombRules = require(ReplicatedStorage.Shared.Boss.BombRules)
local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local CosmeticRing = require(ReplicatedStorage.Shared.Vfx.CosmeticRing)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Settings = require(ReplicatedStorage.Shared.Settings)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local SporeConstants = require(ReplicatedStorage.Shared.BlockSpawner.SporeConstants)

local BombClientConstants = require(script.Parent.BombClientConstants)
local BombClientState = require(script.Parent.BombClientState)

local log = Logger.new("BombVisuals")
local K = BombClientConstants

local LocalPlayer = Players.LocalPlayer

local TAU = math.pi * 2
local CENTRE = 0.5
local HALF = 0.5
local FULL = UDim2.fromScale(1, 1)
local LOCAL_HIDDEN = 1
local NO_TARGET = 0
local UP = Vector3.new(0, 1, 0)

type LetterView = {
	index: number,
	part: BasePart,
	folder: Folder,
	gui: BillboardGui,
	bg: Frame,
	border: UIStroke,
	letter: TextLabel,
	tag: TextLabel,
	badge: TextLabel,
	scale: UIScale,
	proxy: Part,
	ring: CosmeticRing.Ring?,
	ringY: number?,
	pos: Vector3,
	shown: boolean,
	hatched: boolean,
	fireball: Part?,
	hatchedAt: number?,
	gone: RBXScriptConnection,
}

type TimerView = {
	anchor: Part,
	gui: BillboardGui,
	time: TextLabel,
	timeScale: UIScale,
	note: TextLabel,
	ring: CosmeticRing.Ring,
	lastHatchAt: number?,
	penaltyAt: number?,
	penaltySec: number,
}

type PuzzleView = {
	model: Model,
	folder: Folder,
	order: number,
	letterViews: { [number]: LetterView },
	timer: TimerView?,
	allowed: { string },
	allowedText: string,
	-- Derived each frame, read by the progress strip.
	letters: { string },
	accepted: { number },
	broken: boolean,
	chasing: boolean,
	relevance: number,
	destroying: RBXScriptConnection,
}

type Frame_ = {
	dt: number,
	now: number,
	reduced: boolean,
	rootPosition: Vector3?,
	cameraRight: Vector3,
	groundParams: RaycastParams,
}

local views: { [Model]: PuzzleView } = {}
local trackSeq = 0
local clientFolder: Folder = Instance.new("Folder")
clientFolder.Name = K.CLIENT_FOLDER_NAME
clientFolder.Parent = workspace

----------------------------------------------------------------------
-- Progress strip (top-centre HUD)
----------------------------------------------------------------------

local function makeStripLabel(parent: Instance, font: Enum.Font, height: number, top: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = K.SLOT_TEXT_COLOR
	label.Size = UDim2.new(1, 0, 0, height)
	label.Position = UDim2.fromOffset(0, top)
	label.Text = ""
	local outline = Instance.new("UIStroke")
	outline.Color = K.GLYPH_TEXT_OUTLINE
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = label
	label.Parent = parent
	return label
end

local stripGui = Instance.new("ScreenGui")
stripGui.Name = K.HUD_GUI_NAME
stripGui.ResetOnSpawn = false
stripGui.DisplayOrder = HudConstants.LAYERS.Overlay + K.HUD_DISPLAY_ORDER_BOOST
stripGui.Enabled = false

local stripFrame = Instance.new("Frame")
stripFrame.AnchorPoint = Vector2.new(CENTRE, 0)
stripFrame.Position = UDim2.new(CENTRE, 0, 0, K.HUD_TOP_PX)
stripFrame.Size = UDim2.fromOffset(K.HUD_WIDTH_PX, K.HUD_SLOTS_HEIGHT_PX + K.HUD_NOTE_HEIGHT_PX)
stripFrame.BackgroundColor3 = K.HUD_BG_COLOR
stripFrame.BackgroundTransparency = K.HUD_BG_TRANSPARENCY
stripFrame.BorderSizePixel = 0
stripFrame.Parent = stripGui
local stripCorner = Instance.new("UICorner")
stripCorner.CornerRadius = UDim.new(0, K.HUD_CORNER_PX)
stripCorner.Parent = stripFrame

local stripSlots = makeStripLabel(stripFrame, K.LABEL_FONT, K.HUD_SLOTS_HEIGHT_PX, 0)
local stripNote = makeStripLabel(stripFrame, K.NOTE_FONT, K.HUD_NOTE_HEIGHT_PX, K.HUD_SLOTS_HEIGHT_PX)
stripGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function updateStrip()
	local chosen: PuzzleView? = nil
	for _, view in views do
		if view.relevance > 0 and #view.letters > 0 then
			local best = chosen
			if best == nil or view.relevance > best.relevance
				or (view.relevance == best.relevance and view.order < best.order)
			then
				chosen = view
			end
		end
	end
	if chosen == nil then
		stripGui.Enabled = false
		return
	end

	local slots: { string } = {}
	for position = 1, #chosen.letters do
		local tile = chosen.accepted[position]
		table.insert(slots, if tile ~= nil then chosen.letters[tile] or K.SLOT_EMPTY else K.SLOT_EMPTY)
	end
	local text = table.concat(slots, K.SLOT_SEPARATOR)
	if chosen.broken then
		stripSlots.Text = string.format(K.BROKEN_SLOTS_FORMAT, text)
		stripSlots.TextColor3 = K.BROKEN_TEXT_COLOR
		stripNote.Text = K.BROKEN_NOTE_TEXT
		stripNote.TextColor3 = K.BROKEN_NOTE_COLOR
	else
		stripSlots.Text = text
		stripSlots.TextColor3 = K.SLOT_TEXT_COLOR
		stripNote.Text = ""
	end
	stripGui.Enabled = true
end

----------------------------------------------------------------------
-- Building a letter
----------------------------------------------------------------------

local function makeLabel(parent: Instance, font: Enum.Font, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = K.GLYPH_TEXT_COLOR
	label.Size = size
	label.Position = position
	label.Text = ""
	local outline = Instance.new("UIStroke")
	outline.Color = K.GLYPH_TEXT_OUTLINE
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = label
	label.Parent = parent
	return label
end

local function destroyLetter(view: PuzzleView, index: number)
	local letterView = view.letterViews[index]
	if letterView == nil then
		return
	end
	view.letterViews[index] = nil
	letterView.gone:Disconnect()
	if letterView.ring ~= nil then
		letterView.ring.destroy()
		letterView.ring = nil
	end
	-- A hidden fireball is parented to nil, so the folder would not take it.
	if letterView.fireball ~= nil then
		letterView.fireball:Destroy()
		letterView.fireball = nil
	end
	letterView.folder:Destroy()
end

local function makeLetter(view: PuzzleView, index: number, part: BasePart): LetterView
	-- The server part is invisible on this client; the glyph and the tap target
	-- are the client's own proxy.
	part.LocalTransparencyModifier = LOCAL_HIDDEN

	local folder = Instance.new("Folder")
	folder.Name = BombConstants.TILE_PART_PREFIX .. tostring(index)

	local gui = Instance.new("BillboardGui")
	gui.Name = "LetterGlyph"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Active = false
	gui.Size = UDim2.fromScale(K.GLYPH_STUDS, K.GLYPH_STUDS)

	local bg = Instance.new("Frame")
	bg.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	bg.Position = UDim2.fromScale(CENTRE, CENTRE)
	bg.Size = FULL
	bg.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(K.GLYPH_CORNER_SCALE, 0)
	corner.Parent = bg
	local scale = Instance.new("UIScale")
	scale.Parent = bg
	bg.Parent = gui
	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = K.GLYPH_BORDER_COLOR
	border.Thickness = K.GLYPH_BORDER_PX
	border.Parent = bg

	local letter = makeLabel(bg, K.LABEL_FONT, FULL, UDim2.fromScale(0, 0))

	local tag = makeLabel(
		gui,
		K.LABEL_FONT,
		UDim2.fromScale(K.TAG_WIDTH_SCALE, K.TAG_HEIGHT_SCALE),
		UDim2.fromScale(CENTRE, K.TAG_TOP_SCALE)
	)
	tag.AnchorPoint = Vector2.new(CENTRE, 0)
	tag.BackgroundTransparency = 0
	tag.TextColor3 = K.TAG_TEXT_COLOR
	tag.Visible = false
	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(K.GLYPH_CORNER_SCALE, 0)
	tagCorner.Parent = tag

	local badge = makeLabel(
		gui,
		K.LABEL_FONT,
		UDim2.fromScale(K.BADGE_SIZE_SCALE, K.BADGE_SIZE_SCALE),
		UDim2.fromScale(K.BADGE_X_SCALE, K.BADGE_Y_SCALE)
	)
	badge.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = K.BADGE_BG_COLOR
	badge.TextColor3 = K.BADGE_TEXT_COLOR
	badge.Visible = false
	badge.ZIndex = 2
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(K.BADGE_CORNER_SCALE, 0)
	badgeCorner.Parent = badge

	gui.Parent = folder

	-- The enlarged tap target. Client-only; BombTapController hits it.
	local proxy = Instance.new("Part")
	proxy.Name = K.PROXY_NAME
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = true
	proxy.CastShadow = false
	proxy.Transparency = 1
	proxy.Size = Vector3.one * K.PROXY_SIZE_STUDS
	proxy.CFrame = CFrame.new(part.Position)
	proxy:SetAttribute(BombConstants.TILE_INDEX_ATTRIBUTE, index)
	local bombRef = Instance.new("ObjectValue")
	bombRef.Name = K.PROXY_BOMB_VALUE_NAME
	bombRef.Value = view.model
	bombRef.Parent = proxy
	proxy.Parent = folder
	gui.Adornee = proxy

	folder.Parent = view.folder

	-- Everything of this letter goes the moment its part does.
	local gone = part.AncestryChanged:Connect(function()
		if part.Parent ~= view.model then
			destroyLetter(view, index)
		end
	end)

	return {
		index = index,
		part = part,
		folder = folder,
		gui = gui,
		bg = bg,
		border = border,
		letter = letter,
		tag = tag,
		badge = badge,
		scale = scale,
		proxy = proxy,
		ring = nil,
		ringY = nil,
		pos = part.Position,
		shown = true,
		hatched = false,
		fireball = nil,
		hatchedAt = nil,
		gone = gone,
	}
end

----------------------------------------------------------------------
-- Timer (countdown number and ground ring)
----------------------------------------------------------------------

local function destroyTimer(view: PuzzleView)
	local timer = view.timer
	if timer == nil then
		return
	end
	view.timer = nil
	timer.ring.destroy()
	timer.anchor:Destroy()
end

local function makeTimer(view: PuzzleView, centre: Vector3, groundY: number): TimerView
	local anchor = Instance.new("Part")
	anchor.Name = "CountdownAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(centre + UP * (K.ROW_LIFT_STUDS + K.COUNTDOWN_ABOVE_ROW_STUDS))

	-- Pixel-sized on purpose: a stud-sized header covered most of the screen.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Countdown"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Active = false
	gui.Size = UDim2.fromOffset(K.COUNTDOWN_WIDTH_PX, K.COUNTDOWN_TIME_HEIGHT_PX + K.COUNTDOWN_NOTE_HEIGHT_PX)
	gui.Adornee = anchor

	local time = makeLabel(
		gui,
		K.LABEL_FONT,
		UDim2.new(1, 0, 0, K.COUNTDOWN_TIME_HEIGHT_PX),
		UDim2.fromOffset(0, 0)
	)
	time.TextColor3 = K.COUNTDOWN_COLOR
	local timeScale = Instance.new("UIScale")
	timeScale.Parent = time

	local note = makeLabel(
		gui,
		K.NOTE_FONT,
		UDim2.new(1, 0, 0, K.COUNTDOWN_NOTE_HEIGHT_PX),
		UDim2.fromOffset(0, K.COUNTDOWN_TIME_HEIGHT_PX)
	)
	gui.Parent = anchor
	anchor.Parent = view.folder

	local ring = CosmeticRing.new(Vector3.new(centre.X, groundY, centre.Z), {
		radius = K.TIMER_RING_RADIUS_STUDS,
		color = K.TIMER_RING_COLOR,
		strokeStuds = K.TIMER_RING_STROKE_STUDS,
		outlineTransparency = K.TIMER_RING_OUTLINE_TRANSPARENCY,
		fillTransparency = K.TIMER_RING_FILL_TRANSPARENCY,
	})
	ring.part.Parent = view.folder

	return {
		anchor = anchor,
		gui = gui,
		time = time,
		timeScale = timeScale,
		note = note,
		ring = ring,
		lastHatchAt = nil,
		penaltyAt = nil,
		penaltySec = 0,
	}
end

local function updateTimer(view: PuzzleView, centre: Vector3, inReach: boolean, frame: Frame_)
	local model = view.model
	local hatchAt = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE)
	local fuse = model:GetAttribute(BombConstants.FUSE_SEC_ATTRIBUTE)
	local groundY = model:GetAttribute(BombConstants.GROUND_Y_ATTRIBUTE)
	if type(hatchAt) ~= "number" or type(fuse) ~= "number" or fuse <= 0 or type(groundY) ~= "number" then
		return
	end
	local timer = view.timer
	if timer == nil then
		timer = makeTimer(view, centre, groundY)
		view.timer = timer
	end

	-- A refused tap moves the hatch earlier: flash and say by how much.
	local last = timer.lastHatchAt
	if last ~= nil and last - hatchAt > K.HATCH_JUMP_EPSILON_SEC then
		timer.penaltyAt = frame.now
		timer.penaltySec = last - hatchAt
		log:info(string.format("timer jumped earlier by %.2fs", last - hatchAt))
	end
	timer.lastHatchAt = hatchAt

	local remaining = math.max(0, hatchAt - frame.now)
	timer.ring.setFill(1 - remaining / fuse)
	timer.time.Text = string.format(K.COUNTDOWN_FORMAT, math.ceil(remaining))

	local sincePenalty = if timer.penaltyAt ~= nil then frame.now - timer.penaltyAt else math.huge
	local flashing = sincePenalty < K.PENALTY_FLASH_SEC
	local urgent = remaining <= K.COUNTDOWN_URGENT_SEC
	timer.time.TextColor3 = if flashing or urgent then K.COUNTDOWN_URGENT_COLOR else K.COUNTDOWN_COLOR
	timer.timeScale.Scale = if flashing and not frame.reduced
		then 1 + K.PENALTY_FLASH_SCALE * (1 - sincePenalty / K.PENALTY_FLASH_SEC)
		else 1

	if flashing then
		timer.note.Text = string.format(K.PENALTY_NOTE_FORMAT, timer.penaltySec)
		timer.note.TextColor3 = K.PENALTY_COLOR
	elseif not inReach then
		timer.note.Text = K.GET_CLOSER_TEXT
		timer.note.TextColor3 = K.GET_CLOSER_COLOR
	else
		timer.note.Text = ""
	end
end

----------------------------------------------------------------------
-- Tracking
----------------------------------------------------------------------

local function removePuzzle(model: Model)
	local view = views[model]
	if view == nil then
		return
	end
	views[model] = nil
	view.destroying:Disconnect()
	for index in pairs(table.clone(view.letterViews)) do
		destroyLetter(view, index)
	end
	destroyTimer(view)
	view.folder:Destroy()
	BombClientState.forget(model)
end

local function trackPuzzle(instance: Instance)
	if not instance:IsA("Model") or views[instance] ~= nil then
		return
	end
	local model: Model = instance
	local folder = Instance.new("Folder")
	folder.Name = model.Name
	folder.Parent = clientFolder
	trackSeq += 1
	views[model] = {
		model = model,
		folder = folder,
		order = trackSeq,
		letterViews = {},
		timer = nil,
		allowed = {},
		allowedText = "",
		letters = {},
		accepted = {},
		broken = false,
		chasing = false,
		relevance = 0,
		destroying = model.Destroying:Connect(function()
			removePuzzle(model)
		end),
	}
	log:info(string.format("tracking puzzle '%s'", model.Name))
end

for _, puzzle in ipairs(CollectionService:GetTagged(BombConstants.TAG)) do
	trackPuzzle(puzzle)
end
CollectionService:GetInstanceAddedSignal(BombConstants.TAG):Connect(trackPuzzle)
CollectionService:GetInstanceRemovedSignal(BombConstants.TAG):Connect(function(instance)
	if instance:IsA("Model") then
		removePuzzle(instance)
	end
end)

----------------------------------------------------------------------
-- Per frame
----------------------------------------------------------------------

local function isReduced(): boolean
	local holder = Settings.localHolderIfAny()
	return holder ~= nil and Settings.read(holder, Settings.Keys.ReducedVfx) == true
end

local function localRootPosition(): Vector3?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- The camera's right vector flattened to the ground plane: the row's direction.
local function cameraRight(): Vector3
	local camera = workspace.CurrentCamera
	if camera == nil then
		return Vector3.xAxis
	end
	local right = camera.CFrame.RightVector
	local flat = Vector3.new(right.X, 0, right.Z)
	if flat.Magnitude < K.ROW_MIN_RIGHT_STUDS then
		return Vector3.xAxis
	end
	return flat.Unit
end

-- Where letter `index` of `count` stands in the camera-facing row.
local function rowPosition(centre: Vector3, right: Vector3, index: number, count: number): Vector3
	local offset = (index - (count + 1) * HALF) * K.ROW_SPACING_STUDS
	return centre + UP * K.ROW_LIFT_STUDS + right * offset
end

-- What the ground probe must not hit: this client's own drawings, the server's
-- parts and every character.
local function refreshGroundParams(params: RaycastParams)
	local ignore: { Instance } = { clientFolder }
	local serverPuzzles = workspace:FindFirstChild(BombConstants.CONTAINER_NAME)
	if serverPuzzles ~= nil then
		table.insert(ignore, serverPuzzles)
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
end

local function setShown(letterView: LetterView, shown: boolean)
	if letterView.shown == shown then
		return
	end
	letterView.shown = shown
	letterView.gui.Enabled = shown
	letterView.proxy.CanQuery = shown
	if letterView.ring ~= nil then
		letterView.ring.part.Parent = if shown then letterView.folder else nil
	end
end

-- What a hatched seeker looks like: a fireball, in place of its letter. A
-- client-only part in the letter's folder, so it goes with the letter.
local function makeFireball(reduced: boolean): Part
	local ball = Instance.new("Part")
	ball.Name = K.FIREBALL_NAME
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = K.FIREBALL_CORE_COLOR
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.Size = Vector3.one * K.FIREBALL_SIZE_STUDS

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, K.FIREBALL_TRAIL_HALF_WIDTH_STUDS, 0)
	top.Parent = ball
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -K.FIREBALL_TRAIL_HALF_WIDTH_STUDS, 0)
	bottom.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = VfxConfig.FIRE.flame
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Lifetime = K.FIREBALL_TRAIL_LIFETIME_SEC
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = ball

	if not reduced then
		local flame = Instance.new("ParticleEmitter")
		flame.Color = VfxConfig.FIRE.flame
		flame.LightEmission = 1
		flame.Rate = K.FIREBALL_FLAME_RATE
		flame.Lifetime = NumberRange.new(K.FIREBALL_FLAME_LIFETIME_MIN_SEC, K.FIREBALL_FLAME_LIFETIME_MAX_SEC)
		flame.Size = NumberSequence.new(K.FIREBALL_FLAME_SIZE_START, K.FIREBALL_FLAME_SIZE_END)
		flame.Transparency = NumberSequence.new(K.FIREBALL_FLAME_FADE_START, 1)
		flame.Speed = NumberRange.new(0, K.FIREBALL_FLAME_SPEED_MAX)
		flame.SpreadAngle = Vector2.new(K.FIREBALL_FLAME_SPREAD_DEG, K.FIREBALL_FLAME_SPREAD_DEG)
		flame.LockedToPart = false
		flame.Parent = ball

		local light = Instance.new("PointLight")
		light.Color = K.FIREBALL_CORE_COLOR
		light.Range = K.FIREBALL_LIGHT_RANGE
		light.Brightness = K.FIREBALL_LIGHT_BRIGHTNESS
		light.Shadows = false
		light.Parent = ball
	end
	return ball
end

-- The burst ring: under a hatched seeker, on the ground one raycast finds.
local function updateRing(view: PuzzleView, letterView: LetterView, frame: Frame_)
	local radius = view.model:GetAttribute(BombConstants.BURST_RADIUS_ATTRIBUTE)
	if type(radius) ~= "number" or radius <= 0 then
		return
	end
	local origin = letterView.pos + Vector3.new(0, BombConstants.GROUND_PROBE_UP_STUDS, 0)
	local reach = BombConstants.GROUND_PROBE_UP_STUDS + BombConstants.GROUND_PROBE_DOWN_STUDS
	local hit = workspace:Raycast(origin, Vector3.new(0, -reach, 0), frame.groundParams)
	local groundY = if hit ~= nil
		then hit.Position.Y
		else (letterView.ringY or letterView.pos.Y - K.RING_FALLBACK_DROP_STUDS)
	letterView.ringY = groundY
	local ringPosition = Vector3.new(letterView.pos.X, groundY + K.RING_LIFT_STUDS, letterView.pos.Z)
	if letterView.ring == nil then
		local ring = CosmeticRing.new(ringPosition, {
			radius = radius,
			color = SporeConstants.FILL_COLOR,
			strokeStuds = SporeConstants.RING_STROKE_STUDS,
			outlineTransparency = SporeConstants.RING_OUTLINE_TRANSPARENCY,
			fillTransparency = SporeConstants.RING_FILL_TRANSPARENCY,
		})
		ring.part.Parent = letterView.folder
		letterView.ring = ring
	end
	local ring = letterView.ring
	if ring ~= nil then
		ring.part.Position = ringPosition
	end
end

type Scene = {
	centre: Vector3?,
	tint: Color3,
	hintTile: number?,
	restingInReach: boolean,
}

local function updateLetter(view: PuzzleView, letterView: LetterView, scene: Scene, frame: Frame_)
	local index = letterView.index
	local hatched = letterView.part:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) == true
	if hatched and not letterView.hatched then
		log:info(string.format("letter %d (%s) hatched", index, view.letters[index] or ""))
	end
	letterView.hatched = hatched

	local locked = table.find(view.accepted, index) ~= nil
	-- Locked letters' parts go at the hatch; a prediction can hide a seeker early.
	local hidden = BombClientState.isHidden(view.model, index) or (locked and view.chasing)
	setShown(letterView, not hidden)

	-- Where it stands: a hatched letter follows the server part (eased); a
	-- resting one sits in the camera-facing row.
	local partPosition = letterView.part.Position
	if hatched then
		if (partPosition - letterView.pos).Magnitude > K.SNAP_DISTANCE_STUDS then
			letterView.pos = partPosition
		else
			letterView.pos = letterView.pos:Lerp(partPosition, 1 - math.exp(-K.FOLLOW_RATE_PER_SEC * frame.dt))
		end
	elseif scene.centre ~= nil then
		letterView.pos = rowPosition(scene.centre, frame.cameraRight, index, #view.letters)
	else
		letterView.pos = partPosition
	end
	letterView.proxy.CFrame = CFrame.new(letterView.pos)

	-- Hatched, it is a fireball and nothing else: no letter, border, badge or tag.
	if hatched then
		letterView.gui.Enabled = false
		local fireball = letterView.fireball
		if fireball == nil then
			fireball = makeFireball(frame.reduced)
			letterView.fireball = fireball
			letterView.hatchedAt = frame.now
		end
		local ignite = math.clamp((frame.now - (letterView.hatchedAt or frame.now)) / K.FIREBALL_IGNITE_SEC, 0, 1)
		local size = K.FIREBALL_SIZE_STUDS * (K.FIREBALL_IGNITE_SCALE + (1 - K.FIREBALL_IGNITE_SCALE) * ignite)
		local committed = letterView.part:GetAttribute(BombConstants.COMMITTED_ATTRIBUTE) == true
		if committed then
			size *= K.FIREBALL_COMMITTED_SCALE
		end
		fireball.Color = if committed then K.FIREBALL_COMMITTED_COLOR else K.FIREBALL_CORE_COLOR
		fireball.Size = Vector3.one * size
		fireball.CFrame = CFrame.new(letterView.pos)
		fireball.Parent = if hidden then nil else letterView.folder
		if not hidden then
			updateRing(view, letterView, frame)
		end
		return
	end
	if hidden then
		return
	end

	local inReach = true
	if hatched then
		local reach = view.model:GetAttribute(BombConstants.SEEKER_REACH_ATTRIBUTE)
		if type(reach) == "number" and frame.rootPosition ~= nil then
			inReach = (frame.rootPosition - partPosition).Magnitude <= reach
		end
	elseif not view.chasing then
		inReach = scene.restingInReach
	end

	letterView.letter.Text = view.letters[index] or ""
	local lockedLook = locked and not hatched
	if lockedLook then
		letterView.bg.BackgroundColor3 = K.LOCKED_BG_COLOR
		letterView.letter.TextColor3 = K.LOCKED_TEXT_COLOR
	elseif not inReach then
		letterView.bg.BackgroundColor3 = K.FAR_BG_COLOR
		letterView.letter.TextColor3 = K.FAR_TEXT_COLOR
	else
		letterView.bg.BackgroundColor3 = scene.tint
		letterView.letter.TextColor3 = K.GLYPH_TEXT_COLOR
	end
	letterView.bg.BackgroundTransparency = K.GLYPH_BG_TRANSPARENCY

	local isHint = scene.hintTile == index and not view.chasing and not locked
	local sinceRefused = BombClientState.secondsSinceRefused(view.model, index)
	local refused = sinceRefused ~= nil and sinceRefused < K.SHAKE_SEC
	-- After the hatch even a letter still waiting to hatch carries the warning border.
	local warned = hatched or view.chasing
	if refused then
		letterView.border.Color = K.REFUSED_BORDER_COLOR
		letterView.border.Thickness = K.HINT_BORDER_PX
	elseif warned then
		letterView.border.Color = K.WARN_COLOR
		letterView.border.Thickness = K.WARN_BORDER_PX
	elseif isHint then
		letterView.border.Color = K.HINT_COLOR
		letterView.border.Thickness = K.HINT_BORDER_PX
	else
		letterView.border.Color = K.GLYPH_BORDER_COLOR
		letterView.border.Thickness = K.GLYPH_BORDER_PX
	end

	-- The corner badge: the order of a locked letter, or the "!" of a seeker.
	if hatched then
		letterView.badge.Visible = true
		letterView.badge.Text = K.WARN_BADGE_TEXT
		letterView.badge.BackgroundColor3 = K.WARN_COLOR
		letterView.badge.TextColor3 = K.GLYPH_TEXT_COLOR
	elseif lockedLook then
		letterView.badge.Visible = true
		letterView.badge.Text = tostring(table.find(view.accepted, index))
		letterView.badge.BackgroundColor3 = K.BADGE_BG_COLOR
		letterView.badge.TextColor3 = K.BADGE_TEXT_COLOR
	else
		letterView.badge.Visible = false
	end

	if isHint then
		letterView.tag.Visible = true
		letterView.tag.Text = K.HINT_TEXT
		letterView.tag.BackgroundColor3 = K.HINT_COLOR
	else
		letterView.tag.Visible = false
	end

	local pulse = 0
	if not frame.reduced then
		if hatched then
			pulse = (HALF + HALF * math.sin(frame.now / K.WARN_PULSE_PERIOD_SEC * TAU)) * K.WARN_PULSE_SCALE
		elseif isHint then
			pulse = (HALF + HALF * math.sin(frame.now / K.HINT_PULSE_PERIOD_SEC * TAU)) * K.HINT_PULSE_SCALE
		end
	end
	letterView.scale.Scale = 1 + pulse

	local shake = 0
	if refused and not frame.reduced and sinceRefused ~= nil then
		shake = math.sin(sinceRefused * K.SHAKE_HZ * TAU) * K.SHAKE_STUDS * (1 - sinceRefused / K.SHAKE_SEC)
	end
	letterView.gui.StudsOffset = Vector3.new(shake, 0, 0)

	if hatched then
		updateRing(view, letterView, frame)
	end
end

local function updatePuzzle(view: PuzzleView, frame: Frame_)
	local model = view.model
	local lettersText = model:GetAttribute(BombConstants.LETTERS_ATTRIBUTE)
	if type(lettersText) ~= "string" then
		return
	end
	local colorName = model:GetAttribute(BombConstants.COLOR_ATTRIBUTE)

	local wordsText = model:GetAttribute(BombConstants.WORDS_ATTRIBUTE)
	if type(wordsText) == "string" and wordsText ~= view.allowedText then
		view.allowedText = wordsText
		view.allowed = BombRules.decodeWords(wordsText)
	end

	view.letters = BombRules.lettersOf(lettersText)
	view.accepted = BombClientState.effectiveAccepted(model)
	view.broken = model:GetAttribute(BombConstants.BROKEN_ATTRIBUTE) == true
	view.chasing = model:GetAttribute(BombConstants.PHASE_ATTRIBUTE) == BombConstants.Phase.Chasing
	local tint = Colors.tint(if type(colorName) == "string" then colorName else nil)

	local target = model:GetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE)
	if type(target) == "number" and target ~= NO_TARGET and target == LocalPlayer.UserId then
		view.relevance = 2
	elseif Arena.idOf(model) == Arena.idOf(LocalPlayer) then
		view.relevance = 1
	else
		view.relevance = 0
	end

	-- Letters exist from landing: pick up new parts, drop gone ones.
	for _, child in model:GetChildren() do
		local index = child:GetAttribute(BombConstants.TILE_INDEX_ATTRIBUTE)
		if child:IsA("BasePart") and type(index) == "number" and view.letterViews[index] == nil then
			view.letterViews[index] = makeLetter(view, index, child)
		end
	end
	for index, letterView in pairs(table.clone(view.letterViews)) do
		if letterView.part.Parent ~= model then
			destroyLetter(view, index)
		end
	end

	local centreValue = model:GetAttribute(BombConstants.CENTRE_ATTRIBUTE)
	local centre: Vector3? = if typeof(centreValue) == "Vector3" then centreValue else nil

	-- Resting reach is measured to the puzzle centre.
	local restingInReach = true
	if not view.chasing and centre ~= nil and frame.rootPosition ~= nil then
		local reach = model:GetAttribute(BombConstants.REACH_ATTRIBUTE)
		if type(reach) == "number" then
			restingInReach = (frame.rootPosition - centre).Magnitude <= reach
		end
	end

	-- The timer belongs to the resting phase only.
	if view.chasing or centre == nil then
		destroyTimer(view)
	else
		updateTimer(view, centre, restingInReach, frame)
	end

	local hintAt = model:GetAttribute(BombConstants.HINT_AT_ATTRIBUTE)
	local hintTile: number? = nil
	if not view.chasing and type(hintAt) == "number" and frame.now >= hintAt then
		hintTile = BombRules.hintTile(view.letters, view.allowed, view.accepted)
	end

	local scene: Scene = { centre = centre, tint = tint, hintTile = hintTile, restingInReach = restingInReach }
	for _, letterView in pairs(view.letterViews) do
		updateLetter(view, letterView, scene, frame)
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- Heartbeat, as SporeLetterVisuals and LetterBlockAnimator: RenderStepped does
-- not fire at all in an MCP-driven Studio playtest (0 in 1 s, Heartbeat 60),
-- so on RenderStepped nothing here ever ran for the playtest bot.
RunService.Heartbeat:Connect(function(dt: number)
	refreshGroundParams(groundParams)
	local frame: Frame_ = {
		dt = dt,
		now = workspace:GetServerTimeNow(),
		reduced = isReduced(),
		rootPosition = localRootPosition(),
		cameraRight = cameraRight(),
		groundParams = groundParams,
	}
	for model, view in pairs(views) do
		if model.Parent == nil then
			removePuzzle(model)
		else
			updatePuzzle(view, frame)
		end
	end
	updateStrip()
end)

log:info("BombVisuals started")
