-- Level-art prelude. Dev tooling, not game code: nothing in the game requires it.
-- Rojo syncs it to ServerScriptService.Server.Dev.LevelArt.prelude, and the loader
-- (ServerStorage.LevelArtRun) copies it into ServerStorage.LevelArtPrelude, which
-- every level-art file requires:
--   local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
-- The :Clone() defeats the Edit-mode require cache. See README.md.

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ART = {}

----------------------------------------------------------------------
-- Stage
----------------------------------------------------------------------
ART.ROOT_NAME = "LevelArtShowcase"
ART.FLOOR_Y = 200 -- top of the showcase floor; every asset origin sits on it
ART.STAGE_CENTER = Vector3.new(400, ART.FLOOR_Y, 1250)

-- One strip per kit. `z` is the strip's centre line, assets are laid out along
-- +X between xMin and xMax, and face -Z (the review camera stands at lower Z).
ART.ROWS = {
	Rocks = { z = 1120, xMin = 170, xMax = 630, depth = 80 },
	Terrain = { z = 1250, xMin = 170, xMax = 630, depth = 110 },
	SetPieces = { z = 1380, xMin = 170, xMax = 630, depth = 90 },
}

----------------------------------------------------------------------
-- Palette: the only colours and materials an asset may use.
----------------------------------------------------------------------
-- Role names say what the player should read, so a kit never picks a hue.
-- Reserved and absent on purpose: letter red / green / blue and wildcard gold.
local M = Enum.Material
-- Designer rulings (wiki/design/boss-arena.md, Level art): large surfaces
-- S <= 25%, playfield S <= 35%, floor V 30-45%, breakables light and warm-grey
-- so the damage tint toward (46, 38, 32) shows, neon only as thin strips.
ART.PAL = {
	-- Permanent rock (cores): cold, dark, Basalt. Never breaks.
	Bedrock = { M.Basalt, Color3.fromRGB(58, 62, 74) },
	BedrockLight = { M.Basalt, Color3.fromRGB(76, 80, 94) },
	-- Ridge and cliff: cold mid grey-blue, Slate.
	Cliff = { M.Slate, Color3.fromRGB(100, 105, 118) },
	CliffLight = { M.Slate, Color3.fromRGB(126, 131, 144) },
	CliffDark = { M.Slate, Color3.fromRGB(72, 76, 88) },
	-- Breakable letter-stone: desaturated tan, the lightest rock on the island.
	Letterstone = { M.Sandstone, Color3.fromRGB(156, 138, 116) },
	LetterstoneLight = { M.Sandstone, Color3.fromRGB(176, 158, 134) },
	LetterstoneDark = { M.Rock, Color3.fromRGB(132, 116, 98) },
	-- Regenerating gate: cut pale stone with cool light in the seams.
	GateStone = { M.Limestone, Color3.fromRGB(150, 150, 156) },
	GateStoneDark = { M.Limestone, Color3.fromRGB(116, 117, 126) },
	GateSeam = { M.Neon, Color3.fromRGB(216, 236, 255) },
	-- Ground: dark, flat, low saturation. Moss is olive, never letter green.
	Turf = { M.Grass, Color3.fromRGB(88, 98, 76) },
	TurfLight = { M.LeafyGrass, Color3.fromRGB(96, 104, 80) },
	Soil = { M.Ground, Color3.fromRGB(92, 84, 78) },
	Flagstone = { M.Pavement, Color3.fromRGB(104, 106, 114) },
	FlagstoneDark = { M.Cobblestone, Color3.fromRGB(84, 86, 96) },
	-- Boss dais: the only plum on the island.
	Plum = { M.Slate, Color3.fromRGB(74, 52, 82) },
	PlumLight = { M.Marble, Color3.fromRGB(104, 80, 114) },
	Rune = { M.Neon, Color3.fromRGB(214, 150, 255) },
	-- Pads and built things.
	Trim = { M.Metal, Color3.fromRGB(70, 74, 86) },
	TrimLight = { M.Metal, Color3.fromRGB(150, 156, 170) },
	Timber = { M.WoodPlanks, Color3.fromRGB(112, 98, 88) },
	PadArrive = { M.Neon, Color3.fromRGB(53, 201, 192) },
	PadEnter = { M.Neon, Color3.fromRGB(255, 170, 60) },
	PadReturn = { M.Neon, Color3.fromRGB(240, 240, 250) },
	Crystal = { M.Glass, Color3.fromRGB(196, 206, 232) },
	-- Stage only.
	Stage = { M.SmoothPlastic, Color3.fromRGB(40, 42, 48) },
	StageSign = { M.SmoothPlastic, Color3.fromRGB(24, 25, 30) },
}

----------------------------------------------------------------------
-- Folders
----------------------------------------------------------------------
function ART.root(): Folder
	local root = workspace:FindFirstChild(ART.ROOT_NAME)
	if not root then
		root = Instance.new("Folder")
		root.Name = ART.ROOT_NAME
		root.Parent = workspace
	end
	return root
end

function ART.folder(name: string): Folder
	local root = ART.root()
	local folder = root:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
	end
	return folder
end

----------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------
-- Every art part: anchored, smooth surfaces, a palette role, no tags, no
-- attributes that the game reads. `spec.collide` defaults to false: collision
-- is the GreyboxRef's job (see ART.asset).
type Spec = {
	role: string,
	size: Vector3,
	cf: CFrame,
	name: string?,
	shape: string?, -- "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"
	collide: boolean?,
	transparency: number?,
	reflectance: number?,
	shadow: boolean?,
	color: Color3?, -- only to nudge a role's colour by a few points; see ART.shade
}

function ART.shade(role: string, delta: number): Color3
	local base = ART.PAL[role][2]
	local h, s, v = base:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + delta, 0, 1))
end

function ART.prim(parent: Instance, spec: Spec): BasePart
	local pal = ART.PAL[spec.role]
	assert(pal, "unknown palette role: " .. tostring(spec.role))
	local shape = spec.shape or "Block"
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = Enum.PartType[shape]
		part = p
	end
	part.Name = spec.name or (spec.role .. "_" .. shape)
	part.Anchored = true
	part.Massless = true
	part.Material = pal[1]
	part.Color = spec.color or pal[2]
	part.Size = spec.size
	part.CFrame = spec.cf
	part.CanCollide = spec.collide == true
	part.CanQuery = spec.collide == true
	part.CanTouch = false
	part.CastShadow = spec.shadow ~= false
	part.Transparency = spec.transparency or 0
	part.Reflectance = spec.reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A WedgePart, placed by what it does rather than by a CFrame.
-- A wedge's Size is (width, height, run). Its tall vertical face is at local
-- +Z and its slope falls away toward local -Z (checked by raycast in Studio).
--   center      world position of the centre of the wedge's bounding box
--   highToward  world horizontal direction the tall face points to
--   hang        true turns it upside down: the thick end is on top and the
--               slope faces down, for overhangs and the taper under a rock
--   roll        optional degrees about the run axis, to break regularity
type WedgeSpec = {
	role: string,
	width: number,
	height: number,
	run: number,
	center: Vector3,
	highToward: Vector3,
	hang: boolean?,
	roll: number?,
	name: string?,
	color: Color3?,
}

function ART.wedge(parent: Instance, spec: WedgeSpec): BasePart
	local flat = Vector3.new(spec.highToward.X, 0, spec.highToward.Z).Unit
	local cf = CFrame.lookAt(spec.center, spec.center - flat)
	if spec.hang then
		cf *= CFrame.Angles(0, 0, math.pi)
	end
	if spec.roll then
		cf *= CFrame.Angles(0, 0, math.rad(spec.roll))
	end
	return ART.prim(parent, {
		role = spec.role,
		name = spec.name,
		shape = "Wedge",
		size = Vector3.new(spec.width, spec.height, spec.run),
		cf = cf,
		color = spec.color,
	})
end

----------------------------------------------------------------------
-- Assets
----------------------------------------------------------------------
-- One asset = one Model in its kit folder, authored in the local space of the
-- greybox piece it will replace:
--   origin  = centre of the greybox box's footprint, at floor level, +Y up,
--             local X along the box's Size.X, local Z along its Size.Z
--   GreyboxRef = an invisible part the exact size of that greybox box, at
--             `refOffset` (the box centre in local space). It is the model's
--             PrimaryPart, so the swap can drop the model onto a greybox part
--             with `model:PivotTo(greyboxPart.CFrame)`.
-- Re-running a kit rebuilds its assets in place (same name = replaced).
type AssetDef = {
	kit: string, -- kit folder, e.g. "Kit_Rocks"
	name: string, -- e.g. "Cover_Low_A"
	at: Vector3, -- world position of the asset origin (on the stage floor)
	yaw: number?, -- degrees about Y for display
	greybox: Vector3, -- size of the greybox box this asset stands for
	refOffset: Vector3?, -- box centre in local space; default (0, greybox.Y/2, 0)
	class: string, -- greybox prefix it replaces: "Cover", "Core", "Gate", ...
	note: string?, -- one line shown on the sign
	build: (model: Model, origin: CFrame) -> (),
}

function ART.asset(def: AssetDef): Model
	local folder = ART.folder(def.kit)
	local old = folder:FindFirstChild(def.name)
	if old then
		old:Destroy()
	end
	local origin = CFrame.new(def.at) * CFrame.Angles(0, math.rad(def.yaw or 0), 0)

	local model = Instance.new("Model")
	model.Name = def.name

	local ref = Instance.new("Part")
	ref.Name = "GreyboxRef"
	ref.Anchored = true
	ref.Size = def.greybox
	ref.CFrame = origin * CFrame.new(def.refOffset or Vector3.new(0, def.greybox.Y / 2, 0))
	ref.Transparency = 1
	ref.CanCollide = false
	ref.CanQuery = false
	ref.CanTouch = false
	ref.CastShadow = false
	ref.Parent = model
	model.PrimaryPart = ref

	def.build(model, origin)

	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= ref then
			count += 1
		end
	end
	model:SetAttribute("ArtClass", def.class)
	model:SetAttribute("GreyboxSize", def.greybox)
	model:SetAttribute("PartCount", count)
	if def.note then
		model:SetAttribute("Note", def.note)
	end
	model.Parent = folder

	ART.sign(def.kit, def.name, def.at, def.greybox, count, def.note)
	return model
end

-- A floor sign in front of (‑Z of) the asset: its name, the greybox size it
-- stands for, its part count and a note.
function ART.sign(kit: string, name: string, at: Vector3, greybox: Vector3, count: number, note: string?)
	local signs = ART.folder("_Signs")
	local id = kit .. "." .. name
	local old = signs:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local depth = math.max(greybox.X, greybox.Z) / 2 + 9
	local plate = ART.prim(signs, {
		role = "StageSign",
		name = id,
		-- A Top-face SurfaceGui reads along the part's local Z, so the plate is
		-- long in Z and turned to run along the strip.
		size = Vector3.new(7, 0.4, 16),
		cf = CFrame.new(at.X, ART.FLOOR_Y + 0.2, at.Z - depth) * CFrame.Angles(0, math.rad(-90), 0),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Rotation = 180 -- upright for a viewer standing on the -Z side
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 235, 240)
	label.Text = string.format(
		"%s\ngreybox %g x %g x %g  ·  %d parts%s",
		name,
		greybox.X,
		greybox.Y,
		greybox.Z,
		count,
		if note then "\n" .. note else ""
	)
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
end

----------------------------------------------------------------------
-- Breakables
----------------------------------------------------------------------
-- A breakable wall is ONE BasePart in the game (tag BreakableWall), and the
-- wall-visuals client tints and fades that part. The designer's convention for
-- multi-part art, which a later code change will follow:
--   Body     the greybox Block at its exact size: visible, the main mass, and
--            the face the fossil / key glyph is drawn on. In the game this is
--            the tagged part. In the showcase it is NOT tagged.
--   Deco_<n> BaseParts parented directly under Body: take the damage tint and
--            the fade with it.
--   Seam_<n> glow strips parented directly under Body: fade only, no tint.
-- At most 8 children, none more than 1 stud outside the Body box, none over
-- the glyph square on the two broad faces (the pair across the thinnest
-- horizontal axis; the square is 0.7 x min(face width, face height), centred).
type BreakableDef = {
	kit: string,
	name: string,
	at: Vector3,
	yaw: number?,
	size: Vector3, -- the greybox Block
	sink: number?, -- studs the box sits below the floor (cover: 1)
	bodyRole: string,
	class: string,
	note: string?,
	build: (body: BasePart, origin: CFrame) -> (),
}

function ART.breakable(def: BreakableDef): Model
	local sink = def.sink or 0
	local model = ART.asset({
		kit = def.kit,
		name = def.name,
		at = def.at,
		yaw = def.yaw,
		greybox = def.size,
		refOffset = Vector3.new(0, def.size.Y / 2 - sink, 0),
		class = def.class,
		note = def.note,
		build = function(model, origin)
			local body = ART.prim(model, {
				role = def.bodyRole,
				name = "Body",
				size = def.size,
				cf = origin * CFrame.new(0, def.size.Y / 2 - sink, 0),
			})
			def.build(body, origin)
			local children = 0
			for _, child in body:GetChildren() do
				if child:IsA("BasePart") then
					assert(
						child.Name:match("^Deco_%d+$") or child.Name:match("^Seam_%d+$"),
						def.name .. ": child of Body must be Deco_<n> or Seam_<n>, got " .. child.Name
					)
					children += 1
				end
			end
			assert(children <= 8, def.name .. ": more than 8 children under Body")
		end,
	})
	model:SetAttribute("Breakable", true)
	return model
end

-- The game's damage look, applied by hand for review. `fraction` is the lerp
-- toward the damage tint (cracked 0.30, critical 0.60); `transparency` is the
-- part transparency (critical 0.15, regen ghost 0.82).
local DAMAGE_TINT = Color3.fromRGB(46, 38, 32)
function ART.damage(model: Model, fraction: number, transparency: number)
	local body = model:FindFirstChild("Body") :: BasePart
	local function apply(part: BasePart, tint: boolean)
		if tint then
			part.Color = part.Color:Lerp(DAMAGE_TINT, fraction)
		end
		part.Transparency = math.max(part.Transparency, transparency)
	end
	apply(body, true)
	for _, child in body:GetChildren() do
		if child:IsA("BasePart") then
			apply(child, child.Name:match("^Deco_") ~= nil)
		end
	end
end

-- Tile colours a letter is drawn in, both palettes (Shared/Core/Colors).
ART.TILE = {
	default = {
		red = Color3.fromHex("#dc2626"),
		green = Color3.fromHex("#16a34a"),
		blue = Color3.fromHex("#2563eb"),
		wild = Color3.fromHex("#eab308"),
	},
	high_contrast = {
		red = Color3.fromRGB(213, 94, 0),
		green = Color3.fromRGB(0, 158, 115),
		blue = Color3.fromRGB(0, 114, 178),
		wild = Color3.fromRGB(240, 228, 66),
	},
}

-- The fossil / key glyph as the game draws it on a wall's two broad faces
-- (BreakableWallVisuals + FossilConstants.Glyph), for testing a rock's read.
function ART.glyph(body: BasePart, letter: string, tile: string, palette: string?)
	local size = body.Size
	local faces, faceWidth
	if size.X < size.Z then
		faces, faceWidth = { Enum.NormalId.Right, Enum.NormalId.Left }, size.Z
	else
		faces, faceWidth = { Enum.NormalId.Front, Enum.NormalId.Back }, size.X
	end
	local tint = ART.TILE[palette or "default"][tile]:Lerp(Color3.new(1, 1, 1), 0.35)
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "TestGlyph"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		local side = math.min(faceWidth, size.Y) * 0.7 * 24
		label.Size = UDim2.fromOffset(side, side)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.Text = letter
		label.TextColor3 = tint
		label.TextTransparency = 0.1
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(20, 16, 12)
		stroke.Parent = label
		gui.Parent = body
	end
end

-- A stand-in letter block (4 x 4 x 4, glyph on every face) for judging art
-- against the letters. Untagged: the game does not know it exists.
function ART.letterBlock(parent: Instance, position: Vector3, letter: string, tile: string, palette: string?): Part
	local color = ART.TILE[palette or "default"][tile]
	local block = Instance.new("Part")
	block.Name = "TestLetter_" .. letter
	block.Anchored = true
	block.Size = Vector3.new(4, 4, 4)
	block.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(12), math.rad(25), 0)
	block.Material = Enum.Material.SmoothPlastic
	block.Color = color
	block.CanCollide = false
	block.CanQuery = false
	block.CanTouch = false
	block.TopSurface = Enum.SurfaceType.Smooth
	block.BottomSurface = Enum.SurfaceType.Smooth
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45)
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = letter
		label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.7)
		label.Parent = gui
		gui.Parent = block
	end
	block.Parent = parent
	return block
end

-- Wrap a whole kit run in one undo waypoint.
function ART.run(label: string, fn: () -> ())
	local ok, recording = pcall(function()
		return ChangeHistoryService:TryBeginRecording(label)
	end)
	local success, err = pcall(fn)
	if ok and recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if success then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not success then
		error(err, 0)
	end
end

-- Part counts and bounds of every asset in a kit, for the artist's own report.
function ART.report(kit: string): string
	local lines = {}
	for _, model in ART.folder(kit):GetChildren() do
		if model:IsA("Model") then
			local _, size = model:GetBoundingBox()
			table.insert(
				lines,
				string.format(
					"%s parts=%d bounds(%.1f, %.1f, %.1f) greybox(%s)",
					model.Name,
					model:GetAttribute("PartCount") or -1,
					size.X,
					size.Y,
					size.Z,
					tostring(model:GetAttribute("GreyboxSize"))
				)
			)
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

return ART
