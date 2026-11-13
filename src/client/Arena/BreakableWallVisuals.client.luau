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

type Watched = {
	part: BasePart,
	baseColor: Color3,
	baseTransparency: number,
	lastState: string,
	stateConn: RBXScriptConnection,
	-- Fossil letter changes (a new round re-rolls it) redraw a showing glyph.
	fossilConns: { RBXScriptConnection },
	-- One SurfaceGui per broad face while the glyph shows.
	glyphGuis: { SurfaceGui },
	tween: Tween?,
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

local function stopMotion(w: Watched)
	if w.tween then
		w.tween:Cancel()
		w.tween = nil
	end
	if w.telegraphThread then
		pcall(task.cancel, w.telegraphThread)
		w.telegraphThread = nil
	end
end

local function fadeTo(w: Watched, transparency: number, seconds: number, info: TweenInfo?)
	if w.tween then
		w.tween:Cancel()
		w.tween = nil
	end
	if seconds <= 0 and not info then
		w.part.Transparency = transparency
		return
	end
	local tween = TweenService:Create(
		w.part,
		info or TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = transparency }
	)
	w.tween = tween
	tween:Play()
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
	w.part.Transparency = C.GHOST_TRANSPARENCY + C.GHOST_PULSE_DEPTH
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
		part.Transparency = 1
		part.Color = w.baseColor
		if live then
			SkillVisuals.spawnEffectAtPoint(part.Position, C.Vfx.Break)
		end
		scheduleTelegraph(w)
		return
	end

	-- Every non-broken stage is the authored look pushed toward the damage tint.
	local tint = 0
	local transparency = w.baseTransparency
	if state == State.Cracked then
		tint = C.CRACKED_TINT_FRACTION
	elseif state == State.Critical then
		tint = C.CRITICAL_TINT_FRACTION
		transparency = math.max(transparency, C.CRITICAL_TRANSPARENCY)
	end
	part.Color = w.baseColor:Lerp(C.DAMAGE_TINT_COLOR, tint)

	if previous == State.Broken then
		-- Re-sealed. Dust where it closes, and a fade-in from the ghost
		-- rather than a pop.
		if live then
			SkillVisuals.spawnEffectAtPoint(part.Position, C.Vfx.Reseal)
		end
		if live and not isReduced() then
			fadeTo(w, transparency, C.RESEAL_FADE_SEC)
		else
			part.Transparency = transparency
		end
		return
	end

	part.Transparency = transparency
	if live and tint > 0 then
		SkillVisuals.spawnEffectAtPoint(part.Position, C.Vfx.Crack)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("BasePart") or watched[instance] then
		return
	end
	local part: BasePart = instance
	local w: Watched = {
		part = part,
		baseColor = part.Color,
		baseTransparency = part.Transparency,
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
		fossilConns = {},
		glyphGuis = {},
	}
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
	for _, connection in w.fossilConns do
		connection:Disconnect()
	end
	clearGlyph(w)
	stopMotion(w)
	-- Put the authored look back: the part may be re-tagged or re-streamed.
	if w.part.Parent then
		w.part.Color = w.baseColor
		w.part.Transparency = w.baseTransparency
	end
end

CollectionService:GetInstanceAddedSignal(C.TAG):Connect(watch)
CollectionService:GetInstanceRemovedSignal(C.TAG):Connect(unwatch)
for _, instance in CollectionService:GetTagged(C.TAG) do
	watch(instance)
end

log:info("ready")
