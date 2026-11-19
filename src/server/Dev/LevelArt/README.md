# Level art kit (boss island)

Builders for the boss island's level art. The art is made of native Roblox
primitives and built-in materials only, and lives in the place file: the kit on a
showcase under `Workspace.LevelArtShowcase`, and the dressed level under
`Workspace.IslandReviewArt` plus the changes the dress passes make to the greybox
parts of `Workspace.Arena.IslandReview`. These files are the source: re-running a
file rebuilds what it made, so review feedback is a file edit, not hand work in
Studio.

Nothing here is game code and nothing in the game requires it.

## Files

| File | What it is |
|---|---|
| `prelude.luau` | Palette, primitive helper, asset and breakable wrappers, damage / glyph / test-letter helpers, signs |
| `stage.luau` | The showcase floor strips and title boards |
| `kits/rocks.luau` | Cover, cores, spires, gates, cave |
| `kits/terrain.luau` | Floor, ridge, ledges, island underside |
| `kits/setpieces.luau` | Dais, overlook, pads, ready room, dressing |
| `kits/poi_ruins.luau`, `kits/poi_nature.luau`, `kits/poi_monuments.luau` | Points of interest: landmark pieces, all in `Kit_POI` |
| `vignette.luau` | A slice of the island assembled from the kits |
| `dress/rocks.luau`, `dress/terrain.luau`, `dress/setpieces.luau` | The dress passes: each puts one kit on the real island |
| `dress/lead.luau` | The lead's pass: hides the greybox's working volumes. Run it last |
| `dress/lighting.luau` | Local lights on the island (dais, cave, rim crystals). Run after `dress/setpieces.luau`. The sky, sun and haze are game code, not here: `client/Arena/ArenaLighting` |

## Running a file

The folder sits under `src/server/Dev/` only so that Rojo carries the files into
Studio (`ServerScriptService.Server.Dev.LevelArt`). They are ModuleScripts nothing
requires, so they are inert in the game. Studio's assistant sandbox blocks localhost
HTTP, and a new Rojo project mapping needs a `rojo serve` restart, which is why they
are not in `tools/`.

1. Save the file and give Rojo a second or two to sync it.
2. Check Studio is in **Edit** mode (`get_studio_state`). Another session may be
   running a playtest; the Edit datamodel does not exist during Play. Wait and try
   again. Never stop someone else's playtest, and never call `screen_capture` with a
   camera position while Studio is in Play: it moves the playing client's camera.
   A positioned capture also leaves the editor camera `Scriptable`: when you are done,
   run `workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed` on the Edit
   datamodel.
3. Run a file with one `execute_luau` call on the Edit datamodel:
   `return require(game.ServerStorage.LevelArtRun:Clone())("kits/rocks.luau")`

`ServerStorage.LevelArtRun` copies `prelude` into `ServerStorage.LevelArtPrelude` and
runs the named file with `loadstring`, returning what the file returns or the error
with its line number. Both are install artefacts made through MCP, not by Rojo; never
edit them in Studio. If `LevelArtRun` is missing (a fresh place file), its source is
in § Loader at the end of this page. Every file starts with:

```lua
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
```

The `:Clone()` is required: Edit mode caches `require` results across calls
([studio-mcp](../../../../wiki/reference/studio-mcp.md)).

## Conventions

- **Palette roles only.** A part's material and colour come from `ART.PAL[role]`.
  `ART.shade(role, delta)` may move a role's brightness by up to 0.06 for variation.
  A kit never writes a `Color3.fromRGB`. A new role is added to the prelude by the
  lead, not in a kit.
- **Primitives only.** `Block`, `Ball`, `Cylinder`, `Wedge`, `CornerWedge` through
  `ART.prim`. No MeshPart, no unions, no uploaded textures or decals.
- **One asset = one Model** made with `ART.asset`, authored in the local space of the
  greybox box it stands for. The origin is the centre of that box's footprint at floor
  level. `GreyboxRef` is an invisible part of the box's exact size and the model's
  `PrimaryPart`, so the swap is `model:PivotTo(greyboxPart.CFrame)`.
- **Art does not collide.** `ART.prim` makes parts with `CanCollide`, `CanQuery` and
  `CanTouch` off. The greybox box stays the collision and raycast truth. Pass
  `collide = true` only where the rulings below say so.
- **No gameplay tags or attributes.** Art parts carry no CollectionService tag and no
  attribute the game reads (`ArenaId`, `MaxHealth`, `RegenSec`, `GateId`, …).
- **Deterministic.** Use `Random.new(<fixed seed>)`, never `math.random`, so a re-run
  gives the same rock.
- **Stay in your strip.** `ART.ROWS[<row>]` gives each kit its Z line and X range.
- **Leave the rest of the place alone.** No changes to the Lighting service (the arena's look is `ArenaLightingConstants`; local lights go in `dress/lighting.luau`), Terrain,
  `Workspace.Arena`, the lobby or any script.

## Points of interest

A POI is a landmark with no greybox box of its own: an arch, a tower, a fallen head.
It is made with `ART.poi` instead of `ART.asset`, lands in `Kit_POI` on the stage's
POI strip, and differs from a kit asset in three ways.

- **It brings its own collision.** The art still does not collide. Each POI carries 1
  to 8 invisible boxes named `Collide_<n>`, made with `ART.proxy`: the greybox a
  designer would have drawn. They are the only colliding parts in the showcase.
- **`footprint`** is the box the whole piece fits in (its `GreyboxRef`).
- **`placement`** says where it may stand, and is stored on the model as
  `PoiPlacement`: `rim` (on the ridge ring), `outside` (beyond the ring, on its own
  floating islet), `playfield` (inside the ring: nothing above +12, lanes and letter
  bands clear) or `hub` (lobby, ready room, another level: no arena rules).

Designer's rules for POIs (2026-11-19):

- **No tan.** `Letterstone*` means breakable cover. Ruins and monuments are cut
  `GateStone` with `Cliff` / `Bedrock`.
- **No readable letters**, no letter-like runes, no SurfaceGuis. Letters are gameplay.
- **Nothing hovers on the boss island** and no floating piece is cube-like: it would
  read as a letter block or the word ward.
- **No Light objects**, no glowing eyes, glow only as `GateSeam` strips or `Crystal`.
- **Proxies on `rim` and `outside` pieces**: no top a player could step onto from the
  ground (a step is about 7 studs) and no overhang to shelter under, because a perch
  the boss cannot path to is a safe spot. `hub` pieces may be walkable.

## Dressing the island

The kits make assets on the showcase; the dress passes put them on
`Workspace.Arena.IslandReview` and its ready room. Run a pass like any other file:
`return require(game.ServerStorage.LevelArtRun:Clone())("dress/rocks.luau")`. It
returns its audit. Run the kit a pass draws from first: a pass clones what is on the
showcase.

A pass never moves, resizes, renames, re-tags or deletes a greybox part. Through the
prelude it may do four things, each recorded on the part so the pass can be undone:

| Helper | What it does |
|---|---|
| `ART.place(pass, kit, asset, part, opts)` | Clones a showcase asset, stretches its `GreyboxRef` to the part's box and lays it over the part. The part is hidden and stays the collision. `opts.turn` (0 / 90 / 180 / 270) faces the asset; `opts.at` / `opts.size` give the box when it is not the part's own (a Cylinder on its side) |
| `ART.adopt(pass, kit, asset, wall, flip)` | For a `BreakableWall`: the greybox part takes the asset Body's material and colour and gets clones of its `Deco_` / `Seam_` children. The game client tints and fades those with the wall |
| `ART.skin(pass, part, role)` | Gives a greybox part a palette role and leaves it visible |
| `ART.hide(pass, part)` | Makes a greybox part invisible; it still collides and answers raycasts |

Bespoke art is built with `ART.prim` into `ART.dressFolder(pass)`, which is
`Workspace.IslandReviewArt.<pass>`: outside `Workspace.Arena`, so no arena scan walks
it.

- **Re-running a pass is safe.** `ART.dress(pass, fn)` undoes the pass first, runs it
  in one undo waypoint and returns `ART.audit(pass)`.
- **`ART.undress(pass)` puts the greybox back**: the pass's folder and the wall
  children it added go, and every part it claimed gets its original colour, material
  and transparency from the `ArtOrig*` attributes. Undress all four passes and the
  island is the greybox again.
- **One owner per part.** A part claimed by one pass (`ArtPass`) cannot be touched by
  another; the helper errors.
- **`problems: 0` in the audit is the done condition.** It checks that art is anchored,
  does not collide, answer queries or touch, carries no tag and no `ArenaId`, that wall
  children are named `Deco_<n>` / `Seam_<n>` and number at most 12, and that no fitted
  clone is stretched outside 0.6 to 1.6 on an axis.
- **`ART.undressed()`** lists the greybox parts that are still visible and unclaimed.
- Greybox names repeat (three `Cover_10`), so a pass works from `ART.greybox(prefix)`
  and part sizes, never from a name.

## Designer rulings (digest)

From the senior designer consultation of 2026-11-18. The full record, including which
rulings the user has not yet confirmed, is in
[boss-arena.md § Level art](../../../../wiki/design/boss-arena.md). Heights are studs above
the floor top.

**Safety.** No CollectionService tags and no `ArenaId` on anything in the showcase: a
part tagged `BreakableWall` without an `ArenaId` joins the shipped arena.

**Collision.** The greybox boxes stay the collision and raycast truth. Art is
anchored, `CanCollide`, `CanQuery` and `CanTouch` off (`ART.prim` does this).
`CanQuery` off matters: block taps raycast without `RespectCanCollide`.

**Envelope.** The visible shape stays within 1 stud of the greybox box on every side
that faces the playfield, and must not leave a collision face uncovered by more than
1 stud. Tops: +0.5 / -1 for low cover and cores; +-2 for tall cover, spires and ridge
masses.

**Breakables** use `ART.breakable`: a visible `Body` at the exact greybox size with up
to 12 direct children named `Deco_<n>` (tinted and faded with the body) or `Seam_<n>`
(glow, faded only). Children reach at most 1 stud outside the box and never cover the
glyph square: centred on the two broad faces, side 0.7 x min(face width, face height).

**Revised after the dressed island (2026-11-18).** Tall cover and spires: the 1-stud
envelope stands up to +12; above +12 decoration may reach 3 studs outside the box and
the top +3. Exit markers: up to +11 over the mass top, no part more than 3 studs in
front of the gate's boss-facing face or inside its central 14 studs. Ridge mass tops:
+-3. The arrival mark carries no neon and no reserved hue. The Grass material renders
mint green beside letter green: the floor is the `Soil` role, and `Turf` is not used on
anything a letter is read against.

**Colour.** Large surfaces S <= 25%, anything in the playfield S <= 35%, floor value
30-45%. Reserved, and absent from the palette: letter red, green, blue and wildcard
gold in both palettes, spore orange-red, the boss's orange and violet. Plum is the
dais only. Neon only on gate seams and dais runes, as strips at most 0.4 wide.
A player must tell apart at a glance: breakable (warm-grey, light, Sandstone/Rock),
core (cold, dark, Basalt), gate (cut stone, light in the seams), ridge (rough Slate),
floor (flat, dark).

**Silhouettes.**

| Class | Greybox | Keep |
|---|---|---|
| Low cover (breakable) | 10-22 W x 6.5-8 H x 8-11 D, sunk 1 | Top height, flat-ish climbable top, glyph faces |
| Tall cover (breakable) | 12.5 x 17.5 x 10.5, sunk 1 | Not climbable: no step under 7 studs on its sides |
| Spire (breakable) | 13-14 x 36-44 x 9-9.5, sunk 1 | Height +-2, not climbable, a cap of at most 3 |
| Core (permanent) | 14-22 x 6.5-8 x 10-11, sunk 1 | Same height and climbability as low cover |
| Ridge lip | top +3 to +6, 20-70 long, 6-9 thick | Top <= +6: open sky over about 45% of the rim |
| Ridge mass | top +12 to +25, 6-47 long, 6-11 thick | No climbable route over the top |
| Ridge gate (breakable, regenerates) | 4 x 18 x 19.4-21.1 | Flat boss-facing face; central 14 x 14 kept clear for three key letters |
| Cave plug (breakable, regenerates) | 17 x 14 x 3 | Flat face; central 10 x 10 kept clear for four key letters |
| Overhang slab (breakable floor) | 34 x 3 x 30, top -4 | Flat walkable top |
| Cave outcrop | 40 x 36 shell, roof +14 to +18, rocks to +30 | Chamber 32 x 28 x 14 inside, the mouth, the lane to the plug |
| Overlook shelf | 30 x 16 x 22 | No way back up: no step under 7 studs on its faces |
| Stones | cylinders 14 / 11 / 16 across, tops +4 / +1.5 / +3, 7-stud gaps | Gaps and tops within 0.3 |
| Spit | ramp 22 x 24.5, mid 15 x 22, tip 9 x 21; tops -2.5 / -5 / -5 | No railing; narrows to the tip |
| Dais | radius 22, flush | Radius exactly 22 (Ground Slam's reach) |

**Air space.** Nothing, colliding or not, in the letter bands (+18 to +28 over open
ground, +14 to +22 over the centre) or in the lanes from the boss point to each gate
and the cave plug. No trees, banners or crystals inside the ridge ring. Tall dressing
only on the outward faces of ridge masses (at most 3 above the mass top), on the
underside, and as floating rocks outside the ring.

**Floor.** The walkable collision stays flat. Inlays and trim raised at most 0.2;
tufts and pebbles at most 1.5 tall; none within 24 studs of the centre.

**Tells.** Gates and the plug say "sealed, but it opens": cut stone unlike the natural
ridge, light leaking through the seams, a clear carving face. The three exits are
each marked by one silhouette on the ridge mass beside the gate, never in the lane:
Spit a single leaning blade rock, Stones a cairn of three, Overhang a split boulder.
The cave reads from outside as a dark mouth with leaning jambs and a lintel.

## Loader

`ServerStorage.LevelArtRun` (a ModuleScript). Recreate it with `execute_luau` if the
place file loses it:

```lua
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function find(file)
	local node = ServerScriptService:FindFirstChild("Server")
	node = node and node:FindFirstChild("Dev")
	node = node and node:FindFirstChild("LevelArt")
	if not node then
		error("LevelArtRun: Server.Dev.LevelArt is missing (is Rojo connected?)", 0)
	end
	for _, name in string.split((file:gsub("%.luau$", "")), "/") do
		node = node:FindFirstChild(name)
		if not node then
			error("LevelArtRun: " .. file .. " is not in Server.Dev.LevelArt (not synced yet?)", 0)
		end
	end
	return node
end

return function(file)
	local prelude = ServerStorage:FindFirstChild("LevelArtPrelude")
	if not prelude then
		prelude = Instance.new("ModuleScript")
		prelude.Name = "LevelArtPrelude"
		prelude.Parent = ServerStorage
	end
	local preludeSource = find("prelude.luau").Source
	if prelude.Source ~= preludeSource then
		prelude.Source = preludeSource
	end
	local chunk, syntaxError = loadstring(find(file).Source, file)
	if not chunk then
		error("LevelArtRun: " .. tostring(syntaxError), 0)
	end
	local ok, result = xpcall(chunk, function(message)
		return tostring(message) .. "
" .. debug.traceback()
	end)
	if not ok then
		error("LevelArtRun: " .. file .. " failed: " .. tostring(result), 0)
	end
	return result
end
```
