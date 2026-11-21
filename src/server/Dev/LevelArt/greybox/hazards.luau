-- Greybox pass: fall containment for the boss island (2026-11-21).
--
-- Unlike the dress passes this one makes GAMEPLAY parts: collision and kill
-- volumes inside Workspace.Arena.IslandReview and its ready room. Everything
-- it makes carries `GreyboxPass = "Greybox_Hazards"`, and a re-run deletes
-- those parts first, so the file is the source of the layout.
--
-- The rule it builds (user, 2026-11-21): a fall never ends in open sky. The
-- only ways past the ridge are the three exits, so each exit gets a pit:
--   Pit_Floor_<Exit>  a rock shelf under the exit, the visible bottom
--   Pit_Kill_<Exit>   a DeathZone lying on the shelf: the fall ends here
--   Fall_Collider     invisible walls round the exit's air space, joined to
--                     the ridge's own collider ring, so a jump, a dash or a
--                     knock-up cannot carry a player past the pit
-- The ready room gets Fall_Colliders over its rails, which a jump clears.
-- The island's big DeathZone stays below everything as the backstop.
--
-- Run: return require(game.ServerStorage.LevelArtRun:Clone())("greybox/hazards.luau")
-- then dress/hazards.luau for the art.
local CollectionService = game:GetService("CollectionService")

local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Greybox_Hazards"
local ATTR_PASS = "GreyboxPass"
local ATTR_EXIT = "Exit"

-- One pit per exit, in the exit's own frame: `bearing` is degrees clockwise
-- from east (the wiki's convention), r is studs from the island centre, and
-- left / right are studs along the tangent (toward a smaller / larger bearing).
-- The side walls stand at left / right, picked from the 2-stud survey map so
-- each one meets a run of the ridge collider and clears the return stair.
--   inner  how far under the island the shelf reaches (the island's rock is
--          about 20 studs inside the floor edge at shelf depth)
--   far    the far wall: 24 studs past the furthest ledge. The walls are
--          invisible but still stop a block-tap ray (a colliding part always
--          answers raycasts), so they stand well behind where a camera sits
local EXITS = {
	{ name = "Stones", bearing = 71, left = -30, right = 30, inner = 120, far = 232 },
	{ name = "Spit", bearing = 169.5, left = -32, right = 23, inner = 120, far = 230 },
	{ name = "Overhang", bearing = 289, left = -29, right = 27, inner = 120, far = 194 },
}

-- Heights are studs above the island's floor top.
local PIT_FLOOR_TOP = -40 -- a fall of 35 to 44 studs from the ledges: under a second, and in plain sight
local PIT_FLOOR_THICK = 4
local PIT_KILL_TOP = -30 -- the kill starts 10 above the shelf, at the height of the art's spike tips
local BOWL_TOP = -9 -- walls under the island stop here: below the floor and the ledges' undersides
local WALL_THICK = 2 -- the ridge colliders' own thickness
local RING_PROBE_HEIGHT = 30 -- where the ridge collider ring is looked for
local RING_PROBE_FROM = 100 -- the ring is nowhere inside this radius

-- Ready room: the rails are 5 studs high and a jump is about 7.
local READY_WALL_HEIGHT = 40 -- above the rail top

local GREY = Color3.fromRGB(86, 88, 96) -- the greybox look; dress/hazards.luau skins it

local V3 = Vector3.new

local function clear(scope: Instance)
	for _, d in scope:GetDescendants() do
		if d:GetAttribute(ATTR_PASS) == PASS then
			d:Destroy()
		end
	end
end

local function mark(part: BasePart, exit: string?)
	part:SetAttribute(ATTR_PASS, PASS)
	part:SetAttribute(ATTR_EXIT, exit)
end

local report = {}

ART.run(PASS, function()
	local island = ART.island()
	local center = ART.islandCenter()
	local ready = ART.readyRoom()
	clear(island)
	if ready then
		clear(ready)
	end

	-- Templates: a ridge collider and the island's kill volume. Cloning them
	-- carries every property, tag and attribute the game already relies on.
	local colliderTemplate: BasePart? = nil
	local ringParts = {}
	for _, d in island:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Ridge_Collider" then
			colliderTemplate = colliderTemplate or d
			table.insert(ringParts, d)
		end
	end
	assert(colliderTemplate, "no Ridge_Collider on the island")
	local killTemplate = island:FindFirstChild("DeathZone")
	assert(killTemplate and killTemplate:IsA("BasePart"), "no DeathZone on the island")
	assert(CollectionService:HasTag(killTemplate, "DeathZone"), "the island's DeathZone has lost its tag")
	local wallTop = colliderTemplate.Position.Y + colliderTemplate.Size.Y / 2 - center.Y

	local ringOnly = RaycastParams.new()
	ringOnly.FilterType = Enum.RaycastFilterType.Include
	ringOnly.FilterDescendantsInstances = ringParts

	for _, exit in EXITS do
		local theta = math.rad(exit.bearing)
		local radial = V3(math.cos(theta), 0, math.sin(theta))
		local tangent = V3(-math.sin(theta), 0, math.cos(theta))

		-- A box given in the exit's frame: r0..r1 along the radial, t0..t1
		-- along the tangent, y0..y1 above the floor.
		local function box(r0: number, r1: number, t0: number, t1: number, y0: number, y1: number): (CFrame, Vector3)
			local pos = center + radial * ((r0 + r1) / 2) + tangent * ((t0 + t1) / 2) + V3(0, (y0 + y1) / 2, 0)
			return CFrame.fromMatrix(pos, tangent, Vector3.yAxis), V3(t1 - t0, y1 - y0, r1 - r0)
		end

		local function wall(r0: number, r1: number, t0: number, t1: number, y0: number, y1: number)
			local part = colliderTemplate:Clone()
			part.Name = "Fall_Collider"
			part.CFrame, part.Size = box(r0, r1, t0, t1, y0, y1)
			mark(part, exit.name)
			part.Parent = island
		end

		-- Where the ridge collider ring crosses a side wall's line.
		local function ringAt(t: number): number
			local from = center + radial * RING_PROBE_FROM + tangent * t + V3(0, RING_PROBE_HEIGHT, 0)
			local hit = workspace:Raycast(from, radial * (exit.far - RING_PROBE_FROM), ringOnly)
			assert(
				hit,
				string.format("%s: the side wall at t=%d does not meet the ridge collider ring", exit.name, t)
			)
			return (hit.Position - from).Magnitude + RING_PROBE_FROM
		end

		local floorBottom = PIT_FLOOR_TOP - PIT_FLOOR_THICK
		local half = WALL_THICK / 2

		-- The shelf
		local floor = Instance.new("Part")
		floor.Name = "Pit_Floor_" .. exit.name
		floor.Anchored = true
		floor.Material = Enum.Material.Slate
		floor.Color = GREY
		floor.TopSurface = Enum.SurfaceType.Smooth
		floor.BottomSurface = Enum.SurfaceType.Smooth
		floor.CFrame, floor.Size = box(exit.inner, exit.far, exit.left, exit.right, floorBottom, PIT_FLOOR_TOP)
		floor:SetAttribute("ArenaId", killTemplate:GetAttribute("ArenaId"))
		mark(floor, exit.name)
		floor.Parent = island

		-- The kill volume on it
		local kill = killTemplate:Clone()
		kill.Name = "Pit_Kill_" .. exit.name
		kill.CFrame, kill.Size = box(exit.inner, exit.far, exit.left, exit.right, PIT_FLOOR_TOP, PIT_KILL_TOP)
		mark(kill, exit.name)
		kill.Parent = island

		-- Side walls: full height from the ridge collider out to the far wall,
		-- and a low stub under the island from there in to the shelf's inner edge.
		local ringRadii = {}
		for _, t in { exit.left, exit.right } do
			local ring = ringAt(t)
			table.insert(ringRadii, string.format("t=%d meets the ring at r=%.1f", t, ring))
			-- `ring` is the collider's inner face, so the wall starts inside the
			-- collider's own thickness and never stands in the playfield.
			wall(ring, exit.far, t - half, t + half, floorBottom, wallTop)
			wall(exit.inner, ring, t - half, t + half, floorBottom, BOWL_TOP)
		end
		-- Far wall, full height; inner wall under the island, low.
		wall(exit.far - half, exit.far + half, exit.left - half, exit.right + half, floorBottom, wallTop)
		wall(exit.inner - half, exit.inner + half, exit.left - half, exit.right + half, floorBottom, BOWL_TOP)

		table.insert(
			report,
			string.format(
				"%s: shelf %d x %d at %+d, kill top %+d, walls to %+.1f; %s",
				exit.name,
				exit.right - exit.left,
				exit.far - exit.inner,
				PIT_FLOOR_TOP,
				PIT_KILL_TOP,
				wallTop,
				table.concat(ringRadii, ", ")
			)
		)
	end

	-- Ready room: an invisible wall standing on each rail.
	if ready then
		local rails = 0
		for _, d in ready:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Rail" then
				local part = colliderTemplate:Clone()
				part.Name = "Fall_Collider"
				part.Size = V3(d.Size.X, READY_WALL_HEIGHT, d.Size.Z)
				part.CFrame = d.CFrame * CFrame.new(0, (d.Size.Y + READY_WALL_HEIGHT) / 2, 0)
				mark(part, "ReadyRoom")
				part.Parent = ready
				rails += 1
			end
		end
		table.insert(report, string.format("ReadyRoom: %d rails walled to +%d over the rail top", rails, READY_WALL_HEIGHT))
	else
		table.insert(report, "ReadyRoom: not found, nothing built")
	end
end)

return PASS .. "\n" .. table.concat(report, "\n")
