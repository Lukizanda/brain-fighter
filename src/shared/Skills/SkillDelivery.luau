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
--   projectile  — spawn N Parts flying toward ctx.target; they detonate on
--                 the first rig they touch, on world geometry, or on
--                 lifetime expiry (see the handler's impactRadius notes)
--   aoe         — after windup, scan ctx.aoeCenter for humanoids; onImpact each
--   world_spawn — place a solid barrier in the world (Stone Wall);
--                 server-only, see the handler
--
-- ctx.onComplete is called when the delivery fully resolves. Async
-- handlers (projectile, aoe) use task.delay to call it after the
-- last meaningful event. Instant handlers call it synchronously.
-- Callers that don't need a completion signal omit onComplete.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillBuffs     = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local SkillEffects   = require(ReplicatedStorage.Shared.Skills.SkillEffects)
local SkillInterrupt = require(ReplicatedStorage.Shared.Skills.SkillInterrupt)
local SkillTypes     = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local SkillVisuals   = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local VfxConfig      = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect    = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

type SkillSpec   = SkillTypes.SkillSpec
type DeliveryCtx = SkillTypes.DeliveryCtx

export type Result = { ok: boolean, reason: string? }

local log = Logger.new("SkillDelivery")

-- world_spawn fallbacks, used when a spec omits them. The placement
-- distance only applies to target-less casts (no placement reticle yet);
-- far enough ahead that the wall lands between the caster and whatever
-- they're facing rather than on top of them.
local WALL_PLACE_DISTANCE_STUDS = 12
local WALL_DEFAULT_DURATION_SEC = 6
-- Downward probe that settles the wall's base on the floor. Starts above
-- the nominal foot so a placement point already resting on the ground
-- still finds it.
local WALL_GROUND_PROBE_UP_STUDS = 10
local WALL_GROUND_PROBE_DOWN_STUDS = 60

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

-- VfxConfig entry played where a projectile dies on a shield shell.
local SHIELD_BLOCK_EFFECT_ID = "shield_block"

-- What this skill's onImpact would have taken off `hum` — the price a
-- shield shell pays to swallow the shot. Deliberately mirrors the
-- arithmetic in SkillEffects.damage (flat `amount` vs `fractionOfMaxHP`,
-- times the target's damage amp): a blocked shot has to cost the pool
-- exactly what the same shot landing would have, or blocking becomes a
-- way to launder damage up or down.
local function impactDamageAgainst(skill: SkillSpec, hum: Humanoid): number
	local total = 0
	for _, effectSpec in skill.onImpact do
		if effectSpec.kind ~= "damage" then continue end
		if effectSpec.fractionOfMaxHP then
			total += effectSpec.fractionOfMaxHP * hum.MaxHealth
		else
			total += effectSpec.amount or 0
		end
	end
	return total * SkillBuffs.damageAmp(hum)
end

-- Distance along `delta` at which the segment starting at `from` first
-- enters the sphere, or nil if it never does. Returns 0 when the segment
-- starts inside — a projectile spawned within a shell is already blocked.
--
-- Analytic rather than a shapecast because the shell is a pure gameplay
-- volume with no Part behind it: the bubble ShieldVfx draws is a local
-- cosmetic on each client, invisible to the server that owns boss fire.
local function segmentSphereEntry(from: Vector3, delta: Vector3, center: Vector3, radius: number): number?
	local length = delta.Magnitude
	if length <= 0 then return nil end
	local dir = delta / length

	local toStart = from - center
	local proj    = toStart:Dot(dir)
	local gap     = toStart:Dot(toStart) - radius * radius
	-- Outside and travelling away.
	if gap > 0 and proj > 0 then return nil end

	local discriminant = proj * proj - gap
	if discriminant < 0 then return nil end

	local entry = -proj - math.sqrt(discriminant)
	if entry > length then return nil end
	return math.max(entry, 0)
end

-- CollectionService tags whose tagged Models carry a Humanoid+HRP and
-- should be hittable by projectile collision / splash. The project tags
-- spawned NPCs ("NPC"), the active boss ("Boss"), and dev-mode rigs
-- ("Damageable") — anything carrying any of these counts as a target.
-- Player characters are NOT tagged; they're enumerated via Players.
local DAMAGEABLE_TAGS: { string } = { "Damageable", "NPC", "Boss" }

type Hittable = { hum: Humanoid, hrp: BasePart }

-- Frame-level cache: rebuilt once per Heartbeat and shared across all
-- concurrent in-flight projectiles. Boss Volley fires 30 at once — without
-- this every projectile would re-query CollectionService each tick.
-- Deduped by humanoid so a model carrying multiple tags doesn't double-hit.
local _hittablesCache: { Hittable }? = nil
RunService.Heartbeat:Connect(function()
	_hittablesCache = nil
end)

local function collectHittables(): { Hittable }
	if _hittablesCache then return _hittablesCache end
	local results: { Hittable } = {}
	local seen: { [Humanoid]: true } = {}

	local function tryAdd(model: Instance?)
		if not model or not model:IsA("Model") then return end
		local m = model :: Model
		local hum = m:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if seen[hum] then return end
		local hrp = m:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then return end
		seen[hum] = true
		table.insert(results, { hum = hum, hrp = hrp :: BasePart })
	end

	for _, player in Players:GetPlayers() do
		tryAdd(player.Character)
	end
	for _, tag in DAMAGEABLE_TAGS do
		for _, inst in CollectionService:GetTagged(tag) do
			tryAdd(inst)
		end
	end
	_hittablesCache = results
	return results
end

-- Map a raycast hit back to the rig that owns it, if any. Lets the swept
-- segment test below count a limb/head clip as a real hit — the proximity
-- shell only measures to HumanoidRootPart, so it misses tall or wide rigs
-- the projectile visibly passed through.
local function hittableFromPart(part: BasePart, hittables: { Hittable }): Hittable?
	local node: Instance? = part
	while node and node ~= workspace do
		if node:IsA("Model") then
			local hum = (node :: Model):FindFirstChildOfClass("Humanoid")
			if hum then
				for _, h in hittables do
					if h.hum == hum then return h end
				end
				return nil
			end
		end
		node = node.Parent
	end
	return nil
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
	-- Used by Inferno, Mend, Frost Nip, Stasis, Shield, Sanctuary.
	-- (Firebolt and Fireball are projectile delivery — see below.)
	instant = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local result = applyImpactEffects(skill, ctx.target, ctx.source)
		if ctx.onComplete then ctx.onComplete() end
		return result
	end,

	-- "projectile": spawn deliveryParams.count Parts flying toward ctx.target.
	-- After last launch: ctx.onComplete().
	--
	-- A projectile detonates on whichever comes first each Heartbeat:
	--   1. lifetime expiry              (cause="expiry")
	--   2. a swept ray over this frame's step hitting world geometry or a
	--      rig's limb — this is what stops the shot from passing through
	--      walls and from tunnelling past a target on a frame hitch
	--                                   (cause="impact")
	--   3. an HRP within proximityRadius (cause="proximity")
	--   4. closest approach to ctx.target while inside impactRadius — the
	--      proximity fuze, splash spells only
	--                                   (cause="fuze")
	-- Every path routes through detonate(), so splash spells damage on all
	-- four. When impactRadius == 0 the fuze is off and only a direct hit
	-- (2 or 3) damages.
	--
	-- deliveryParams:
	--   count, speed, spreadDegrees, lifetimeSec, proximityRadius, size,
	--   color, staggerSec
	--   trackTarget       — if true, re-resolve target position at each
	--                       per-shot launch. Falls back to the cached
	--                       targetPos if the target dies/despawns
	--                       between fire-time and the staggered launch.
	--                       In-flight projectiles do NOT curve after
	--                       launch.
	--   impactRadius      — if > 0, on detonation applyImpactEffects fires
	--                       for every hittable within this radius of the
	--                       detonation position (splash) — including when
	--                       the projectile detonated on a wall or expired
	--                       in mid-air, so a near-miss still deals damage.
	--                       0 = single-target: only a directly struck
	--                       humanoid takes damage, and a wall/expiry
	--                       detonation deals none.
	--   impactEffectId    — optional VfxConfig.EFFECTS key spawned at the
	--                       impact position. For impactRadius == 0 the
	--                       burst anchors to the hit humanoid's HRP; for
	--                       impactRadius > 0 it anchors to the shockwave.
	--   impactColor       — optional shockwave color tint. impactRadius > 0
	--                       only.
	--   cosmeticEffectId  — optional VfxConfig.EFFECTS key attached to
	--                       each moving Part as a trail/glow.
	projectile = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local params = skill.deliveryParams
		local count:          number  = params.count          or 1
		local speed:          number  = params.speed          or 30
		local spreadDegrees:  number  = params.spreadDegrees  or 0
		local lifetimeSec:    number  = params.lifetimeSec    or 3
		local proximityRadius:number  = params.proximityRadius or 3
		local staggerSec:     number  = params.staggerSec     or 0
		local trackTarget:    boolean = params.trackTarget     or false
		local impactRadius:   number  = params.impactRadius    or 0
		local color:          Color3  = params.color          or Color3.fromRGB(255, 120, 0)
		local cosmeticEffectId: string? = params.cosmeticEffectId
		local impactEffectId:   string? = params.impactEffectId
		local impactColor:      Color3? = params.impactColor
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

		-- Resolve a projectile's impact at hitPos, then destroy the Part.
		--   victim ~= nil → something was struck directly (proximity shell,
		--                   or a swept ray that clipped its rig).
		--   victim == nil → world geometry or lifetime expiry.
		-- A splash projectile detonates either way: the blast is what deals
		-- the damage, so gating it behind a direct hit meant a Fireball
		-- landing a stud wide of an enemy — or expiring in mid-air — dealt
		-- nothing at all despite a 7-stud blast radius.
		local function detonate(part: BasePart, hitPos: Vector3, victim: Hittable?, cause: string)
			if impactRadius > 0 then
				-- spawnShockwave anchors the impact burst to itself via
				-- cosmeticEffectId. collectHittables() is frame-cached, so
				-- this re-read returns the same snapshot the caller tested
				-- against — a humanoid inside proximityRadius is guaranteed
				-- to also be considered for splash.
				SkillVisuals.spawnShockwave(hitPos, impactRadius, {
					color            = impactColor,
					cosmeticEffectId = impactEffectId,
				})
				local struck = 0
				for _, h in collectHittables() do
					if h.hum.Parent == source then continue end -- skip caster
					if h.hum.Health <= 0 then continue end
					if (h.hrp.Position - hitPos).Magnitude <= impactRadius then
						applyImpactEffects(skill, h.hum, source)
						struck += 1
					end
				end
				log:info(("SkillProjectile splash @ %s r=%.1f struck=%d cause=%s (skill=%s)"):format(
					tostring(hitPos), impactRadius, struck, cause, skill.name
				))
			elseif victim then
				-- Single-target: apply effects to the struck humanoid only.
				-- Anchor the impact burst on its HRP.
				applyImpactEffects(skill, victim.hum, source)
				if impactEffectId then
					local impactEffect = VfxConfig.EFFECTS[impactEffectId]
					if impactEffect then
						spawnEffect(impactEffect, victim.hrp)
					end
				end
				log:info(("SkillProjectile hit %s cause=%s (skill=%s)"):format(
					victim.hum.Parent and victim.hum.Parent.Name or "?", cause, skill.name
				))
			else
				-- Single-target projectile that stopped on nothing damageable.
				log:info(("SkillProjectile spent @ %s cause=%s (skill=%s)"):format(
					tostring(hitPos), cause, skill.name
				))
			end
			part:Destroy()
		end

		-- A projectile that reaches a shielded rig's shell dies there. The
		-- pool pays the shot's full damage and the Part is consumed, so
		-- nothing reaches the holder — including splash, which is why a
		-- shielded player also covers whoever is standing next to them.
		--
		-- Absorption is deliberately not partial: a pool with 5 left still
		-- swallows a 20-damage shot whole and pops. "The shield saved you
		-- and broke doing it" reads better than a shot that half-lands, and
		-- the shell only ever sees projectiles, so this can't be used to eat
		-- an instant-delivery nuke like Inferno. Damage that arrives any
		-- other way still goes through applyDamage's shieldModifier, which
		-- *does* split partially.
		local function blockOnShell(part: BasePart, victim: Hittable, contact: Vector3)
			local cost     = impactDamageAgainst(skill, victim.hum)
			local absorbed = SkillBuffs.consumeShield(victim.hum, cost)
			SkillVisuals.spawnEffectAtPoint(contact, SHIELD_BLOCK_EFFECT_ID)
			log:info(("SkillProjectile blocked by shield on %s absorbed=%.1f left=%.1f (skill=%s)"):format(
				victim.hum.Parent and victim.hum.Parent.Name or "?",
				absorbed,
				SkillBuffs.getShield(victim.hum),
				skill.name
			))
			part:Destroy()
		end

		-- Nearest shell this frame's step enters, if any. Caster excluded
		-- for the same reason they're excluded from the raycast: their own
		-- bubble sits over the muzzle, and every shot would die in it.
		local function nearestShellEntry(from: Vector3, step: Vector3, hittables: { Hittable }): (Hittable?, number, Vector3)
			local nearest: Hittable? = nil
			local nearestDist = math.huge
			local contact = from
			for _, h in hittables do
				if h.hum.Parent == source then continue end
				if SkillBuffs.getShield(h.hum) <= 0 then continue end
				local entry = segmentSphereEntry(from, step, h.hrp.Position, SkillBuffs.SHELL_RADIUS_STUDS)
				if entry and entry < nearestDist then
					nearest     = h
					nearestDist = entry
					contact     = from + step.Unit * entry
				end
			end
			return nearest, nearestDist, contact
		end

		-- Register a cancellation token tied to the caster so freeze (or any
		-- future interrupt) can stop pending volley shots from launching.
		-- In-flight projectiles are independent of the token by design.
		local castToken = SkillInterrupt.begin(source)

		for i = 1, count do
			task.delay((i - 1) * staggerSec, function()
				if castToken.cancelled then return end
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

				local startTime = os.clock()
				local lastPos   = muzzlePos
				-- Seeded at infinity so the fuze can never fire on its first
				-- sample — it needs a previous frame to compare against.
				local lastTargetDist = math.huge
				local conn: RBXScriptConnection

				-- Swept-segment filter. The caster is excluded because the
				-- muzzle sits inside their own rig (and the staff Tip is a
				-- descendant of it); the projectile because a ray must not
				-- stop on its own origin Part. Other in-flight projectiles
				-- are already invisible to it (CanQuery = false), and
				-- RespectCanCollide keeps shockwaves and decorative parts
				-- from blocking the shot — only real geometry and rigs do.
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = if source
					then { projectile :: Instance, source :: Instance }
					else { projectile :: Instance }
				rayParams.IgnoreWater = true
				rayParams.RespectCanCollide = true

				conn = RunService.Heartbeat:Connect(function()
					if not projectile or not projectile.Parent then
						conn:Disconnect()
						return
					end

					local pos = projectile.Position
					-- Snapshot all hittables this tick (players + tagged NPCs +
					-- boss + Damageable rigs). detonate() re-reads the same
					-- frame-cached table.
					local hittables = collectHittables()

					if os.clock() - startTime >= lifetimeSec then
						conn:Disconnect()
						detonate(projectile, pos, nil, "expiry")
						return
					end

					-- Swept test before the endpoint test: it reports the
					-- earliest blocker along this frame's step, which the
					-- endpoint-only proximity shell can step clean over. At
					-- Fireball's 55 studs/s a 55 ms frame advances further
					-- than the 3-stud shell is wide.
					local step = pos - lastPos
					if step.Magnitude > 0 then
						local rayHit = workspace:Raycast(lastPos, step, rayParams)
						local rayDist = if rayHit
							then (rayHit.Position - lastPos).Magnitude
							else math.huge

						-- Shield shells are swept against the same segment and
						-- the nearer blocker wins. Tested here rather than after
						-- the raycast because a shot that would clip a limb this
						-- frame still had to cross the bubble to reach it — and
						-- the shell is invisible to Raycast by construction (no
						-- Part backs it; the bubble is a per-client cosmetic).
						local shellVictim, shellDist, shellContact =
							nearestShellEntry(lastPos, step, hittables)
						if shellVictim and shellDist <= rayDist then
							conn:Disconnect()
							blockOnShell(projectile, shellVictim, shellContact)
							return
						end

						if rayHit then
							conn:Disconnect()
							detonate(
								projectile,
								rayHit.Position,
								hittableFromPart(rayHit.Instance, hittables),
								"impact"
							)
							return
						end
					end
					lastPos = pos

					for _, h in hittables do
						if h.hum.Parent == source then continue end -- skip caster
						if (h.hrp.Position - pos).Magnitude <= proximityRadius then
							conn:Disconnect()
							-- The shell is wider than any proximity radius in the
							-- roster, so a shielded rig is normally caught by the
							-- swept test above. This is the degenerate case: a
							-- projectile that materialised inside the shell with
							-- no step to sweep (stationary target, first frame).
							if SkillBuffs.getShield(h.hum) > 0 then
								blockOnShell(projectile, h, pos)
							else
								detonate(projectile, pos, h, "proximity")
							end
							return
						end
					end

					-- Proximity fuze — splash spells only, intended target only.
					-- The shot is aimed where the target stood at launch and
					-- never curves, so a target that strafes during the flight
					-- is routinely missed by the 3-stud shell while still well
					-- inside a 7-stud blast radius; expiry doesn't save it
					-- either, since a Fireball outruns its target by ~80 studs
					-- before the timer runs out. Detonating at closest approach
					-- is what actually converts those near-misses into damage:
					-- once we're inside impactRadius and the gap starts
					-- widening, this frame is as close as the shot will get.
					-- Restricted to ctx.target so a bystander standing near the
					-- muzzle can't fuze the shot the moment it leaves the staff.
					if impactRadius > 0 then
						local livePos = resolveTargetPosition(ctx.target)
						if livePos then
							local dist = (livePos - pos).Magnitude
							if dist <= impactRadius and dist > lastTargetDist then
								conn:Disconnect()
								detonate(projectile, pos, nil, "fuze")
								return
							end
							lastTargetDist = dist
						end
					end
				end)
			end)
		end

		-- Mark complete after all projectiles are in flight
		task.delay((count - 1) * staggerSec + 0.1, function()
			SkillInterrupt.finish(source, castToken)
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

		-- Token gates the windup task.delay so a frozen caster can't drop a
		-- slam mid-telegraph. Mirrors the projectile branch — only future
		-- scheduled work is blocked.
		local castToken = SkillInterrupt.begin(source)

		-- Capture center at fire-time (boss may have moved by windup end).
		-- Callers that want to use the boss's position at impact should update
		-- ctx.aoeCenter before calling. Capturing now matches historical behavior.
		task.delay(windupSec, function()
			if castToken.cancelled then return end
			-- Visual shockwave ring on the ground plane. SkillVisuals
			-- owns the geometry + cosmetic-effect attachment; this branch
			-- only chooses what to render.
			SkillVisuals.spawnShockwave(center, radius, {
				cosmeticEffectId = cosmeticEffectId,
			})

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
			SkillInterrupt.finish(source, castToken)
			if onComplete then onComplete() end
		end)

		log:info(("aoe started (skill=%s)"):format(skill.name))
		return { ok = true }
	end,

	-- "world_spawn": place a solid barrier in the world (Stone Wall).
	-- The Part IS the effect, so onImpact is normally empty.
	--
	-- Server-only by design. An anchored Part created on a client is
	-- local to that client — it wouldn't block the server-owned boss, and
	-- the server's own copy replicates down anyway, so spawning on both
	-- would double the wall. The client branch returns ok so CastAction
	-- doesn't refund a cast that the server is about to honour.
	--
	-- deliveryParams: durationSec, size (Vector3), color,
	--                 placeDistanceStuds, cosmeticEffectId.
	world_spawn = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local params = skill.deliveryParams
		local onComplete = ctx.onComplete

		if not RunService:IsServer() then
			if onComplete then onComplete() end
			return { ok = true }
		end

		-- Placement mode hands us a Vector3; until the placement reticle
		-- ships, a target-less cast drops the wall a fixed distance ahead
		-- of the caster, standing across their facing.
		local placeDistance: number = params.placeDistanceStuds or WALL_PLACE_DISTANCE_STUDS
		local footCFrame: CFrame
		local explicitPos = typeof(ctx.target) == "Vector3" and (ctx.target :: Vector3) or nil
		if explicitPos then
			-- Face the wall back toward the caster so its broad side blocks.
			local flatToCaster = Vector3.new(
				ctx.origin.Position.X - explicitPos.X,
				0,
				ctx.origin.Position.Z - explicitPos.Z
			)
			footCFrame = flatToCaster.Magnitude > 0
				and CFrame.lookAt(explicitPos, explicitPos + flatToCaster.Unit)
				or CFrame.new(explicitPos)
		else
			-- Face off the caster's rig, not ctx.origin: origin is the staff
			-- Tip attachment, whose LookVector tracks wherever the weapon
			-- happens to be swung rather than where the player is looking.
			local placeFrom = ctx.origin
			if ctx.source and ctx.source:IsA("Model") then
				local hrp = (ctx.source :: Model):FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					placeFrom = (hrp :: BasePart).CFrame
				end
			end
			local look = placeFrom.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			flatLook = flatLook.Magnitude > 0 and flatLook.Unit or Vector3.new(0, 0, -1)
			local footPos = placeFrom.Position + flatLook * placeDistance
			footCFrame = CFrame.lookAt(footPos, footPos - flatLook)
		end

		-- Drop the foot onto whatever's underneath. Both branches above
		-- derive their height from a rig's HumanoidRootPart or a reticle
		-- hit, either of which can sit well above the floor — without this
		-- the wall hovers and the boss walks under it.
		local groundParams = RaycastParams.new()
		groundParams.FilterType = Enum.RaycastFilterType.Exclude
		groundParams.FilterDescendantsInstances = ctx.source and { ctx.source :: Instance } or {}
		groundParams.IgnoreWater = true
		-- Non-negotiable: the arena is full of non-collidable trigger volumes
		-- (SpawnZoneBox, block spawn volumes) that sit metres above the floor.
		-- Without this the probe stops on one of them and the wall hovers in
		-- mid-air with a gap the boss walks straight under.
		groundParams.RespectCanCollide = true
		local groundHit = workspace:Raycast(
			footCFrame.Position + Vector3.new(0, WALL_GROUND_PROBE_UP_STUDS, 0),
			Vector3.new(0, -WALL_GROUND_PROBE_DOWN_STUDS, 0),
			groundParams
		)
		if groundHit then
			footCFrame = CFrame.lookAt(groundHit.Position, groundHit.Position + footCFrame.LookVector)
		end

		local barrier = SkillVisuals.spawnBarrier(footCFrame, {
			size             = params.size,
			color            = params.color,
			lifetimeSec      = params.durationSec,
			cosmeticEffectId = params.cosmeticEffectId,
		})

		-- Effects still run if a spec declares them (e.g. a future wall
		-- that also knocks back whatever it materialises through).
		local result = #skill.onImpact > 0
			and applyImpactEffects(skill, ctx.target, ctx.source)
			or { ok = true }

		log:info(("world_spawn: %s placed at %s (lifetime=%.1fs)"):format(
			skill.name,
			tostring(barrier.Position),
			(params.durationSec or WALL_DEFAULT_DURATION_SEC) :: number
		))
		if onComplete then onComplete() end
		return result
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
