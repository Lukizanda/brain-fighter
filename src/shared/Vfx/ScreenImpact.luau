--!strict

----------------------------------------------------------------------
-- ScreenImpact — the screen-space layer of a big hit.
----------------------------------------------------------------------
-- A third VFX lane, alongside the burst path (VfxConfig + spawnEffect)
-- and the status-visual path (StatusVisuals/*). Those two draw things
-- *in the world*; this one draws on the viewer. Nothing here is attached
-- to a rig, has a position, or replicates.
--
-- Why it earns a module. Particles are how you show that something
-- happened over there; a tint and a shake are how you show that it
-- happened hard enough to matter to *you*. Inferno's problem was never
-- that it lacked particles — the pre-2026-08-08 eruption had 86 of them —
-- it was that the game's heaviest spell asked nothing of the player's
-- screen, so it read as an event the camera merely witnessed.
--
-- Deliberately generic, and deliberately not named after Inferno. A boss
-- slam landing next to you wants the same primitive with different
-- numbers, and the second caller should not have to lift this out of a
-- spell-specific file first.
--
-- CLIENT ONLY. The post-processing instances live in Lighting on the
-- local machine and are never replicated; the shake writes
-- `Humanoid.CameraOffset` on the local character.
----------------------------------------------------------------------

local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("ScreenImpact")

export type Profile = {
	-- Peak post-processing, all reached instantly and decayed from there.
	tintColor: Color3,
	brightness: number,
	contrast: number,
	blurSize: number,
	-- Peak camera displacement in studs.
	shakeStuds: number,
	-- How fast the shake oscillates. Higher reads as a sharper crack,
	-- lower as a rolling rumble.
	shakeHz: number,
	-- How long everything takes to return to neutral.
	releaseSec: number,
}

-- Below this the effect is invisible but still costs a RenderStepped
-- connection and two enabled post-processing passes every frame. A
-- distant Inferno should cost nothing, not a little.
local MIN_INTENSITY = 0.05

local _cc: ColorCorrectionEffect? = nil
local _blur: BlurEffect? = nil

-- Bumped on every `play`. The decay loop and the shake loop both capture
-- the value current when they started and stop the moment it changes, so
-- a second impact landing mid-decay takes over cleanly instead of the two
-- fighting over CameraOffset and the tint until the first one's timer
-- happens to expire.
local _generation = 0

local function ensureInstances(): (ColorCorrectionEffect, BlurEffect)
	local cc = _cc
	if not cc or not cc.Parent then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name    = "ScreenImpactCC"
		cc.Enabled = false
		cc.Parent  = Lighting
		_cc = cc
	end

	local blur = _blur
	if not blur or not blur.Parent then
		blur = Instance.new("BlurEffect")
		blur.Name    = "ScreenImpactBlur"
		blur.Size    = 0
		blur.Enabled = false
		blur.Parent  = Lighting
		_blur = blur
	end

	return cc :: ColorCorrectionEffect, blur :: BlurEffect
end

local function localHumanoid(): Humanoid?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local ScreenImpact = {}

-- Hit the screen at `intensity` (0–1) and decay back to neutral.
--
-- `intensity` is the caller's business: it is where distance falloff,
-- accessibility settings and "was this my cast" all get folded in. This
-- function only scales by it.
function ScreenImpact.play(profile: Profile, intensity: number)
	if RunService:IsServer() then
		log:warnThrottled("server_call", 5, string.format(
			"refused on the server — the server has no screen and no camera.\n%s",
			debug.traceback()
		))
		return
	end
	if intensity < MIN_INTENSITY then return end

	local scale = math.clamp(intensity, 0, 1)
	_generation += 1
	local generation = _generation

	----------------------------------------------------------------
	-- Post-processing
	----------------------------------------------------------------
	local cc, blur = ensureInstances()

	cc.TintColor  = profile.tintColor
	cc.Brightness = profile.brightness * scale
	cc.Contrast   = profile.contrast * scale
	cc.Enabled    = true
	blur.Size     = profile.blurSize * scale
	blur.Enabled  = true

	local release = TweenInfo.new(profile.releaseSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- TintColor decays to white, not to the tint at zero saturation:
	-- ColorCorrection multiplies by TintColor, so white is the identity.
	TweenService:Create(cc, release, {
		Brightness = 0,
		Contrast   = 0,
		TintColor  = Color3.new(1, 1, 1),
	}):Play()
	TweenService:Create(blur, release, { Size = 0 }):Play()

	task.delay(profile.releaseSec, function()
		-- Only the most recent impact turns the passes back off. Without
		-- this check a short impact landing after a long one would disable
		-- both mid-decay and snap the screen back.
		if generation ~= _generation then return end
		if _cc then (_cc :: ColorCorrectionEffect).Enabled = false end
		if _blur then (_blur :: BlurEffect).Enabled = false end
	end)

	----------------------------------------------------------------
	-- Camera shake
	----------------------------------------------------------------
	-- Via `Humanoid.CameraOffset`, not `Camera.CFrame`. The default Roblox
	-- camera scripts own the CFrame and rewrite it every frame, so a
	-- second writer would either be overwritten or have to fight for it —
	-- the Single Ownership Rule, applied to something this repo does not
	-- own. CameraOffset is the sanctioned displacement applied on top of
	-- whatever the camera controller decided, and nothing else in the
	-- project writes it.
	local humanoid = localHumanoid()
	if not humanoid or profile.shakeStuds <= 0 then return end

	local peak    = profile.shakeStuds * scale
	local elapsed = 0

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if generation ~= _generation then
			conn:Disconnect()
			return
		end
		elapsed += dt
		if elapsed >= profile.releaseSec or not humanoid.Parent then
			conn:Disconnect()
			if humanoid.Parent then humanoid.CameraOffset = Vector3.zero end
			return
		end

		-- Linear amplitude decay under a sine carrier. The two axes run at
		-- different multiples of the base frequency so the motion is a
		-- wobble rather than a diagonal line.
		local remaining = 1 - (elapsed / profile.releaseSec)
		local amplitude = peak * remaining
		local phase     = elapsed * profile.shakeHz * math.pi * 2
		humanoid.CameraOffset = Vector3.new(
			math.sin(phase) * amplitude,
			math.sin(phase * 1.7) * amplitude * 0.6,
			0
		)
	end)
end

-- Drop everything immediately and leave no trace. For teardown paths that
-- must not leave a tinted screen behind — a character dying mid-shake, or
-- a controller being disabled.
function ScreenImpact.clear()
	_generation += 1
	if _cc then
		local cc = _cc :: ColorCorrectionEffect
		cc.Enabled    = false
		cc.Brightness = 0
		cc.Contrast   = 0
		cc.TintColor  = Color3.new(1, 1, 1)
	end
	if _blur then
		local blur = _blur :: BlurEffect
		blur.Enabled = false
		blur.Size    = 0
	end
	local humanoid = localHumanoid()
	if humanoid then humanoid.CameraOffset = Vector3.zero end
end

return ScreenImpact
