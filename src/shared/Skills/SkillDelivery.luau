--!strict

----------------------------------------------------------------------
-- SkillDelivery
----------------------------------------------------------------------
-- Pure delivery handlers for the unified skill pipeline.
-- Each handler: (skill, ctx) → Result
--
-- Handlers are pure: they never branch on caster type, don't know
-- about staff tips, mana, or cooldowns. Callers resolve origin CFrame
-- and pass it via DeliveryCtx.
--
-- Delivery kinds:
--   instant     — apply onImpact immediately to ctx.target
--   projectile  — spawn N Parts flying toward ctx.target; onImpact on hit
--   aoe         — after windup, scan ctx.aoeCenter for humanoids; onImpact each
--   world_spawn — stub; used for Stone Wall / terrain placements
--
-- ctx.onComplete is called when the delivery fully resolves. Async
-- handlers (projectile, aoe) use task.delay to call it after the
-- last meaningful event. Instant handlers call it synchronously.
-- Callers that don't need a completion signal omit onComplete.
----------------------------------------------------------------------

local Debris        = game:GetService("Debris")
local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService    = game:GetService("RunService")

local Logger       = require(ReplicatedStorage.Shared.Core.Logger)
local SkillEffects = require(ReplicatedStorage.Shared.Skills.SkillEffects)
local SkillTypes   = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local VfxConfig    = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect  = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

type SkillSpec   = SkillTypes.SkillSpec
type DeliveryCtx = SkillTypes.DeliveryCtx

export type Result = { ok: boolean, reason: string? }

local log = Logger.new("SkillDelivery")

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Apply every onImpact effect spec to hitTarget.
-- Returns the first failure encountered, or { ok = true } if all succeed.
local function applyImpactEffects(skill: SkillSpec, hitTarget: any, source: any?): SkillEffects.Result
	local firstFailure: SkillEffects.Result? = nil
	for _, effectSpec in skill.onImpact do
		local result = SkillEffects.apply(effectSpec, hitTarget, source)
		if not result.ok and firstFailure == nil then
			firstFailure = result
		end
	end
	return firstFailure or { ok = true }
end

-- Resolve a position from any target value (BasePart, Humanoid, Model, Vector3).
local function resolveTargetPosition(target: any): Vector3?
	if typeof(target) == "Vector3" then return target :: Vector3 end
	if typeof(target) ~= "Instance" then return nil end
	local inst = target :: Instance
	if inst:IsA("BasePart") then return (inst :: BasePart).Position end
	if inst:IsA("Humanoid") then
		local char = (inst :: Humanoid).Parent
		local hrp = char and (char :: Model):FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then return (hrp :: BasePart).Position end
	end
	if inst:IsA("Model") then
		local hrp = (inst :: Model):FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then return (hrp :: BasePart).Position end
	end
	return nil
end

----------------------------------------------------------------------
-- Delivery handlers
----------------------------------------------------------------------

local SkillDelivery = {}

SkillDelivery.handlers = {

	-- "instant": apply onImpact immediately to ctx.target.
	-- Used by Spark, Fireball, Inferno, Mend, Frost Nip, Stasis, Shield, Sanctuary.
	instant = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local result = applyImpactEffects(skill, ctx.target, ctx.source)
		if ctx.onComplete then ctx.onComplete() end
		return result
	end,

	-- "projectile": spawn deliveryParams.count Parts flying toward ctx.target.
	-- On each hit: applyImpactEffects. After last launch: ctx.onComplete().
	-- deliveryParams: count, speed, spreadDegrees, lifetimeSec,
	--                 proximityRadius, size, color, staggerSec,
	--                 cosmeticEffectId (optional VfxConfig.EFFECTS key —
	--                 attaches a trail/glow/sound burst to each Part).
	projectile = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local params = skill.deliveryParams
		local count:          number  = params.count          or 1
		local speed:          number  = params.speed          or 30
		local spreadDegrees:  number  = params.spreadDegrees  or 0
		local lifetimeSec:    number  = params.lifetimeSec    or 3
		local proximityRadius:number  = params.proximityRadius or 3
		local staggerSec:     number  = params.staggerSec     or 0
		local trackTarget:    boolean = params.trackTarget     or false
		local color:          Color3  = params.color          or Color3.fromRGB(255, 120, 0)
		local cosmeticEffectId: string? = params.cosmeticEffectId
		local sizeRaw                 = params.size            or 1.5
		local sizeVec: Vector3        = typeof(sizeRaw) == "Vector3"
			and (sizeRaw :: Vector3)
			or Vector3.new(sizeRaw, sizeRaw, sizeRaw)

		local targetPos = resolveTargetPosition(ctx.target)
		if not targetPos then
			log:warn(("projectile: no resolvable target position (skill=%s)"):format(skill.name))
			if ctx.onComplete then ctx.onComplete() end
			return { ok = false, reason = "projectile requires a target with a position" }
		end

		local muzzlePos = ctx.origin.Position
		local baseDir   = (targetPos - muzzlePos).Unit
		local source    = ctx.source
		local onComplete = ctx.onComplete

		for i = 1, count do
			task.delay((i - 1) * staggerSec, function()
				local currentTargetPos = (trackTarget and resolveTargetPosition(ctx.target))
					or targetPos
				local currentDir = (currentTargetPos and (currentTargetPos - muzzlePos).Unit)
					or baseDir

				local spreadYaw   = math.rad((math.random() * 2 - 1) * spreadDegrees)
				local spreadPitch = math.rad((math.random() * 2 - 1) * spreadDegrees * 0.4)
				local lookCF      = CFrame.lookAt(Vector3.zero, currentDir)
					* CFrame.Angles(spreadPitch, spreadYaw, 0)
				local dir         = lookCF.LookVector

				local projectile = Instance.new("Part")
				projectile.Name        = "SkillProjectile"
				projectile.Size        = sizeVec
				projectile.Color       = color
				projectile.Material    = Enum.Material.Neon
				projectile.Anchored    = false
				projectile.CanCollide  = false
				projectile.CanQuery    = false
				projectile.CastShadow  = false
				projectile.CFrame      = CFrame.new(muzzlePos)
				projectile.Parent      = workspace

				local att = Instance.new("Attachment", projectile)
				local lv  = Instance.new("LinearVelocity", projectile)
				lv.Attachment0            = att
				lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
				lv.MaxForce               = math.huge
				lv.VectorVelocity         = dir * speed

				Debris:AddItem(projectile, lifetimeSec + 1)

				-- Cosmetic layer: trail/glow/sound that travels with the Part.
				-- Physics ownership stays here; visual layer lives in VfxConfig.
				if cosmeticEffectId then
					local cosmeticEffect = VfxConfig.EFFECTS[cosmeticEffectId]
					if cosmeticEffect then
						spawnEffect(cosmeticEffect, projectile)
					end
				end

				local startTime  = os.clock()
				local hitPlayers: { [Player]: boolean } = {}
				local conn: RBXScriptConnection

				conn = RunService.Heartbeat:Connect(function()
					if not projectile or not projectile.Parent then
						conn:Disconnect()
						return
					end
					if os.clock() - startTime >= lifetimeSec then
						conn:Disconnect()
						projectile:Destroy()
						return
					end

					local pos = projectile.Position
					for _, player in Players:GetPlayers() do
						if hitPlayers[player] then continue end
						local char = player.Character
						if not char then continue end
						local hrp = char:FindFirstChild("HumanoidRootPart")
						if not hrp or not hrp:IsA("BasePart") then continue end
						local hum = char:FindFirstChildOfClass("Humanoid")
						if not hum or hum.Health <= 0 then continue end
						if ((hrp :: BasePart).Position - pos).Magnitude <= proximityRadius then
							hitPlayers[player] = true
							applyImpactEffects(skill, hum, source)
							log:info(("SkillProjectile hit %s (skill=%s)"):format(player.Name, skill.name))
							conn:Disconnect()
							projectile:Destroy()
							return
						end
					end
				end)
			end)
		end

		-- Mark complete after all projectiles are in flight
		task.delay((count - 1) * staggerSec + 0.1, function()
			if onComplete then onComplete() end
		end)

		log:info(("projectile: %d launched (skill=%s)"):format(count, skill.name))
		return { ok = true }
	end,

	-- "aoe": after deliveryParams.windupSec, scan ctx.aoeCenter (or origin.Position)
	-- for all player humanoids within deliveryParams.radius; run onImpact on each.
	-- deliveryParams: radius, windupSec, completeSec,
	--                 cosmeticEffectId (optional VfxConfig.EFFECTS key —
	--                 attached to the shockwave Part at impact).
	aoe = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local params       = skill.deliveryParams
		local radius:       number = params.radius      or 12
		local windupSec:    number = params.windupSec   or 0.5
		local completeSec:  number = params.completeSec or 1.0
		local cosmeticEffectId: string? = params.cosmeticEffectId

		local center = ctx.aoeCenter or ctx.origin.Position
		local source = ctx.source
		local onComplete = ctx.onComplete

		-- Capture center at fire-time (boss may have moved by windup end).
		-- Callers that want to use the boss's position at impact should update
		-- ctx.aoeCenter before calling. Capturing now matches historical behavior.
		task.delay(windupSec, function()
			-- Visual shockwave ring on the ground plane
			local shockwave = Instance.new("Part")
			shockwave.Name        = "SkillShockwave"
			shockwave.Shape       = Enum.PartType.Cylinder
			shockwave.Size        = Vector3.new(0.4, radius * 2, radius * 2)
			shockwave.CFrame      = CFrame.new(center.X, center.Y - 2, center.Z)
				* CFrame.Angles(0, 0, math.pi / 2)
			shockwave.Anchored    = true
			shockwave.CanCollide  = false
			shockwave.Color       = Color3.fromRGB(255, 210, 0)
			shockwave.Material    = Enum.Material.Neon
			shockwave.Transparency = 0.35
			shockwave.Parent      = workspace
			Debris:AddItem(shockwave, 0.5)

			-- Cosmetic layer parallel to projectile branch (see above).
			if cosmeticEffectId then
				local cosmeticEffect = VfxConfig.EFFECTS[cosmeticEffectId]
				if cosmeticEffect then
					spawnEffect(cosmeticEffect, shockwave)
				end
			end

			-- Apply onImpact to all players in radius
			for _, player in Players:GetPlayers() do
				local char = player.Character
				if not char then continue end
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp or not hrp:IsA("BasePart") then continue end
				local hum = char:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health <= 0 then continue end
				local dist = ((hrp :: BasePart).Position - center).Magnitude
				if dist > radius then continue end
				applyImpactEffects(skill, hum, source)
				log:info(("aoe hit %s dist=%.1f (skill=%s)"):format(player.Name, dist, skill.name))
			end
		end)

		-- Mark complete after total animation time
		task.delay(completeSec, function()
			if onComplete then onComplete() end
		end)

		log:info(("aoe started (skill=%s)"):format(skill.name))
		return { ok = true }
	end,

	-- "world_spawn": stub for Stone Wall and terrain placements.
	-- onImpact is typically empty for walls (the Part IS the effect).
	world_spawn = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		log:info(("world_spawn stub — %s at %s"):format(
			skill.name, tostring(ctx.target or ctx.origin.Position)
		))
		if ctx.onComplete then ctx.onComplete() end
		return { ok = true }
	end,
}

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function SkillDelivery.deliver(skill: SkillSpec, ctx: DeliveryCtx): Result
	local handler = SkillDelivery.handlers[skill.delivery]
	if not handler then
		log:warn(("unknown delivery kind: %s (skill=%s)"):format(
			tostring(skill.delivery), skill.name
		))
		if ctx.onComplete then ctx.onComplete() end
		return { ok = false, reason = "unknown delivery kind: " .. tostring(skill.delivery) }
	end
	return handler(skill, ctx)
end

return SkillDelivery
