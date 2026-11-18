--!strict

----------------------------------------------------------------------
-- BreakableWallVisuals
----------------------------------------------------------------------
-- Draws every part tagged "BreakableWall": the crack stages, the break,
-- and the regen telegraph. The server owns the wall's health and
-- collision and publishes `WallState` on the part
-- (server/Arena/BreakableWallService); this controller owns everything a
-- player sees and hears of it and is the only writer of the part's
-- Color and Transparency on this client. Server code never sets either.
--
-- Level art: a wall may carry art as BaseParts parented directly under it,
-- named `Deco_<n>` (takes the damage tint and every fade with the wall) or
-- `Seam_<n>` (a glow strip: fades with the wall, never tinted). They are
-- pieces of the wall's look, so this controller is the only writer of their
-- Color and Transparency too. With streaming a child can arrive after its
-- wall; it is drawn in the wall's current state when it does.
--
-- Greybox quality on purpose: a tint toward a dark stone colour per stage,
-- a little transparency at the critical stage, the break as a burst plus
-- hide, and the regen as a faint pulsing ghost before the wall re-seals.
-- The sounds and bursts are VfxConfig.EFFECTS entries, so a real art pass
-- is a config change.
--
-- Late joiners and re-streamed walls: a wall seen for the first time is
-- drawn in whatever state it is already in, silently. Only a transition
-- observed live plays a sound or burst.
--
-- Fossil letters: a wall carrying a server-published `FossilLetter` also
-- draws that letter on its broad faces while cracked or critical (see
-- "Fossil glyph" below); this controller owns that glyph too.
--
-- Reduced effects (Settings) is honoured the way spawnEffect honours it:
-- bursts and sounds are spawnEffect's to scale; this controller drops the
-- ghost pulse and the re-seal fade, which are motion for its own sake.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BreakableWallConstants = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Settings = require(ReplicatedStorage.Shared.Settings)
local SkillVisuals = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local log = Logger.new("BreakableWallVisuals")

local C = BreakableWallConstants
local State = C.State
local Fossil = FossilConstants
local Glyph = FossilConstants.Glyph

-- One visible piece of a wall: the tagged part itself, or an art child.
type Piece = {
	part: BasePart,
	baseColor: Color3,
	baseTransparency: number,
	tinted: boolean, -- false for seams: they keep their colour
	tween: Tween?,
}

type Watched = {
	part: BasePart,
	-- pieces[1] is the tagged part; the rest are its art children.
	pieces: { Piece },
	-- What the wall currently shows, kept so a late art child can match it.
	tintFraction: number,
	transparency: number,
	lastState: string,
	stateConn: RBXScriptConnection,
	childConns: { RBXScriptConnection },
	-- Fossil letter changes (a new round re-rolls it) redraw a showing glyph.
	fossilConns: { RBXScriptConnection },
	-- One SurfaceGui per broad face while the glyph shows.
	glyphGuis: { SurfaceGui },
	telegraphThread: thread?,
}

local watched: { [BasePart]: Watched } = {}

local function isReduced(): boolean
	local holder = Settings.localHolderIfAny()
	return holder ~= nil and Settings.read(holder, Settings.Keys.ReducedVfx) == true
end

local function stateOf(part: BasePart): string
	local value = part:GetAttribute(C.Published.State)
	return if type(value) == "string" then value else State.Intact
end

-- A piece never shows more solid than it was authored: a half-clear seam
-- stays half-clear on an intact wall and goes with the wall when it fades.
local function pieceTransparency(piece: Piece, wallTransparency: number): number
	return math.max(piece.baseTransparency, wallTransparency)
end

local function cancelTweens(w: Watched)
	for _, piece in w.pieces do
		if piece.tween then
			piece.tween:Cancel()
			piece.tween = nil
		end
	end
end

-- Push every tinted piece `fraction` of the way to the damage colour.
local function setTint(w: Watched, fraction: number)
	w.tintFraction = fraction
	for _, piece in w.pieces do
		if piece.tinted then
			piece.part.Color = piece.baseColor:Lerp(C.DAMAGE_TINT_COLOR, fraction)
		end
	end
end

local function setTransparency(w: Watched, transparency: number)
	w.transparency = transparency
	for _, piece in w.pieces do
		piece.part.Transparency = pieceTransparency(piece, transparency)
	end
end

local function stopMotion(w: Watched)
	cancelTweens(w)
	if w.telegraphThread then
		pcall(task.cancel, w.telegraphThread)
		w.telegraphThread = nil
	end
end

local function fadeTo(w: Watched, transparency: number, seconds: number, info: TweenInfo?)
	cancelTweens(w)
	if seconds <= 0 and not info then
		setTransparency(w, transparency)
		return
	end
	w.transparency = transparency
	local tweenInfo = info or TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, piece in w.pieces do
		local tween = TweenService:Create(
			piece.part,
			tweenInfo,
			{ Transparency = pieceTransparency(piece, transparency) }
		)
		piece.tween = tween
		tween:Play()
	end
end

-- The ghost of a wall that is about to re-seal. A pulse unless the viewer
-- asked for reduced effects, in which case a steady ghost.
local function showGhost(w: Watched)
	if w.lastState ~= State.Broken or not w.part.Parent then
		return
	end
	w.telegraphThread = nil
	if isReduced() then
		fadeTo(w, C.GHOST_TRANSPARENCY, 0)
		return
	end
	setTransparency(w, C.GHOST_TRANSPARENCY + C.GHOST_PULSE_DEPTH)
	fadeTo(w, C.GHOST_TRANSPARENCY - C.GHOST_PULSE_DEPTH, 0, TweenInfo.new(
		C.GHOST_PULSE_SEC,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	))
end

local function scheduleTelegraph(w: Watched)
	local regenSec = w.part:GetAttribute(C.Authored.RegenSec)
	if type(regenSec) ~= "number" or regenSec <= 0 then
		return
	end
	-- Counted from now, when this client saw the break. The server may re-seal a
	-- touch earlier or (while a character overlaps) later than this
	-- estimate; the ghost simply shows until the state changes.
	local wait = math.max(0, regenSec - C.REGEN_TELEGRAPH_LEAD_SEC)
	w.telegraphThread = task.delay(wait, showGhost, w)
end

----------------------------------------------------------------------
-- Fossil glyph
----------------------------------------------------------------------
-- A wall with a `FossilLetter` (published by the server's FossilWatcher)
-- shows that letter on its two broad faces while it is cracked or critical:
-- the crack opens onto the letter. Intact walls show nothing, and a broken
-- one has already freed its letter as a block. The server draws none of it.

local function clearGlyph(w: Watched)
	for _, gui in w.glyphGuis do
		gui:Destroy()
	end
	table.clear(w.glyphGuis)
end

-- The two faces of the wall's thinnest horizontal axis: a wall 20 wide and
-- 2 thick shows on front and back, not on its 2-stud ends. (A rock that is
-- roughly square gets two of its four sides; either reads.)
local function broadFaces(part: BasePart): (Enum.NormalId, Enum.NormalId, number, number)
	local size = part.Size
	if size.X < size.Z then
		return Enum.NormalId.Right, Enum.NormalId.Left, size.Z, size.Y
	end
	return Enum.NormalId.Front, Enum.NormalId.Back, size.X, size.Y
end

local function showGlyph(w: Watched)
	clearGlyph(w)
	local letter = w.part:GetAttribute(Fossil.LETTER_ATTRIBUTE)
	local color = w.part:GetAttribute(Fossil.COLOR_ATTRIBUTE)
	if type(letter) ~= "string" or type(color) ~= "string" then
		return
	end

	local tint = Colors.tint(color):Lerp(Color3.new(1, 1, 1), Glyph.LIGHTEN)
	local faceA, faceB, faceWidth, faceHeight = broadFaces(w.part)
	for _, face in { faceA, faceB } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = Glyph.GUI_NAME
		gui.Face = face
		gui.Adornee = w.part
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = Glyph.PIXELS_PER_STUD
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		-- A square, as tall as the face allows, so the letter is not stretched.
		local side = math.min(faceWidth, faceHeight) * Glyph.SIZE_FRACTION * Glyph.PIXELS_PER_STUD
		label.Size = UDim2.fromOffset(side, side)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.Text = Wildcard.toDisplay(letter)
		label.TextColor3 = tint
		label.TextTransparency = Glyph.TEXT_TRANSPARENCY
		label.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = Glyph.STROKE_THICKNESS
		stroke.Color = Glyph.STROKE_COLOR
		stroke.Parent = label

		gui.Parent = w.part
		table.insert(w.glyphGuis, gui)
	end
end

local function updateGlyph(w: Watched, state: string)
	if state == State.Cracked or state == State.Critical then
		showGlyph(w)
	else
		clearGlyph(w)
	end
end

local function draw(w: Watched, state: string, live: boolean)
	local previous = w.lastState
	w.lastState = state
	stopMotion(w)
	updateGlyph(w, state)
	local part = w.part

	if state == State.Broken then
		setTransparency(w, C.BROKEN_TRANSPARENCY)
		setTint(w, 0)
		if live then
			SkillVisuals.spawnEffectAtPoint(part.Position, C.Vfx.Break)
		end
		scheduleTelegraph(w)
		return
	end

	-- Every non-broken stage is the authored look pushed toward the damage tint.
	local tint = 0
	local transparency = 0
	if state == State.Cracked then
		tint = C.CRACKED_TINT_FRACTION
	elseif state == State.Critical then
		tint = C.CRITICAL_TINT_FRACTION
		transparency = C.CRITICAL_TRANSPARENCY
	end
	setTint(w, tint)

	if previous == State.Broken then
		-- Re-sealed. Dust where it closes, and a fade-in from the ghost
		-- rather than a pop.
		if live then
			SkillVisuals.spawnEffectAtPoint(part.Position, C.Vfx.Reseal)
		end
		if live and not isReduced() then
			fadeTo(w, transparency, C.RESEAL_FADE_SEC)
		else
			setTransparency(w, transparency)
		end
		return
	end

	setTransparency(w, transparency)
	if live and tint > 0 then
		SkillVisuals.spawnEffectAtPoint(part.Position, C.Vfx.Crack)
	end
end

----------------------------------------------------------------------
-- Art children
----------------------------------------------------------------------

local function isDeco(child: Instance): boolean
	return string.find(child.Name, C.Art.DECO_PATTERN) ~= nil
end

local function isArtChild(child: Instance): boolean
	return child:IsA("BasePart") and (isDeco(child) or string.find(child.Name, C.Art.SEAM_PATTERN) ~= nil)
end

local function newPiece(part: BasePart, tinted: boolean): Piece
	return {
		part = part,
		baseColor = part.Color,
		baseTransparency = part.Transparency,
		tinted = tinted,
	}
end

-- An art child seen for the first time takes the wall's current look at
-- once. If the wall is mid-fade or pulsing, the child joins the motion at
-- the next state change: a streamed-in rock does not start a tween of its own.
local function addArtChild(w: Watched, child: Instance)
	if not isArtChild(child) then
		return
	end
	local part = child :: BasePart
	for _, piece in w.pieces do
		if piece.part == part then
			return
		end
	end
	local piece = newPiece(part, isDeco(part))
	table.insert(w.pieces, piece)
	if piece.tinted then
		part.Color = piece.baseColor:Lerp(C.DAMAGE_TINT_COLOR, w.tintFraction)
	end
	part.Transparency = pieceTransparency(piece, w.transparency)
end

-- pieces[1] is the wall itself and is never dropped here.
local function removeArtChild(w: Watched, child: Instance)
	for index = #w.pieces, 2, -1 do
		local piece = w.pieces[index]
		if piece.part == child then
			if piece.tween then
				piece.tween:Cancel()
			end
			table.remove(w.pieces, index)
		end
	end
end

local function watch(instance: Instance)
	if not instance:IsA("BasePart") or watched[instance] then
		return
	end
	local part: BasePart = instance
	local w: Watched = {
		part = part,
		pieces = { newPiece(part, true) },
		tintFraction = 0,
		transparency = 0,
		lastState = State.Intact,
		stateConn = part:GetAttributeChangedSignal(C.Published.State):Connect(function()
			local current = watched[part]
			if not current then
				return
			end
			local state = stateOf(part)
			if state ~= current.lastState then
				draw(current, state, true)
			end
		end),
		childConns = {},
		fossilConns = {},
		glyphGuis = {},
	}
	for _, child in part:GetChildren() do
		addArtChild(w, child)
	end
	table.insert(w.childConns, part.ChildAdded:Connect(function(child: Instance)
		local current = watched[part]
		if current then
			addArtChild(current, child)
		end
	end))
	table.insert(w.childConns, part.ChildRemoved:Connect(function(child: Instance)
		local current = watched[part]
		if current then
			removeArtChild(current, child)
		end
	end))
	-- A re-rolled (or late-replicated) letter redraws the glyph if the wall
	-- is in a state that shows it.
	for _, attribute in { Fossil.LETTER_ATTRIBUTE, Fossil.COLOR_ATTRIBUTE } do
		table.insert(w.fossilConns, part:GetAttributeChangedSignal(attribute):Connect(function()
			local current = watched[part]
			if current then
				updateGlyph(current, current.lastState)
			end
		end))
	end
	watched[part] = w

	local state = stateOf(part)
	if state ~= State.Intact then
		draw(w, state, false)
	end
end

local function unwatch(instance: Instance)
	local w = watched[instance :: BasePart]
	if not w then
		return
	end
	watched[instance :: BasePart] = nil
	w.stateConn:Disconnect()
	for _, connection in w.childConns do
		connection:Disconnect()
	end
	for _, connection in w.fossilConns do
		connection:Disconnect()
	end
	clearGlyph(w)
	stopMotion(w)
	-- Put the authored look back: the part may be re-tagged or re-streamed.
	for _, piece in w.pieces do
		if piece.part.Parent then
			piece.part.Color = piece.baseColor
			piece.part.Transparency = piece.baseTransparency
		end
	end
end

CollectionService:GetInstanceAddedSignal(C.TAG):Connect(watch)
CollectionService:GetInstanceRemovedSignal(C.TAG):Connect(unwatch)
for _, instance in CollectionService:GetTagged(C.TAG) do
	watch(instance)
end

log:info("ready")
