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
-- At most ART.MAX_WALL_CHILDREN children, none more than 1 stud outside the Body
-- box (tall cover and spires: 3 studs above +12, designer ruling 2026-11-18),
-- none over the glyph square on the two broad faces (the pair across the thinnest
-- horizontal axis; the square is 0.7 x min(face width, face height), centred).
ART.MAX_WALL_CHILDREN = 12 -- the game client sets no limit; this keeps a wall cheap

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
			assert(
				children <= ART.MAX_WALL_CHILDREN,
				def.name .. ": more than " .. ART.MAX_WALL_CHILDREN .. " children under Body"
			)
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

----------------------------------------------------------------------
-- Dressing the island
----------------------------------------------------------------------
-- The second half of the kit: putting the art on the real greybox. A dress
-- pass is one file under dress/ that owns a named pass ("Dress_Rocks", ...).
-- Everything a pass does is recorded so `ART.undress(pass)` puts the greybox
-- back exactly, and `ART.dress` undresses first, so re-running a file is safe.
--
-- A pass may do four things, all through the helpers below:
--   place   clone a showcase asset onto a greybox part (the part is hidden
--           and stays the collision); the clone lives in the art folder
--   adopt   turn a BreakableWall greybox part into an asset's Body: the part
--           takes the Body's material and colour and gets its Deco_/Seam_
--           children. The part keeps its tag, attributes, size and place
--   skin    give a greybox part a palette role and leave it visible
--   hide    make a greybox part invisible (it still collides)
-- and it may build bespoke art with ART.prim into `ART.dressFolder(pass)`.
-- No helper moves, resizes, renames, re-tags or deletes a greybox part.
ART.ISLAND_NAME = "IslandReview"
ART.READY_ROOM_NAME = "IslandReviewReadyRoom"
ART.DRESS_ROOT_NAME = "IslandReviewArt"
-- A fitted clone stretched beyond this on any axis is reported by ART.audit:
-- past it a rock stops looking like the rock the artist made.
ART.FIT_MIN = 0.6
ART.FIT_MAX = 1.6

local ATTR_PASS = "ArtPass"
local ATTR_COLOR = "ArtOrigColor"
local ATTR_MATERIAL = "ArtOrigMaterial"
local ATTR_TRANSPARENCY = "ArtOrigTransparency"
local ATTR_ADDED = "ArtAdded" -- on a Deco_/Seam_ child a pass parented under a wall
local ATTR_FOR = "ArtFor" -- on a placed model: the greybox part's name
local ATTR_STRETCH = "ArtStretch" -- on a placed / adopted piece: the fit scale

function ART.island(): Model
	local arena = workspace:FindFirstChild("Arena")
	local island = arena and arena:FindFirstChild(ART.ISLAND_NAME)
	assert(island and island:IsA("Model"), "Workspace.Arena." .. ART.ISLAND_NAME .. " is missing")
	return island
end

function ART.readyRoom(): Model?
	local arena = workspace:FindFirstChild("Arena")
	return arena and arena:FindFirstChild(ART.READY_ROOM_NAME) :: Model?
end

-- Centre of the island at the top of the walkable floor.
function ART.islandCenter(): Vector3
	local island = ART.island()
	return Vector3.new(
		island:GetAttribute("CenterX") :: number,
		island:GetAttribute("FloorY") :: number,
		island:GetAttribute("CenterZ") :: number
	)
end

-- Greybox parts of the island whose name starts with `prefix`, in a stable
-- order (names repeat on the island, so order by position, not by name).
function ART.greybox(prefix: string): { BasePart }
	local found = {}
	for _, d in ART.island():GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, #prefix) == prefix and not d:GetAttribute(ATTR_ADDED) then
			table.insert(found, d)
		end
	end
	table.sort(found, function(a, b)
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		if a.Position.X ~= b.Position.X then
			return a.Position.X < b.Position.X
		end
		return a.Position.Z < b.Position.Z
	end)
	return found
end

-- Where a pass keeps the art it builds: Workspace.IslandReviewArt.<pass>.
-- Outside Workspace.Arena on purpose, so no arena scan ever walks it.
function ART.dressFolder(pass: string): Folder
	local root = workspace:FindFirstChild(ART.DRESS_ROOT_NAME)
	if not root then
		root = Instance.new("Folder")
		root.Name = ART.DRESS_ROOT_NAME
		root.Parent = workspace
	end
	local folder = root:FindFirstChild(pass)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = pass
		folder.Parent = root
	end
	return folder
end

-- The horizontal direction from `part` to the island centre, in the part's
-- own space. Its largest component says which local face looks inward.
function ART.towardCenter(part: BasePart): Vector3
	local c = ART.islandCenter()
	local world = Vector3.new(c.X - part.Position.X, 0, c.Z - part.Position.Z)
	if world.Magnitude < 1e-3 then
		return Vector3.zero
	end
	return part.CFrame:VectorToObjectSpace(world.Unit)
end

local function claim(pass: string, part: BasePart)
	local owner = part:GetAttribute(ATTR_PASS)
	assert(
		owner == nil or owner == pass,
		string.format("%s is already dressed by %s; %s must not touch it", part.Name, tostring(owner), pass)
	)
	if owner == nil then
		part:SetAttribute(ATTR_PASS, pass)
		part:SetAttribute(ATTR_COLOR, part.Color)
		part:SetAttribute(ATTR_MATERIAL, part.Material.Name)
		part:SetAttribute(ATTR_TRANSPARENCY, part.Transparency)
	end
end

-- Make a greybox part invisible. It keeps colliding and answering raycasts.
function ART.hide(pass: string, part: BasePart)
	claim(pass, part)
	part.Transparency = 1
end

-- Give a greybox part a palette role and leave it visible.
function ART.skin(pass: string, part: BasePart, role: string, color: Color3?)
	local pal = ART.PAL[role]
	assert(pal, "unknown palette role: " .. tostring(role))
	claim(pass, part)
	part.Material = pal[1]
	part.Color = color or pal[2]
end

local function showcaseAsset(kit: string, asset: string): Model
	local folder = ART.root():FindFirstChild(kit)
	local model = folder and folder:FindFirstChild(asset)
	assert(model and model:IsA("Model"), "no showcase asset " .. kit .. "/" .. asset .. " (run the kit first)")
	return model
end

-- Move one part from `from`'s space into `to`'s space, stretching by `scale`
-- per axis of that space. A rotated part cannot be sheared, so each of its
-- own axes takes the stretch along the direction it points in.
local function refit(part: BasePart, from: CFrame, to: CFrame, scale: Vector3)
	local rel = from:ToObjectSpace(part.CFrame)
	local function along(axis: Vector3): number
		return (axis * scale).Magnitude
	end
	local fx, fy, fz = along(rel.XVector), along(rel.YVector), along(rel.ZVector)
	if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		local f = (fx + fy + fz) / 3
		fx, fy, fz = f, f, f
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		local f = (fy + fz) / 2
		fy, fz = f, f
	end
	part.Size = Vector3.new(part.Size.X * fx, part.Size.Y * fy, part.Size.Z * fz)
	part.CFrame = to * CFrame.new(rel.Position * scale) * rel.Rotation
end

local function stretchOf(scale: Vector3): string
	return string.format("%.2f, %.2f, %.2f", scale.X, scale.Y, scale.Z)
end

type PlaceOpts = {
	name: string?, -- model name in the art folder; default "<part>__<asset>"
	turn: number?, -- 0 / 90 / 180 / 270 about the box's Y: which way the asset faces
	at: CFrame?, -- the box's CFrame, if not the part's own (a Cylinder lying on its side)
	size: Vector3?, -- the box's size, if not the part's own
	keepVisible: boolean?, -- true leaves the greybox part visible under the art
}

-- Clone showcase asset `kit`/`asset` onto a greybox part: the clone's
-- GreyboxRef is stretched to the part's box and laid over it, every art part
-- following. The greybox part is hidden and stays the collision. Returns the
-- clone, which lives in the pass's art folder.
function ART.place(pass: string, kit: string, asset: string, part: BasePart, opts: PlaceOpts?): Model
	local o: PlaceOpts = opts or {}
	local source = showcaseAsset(kit, asset)
	local clone = source:Clone()
	local ref = clone.PrimaryPart
	assert(ref and ref.Name == "GreyboxRef", asset .. " has no GreyboxRef")

	local turn = (o.turn or 0) % 360
	assert(turn % 90 == 0, "turn must be a multiple of 90")
	local box = o.size or part.Size
	local boxCf = (o.at or part.CFrame) * CFrame.Angles(0, math.rad(turn), 0)
	if turn % 180 ~= 0 then
		box = Vector3.new(box.Z, box.Y, box.X)
	end
	local scale = box / ref.Size

	local from = ref.CFrame
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and d ~= ref then
			refit(d, from, boxCf, scale)
		elseif d:IsA("SurfaceGui") and d.Name == "TestGlyph" then
			d:Destroy()
		end
	end
	ref.Size = box
	ref.CFrame = boxCf

	clone.Name = o.name or (part.Name .. "__" .. asset)
	clone:SetAttribute(ATTR_FOR, part.Name)
	clone:SetAttribute(ATTR_STRETCH, stretchOf(scale))
	clone.Parent = ART.dressFolder(pass)
	if not o.keepVisible then
		ART.hide(pass, part)
	else
		claim(pass, part)
	end
	return clone
end

-- Turn a BreakableWall greybox part into the Body of breakable asset
-- `kit`/`asset`: the part takes the Body's material and colour, and clones of
-- the Body's Deco_/Seam_ children are stretched to the part and parented
-- under it. `flip` turns the decoration 180 degrees about the part's Y.
function ART.adopt(pass: string, kit: string, asset: string, wall: BasePart, flip: boolean?)
	local source = showcaseAsset(kit, asset)
	local body = source:FindFirstChild("Body")
	assert(body and body:IsA("BasePart"), asset .. " is not a breakable asset (no Body)")
	claim(pass, wall)
	wall.Material = body.Material
	wall.Color = body.Color

	local scale = wall.Size / body.Size
	local to = wall.CFrame * CFrame.Angles(0, if flip then math.pi else 0, 0)
	for _, child in body:GetChildren() do
		if child:IsA("BasePart") then
			local piece = child:Clone()
			refit(piece, body.CFrame, to, scale)
			piece:SetAttribute(ATTR_ADDED, pass)
			piece:SetAttribute(ATTR_STRETCH, stretchOf(scale))
			piece.Parent = wall
		end
	end
end

-- Put back everything `pass` did: its art folder goes, the Deco_/Seam_
-- children it added go, and every greybox part it claimed gets its original
-- colour, material and transparency back.
function ART.undress(pass: string)
	local root = workspace:FindFirstChild(ART.DRESS_ROOT_NAME)
	local folder = root and root:FindFirstChild(pass)
	if folder then
		folder:Destroy()
	end
	local scopes: { Instance } = { ART.island() }
	local ready = ART.readyRoom()
	if ready then
		table.insert(scopes, ready)
	end
	for _, scope in scopes do
		for _, d in scope:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute(ATTR_ADDED) == pass then
					d:Destroy()
				elseif d:GetAttribute(ATTR_PASS) == pass then
					d.Color = d:GetAttribute(ATTR_COLOR) :: Color3
					d.Material = (Enum.Material :: any)[d:GetAttribute(ATTR_MATERIAL) :: string]
					d.Transparency = d:GetAttribute(ATTR_TRANSPARENCY) :: number
					d:SetAttribute(ATTR_PASS, nil)
					d:SetAttribute(ATTR_COLOR, nil)
					d:SetAttribute(ATTR_MATERIAL, nil)
					d:SetAttribute(ATTR_TRANSPARENCY, nil)
				end
			end
		end
	end
end

-- Run a dress pass: one undo waypoint, undressed first, audited after.
-- Returns the audit text, so `return ART.dress(...)` reports from the file.
function ART.dress(pass: string, fn: (folder: Folder) -> ()): string
	ART.run(pass, function()
		ART.undress(pass)
		fn(ART.dressFolder(pass))
	end)
	return ART.audit(pass)
end

-- What a pass left behind, checked against the rules every art part obeys.
-- "problems: 0" is the done condition for a pass.
function ART.audit(pass: string): string
	local CollectionService = game:GetService("CollectionService")
	local problems = {}
	local artParts, models, adopted, hidden, skinned, deco = 0, 0, 0, 0, 0, 0
	local function note(text: string)
		if #problems < 40 then
			table.insert(problems, text)
		end
	end
	local function checkArt(d: BasePart)
		artParts += 1
		if not d.Anchored then
			note(d:GetFullName() .. " is not anchored")
		end
		if d.CanCollide or d.CanQuery or d.CanTouch then
			note(d:GetFullName() .. " collides, answers queries or touches")
		end
		if #CollectionService:GetTags(d) > 0 then
			note(d:GetFullName() .. " carries a tag")
		end
		if d:GetAttribute("ArenaId") ~= nil then
			note(d:GetFullName() .. " carries an ArenaId")
		end
	end
	local function checkStretch(inst: Instance)
		local text = inst:GetAttribute(ATTR_STRETCH)
		if type(text) ~= "string" then
			return
		end
		for number in text:gmatch("[%d%.]+") do
			local f = tonumber(number) :: number
			if f < ART.FIT_MIN or f > ART.FIT_MAX then
				note(string.format("%s is stretched (%s)", inst:GetFullName(), text))
				break
			end
		end
	end

	local root = workspace:FindFirstChild(ART.DRESS_ROOT_NAME)
	local folder = root and root:FindFirstChild(pass)
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				checkArt(d)
			elseif d:IsA("Model") then
				if d:GetAttribute(ATTR_FOR) ~= nil then
					models += 1
					checkStretch(d)
				end
			end
		end
	end
	local scopes: { Instance } = { ART.island() }
	local ready = ART.readyRoom()
	if ready then
		table.insert(scopes, ready)
	end
	for _, scope in scopes do
		for _, d in scope:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute(ATTR_ADDED) == pass then
					deco += 1
					checkArt(d)
					if not (d.Name:match("^Deco_%d+$") or d.Name:match("^Seam_%d+$")) then
						note(d:GetFullName() .. " is under a wall but not named Deco_<n> or Seam_<n>")
					end
				elseif d:GetAttribute(ATTR_PASS) == pass then
					if d.Transparency >= 1 then
						hidden += 1
					elseif CollectionService:HasTag(d, "BreakableWall") then
						adopted += 1
						local count = 0
						for _, child in d:GetChildren() do
							if child:IsA("BasePart") then
								count += 1
								if count == 1 then
									checkStretch(child)
								end
							end
						end
						if count > ART.MAX_WALL_CHILDREN then
							note(d.Name .. " has more than " .. ART.MAX_WALL_CHILDREN .. " art children")
						end
					else
						skinned += 1
					end
				end
			end
		end
	end
	return string.format(
		"%s: %d art parts in the folder (%d placed models), %d walls adopted with %d children, %d greybox hidden, %d skinned\nproblems: %d%s",
		pass,
		artParts,
		models,
		adopted,
		deco,
		hidden,
		skinned,
		#problems,
		if #problems > 0 then "\n  " .. table.concat(problems, "\n  ") else ""
	)
end

-- Greybox parts no pass has claimed yet and that a player can still see:
-- the lead's list of what is left to dress.
function ART.undressed(): string
	local counts: { [string]: number } = {}
	local scopes: { Instance } = { ART.island() }
	local ready = ART.readyRoom()
	if ready then
		table.insert(scopes, ready)
	end
	for _, scope in scopes do
		for _, d in scope:GetDescendants() do
			if
				d:IsA("BasePart")
				and d.Transparency < 1
				and d:GetAttribute(ATTR_PASS) == nil
				and d:GetAttribute(ATTR_ADDED) == nil
			then
				local key = (d.Name:gsub("_%d+$", ""))
				counts[key] = (counts[key] or 0) + 1
			end
		end
	end
	local lines = {}
	for key, count in counts do
		table.insert(lines, string.format("%s x%d", key, count))
	end
	table.sort(lines)
	return if #lines > 0 then table.concat(lines, "\n") else "nothing left"
end

return ART
