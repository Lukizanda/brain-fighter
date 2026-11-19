-- Points of interest: natural wonders. A wind-cut arch on a floating islet, a
-- split geode boulder and a petrified tree, all in the same slate / basalt as the
-- ridge masses.
-- Run: return require(game.ServerStorage.LevelArtRun:Clone())("kits/poi_nature.luau")

local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
local row = ART.ROWS.POI

local function rad(d: number): number
	return math.rad(d)
end

-- A rock slab at a local position with yaw / roll / pitch in degrees. Colour is
-- nudged a few points around its role so stacked strata read as layers.
local function slab(model: Model, origin: CFrame, rng: Random, role: string, pos: Vector3, size: Vector3, yaw: number?, roll: number?, pitch: number?, shape: string?): BasePart
	return ART.prim(model, {
		role = role,
		shape = shape,
		size = size,
		cf = origin * CFrame.new(pos) * CFrame.Angles(rad(pitch or 0), rad(yaw or 0), rad(roll or 0)),
		color = ART.shade(role, rng:NextNumber(-0.03, 0.03)),
	})
end

-- A thin cap standing 0.2 proud of the upper face of `base`, offset along the
-- base's own X / Z. It takes the base's tilt, so it stays parallel to it.
local function cap(model: Model, rng: Random, role: string, base: BasePart, ox: number, oz: number, sx: number, sy: number, sz: number): BasePart
	return ART.prim(model, {
		role = role,
		size = Vector3.new(sx, sy, sz),
		cf = base.CFrame * CFrame.new(ox, base.Size.Y / 2 - sy / 2 + 0.2, oz),
		color = ART.shade(role, rng:NextNumber(-0.02, 0.02)),
	})
end

local function wedge(model: Model, origin: CFrame, rng: Random, role: string, pos: Vector3, w: number, h: number, run: number, dir: Vector3, roll: number?, hang: boolean?): BasePart
	return ART.wedge(model, {
		role = role,
		width = w,
		height = h,
		run = run,
		center = origin:PointToWorldSpace(pos),
		highToward = origin:VectorToWorldSpace(dir),
		roll = roll,
		hang = hang,
		color = ART.shade(role, rng:NextNumber(-0.03, 0.03)),
	})
end

ART.run("LevelArt: POI nature", function()
	-- 1. Natural arch ---------------------------------------------------------
	ART.poi({
		name = "POI_NaturalArch",
		at = Vector3.new(392, ART.FLOOR_Y, row.z),
		footprint = Vector3.new(30, 34, 14),
		placement = "outside",
		note = "floating islet arch, raised 14 so the tapered underside shows",
		build = function(model, groundOrigin)
			local rng = Random.new(4101)
			local LIFT = 14 -- the islet's top sits this high; its point hangs beneath
			local TILT = 5 -- strata tilt, the same on every slab and band
			local LEAN_IN = 7 -- the thin leg leans toward the opening
			local origin = groundOrigin * CFrame.new(0, LIFT, 0)
			-- floating rock platform: Turf-capped top, tiers, then hanging wedges to a point
			local top = slab(model, groundOrigin, rng, "Cliff", Vector3.new(0, 12.8, 0), Vector3.new(29, 2.4, 13.2), 3)
			slab(model, groundOrigin, rng, "CliffDark", Vector3.new(0.5, 9.8, 0), Vector3.new(21, 3.8, 10.4), -6)
			slab(model, groundOrigin, rng, "CliffDark", Vector3.new(-0.5, 6.4, 0), Vector3.new(12.5, 3.6, 7.6), 9)
			wedge(model, groundOrigin, rng, "Bedrock", Vector3.new(-3.6, 3.2, 0), 7.2, 6.6, 7.4, Vector3.new(-1, 0, 0), nil, true)
			wedge(model, groundOrigin, rng, "Bedrock", Vector3.new(3.6, 3.2, 0.4), 6.8, 6.6, 7.4, Vector3.new(1, 0, 0), nil, true)
			wedge(model, groundOrigin, rng, "CliffDark", Vector3.new(0.4, 3.4, -3.0), 6.4, 6.0, 5.6, Vector3.new(0, 0, -1), nil, true)
			wedge(model, groundOrigin, rng, "CliffDark", Vector3.new(-0.4, 3.4, 3.0), 6.4, 6.0, 5.6, Vector3.new(0, 0, 1), nil, true)
			cap(model, rng, "Turf", top, -9, -2.5, 4.4, 0.3, 3.4)
			cap(model, rng, "Turf", top, 4, 3.4, 3.6, 0.3, 3.0)
			cap(model, rng, "Turf", top, 11, -3.2, 2.6, 0.3, 2.4)
			ART.proxy(model, groundOrigin, Vector3.new(0, 9.5, 0), Vector3.new(27, 9, 12))

			-- thick leg (left, about 9 wide): leans out as it rises
			slab(model, origin, rng, "CliffDark", Vector3.new(-9.4, 2.3, 0), Vector3.new(9.8, 4.6, 9.0), 2, TILT)
			slab(model, origin, rng, "Cliff", Vector3.new(-9.9, 6.8, 0.1), Vector3.new(9.4, 4.4, 8.6), -3, TILT)
			slab(model, origin, rng, "Cliff", Vector3.new(-10.4, 11.0, 0), Vector3.new(9.0, 4.4, 8.2), 2, TILT)
			-- thin leg (right, about 4.5 wide): leans in toward the opening
			slab(model, origin, rng, "CliffDark", Vector3.new(12.2, 2.0, 0), Vector3.new(5.2, 4.0, 6.2), -2, LEAN_IN)
			slab(model, origin, rng, "Cliff", Vector3.new(11.7, 5.9, 0), Vector3.new(4.6, 3.8, 5.6), 3, LEAN_IN)
			slab(model, origin, rng, "Cliff", Vector3.new(11.2, 9.7, 0), Vector3.new(4.2, 4.4, 5.0), -2, LEAN_IN)
			-- span: four overlapping slabs, stepping down and thinning toward the thin leg
			slab(model, origin, rng, "CliffLight", Vector3.new(-9.0, 15.1, 0), Vector3.new(11.6, 7.4, 8.4), 1, TILT)
			slab(model, origin, rng, "Cliff", Vector3.new(-1.8, 13.7, 0), Vector3.new(8.4, 5.4, 7.6), -2, TILT)
			slab(model, origin, rng, "Cliff", Vector3.new(4.8, 13.2, 0), Vector3.new(7.0, 4.2, 6.6), 2, TILT)
			slab(model, origin, rng, "CliffLight", Vector3.new(10.6, 12.9, 0), Vector3.new(7.8, 3.0, 5.4), -2, TILT)
			-- upper corners of the opening filled by hanging wedges: a flattened curve
			wedge(model, origin, rng, "Cliff", Vector3.new(-3.2, 9.0, 0), 6.4, 4.2, 4.6, Vector3.new(-1, 0, 0), nil, true)
			wedge(model, origin, rng, "Cliff", Vector3.new(7.5, 9.1, 0), 5.6, 4.0, 4.2, Vector3.new(1, 0, 0), nil, true)
			-- feet flare toward the opening
			wedge(model, origin, rng, "CliffDark", Vector3.new(-3.1, 2.2, 0), 7.0, 4.4, 3.6, Vector3.new(-1, 0, 0))
			wedge(model, origin, rng, "CliffDark", Vector3.new(8.5, 2.0, 0), 5.0, 4.0, 3.4, Vector3.new(1, 0, 0))
			-- broken skyline on the span
			wedge(model, origin, rng, "CliffLight", Vector3.new(-12.6, 19.3, 0.2), 6.0, 1.6, 4.4, Vector3.new(1, 0, 0))
			wedge(model, origin, rng, "CliffLight", Vector3.new(-2.0, 17.2, 0), 5.0, 1.6, 3.6, Vector3.new(-1, 0, 0))
			-- thin pale strata bands through legs and span, same tilt
			slab(model, origin, rng, "CliffLight", Vector3.new(-10.1, 9.2, 0), Vector3.new(9.9, 0.7, 8.9), -1, TILT)
			slab(model, origin, rng, "CliffLight", Vector3.new(-9.0, 15.0, 0), Vector3.new(11.9, 0.7, 8.7), 1, TILT)
			slab(model, origin, rng, "CliffLight", Vector3.new(11.5, 7.8, 0), Vector3.new(4.5, 0.7, 5.5), -2, TILT)
			-- scree at the thick leg
			slab(model, origin, rng, "CliffDark", Vector3.new(-12.4, 1.1, -4.6), Vector3.new(3.4, 2.6, 3.0), 30, 8, 6)
			-- collision: legs and span, opening left open
			ART.proxy(model, origin, Vector3.new(-9.7, 6.6, 0), Vector3.new(9.6, 13.2, 8.4))
			ART.proxy(model, origin, Vector3.new(11.8, 6, 0), Vector3.new(4.6, 12, 5.6))
			ART.proxy(model, origin, Vector3.new(0.3, 15, 0), Vector3.new(29, 8, 7.6))
		end,
	})

	-- 2. Geode boulder --------------------------------------------------------
	ART.poi({
		name = "POI_GeodeBoulder",
		at = Vector3.new(432, ART.FLOOR_Y, row.z),
		footprint = Vector3.new(20, 16, 16),
		placement = "rim",
		note = "boulder split in two, crystal growing into the cleft",
		build = function(model, origin)
			local rng = Random.new(4202)
			local HALF_GAP = 1.7 -- half the gap at the foot (3.4); the cleft opens to about 6 at the top
			local TILT = 6.5 -- degrees each half leans away from the cleft
			-- shards in half-local space (x outward from the split plane):
			-- y on the plane, z along it, length, thickness, lean upward in degrees, kind
			local shards = {
				{ 2.6, 0.3, 4.6, 1.5, 58, "block" },
				{ 4.8, -2.4, 3.6, 1.1, 40, "wedge" },
				{ 3.4, 2.8, 3.0, 1.0, 25, "block" },
				{ 6.4, 0.8, 2.6, 0.9, 20, "wedge" },
				{ 1.2, -3.2, 2.2, 0.9, 12, "wedge" },
			}
			for _, side in { -1, 1 } do
				local halfCf = origin * CFrame.new(side * HALF_GAP, 0, 0) * CFrame.Angles(0, rad(-side * 3), rad(-side * TILT))
				-- half-local: x outward from the split plane, mirrored by `side`
				local function at(x: number, y: number, z: number): Vector3
					return Vector3.new(side * x, y, z)
				end
				local function ball(role: string, x: number, y: number, z: number, size: Vector3)
					return ART.prim(model, {
						role = role,
						shape = "Ball",
						size = size,
						cf = halfCf * CFrame.new(at(x, y, z)),
						color = ART.shade(role, rng:NextNumber(-0.03, 0.03)),
					})
				end
				-- one big round mass per half, its lower third buried; its inner bulge stops
				-- 0.3 behind the split plane, so the flat dark slab stands 0.3 proud of it
				ball("Bedrock", 4.7, 3.4, 0, Vector3.new(8.6, 8.6, 8.6))
				ball("BedrockLight", 5.0, 2.6, -4.3, Vector3.new(6.6, 6.6, 6.6))
				ART.prim(model, {
					role = "CliffDark",
					size = Vector3.new(1.0, 9.0, 9.0),
					cf = halfCf * CFrame.new(at(0.5, 4.0, 0)),
					color = ART.shade("CliffDark", rng:NextNumber(-0.02, 0.02)),
				})
				-- a crown wedge breaks the roundness, rising toward the cleft
				ART.wedge(model, {
					role = "BedrockLight",
					width = 6.0,
					height = 3.4,
					run = 4.4,
					center = halfCf:PointToWorldSpace(at(4.2, 7.6, 0.5)),
					highToward = halfCf:VectorToWorldSpace(Vector3.new(-side, 0, 0)),
					color = ART.shade("BedrockLight", -0.02),
				})

				-- crystal shards: base buried 0.5 into the split plane, tip toward the cleft
				for index, c in shards do
					local y, z, len, thick, lean, kind = c[1], c[2] * side, c[3] * 1.2, c[4] * 1.25, c[5], c[6]
					local base = halfCf * CFrame.new(side * 0.5, y, z) * CFrame.Angles(0, 0, rad(-side * lean))
					local part: BasePart
					if kind == "block" then
						part = ART.prim(model, {
							role = "Crystal",
							size = Vector3.new(len, thick, thick * 0.9),
							cf = base * CFrame.new(-side * len / 2, 0, 0) * CFrame.Angles(rad(rng:NextNumber(-20, 20)), 0, 0),
						})
					else
						part = ART.prim(model, {
							role = "Crystal",
							shape = "Wedge",
							size = Vector3.new(thick, thick * 1.4, len),
							cf = base
								* CFrame.new(-side * len / 2, 0, 0)
								* CFrame.lookAt(Vector3.zero, Vector3.new(-side, 0, 0))
								* CFrame.Angles(0, 0, rad(rng:NextNumber(-25, 25))),
						})
					end
					part.Transparency = 0.15 + 0.05 * (index % 4)
					part.Name = "Crystal_" .. index
				end
				ART.proxy(model, origin, Vector3.new(side * 5.6, 5, 0), Vector3.new(7.4, 10, 9.4))
			end
		end,
	})

	-- 3. Petrified tree -------------------------------------------------------
	ART.poi({
		name = "POI_PetrifiedTree",
		at = Vector3.new(470, ART.FLOOR_Y, row.z),
		footprint = Vector3.new(18, 26, 18),
		placement = "outside",
		note = "dead tree turned to stone, forked boughs",
		build = function(model, origin)
			local rng = Random.new(4303)
			-- low rough rock mound: a dome and two tumbled rocks
			local dome = slab(model, origin, rng, "CliffDark", Vector3.new(0, 0.6, 0), Vector3.new(15, 5.0, 14), 0, 0, 0, "Ball")
			slab(model, origin, rng, "Cliff", Vector3.new(4.8, 0.9, -4.2), Vector3.new(4.4, 2.8, 3.8), 35, 6, 8)
			slab(model, origin, rng, "CliffDark", Vector3.new(-5.2, 0.8, 3.8), Vector3.new(3.8, 2.4, 3.6), -25, -7, 6)
			cap(model, rng, "Turf", dome, 2.2, 1.6, 2.6, 0.3, 2.2)
			cap(model, rng, "Turf", dome, -3.6, -1.4, 2.0, 0.3, 1.8)
			-- roots flaring 4 to 5 studs out
			for index, az in { 20, 95, 165, 235, 310 } do
				local a = rad(az)
				local radial = Vector3.new(math.cos(a), 0, math.sin(a))
				wedge(model, origin, rng, "Bedrock", radial * 5.1 + Vector3.new(0, 2.0, 0), 4.2, 3.8 + 0.5 * (index % 3), 5.0, -radial)
			end
			-- trunk: three kinked segments, 5 wide at the foot to 3 at the fork
			local trunk = {
				{ w = 5.5, h = 4.2, kink = Vector3.new(3, 5, -5), role = "Bedrock" },
				{ w = 4.5, h = 4.0, kink = Vector3.new(-4, -8, 4), role = "BedrockLight" },
				{ w = 3.5, h = 3.8, kink = Vector3.zero, role = "Bedrock" },
			}
			local frames = {}
			local f = origin * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, rad(15), 0)
			local topSeg
			for index, seg in trunk do
				frames[index] = f
				topSeg = slab(model, origin, rng, seg.role, Vector3.zero, Vector3.new(seg.w, seg.h, seg.w * 0.92))
				topSeg.CFrame = f * CFrame.new(0, seg.h / 2, 0)
				f = f * CFrame.new(0, seg.h - 0.4, 0) * CFrame.Angles(rad(seg.kink.X), rad(seg.kink.Y), rad(seg.kink.Z))
			end
			cap(model, rng, "CliffLight", topSeg, 0, 0, 3.0, 0.5, 2.8)

			-- one limb: yaw about the parent, tilt (degrees, + leans outward), then
			-- its own length. Returns the part and the frame at its blunt end.
			local function limb(parent: CFrame, w: number, h: number, yaw: number, tilt: number, role: string): (BasePart, CFrame)
				local lf = parent * CFrame.Angles(0, rad(yaw), 0) * CFrame.Angles(0, 0, rad(-tilt))
				local part = slab(model, origin, rng, role, Vector3.zero, Vector3.new(w, h, w * 0.85))
				part.CFrame = lf * CFrame.new(0, h / 2, 0)
				return part, lf * CFrame.new(0, h - 0.35, 0)
			end
			local function attach(seg: number, t: number, az: number): CFrame
				return frames[seg] * CFrame.new(0, t * trunk[seg].h, 0) * CFrame.Angles(0, rad(az), 0) * CFrame.new(trunk[seg].w * 0.3, 0, 0)
			end
			local function tip(part: BasePart, w: number)
				cap(model, rng, "CliffLight", part, 0, 0, w * 0.85, 0.5, w * 0.75)
			end

			-- dominant bough A, low on the fork and reaching sideways, forks again
			local aBase = attach(3, 0.3, 0)
			local a1, aEnd = limb(aBase, 3.0, 5.0, 0, 62, "BedrockLight")
			local a2 = limb(aEnd, 2.2, 4.2, 8, -32, "Bedrock")
			local a3 = limb(aEnd, 2.0, 2.8, -12, 16, "BedrockLight")
			tip(a2, 2.2)
			tip(a3, 2.0)
			wedge(model, origin, rng, "Bedrock", origin:PointToObjectSpace(aBase:PointToWorldSpace(Vector3.new(0.4, -1.6, 0))), 3.6, 2.8, 3.6, Vector3.new(-1, 0, 0), nil, true)
			-- bough B, from the top of the trunk and taller, forks into two
			local bBase = attach(3, 1.0, 180)
			local b1, bEnd = limb(bBase, 2.8, 5.6, 0, 16, "BedrockLight")
			local b2 = limb(bEnd, 2.2, 5.8, -15, -10, "Bedrock")
			local b3 = limb(bEnd, 2.0, 4.2, 30, 28, "BedrockLight")
			tip(b2, 2.2)
			tip(b3, 2.0)
			-- broken stub low on the trunk
			local stub = limb(attach(2, 0.5, 120), 2.4, 3.4, 0, 70, "Bedrock")
			tip(stub, 2.4)
			ART.proxy(model, origin, Vector3.new(0, 7.5, 0), Vector3.new(4.8, 15, 4.8))
			ART.proxy(model, origin, Vector3.new(0, 1.5, 0), Vector3.new(13, 3, 12))
		end,
	})
end)

return ART.report("Kit_POI")
