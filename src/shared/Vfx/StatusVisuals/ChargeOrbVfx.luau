--!strict

----------------------------------------------------------------------
-- ChargeOrbVfx — the orb over a player winding up a held cast.
----------------------------------------------------------------------
-- Same lane as ShieldVfx: welded geometry that lives for as long as a
-- status is active, driven by a character attribute, rather than a
-- fire-and-forget particle burst. Copied from that file's shape on
-- purpose — `start` / `setTier` / `release` / `stop` against an
-- `_active[Model]` table is the one persistent-visual pattern this
-- codebase has, and a second shape would be a second set of leak bugs.
--
-- **Why this cannot be a VfxConfig.EFFECTS entry played through
-- spawnEffect.** spawnEffect returns nothing, hands every instance it
-- makes to Debris with a duration fixed at author time, and its only
-- sustained branch is a `task.delay` that flips `Enabled = false`. A
-- charge has no author-time duration — it ends when the player lets go —
-- and it has to be *grown* while it runs. There is no handle to do either
-- with. The mote halo's *look* still lives in VfxConfig
-- (`charge_motes_<colour>`); only its lifetime is owned here.
--
-- Three layers:
--   orb    a neon Ball welded above the Head, growing with tier
--   motes  Parts spawned on a ring around the caster that curve inward
--          into the orb, plus the sustained particle halo on the orb
--          itself. The convergence math is lifted from collectStream —
--          the only difference is that the destination is the orb rather
--          than a player's torso, and the source is a ring rather than a
--          popped block.
--   name   a BillboardGui over the orb naming the spell this charge would
--          fire right now. It pops in on every tier crossing and
--          dissipates on release. This is where the spell name went when
--          the HUD panels became circles and it no longer fitted on one;
--          putting it here rather than back on the HUD means it lands
--          where the player is already looking mid-charge, and that an
--          opponent reads it too — `setTier` resolves the name from the
--          entry's own colour, so the remote path gets it with no extra
--          wiring.
--
-- CLIENT ONLY, like every other module in this folder: the orb's particle
-- halo and the mote flight are both things the server can create but
-- nobody can see correctly. See CLAUDE.md § Player-Facing Output.
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Logger        = require(ReplicatedStorage.Shared.Core.Logger)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local VfxConfig     = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("ChargeOrbVfx")

-- Same bounded wait spawnEffect uses. FindFirstChild would race: this
-- module is required from HUD code that runs on the first frames of a
-- session, before the Studio-side templates folder has necessarily
-- replicated, and a nil here costs the halo silently.
local VfxTemplates: Instance? = ReplicatedStorage:WaitForChild("VfxTemplates", 10)

----------------------------------------------------------------------
-- Orb geometry
----------------------------------------------------------------------

-- Height above the Head's centre. High enough to clear an R15 hat and to
-- be visible over cover, low enough that it still reads as belonging to
-- the player rather than floating independently.
local ORB_HEIGHT_STUDS = 2.6

-- Diameter at T1 and at the top tier. The grow-with-charge shape (and the
-- sine wobble below) is lifted from BossWindupClient's `charge_glow`,
-- which is the look this promotes into a reusable module — a player
-- winding up should read as the same class of event as the boss doing it.
--
-- Scaled down from that script's 3→6 studs, because the boss's glow sits
-- on a rig several times a player's size and a 6-stud ball over an R15
-- head is a beach ball that hides the player behind it.
local ORB_DIAMETER_MIN = 1.4
local ORB_DIAMETER_MAX = 3.6

-- Spawn size, so `start` has something to expand out of rather than
-- popping into existence at full size.
local ORB_SPAWN_DIAMETER = 0.2

local ORB_TRANSPARENCY = 0.25

-- Sine wobble on the orb's size, so it breathes instead of sitting inert
-- between tier crossings. Amplitude is a fraction of the current
-- diameter, not an absolute, or a T1 orb would wobble as hard as a T4.
local ORB_WOBBLE_FREQ = 7
local ORB_WOBBLE_AMPLITUDE = 0.08

-- Extra wobble once the charge has topped out at what the player can
-- afford. This is the "as big as it gets" tell, matching the HUD panel's
-- ceiling pulse — the orb stops growing and starts straining.
local ORB_CEILING_WOBBLE_FREQ = 16
local ORB_CEILING_WOBBLE_AMPLITUDE = 0.16

local ORB_LIGHT_BRIGHTNESS_MIN = 2
local ORB_LIGHT_BRIGHTNESS_MAX = 6
local ORB_LIGHT_RANGE_MIN = 8
local ORB_LIGHT_RANGE_MAX = 20

local EXPAND_TIME   = 0.18
local COLLAPSE_TIME = 0.14

-- The pop on a successful release: the orb flares out and vanishes,
-- rather than shrinking. Same reasoning as ShieldVfx.shatter — popping
-- outward is what separates "it fired" from "it was switched off".
local RELEASE_EXPAND_FACTOR = 1.9
local RELEASE_TIME = 0.16

----------------------------------------------------------------------
-- Mote layer (Chunk 4)
----------------------------------------------------------------------

-- Radius of the ring motes are born on, and how far below the orb it
-- sits. A ring around the caster's feet rather than a shell around the
-- orb: the mana is being pulled *out of the world into* the player, and
-- motes spawning next to their destination convey nothing.
local MOTE_RING_RADIUS_STUDS = 7
local MOTE_RING_DROP_STUDS = 3.5

local MOTE_SIZE_STUDS = 0.4
local MOTE_END_SCALE = 0.2
local MOTE_FLIGHT_SEC = 0.55
local MOTE_FLIGHT_JITTER = 0.3
local MOTE_CURVE_STUDS = 4

-- Motes launched per second, per tier reached. A T1 charge trickles; a T4
-- charge at the ceiling is a stream. Multiplied by CEILING_RATE_FACTOR
-- once the charge has topped out.
local MOTE_SPAWN_PER_SEC_PER_TIER = 7
local CEILING_RATE_FACTOR = 1.8

-- Hard ceiling on live mote Parts across every charging player on this
-- client. Charges are *sustained*, unlike every burst in VfxConfig, so
-- this is the one layer that could grow without bound in a crowded fight.
-- Past the cap the orb keeps its particle halo and simply stops receiving
-- flown-in motes: flavour degrades, the tell survives.
local MOTE_PART_CAP = 48

-- Concurrent particle-halo emitters. One per charging player, against
-- VfxConfig.PERF.maxEmitters = 32 — deliberately a small slice of that,
-- because unlike a burst these run for the whole hold and overlap with
-- every projectile and impact effect in flight.
local MOTE_EMITTER_CAP = 6

-- Multipliers on the halo's authored Rate, indexed by tier.
local HALO_RATE_PER_TIER = 1.25
local HALO_CEILING_RATE_FACTOR = 2.2

----------------------------------------------------------------------
-- Name label
----------------------------------------------------------------------

-- Billboard footprint in studs (the Scale half of a BillboardGui's Size
-- is studs, not a fraction). Wide enough for the longest name in the
-- roster at a readable weight; the TextLabel is TextScaled, so "Mend"
-- and "Sanctuary" fill the same box rather than jumping in size.
local LABEL_WIDTH_STUDS  = 9
local LABEL_HEIGHT_STUDS = 1.6

-- Clearance between the top of the orb and the bottom of the text. The
-- orb *grows*, so this is applied against its live radius every frame
-- rather than baked once — otherwise a T4 orb swallows its own name.
local LABEL_GAP_STUDS = 0.9

-- Past this the label stops drawing. The orb is still visible much
-- further out, which is the intent: at range an opponent should read
-- *that* you are charging and roughly how big, not exactly what.
local LABEL_MAX_DISTANCE_STUDS = 120

-- Heavier than the HUD's GothamBold, because this one sits over an
-- arbitrary 3D scene instead of a flat panel and has no background to
-- separate it. Stroke does the rest.
local LABEL_FONT = Enum.Font.GothamBlack
local LABEL_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local LABEL_STROKE_COLOR = Color3.fromRGB(12, 10, 18)
local LABEL_STROKE_TRANSPARENCY = 0.1

-- The pop. Back/Out overshoots and settles, which is the spring; scaling
-- up from zero is what makes a tier crossing register as an *event*
-- rather than a text swap you can miss.
local LABEL_POP_FROM_SCALE = 0
local LABEL_POP_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- The dissipate on a successful release: fade while drifting up, so the
-- name leaves with the spell instead of being switched off. Longer than
-- the orb's own RELEASE_TIME, which is why the billboard hangs off the
-- head rather than off the orb — it has to outlive the flash.
local LABEL_DISSIPATE_TIME = 0.3
local LABEL_DISSIPATE_RISE_STUDS = 1.2

local _liveMoteParts = 0
local _liveMoteEmitters = 0

type Mote = {
	part: BasePart,
	origin: Vector3,
	control: Vector3,
	elapsed: number,
	duration: number,
}

type Entry = {
	orb: Part,
	light: PointLight?,
	halo: ParticleEmitter?,
	haloBaseRate: number,
	color: string,
	tint: Color3,
	tier: number,
	-- 0–1 progress toward the next tier. The casting client feeds this live
	-- off its own clock; a remote observer leaves it at 0 and lets the tier
	-- crossings alone drive the size.
	alpha: number,
	atCeiling: boolean,
	clock: number,
	moteBudget: number,
	motes: { Mote },
	connection: RBXScriptConnection?,
	released: boolean,
	-- Name label. Built lazily on the first tier that names a spell, so a
	-- press that never reaches T1 raises an orb and no text.
	labelGui: BillboardGui?,
	labelText: TextLabel?,
	labelScale: UIScale?,
	labelName: string?,
	labelTween: Tween?,
}

local _active: { [Model]: Entry } = {}

local function resolveHead(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head :: BasePart end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp :: BasePart else nil
end

local function paletteFor(color: string)
	return (VfxConfig.COLORS :: any)[color] or VfxConfig.COLORS.red
end

-- Diameter for a tier plus its in-between progress. `tier` 0 means the
-- press has landed but the charge has not reached T1 yet, which draws the
-- smallest orb there is rather than nothing — the player pressed, and the
-- press should be visible.
local function diameterFor(tier: number, alpha: number): number
	-- Scaled against the roster's top tier rather than the colour's, so a
	-- green T3 (that school's maximum) is visibly smaller than a red T4. The
	-- orb is a PvP tell: what an opponent needs to read off it is how much
	-- is coming, not how close to their own ceiling the caster is.
	local topTier = math.max(SpellRegistry.NUM_TIERS, 2)
	local reached = math.clamp(tier + alpha, 0, topTier)
	local t = math.clamp((reached - 1) / (topTier - 1), 0, 1)
	return ORB_DIAMETER_MIN + (ORB_DIAMETER_MAX - ORB_DIAMETER_MIN) * t
end

----------------------------------------------------------------------
-- Name label
----------------------------------------------------------------------

-- The spell this charge would fire right now, or nil below T1.
--
-- Bounded by `tierCount` rather than by `getSpell` alone: getSpell
-- validates the tier against the *roster* maximum of 4, and green tops
-- out at 3, so `getSpell("green", 4)` passes validation and hands back
-- nil. Reading `.name` off that is the crash this guard exists to avoid.
local function spellNameFor(color: string, tier: number): string?
	if tier < 1 then return nil end
	local okCount, count = pcall(SpellRegistry.tierCount, color :: any)
	if not okCount or typeof(count) ~= "number" or tier > (count :: number) then
		return nil
	end
	local okSpec, spec = pcall(SpellRegistry.getSpell, color :: any, tier)
	if not okSpec or typeof(spec) ~= "table" then return nil end
	return (spec :: SpellRegistry.Spec).name
end

-- Parented to the head rather than to the orb, so the dissipate can
-- outlive the orb's release flash — the orb is destroyed RELEASE_TIME
-- after it fires, and the name is still drifting up at that point.
local function buildLabel(entry: Entry, character: Model)
	if entry.labelGui then return end

	local head = resolveHead(character)
	if not head then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "SpellChargeName"
	gui.Size = UDim2.fromScale(LABEL_WIDTH_STUDS, LABEL_HEIGHT_STUDS)
	gui.MaxDistance = LABEL_MAX_DISTANCE_STUDS
	gui.LightInfluence = 0
	-- AlwaysOnTop deliberately off. The orb is occluded by cover and the
	-- name has to be occluded with it — a label that reads through a wall
	-- turns a PvP tell into a wallhack.
	gui.AlwaysOnTop = false
	gui.StudsOffsetWorldSpace = Vector3.new(0, ORB_HEIGHT_STUDS + LABEL_GAP_STUDS, 0)
	gui.Parent = head

	local text = Instance.new("TextLabel")
	text.Name = "Name"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = LABEL_FONT
	text.TextScaled = true
	text.TextColor3 = LABEL_TEXT_COLOR
	text.TextStrokeColor3 = LABEL_STROKE_COLOR
	text.TextStrokeTransparency = LABEL_STROKE_TRANSPARENCY
	text.Text = ""
	text.Parent = gui

	-- Anchored at its own centre above, so the pop grows out of the middle
	-- rather than out of the top-left corner.
	local scale = Instance.new("UIScale")
	scale.Scale = LABEL_POP_FROM_SCALE
	scale.Parent = text

	entry.labelGui = gui
	entry.labelText = text
	entry.labelScale = scale
end

local function popLabel(entry: Entry, name: string)
	local text, scale = entry.labelText, entry.labelScale
	if not text or not scale then return end

	-- Cancel first: without this a crossing landing inside the previous
	-- pop leaves two tweens writing Scale, and the loser wins.
	local previous = entry.labelTween
	if previous then previous:Cancel() end

	text.Text = name
	text.TextTransparency = 0
	text.TextStrokeTransparency = LABEL_STROKE_TRANSPARENCY
	scale.Scale = LABEL_POP_FROM_SCALE

	local tween = TweenService:Create(scale, LABEL_POP_TWEEN, { Scale = 1 })
	entry.labelTween = tween
	tween:Play()
end

-- Detaches the label from the entry and lets it finish on its own, so a
-- teardown arriving mid-dissipate cannot cut it short. `rise` separates
-- the two exits: a cast drifts the name upward as it fades, a cancel just
-- goes, on the same clock as the orb's quiet collapse.
local function dissipateLabel(entry: Entry, rise: boolean)
	local gui, text = entry.labelGui, entry.labelText
	local previous = entry.labelTween
	if previous then previous:Cancel() end

	entry.labelGui = nil
	entry.labelText = nil
	entry.labelScale = nil
	entry.labelName = nil
	entry.labelTween = nil

	if not gui or not text then return end
	if not gui.Parent then
		gui:Destroy()
		return
	end

	local duration = if rise then LABEL_DISSIPATE_TIME else COLLAPSE_TIME
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(text, info, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	if rise then
		TweenService:Create(gui, info, {
			StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace
				+ Vector3.new(0, LABEL_DISSIPATE_RISE_STUDS, 0),
		}):Play()
	end

	task.delay(duration, function()
		if gui.Parent then gui:Destroy() end
	end)
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local inv = 1 - t
	return (p0 * (inv * inv)) + (p1 * (2 * inv * t)) + (p2 * (t * t))
end

local function spawnMote(entry: Entry, toward: Vector3)
	if _liveMoteParts >= MOTE_PART_CAP then return end

	local angle = math.random() * math.pi * 2
	local radius = MOTE_RING_RADIUS_STUDS * (0.7 + math.random() * 0.5)
	local spawnAt = toward
		+ Vector3.new(math.cos(angle) * radius, -MOTE_RING_DROP_STUDS, math.sin(angle) * radius)

	local part = Instance.new("Part")
	part.Name         = "ChargeMote"
	part.Shape        = Enum.PartType.Ball
	part.Size         = Vector3.one * MOTE_SIZE_STUDS
	part.Anchored     = true
	part.CanCollide   = false
	-- CanQuery off for the same load-bearing reason ShieldVfx's bubble has
	-- it: block taps and spell raycasts sweep the workspace, and a cloud of
	-- Parts around the caster would swallow their own shots.
	part.CanQuery     = false
	part.CanTouch     = false
	part.CastShadow   = false
	part.Material     = Enum.Material.Neon
	part.Color        = entry.tint
	part.Position     = spawnAt
	part.Parent       = workspace

	local travel = toward - spawnAt
	local axis = if travel.Magnitude > 0.01 then travel.Unit else Vector3.yAxis
	local perp = axis:Cross(Vector3.yAxis)
	if perp.Magnitude < 0.01 then
		perp = axis:Cross(Vector3.xAxis)
	end
	local roll = CFrame.fromAxisAngle(axis, math.random() * math.pi * 2)
	local bow = (roll * perp.Unit) * (MOTE_CURVE_STUDS * (0.3 + math.random() * 0.7))

	_liveMoteParts += 1
	table.insert(entry.motes, {
		part     = part,
		origin   = spawnAt,
		control  = spawnAt:Lerp(toward, 0.5) + bow,
		elapsed  = 0,
		duration = MOTE_FLIGHT_SEC * (1 - math.random() * MOTE_FLIGHT_JITTER),
	})
end

local function destroyMote(entry: Entry, index: number)
	local mote = entry.motes[index]
	if not mote then return end
	table.remove(entry.motes, index)
	_liveMoteParts -= 1
	if mote.part.Parent then mote.part:Destroy() end
end

local function clearMotes(entry: Entry)
	for i = #entry.motes, 1, -1 do
		destroyMote(entry, i)
	end
end

-- Build the sustained particle halo from the authored `charge_motes_*`
-- entry. Returns nil when the emitter budget is spent or the template is
-- missing — the orb is unaffected either way.
local function buildHalo(entry: Entry, parent: Instance): (ParticleEmitter?, number)
	if _liveMoteEmitters >= MOTE_EMITTER_CAP then return nil, 0 end
	if not VfxTemplates then return nil, 0 end

	-- EFFECTS is a literal table, so a dynamic key needs the cast; the
	-- resolver has already guaranteed the id exists.
	local spec = (VfxConfig.EFFECTS :: any)[VfxConfig.resolveChargeMotesId(entry.color)] :: VfxConfig.EffectSpec?
	local emitters = spec and spec.emitters
	local emitterSpec = emitters and emitters[1]
	if not emitterSpec then return nil, 0 end

	local template = VfxTemplates:FindFirstChild(emitterSpec.template)
	if not template or not template:IsA("ParticleEmitter") then
		log:warnThrottled("halo_template", 30, string.format(
			"template %q missing or wrong class — charge orb draws without its halo",
			emitterSpec.template
		))
		return nil, 0
	end

	local emitter = template:Clone() :: ParticleEmitter
	if emitterSpec.color then
		emitter.Color = ColorSequence.new(emitterSpec.color.primary)
		emitter.LightEmission = 0.5
	end
	if emitterSpec.lifetime     then emitter.Lifetime     = emitterSpec.lifetime     end
	if emitterSpec.size         then emitter.Size         = emitterSpec.size         end
	if emitterSpec.speed        then emitter.Speed        = emitterSpec.speed        end
	if emitterSpec.spreadAngle  then emitter.SpreadAngle  = emitterSpec.spreadAngle  end
	if emitterSpec.transparency then emitter.Transparency = emitterSpec.transparency end

	local baseRate = emitterSpec.rate or 0
	emitter.Rate = baseRate
	emitter.Enabled = true
	emitter.Parent = parent

	_liveMoteEmitters += 1
	return emitter, baseRate
end

local function releaseHalo(entry: Entry)
	local halo = entry.halo
	if not halo then return end
	entry.halo = nil
	_liveMoteEmitters -= 1
	halo.Enabled = false
	-- Destroyed a beat late so particles already in the air finish their
	-- lifetime instead of being cut off with the emitter.
	Debris:AddItem(halo, halo.Lifetime.Max)
end

local ChargeOrbVfx = {}

-- Advance one entry: orb size/wobble, light, halo rate, mote spawning and
-- mote flight. One connection per charging character, in the same
-- single-driver shape collectStream uses.
local function step(character: Model, entry: Entry, dt: number)
	local orb = entry.orb
	if not orb.Parent then
		ChargeOrbVfx.stop(character)
		return
	end

	local head = resolveHead(character)
	if not head then
		ChargeOrbVfx.stop(character)
		return
	end

	entry.clock += dt
	local target = head.Position + Vector3.new(0, ORB_HEIGHT_STUDS, 0)

	if not entry.released then
		local diameter = diameterFor(entry.tier, entry.alpha)
		local freq = if entry.atCeiling then ORB_CEILING_WOBBLE_FREQ else ORB_WOBBLE_FREQ
		local amp  = if entry.atCeiling then ORB_CEILING_WOBBLE_AMPLITUDE else ORB_WOBBLE_AMPLITUDE
		local wobbled = diameter * (1 + amp * math.sin(entry.clock * freq))
		orb.Size = Vector3.one * wobbled

		-- Ride the orb's live radius so the gap under the text stays constant
		-- as it grows, instead of the orb creeping up into its own name.
		local labelGui = entry.labelGui
		if labelGui then
			labelGui.StudsOffsetWorldSpace =
				Vector3.new(0, ORB_HEIGHT_STUDS + wobbled / 2 + LABEL_GAP_STUDS, 0)
		end

		local light = entry.light
		if light then
			local t = math.clamp((diameter - ORB_DIAMETER_MIN) / (ORB_DIAMETER_MAX - ORB_DIAMETER_MIN), 0, 1)
			light.Brightness = ORB_LIGHT_BRIGHTNESS_MIN + (ORB_LIGHT_BRIGHTNESS_MAX - ORB_LIGHT_BRIGHTNESS_MIN) * t
			light.Range = ORB_LIGHT_RANGE_MIN + (ORB_LIGHT_RANGE_MAX - ORB_LIGHT_RANGE_MIN) * t
		end

		-- Motes only once the charge is actually worth something. A tier-0
		-- press draws the orb but pulls in no mana, because none is reserved.
		if entry.tier >= 1 then
			local rate = MOTE_SPAWN_PER_SEC_PER_TIER * entry.tier
			if entry.atCeiling then
				rate *= CEILING_RATE_FACTOR
			end
			entry.moteBudget += rate * dt
			while entry.moteBudget >= 1 do
				entry.moteBudget -= 1
				spawnMote(entry, target)
			end
		end
	end

	-- Motes keep flying through the release flash: they were already in the
	-- air, and cutting them on the frame the spell fires reads as a hitch.
	for i = #entry.motes, 1, -1 do
		local mote = entry.motes[i]
		if not mote.part.Parent then
			destroyMote(entry, i)
			continue
		end
		mote.elapsed += dt
		local a = math.min(mote.elapsed / mote.duration, 1)
		mote.part.Position = bezier(mote.origin, mote.control, target, a)
		mote.part.Size = Vector3.one * (MOTE_SIZE_STUDS * (1 - (1 - MOTE_END_SCALE) * a))
		if a >= 1 then
			destroyMote(entry, i)
		end
	end
end

-- Raise the orb on `character`. No-op if one is already up — use `setTier`
-- to re-tune an existing orb.
function ChargeOrbVfx.start(character: Model, color: string)
	if RunService:IsServer() then
		log:warnThrottled("server_call", 5, string.format(
			"refused on the server — the halo and the mote flight render for nobody there. " ..
			"Write the charge attributes instead and let ChargeOrbController draw it.\n%s",
			debug.traceback()
		))
		return
	end
	if _active[character] then return end

	local head = resolveHead(character)
	if not head then return end

	local palette = paletteFor(color)

	local orb = Instance.new("Part")
	orb.Name         = "SpellChargeOrb"
	orb.Shape        = Enum.PartType.Ball
	orb.Material     = Enum.Material.Neon
	orb.Color        = palette.glow
	orb.Transparency = ORB_TRANSPARENCY
	orb.Size         = Vector3.one * ORB_SPAWN_DIAMETER
	orb.CFrame       = CFrame.new(head.Position + Vector3.new(0, ORB_HEIGHT_STUDS, 0))
	orb.Anchored     = false
	orb.CanCollide   = false
	orb.CanQuery     = false
	orb.CanTouch     = false
	orb.CastShadow   = false
	orb.Massless     = true
	-- Parented to workspace rather than under the character, for the same
	-- reason ShieldVfx's bubble is: FreezeVfx shards every BasePart under a
	-- character, and an orb living in there would grow its own ice shell.
	orb.Parent       = workspace

	-- Welded rather than CFrame-tracked per Heartbeat. BossWindupClient does
	-- the per-frame version and it is the more expensive half of that
	-- script; a weld is one constraint and the engine moves it for free.
	local weld = Instance.new("WeldConstraint")
	weld.Part0  = orb
	weld.Part1  = head
	weld.Parent = orb

	local light: PointLight? = nil
	if VfxConfig.PERF.allowLights then
		local l = Instance.new("PointLight")
		l.Name       = "ChargeOrbLight"
		l.Color      = palette.primary
		l.Brightness = ORB_LIGHT_BRIGHTNESS_MIN
		l.Range      = ORB_LIGHT_RANGE_MIN
		l.Shadows    = false
		l.Parent     = orb
		light = l
	end

	local entry: Entry = {
		orb          = orb,
		light        = light,
		halo         = nil,
		haloBaseRate = 0,
		color        = color,
		tint         = palette.glow,
		tier         = 0,
		alpha        = 0,
		atCeiling    = false,
		clock        = 0,
		moteBudget   = 0,
		motes        = {},
		connection   = nil,
		released     = false,
		labelGui     = nil,
		labelText    = nil,
		labelScale   = nil,
		labelName    = nil,
		labelTween   = nil,
	}

	local attachment = Instance.new("Attachment")
	attachment.Name = "ChargeHalo"
	attachment.Parent = orb
	entry.halo, entry.haloBaseRate = buildHalo(entry, attachment)

	TweenService:Create(
		orb,
		TweenInfo.new(EXPAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.one * diameterFor(0, 0) }
	):Play()

	_active[character] = entry
	entry.connection = RunService.Heartbeat:Connect(function(dt: number)
		local live = _active[character]
		if live ~= entry then return end
		step(character, entry, dt)
	end)
end

-- Re-tune an existing orb. `alpha` is 0–1 progress toward the *next*
-- tier, so the casting client (which knows its own hold clock) gets
-- continuous growth while a remote observer, which only ever sees
-- discrete tier crossings, passes 0 and gets the stepped version.
--
-- `atCeiling` swaps the growth for a harder, faster wobble — the orb
-- straining rather than climbing, matching the HUD panel's ceiling pulse.
function ChargeOrbVfx.setTier(character: Model, tier: number, alpha: number?, atCeiling: boolean?)
	local entry = _active[character]
	if not entry then return end

	entry.tier = math.max(tier, 0)
	entry.alpha = math.clamp(alpha or 0, 0, 1)
	entry.atCeiling = atCeiling == true

	-- The name of the spell this release would fire. Built on the first
	-- tier that names one — for T1 that is the press frame, because
	-- chargeTimeFor(1) is zero — and re-popped on every crossing after.
	--
	-- The nil branch is not dead: `setChargeAffordability` can lower the
	-- ceiling mid-hold if the reservoir is spent elsewhere, which can drop
	-- a live charge back below T1.
	if not entry.released then
		local name = spellNameFor(entry.color, entry.tier)
		if name then
			buildLabel(entry, character)
			if name ~= entry.labelName then
				entry.labelName = name
				popLabel(entry, name)
			end
		elseif entry.labelGui then
			dissipateLabel(entry, false)
		end
	end

	local halo = entry.halo
	if halo then
		local rate = entry.haloBaseRate * (1 + HALO_RATE_PER_TIER * math.max(tier - 1, 0))
		if entry.atCeiling and tier >= 1 then
			rate *= HALO_CEILING_RATE_FACTOR
		end
		halo.Rate = if tier >= 1 then rate else 0
	end
end

-- The charge firing, as opposed to being cancelled.
--
-- `stop` collapses quietly, which is right when the hold was abandoned.
-- This one is an event the player (and their opponent) is meant to
-- notice: the orb flares outward and vanishes on the frame the spell goes
-- out. Motes already in the air keep flying in behind it.
function ChargeOrbVfx.release(character: Model, _tier: number?)
	local entry = _active[character]
	if not entry then return end
	if entry.released then return end
	entry.released = true

	releaseHalo(entry)
	dissipateLabel(entry, true)

	local orb = entry.orb
	if orb.Parent then
		TweenService:Create(
			orb,
			TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = orb.Size * RELEASE_EXPAND_FACTOR, Transparency = 1 }
		):Play()
	end

	task.delay(RELEASE_TIME, function()
		-- A new charge may have started inside the flash — a fast player can
		-- press again before this fires. Only tear down the entry this call
		-- was made against.
		if _active[character] == entry then
			ChargeOrbVfx.stop(character)
		end
	end)
end

-- Collapse and destroy. Idempotent — a cancel, a death, a respawn and a
-- character despawn can all fire for one orb.
function ChargeOrbVfx.stop(character: Model)
	local entry = _active[character]
	if not entry then return end
	_active[character] = nil

	if entry.connection then
		entry.connection:Disconnect()
		entry.connection = nil
	end
	releaseHalo(entry)
	clearMotes(entry)
	-- No-op after a release, which already handed the label off to its own
	-- dissipate; this is the cancel / death / despawn path.
	dissipateLabel(entry, false)

	local orb = entry.orb
	if not orb.Parent then return end

	if entry.released then
		-- The release flash already faded it out; nothing left to animate.
		orb:Destroy()
		return
	end

	TweenService:Create(
		orb,
		TweenInfo.new(COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.zero, Transparency = 1 }
	):Play()
	task.delay(COLLAPSE_TIME, function()
		if orb.Parent then orb:Destroy() end
	end)
end

-- Read-only probes for tests and for the leak check in
-- wiki/systems/ChargeCast.md § Verification.
function ChargeOrbVfx.isActive(character: Model): boolean
	return _active[character] ~= nil
end

-- `labels` counts only labels still attached to a live charge. One
-- mid-dissipate has already been handed off and is nobody's to count —
-- scan the workspace for `SpellChargeName` if that is what you need.
function ChargeOrbVfx.debugCounts(): {
	orbs: number,
	moteParts: number,
	moteEmitters: number,
	labels: number,
}
	local orbs, labels = 0, 0
	for _, entry in _active do
		orbs += 1
		if entry.labelGui then labels += 1 end
	end
	return {
		orbs = orbs,
		moteParts = _liveMoteParts,
		moteEmitters = _liveMoteEmitters,
		labels = labels,
	}
end

return ChargeOrbVfx
