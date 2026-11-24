--!strict

----------------------------------------------------------------------
-- CosmeticLob — the *seen* lob: pods in flight and where they will land.
----------------------------------------------------------------------
-- Per landing, a small neon pod flies a parabolic arc from the origin to the
-- arrival point, and a ring marker on the ground fills up to the landing
-- radius exactly as the pod arrives (CosmeticRing), then both are removed.
-- The server only describes the lob (VfxBroadcast.lob); every client draws
-- it. Geometry and Parts only: this module requires neither the Skills nor
-- the Boss layer, like CosmeticProjectile beside it.
--
-- The pod's position is a pure function of server time,
-- `workspace:GetServerTimeNow()` (never os.clock, which differs per VM), so
-- it arrives exactly at `arriveAt` whatever the latency. A payload that
-- arrives late starts part-way along the arc; one that arrives after
-- `arriveAt` draws nothing.
--
-- This is gameplay information, so it is drawn with Reduced effects on too.
-- Only the Trail is dropped then.
--
-- Everything is client-local, CanCollide / CanQuery / CanTouch false (letter
-- block taps raycast into the world; nothing here may block a ray), and
-- cleans itself up.
----------------------------------------------------------------------

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CosmeticRing = require(ReplicatedStorage.Shared.Vfx.CosmeticRing)
local Settings = require(ReplicatedStorage.Shared.Settings)

local CosmeticLob = {}

local CosmeticLobConstants = {
	POD_DIAMETER_STUDS = 2,
	POD_NAME = "CosmeticLobPod",
	-- The apex sits this far above the straight line between the endpoints,
	-- plus a share of the horizontal distance, so a long throw is higher.
	-- Kept low on purpose: at 12 + 0.35 per stud the pods left the top of the
	-- third-person camera's frame for most of the flight (playtest 2026-11-20).
	APEX_MIN_STUDS = 6,
	APEX_PER_HORIZONTAL_STUD = 0.12,
	-- The arc is a parabola: height factor 4t(1-t) peaks at 1 at t = 0.5.
	PARABOLA_FACTOR = 4,
	TRAIL_WIDTH_STUDS = 1.6,
	TRAIL_LIFETIME_SEC = 0.45,
	TRAIL_LIGHT_EMISSION = 0.65,
	-- The glyph is a fixed on-screen size (offset, not scale) so it reads at
	-- 60+ studs.
	GLYPH_SIZE_PIXELS = 96,
	GLYPH_STUDS_OFFSET = Vector3.new(0, 2.4, 0),
	GLYPH_STROKE_TRANSPARENCY = 0,
	GLYPH_STROKE_COLOR = Color3.new(0, 0, 0),
	GLYPH_FONT = Enum.Font.GothamBlack,
	-- Leak guard on the Debris fallback, past the arrival.
	CLEANUP_GRACE_SEC = 1,
}
local K = CosmeticLobConstants

export type LobLanding = {
	-- Where the pod arrives (the block's hover position).
	arrival: Vector3,
	-- The ground point under it: the marker is centred here.
	ground: Vector3,
	glyph: string?,
	glyphColor: Color3?,
}

export type LobParams = {
	origin: Vector3,
	landings: { LobLanding },
	-- When the payload was sent, `workspace:GetServerTimeNow()` seconds.
	launchedAt: number,
	-- When the pods arrive, same clock.
	arriveAt: number,
	color: Color3,
	markerRadius: number,
}

local function isReducedVfx(): boolean
	local holder = Settings.localHolderIfAny()
	return holder ~= nil and Settings.read(holder, Settings.Keys.ReducedVfx) == true
end

local function buildPod(color: Color3, glyph: string?, glyphColor: Color3?, withTrail: boolean): Part
	local pod = Instance.new("Part")
	pod.Name = K.POD_NAME
	pod.Shape = Enum.PartType.Ball
	pod.Size = Vector3.one * K.POD_DIAMETER_STUDS
	pod.Material = Enum.Material.Neon
	pod.Color = color
	pod.Anchored = true
	pod.CanCollide = false
	pod.CanQuery = false
	pod.CanTouch = false
	pod.CastShadow = false

	if withTrail then
		local half = K.TRAIL_WIDTH_STUDS * 0.5
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, half, 0)
		top.Parent = pod
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -half, 0)
		bottom.Parent = pod

		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(color)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = K.TRAIL_LIFETIME_SEC
		trail.LightEmission = K.TRAIL_LIGHT_EMISSION
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.MinLength = 0
		trail.Parent = pod
	end

	if glyph ~= nil and glyph ~= "" then
		local gui = Instance.new("BillboardGui")
		gui.Adornee = pod
		-- Not AlwaysOnTop: with it set the glyph did not draw at all in the
		-- client view (playtest 2026-11-20, cause not found). A pod flies in
		-- open air, so depth-tested is fine.
		gui.AlwaysOnTop = false
		gui.Size = UDim2.fromOffset(K.GLYPH_SIZE_PIXELS, K.GLYPH_SIZE_PIXELS)
		gui.StudsOffset = K.GLYPH_STUDS_OFFSET
		gui.MaxDistance = math.huge
		gui.LightInfluence = 0
		gui.Parent = pod

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = glyph
		label.TextColor3 = glyphColor or color
		label.TextScaled = true
		label.Font = K.GLYPH_FONT
		label.TextStrokeTransparency = K.GLYPH_STROKE_TRANSPARENCY
		label.TextStrokeColor3 = K.GLYPH_STROKE_COLOR
		label.Parent = gui
	end
	return pod
end

-- Pod centre at flight fraction `t` (0 at the origin, 1 at the arrival).
local function arcPosition(origin: Vector3, arrival: Vector3, apexHeight: number, t: number): Vector3
	local straight = origin:Lerp(arrival, t)
	return straight + Vector3.yAxis * (apexHeight * K.PARABOLA_FACTOR * t * (1 - t))
end

-- Draw a lob. Returns immediately; everything cleans itself up. Draws nothing
-- when the arrival time has already passed.
function CosmeticLob.launch(params: LobParams)
	local duration = params.arriveAt - params.launchedAt
	if duration <= 0 or workspace:GetServerTimeNow() >= params.arriveAt then
		return
	end

	local withTrail = not isReducedVfx()
	local pods: { { pod: Part, origin: Vector3, arrival: Vector3, apex: number } } = {}
	local rings: { CosmeticRing.Ring } = {}
	-- A late payload starts part-way along the arc, so the pod is placed
	-- before it is parented (no frame at the world origin, no stray trail).
	local startT = math.clamp((workspace:GetServerTimeNow() - params.launchedAt) / duration, 0, 1)
	for _, landing in params.landings do
		local horizontal = Vector3.new(landing.arrival.X - params.origin.X, 0, landing.arrival.Z - params.origin.Z).Magnitude
		local apex = K.APEX_MIN_STUDS + horizontal * K.APEX_PER_HORIZONTAL_STUD
		local pod = buildPod(params.color, landing.glyph, landing.glyphColor, withTrail)
		pod.CFrame = CFrame.new(arcPosition(params.origin, landing.arrival, apex, startT))
		pod.Parent = workspace
		Debris:AddItem(pod, duration + K.CLEANUP_GRACE_SEC)
		table.insert(pods, { pod = pod, origin = params.origin, arrival = landing.arrival, apex = apex })

		local ring = CosmeticRing.new(landing.ground, {
			radius = params.markerRadius,
			color = params.color,
		})
		ring.setFill(startT)
		Debris:AddItem(ring.part, duration + K.CLEANUP_GRACE_SEC)
		table.insert(rings, ring)
	end

	local connection: RBXScriptConnection
	local function finish()
		connection:Disconnect()
		for _, entry in pods do
			entry.pod:Destroy()
		end
		for _, ring in rings do
			ring.destroy()
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now >= params.arriveAt then
			finish()
			return
		end
		local t = math.clamp((now - params.launchedAt) / duration, 0, 1)
		for _, entry in pods do
			entry.pod.CFrame = CFrame.new(arcPosition(entry.origin, entry.arrival, entry.apex, t))
		end
		for _, ring in rings do
			ring.setFill(t)
		end
	end)
end

return CosmeticLob
