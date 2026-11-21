-- Containment check for the fall pits (greybox/hazards.luau). Read-only.
--
-- From every standable spot above each pit it throws a body in twelve
-- directions four ways (walk off, jump, jump with a dash, a hard knock-up)
-- and follows it: a sphere swept through the island's collision. Each throw
-- must end on something solid or inside a pit's kill volume. "ESCAPE" means
-- a body got below the pit without dying: a hole in the walls.
--
-- Run in Edit: return require(game.ServerStorage.LevelArtRun:Clone())("greybox/hazards_check.luau")
-- Done condition: ESCAPE = 0 on every pit. A few TIMEOUTs are bodies the
-- simple slide rule leaves stuck on a slope inside the ring; they are listed
-- with their end height so a real one (below the floor) would show.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local V3 = Vector3.new

-- The body: the game's own numbers (StarterPlayer and GameConfig.DASH_*).
local WALK_SPEED = 16
local JUMP_HEIGHT = 7.2
local DASH_SPEED = 60
local DASH_SEC = 0.2
local KNOCK_SIDE = 50 -- a knock-up harder than anything the boss does today
local KNOCK_UP = 90
local BODY_RADIUS = 1.2
local BODY_LIFT = 3 -- the body's centre above the surface it stands on

local GRID = 3 -- studs between start points
local RING_INSET = 126 -- start points begin this far from the centre: inside the ridge ring
local EDGE_INSET = 2 -- and stop this far inside the pit's walls
local PROBE_ABOVE = 60 -- start points are found by a ray from this high
local PROBE_DEPTH = 75
local STAND_MAX = 12 -- surfaces higher than this over the floor are not ledges
local STAND_NORMAL = 0.7 -- flatter than this counts as ground
local DIRECTIONS = 12
local STEP = 1 / 60
local MAX_SEC = 6
local BACK_OFF = 0.05 -- stop this short of a hit, so the next sweep does not start inside it
local BELOW_PIT = -46 -- under the shelf: nothing alive should get here
local KILL_SLACK = 1 -- the body's centre may sit this far above a kill volume and count
local MAX_LISTED = 12
local PACE_EVERY = 4 -- start points per yield

local island = ART.island()
local center = ART.islandCenter()
local gravity = workspace.Gravity
local jumpSpeed = math.sqrt(2 * gravity * JUMP_HEIGHT)

local solid = RaycastParams.new()
solid.FilterType = Enum.RaycastFilterType.Include
solid.FilterDescendantsInstances = { island }
solid.RespectCanCollide = true
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { island }
overlap.RespectCanCollide = true

local kills = ART.greybox("Pit_Kill")
local shelves = ART.greybox("Pit_Floor")
assert(#shelves > 0, "no Pit_Floor on the island: run greybox/hazards.luau first")

local function inKill(pos: Vector3): boolean
	for _, kill in kills do
		local l = kill.CFrame:PointToObjectSpace(pos)
		if
			math.abs(l.X) <= kill.Size.X / 2
			and math.abs(l.Y) <= kill.Size.Y / 2 + KILL_SLACK
			and math.abs(l.Z) <= kill.Size.Z / 2
		then
			return true
		end
	end
	return false
end

local function throw(start: Vector3, velocity: Vector3, dash: Vector3?): (string, Vector3)
	local pos = start + V3(0, BODY_LIFT, 0)
	if #workspace:GetPartBoundsInRadius(pos, BODY_RADIUS, overlap) > 0 then
		return "blocked start", pos
	end
	local t = 0
	while t < MAX_SEC do
		local v = velocity
		if dash and t < DASH_SEC then
			v = V3(dash.X * DASH_SPEED, velocity.Y, dash.Z * DASH_SPEED)
		end
		local step = v * STEP
		local hit = if step.Magnitude > 0 then workspace:Spherecast(pos, BODY_RADIUS, step, solid) else nil
		if hit then
			pos += step.Unit * math.max(hit.Distance - BACK_OFF, 0)
			if hit.Normal.Y > STAND_NORMAL then
				return "landed", pos
			end
			-- a wall: lose the speed into it and slide
			local into = velocity:Dot(hit.Normal)
			if into < 0 then
				velocity -= hit.Normal * into
			end
			if dash then
				local dashInto = dash:Dot(hit.Normal)
				if dashInto < 0 then
					dash -= hit.Normal * dashInto
				end
			end
		else
			pos += step
		end
		velocity -= V3(0, gravity * STEP, 0)
		if inKill(pos) then
			return "kill", pos
		end
		if pos.Y - center.Y < BELOW_PIT then
			return "ESCAPE", pos
		end
		t += STEP
	end
	return "TIMEOUT", pos
end

local lines = {}
local listed = {}
for _, shelf in shelves do
	-- The shelf's own frame: X across, Z along the radial.
	local halfX = shelf.Size.X / 2 - EDGE_INSET
	local halfZ = shelf.Size.Z / 2 - EDGE_INSET
	local starts = {}
	local x = -halfX
	while x <= halfX do
		local z = -halfZ
		while z <= halfZ do
			local world = shelf.CFrame:PointToWorldSpace(V3(x, 0, z))
			local flat = V3(world.X - center.X, 0, world.Z - center.Z)
			if flat.Magnitude >= RING_INSET then
				local from = V3(world.X, center.Y + PROBE_ABOVE, world.Z)
				local hit = workspace:Raycast(from, V3(0, -PROBE_DEPTH, 0), solid)
				if
					hit
					and hit.Instance.Name ~= "Ridge_Collider"
					and hit.Instance.Name ~= "Fall_Collider"
					and hit.Normal.Y > STAND_NORMAL
					and hit.Position.Y - center.Y < STAND_MAX
				then
					table.insert(starts, hit.Position)
				end
			end
			z += GRID
		end
		x += GRID
	end

	local tally = {}
	for i, start in starts do
		for d = 0, DIRECTIONS - 1 do
			local angle = d / DIRECTIONS * math.pi * 2
			local dir = V3(math.cos(angle), 0, math.sin(angle))
			local throws = {
				{ "walk", dir * WALK_SPEED, nil },
				{ "jump", dir * WALK_SPEED + V3(0, jumpSpeed, 0), nil },
				{ "dash", dir * WALK_SPEED + V3(0, jumpSpeed, 0), dir },
				{ "knock", dir * KNOCK_SIDE + V3(0, KNOCK_UP, 0), nil },
			}
			for _, case in throws do
				local result, at = throw(start, case[2], case[3])
				tally[result] = (tally[result] or 0) + 1
				if (result == "ESCAPE" or result == "TIMEOUT") and #listed < MAX_LISTED then
					table.insert(
						listed,
						string.format(
							"  %s %s %s from (%.0f, %+.1f, %.0f), ended at (%.0f, %+.1f, %.0f)",
							shelf.Name,
							result,
							case[1],
							start.X,
							start.Y - center.Y,
							start.Z,
							at.X,
							at.Y - center.Y,
							at.Z
						)
					)
				end
			end
		end
		if i % PACE_EVERY == 0 then
			task.wait()
		end
	end
	local parts = {}
	for result, count in tally do
		table.insert(parts, result .. "=" .. count)
	end
	table.sort(parts)
	table.insert(
		lines,
		string.format("%s: %d start points, ESCAPE=%d; %s", shelf.Name, #starts, tally.ESCAPE or 0, table.concat(parts, " "))
	)
end

return table.concat(lines, "\n") .. (if #listed > 0 then "\n" .. table.concat(listed, "\n") else "")
