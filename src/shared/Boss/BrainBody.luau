--!strict

----------------------------------------------------------------------
-- BrainBody
----------------------------------------------------------------------
-- The Brain boss's visible body, built from native primitives on
-- Motor6Ds so each client can animate it (wiki/design/boss-movement.md).
--
--   HumanoidRootPart
--   └─ BrainRoot (invisible pivot: hover, lean, wobble)
--      ├─ LeftLobe / RightLobe  (ellipsoids hinged at the bottom of the
--      │   fissure, so a lobe can swing open; gyri welded on top)
--      ├─ Core                  (neon ball the closed lobes hide)
--      ├─ Cerebellum, Stem
--      ├─ LeftEye / RightEye    (pupil welded in front; turning the eye
--      │                         moves the pupil)
--      └─ Neuron1..N            (orbit; a Beam ties each to the Core)
--
-- Ownership (wiki/concepts/SingleOwnership.md): the server builds the
-- parts and joints once, and owns their colour. Every joint's
-- `Transform`, and each mesh's `Scale`, is written only by the client's
-- BossPuppet; neither replicates.
--
-- Shared, not server-only, because the puppet reads the joint names and
-- the rest values from here.
----------------------------------------------------------------------

local BrainBody = {}

-- The attribute a spawned boss carries to say which body it wears; the
-- puppet animates only the bodies it knows.
BrainBody.BODY_ATTRIBUTE = "BossBody"
BrainBody.BODY_NAME = "Brain"

-- Parts of the old welded BossBrain template that this body replaces.
BrainBody.LEGACY_PARTS = { "BrainBody", "BrainStem", "LeftEye", "RightEye" }

-- Joint names, read by the puppet.
BrainBody.Joint = {
	Root       = "BrainRootJoint",
	LeftLobe   = "LeftLobeJoint",
	RightLobe  = "RightLobeJoint",
	Core       = "CoreJoint",
	Cerebellum = "CerebellumJoint",
	Stem       = "StemJoint",
	LeftEye    = "LeftEyeJoint",
	RightEye   = "RightEyeJoint",
}

BrainBody.NEURON_JOINT_PREFIX = "NeuronJoint"
BrainBody.NEURON_COUNT = 4
BrainBody.CORE_LIGHT_NAME = "CoreLight"
BrainBody.LOBE_PARTS = { "LeftLobe", "RightLobe" }

-- ---------------------------------------------------------------
-- Geometry (studs, in the frame of the part each joint hangs from)
-- ---------------------------------------------------------------

-- BrainRoot sits this far above the HumanoidRootPart.
local ROOT_OFFSET = Vector3.new(0, 4, 0)

local LOBE_SIZE = Vector3.new(5, 8, 9.5)
local LOBE_CENTRE_X = 2.3
-- The hinge each lobe swings open on: the bottom of the fissure.
local LOBE_HINGE = Vector3.new(0.2, -3.6, 0)

-- Ridges along the top of each lobe: x across the lobe, y up, length
-- front to back, each a flattened ellipsoid.
local GYRI = {
	{ offset = Vector3.new(-0.2, 3.2, 0), size = Vector3.new(2.2, 1.6, 8) },
	{ offset = Vector3.new(-1.4, 2.0, 0.5), size = Vector3.new(1.6, 2.6, 7) },
	{ offset = Vector3.new(-1.9, -0.2, 0), size = Vector3.new(1.4, 2.8, 7.5) },
}
-- How much darker a ridge is than its lobe (0 = same, 1 = black).
local GYRUS_DARKEN = 0.25

local CORE_DIAMETER = 5
local CORE_OFFSET = Vector3.new(0, 0.2, 0)
local CORE_COLOR = Color3.fromRGB(255, 225, 140)
local CORE_LIGHT_RANGE = 14
local CORE_LIGHT_BRIGHTNESS = 1

local CEREBELLUM_SIZE = Vector3.new(6, 3, 3)
local CEREBELLUM_OFFSET = Vector3.new(0, -2.4, 3.2)

local STEM_SIZE = Vector3.new(2, 4, 2)
-- The stem hangs from its top end.
local STEM_HINGE = Vector3.new(0, -2.8, 1.2)

local EYE_DIAMETER = 2.2
local EYE_OFFSET = Vector3.new(2.0, 1.2, -4.4)
local EYE_COLOR = Color3.fromRGB(255, 230, 60)
local PUPIL_DIAMETER = 1.1
local PUPIL_FORWARD = 0.85
local PUPIL_COLOR = Color3.fromRGB(20, 10, 10)

local NEURON_DIAMETER = 1.2
local NEURON_COLOR = Color3.fromRGB(255, 225, 140)
local SYNAPSE_WIDTH = 0.15
local SYNAPSE_TRANSPARENCY = 0.6

-- ---------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------

local function newPart(name: string, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A Part drawn as an ellipsoid of its own size (a Ball part is forced
-- round; a Sphere SpecialMesh is not).
local function newEllipsoid(name: string, size: Vector3, parent: Instance): Part
	local part = newPart(name, size, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function newBall(name: string, diameter: number, parent: Instance): Part
	local part = newPart(name, Vector3.one * diameter, parent)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Hangs `child` from `parent` on a Motor6D named `jointName`. `c0` is the
-- joint's place in the parent, `c1` the same point in the child.
local function joint(jointName: string, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = jointName
	motor.Part0 = parent
	motor.Part1 = child
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = child
	child.CFrame = parent.CFrame * c0 * c1:Inverse()
	return motor
end

-- Rigidly fixes `child` to `parent` at `offset`, for detail that never
-- moves on its own.
local function weld(parent: BasePart, child: BasePart, offset: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = parent
	w.Part1 = child
	w.C0 = offset
	w.Parent = child
	child.CFrame = parent.CFrame * offset
end

local function attach(part: BasePart, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = part
	return a
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function buildLobe(name: string, side: number, root: BasePart, boss: Model, color: Color3): Part
	local lobe = newEllipsoid(name, LOBE_SIZE, boss)
	lobe.Color = color
	lobe.CastShadow = true
	-- side = -1 for the left lobe, +1 for the right.
	local hingeInRoot = Vector3.new(LOBE_HINGE.X * side, LOBE_HINGE.Y, LOBE_HINGE.Z)
	local centreInRoot = Vector3.new(LOBE_CENTRE_X * side, 0, 0)
	joint(
		name .. "Joint",
		root,
		lobe,
		CFrame.new(hingeInRoot),
		CFrame.new(hingeInRoot - centreInRoot)
	)
	for i, gyrus in GYRI do
		local ridge = newEllipsoid(name .. "Gyrus" .. i, gyrus.size, boss)
		ridge.Color = darken(color, GYRUS_DARKEN)
		ridge:SetAttribute("GyrusOf", name)
		local offset = Vector3.new(-gyrus.offset.X * side, gyrus.offset.Y, gyrus.offset.Z)
		weld(lobe, ridge, CFrame.new(offset))
	end
	return lobe
end

local function buildEye(name: string, side: number, root: BasePart, boss: Model)
	local eye = newBall(name, EYE_DIAMETER, boss)
	eye.Material = Enum.Material.Neon
	eye.Color = EYE_COLOR
	local at = CFrame.new(EYE_OFFSET.X * side, EYE_OFFSET.Y, EYE_OFFSET.Z)
	joint(name .. "Joint", root, eye, at, CFrame.identity)
	local pupil = newBall(name .. "Pupil", PUPIL_DIAMETER, boss)
	pupil.Color = PUPIL_COLOR
	weld(eye, pupil, CFrame.new(0, 0, -PUPIL_FORWARD))
end

-- Builds the body on `boss`, hung from `hrp`, in `color`. Removes the old
-- template's welded parts first.
function BrainBody.build(boss: Model, hrp: BasePart, color: Color3)
	for _, legacyName in BrainBody.LEGACY_PARTS do
		local legacy = boss:FindFirstChild(legacyName)
		if legacy then
			legacy:Destroy()
		end
	end
	for _, child in boss:GetChildren() do
		if child:IsA("WeldConstraint") and (child.Part0 == nil or child.Part1 == nil) then
			child:Destroy()
		end
	end

	local root = newPart("BrainRoot", Vector3.one, boss)
	root.Transparency = 1
	joint(BrainBody.Joint.Root, hrp, root, CFrame.new(ROOT_OFFSET), CFrame.identity)

	local core = newBall("Core", CORE_DIAMETER, boss)
	core.Material = Enum.Material.Neon
	core.Color = CORE_COLOR
	joint(BrainBody.Joint.Core, root, core, CFrame.new(CORE_OFFSET), CFrame.identity)
	local light = Instance.new("PointLight")
	light.Name = BrainBody.CORE_LIGHT_NAME
	light.Color = CORE_COLOR
	light.Range = CORE_LIGHT_RANGE
	light.Brightness = CORE_LIGHT_BRIGHTNESS
	light.Parent = core

	buildLobe("LeftLobe", -1, root, boss, color)
	buildLobe("RightLobe", 1, root, boss, color)

	local cerebellum = newEllipsoid("Cerebellum", CEREBELLUM_SIZE, boss)
	cerebellum.Color = darken(color, GYRUS_DARKEN)
	cerebellum:SetAttribute("GyrusOf", "Cerebellum")
	joint(BrainBody.Joint.Cerebellum, root, cerebellum, CFrame.new(CEREBELLUM_OFFSET), CFrame.identity)

	local stem = newEllipsoid("Stem", STEM_SIZE, boss)
	stem.Color = color
	joint(BrainBody.Joint.Stem, root, stem, CFrame.new(STEM_HINGE), CFrame.new(0, STEM_SIZE.Y / 2, 0))

	buildEye("LeftEye", -1, root, boss)
	buildEye("RightEye", 1, root, boss)

	local coreAttachment = attach(core, "SynapseHub")
	for i = 1, BrainBody.NEURON_COUNT do
		local neuron = newBall("Neuron" .. i, NEURON_DIAMETER, boss)
		neuron.Material = Enum.Material.Neon
		neuron.Color = NEURON_COLOR
		-- Rests inside the core; the puppet's Transform carries it out to
		-- its orbit.
		joint(BrainBody.NEURON_JOINT_PREFIX .. i, root, neuron, CFrame.new(CORE_OFFSET), CFrame.identity)
		local beam = Instance.new("Beam")
		beam.Name = "Synapse"
		beam.Attachment0 = attach(neuron, "Synapse")
		beam.Attachment1 = coreAttachment
		beam.Width0 = SYNAPSE_WIDTH
		beam.Width1 = SYNAPSE_WIDTH
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(NEURON_COLOR)
		beam.Transparency = NumberSequence.new(SYNAPSE_TRANSPARENCY)
		beam.Parent = neuron
	end

	boss:SetAttribute(BrainBody.BODY_ATTRIBUTE, BrainBody.BODY_NAME)
end

-- Paints the body for a phase: lobes and stem in `color`, ridges and the
-- cerebellum a shade darker.
function BrainBody.recolor(boss: Model, color: Color3)
	for _, name in { "LeftLobe", "RightLobe", "Stem" } do
		local part = boss:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
	for _, child in boss:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("GyrusOf") then
			child.Color = darken(color, GYRUS_DARKEN)
		end
	end
end

return BrainBody
