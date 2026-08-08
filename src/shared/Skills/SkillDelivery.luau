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
--   world_spawn — place a solid barrier in the world (Stone Wall)
--
-- EVERY handler is authoritative-only (Phase 5.6 Stage 4). A run with
-- ctx.mode == "predicted" returns ok immediately, having spawned nothing,
-- hit-tested nothing and written nothing. `world_spawn` was the first to
-- work this way and is now simply the least surprising of the four.
--
-- That means this module no longer branches on RunService:IsServer() at
-- all. It runs on the server, or it does nothing. Anything a player has to
-- see is described to the clients via VfxBroadcast / ProjectileVfxEvent
-- and drawn there — see wiki/design/client-server-boundary.md.
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
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local SkillEffects   = require(ReplicatedStorage.Shared.Skills.SkillEffects)
local SkillInterrupt = require(ReplicatedStorage.Shared.Skills.SkillInterrupt)
local SkillTypes     = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local SkillVisuals   = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local VfxConfig      = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

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
--
-- Only the authoritative run applies anything. Damage, heals, freezes,
-- shields and buffs all write state that belongs to somebody else — the
-- victim's Humanoid, their character's attributes — and a predicted run
-- may only write what its own client already owns. Both runs used to do
-- all of it, and it appeared to work solely because a client's writes to a
-- server-owned rig are local and get corrected by replication a moment
-- later. That is not agreement; it is the server overwriting a second,
-- unrelated simulation.
--
-- Nothing is validated here on the predicted path either. CastAction has
-- already asked `SpellExecutor.canCast` whether this could land, before it
-- drained (see wiki/design/client-server-boundary.md, Stage 5), so
-- re-deriving the same answer at impact would tell nobody anything.
--
-- The gate is here rather than inside SkillEffects deliberately.
-- SkillEffects is the layer that does the writing; whether a write should
-- happen at all is its caller's business, and the caller is the one
-- holding the run context.
local function applyImpactEffects(
	skill: SkillSpec,
	hitTarget: any,
	source: any?,
	mode: SkillTypes.DeliveryMode
): SkillEffects.Result
	if mode ~= "authoritative" then return { ok = true } end

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

-- VfxConfig entry played where a projectile dies with nothing else to
-- announce it — see the entry's own comment for why every shot needs an
-- audible death. Overridable per-spell via deliveryParams.destroyEffectId;
-- the default is what makes it apply to the whole roster without touching
-- every spec.
local DEFAULT_DESTROY_EFFECT_ID = "projectile_destroy"

-- Tells every client to draw its own copy of a shot. Resolved lazily:
-- SkillDelivery is required during server boot (BossService), and a
-- module-scope WaitForChild would stall that indefinitely if the remote
-- were ever missing rather than failing one cast.
local _projectileVfxEvent: RemoteEvent? = nil
local function projectileVfxRemote(): RemoteEvent?
	if _projectileVfxEvent then return _projectileVfxEvent end
	local remotes = ReplicatedStorage.Shared.Vfx:FindFirstChild("Remotes")
	local found = remotes and remotes:FindFirstChild("ProjectileVfxEvent")
	if found and found:IsA("RemoteEvent") then
		_projectileVfxEvent = found :: RemoteEvent
	end
	return _projectileVfxEvent
end

-- CollectionService tags whose tagged Models carry a Humanoid+HRP and
-- should be hittable by projectile collision / splash. The project tags
-- spawned NPCs ("NPC"), the active boss ("Boss"), and dev-mode rigs
-- ("Damageable") — anything carrying any of these counts as a target.
-- Player characters are NOT tagged; they're enumerated via Players.
--
-- Shared with FreezeVfxController, which watches the same set for the
-- `_frozen` flag. A rig in one list but not the other would be hittable
-- without ever drawing its status visual.
local DAMAGEABLE_TAGS: { string } = SkillConstants.DAMAGEABLE_TAGS

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
		local result = applyImpactEffects(skill, ctx.target, ctx.source, ctx.mode)
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
	--                       impactRadius > 0 it anchors to the shockwave,
	--                       or to a throwaway point anchor when
	--                       impactRing is false.
	--   impactColor       — optional shockwave color tint. impactRadius > 0
	--                       and impactRing only.
	--   impactRing        — default true: a splash detonation draws the
	--                       neon ground disc (SkillVisuals.spawnShockwave)
	--                       sized to impactRadius. False keeps the splash
	--                       and its burst but skips the disc, for spells
	--                       whose impact effect already reads as an
	--                       explosion on its own — see Fireball. Radius
	--                       legibility is the tradeoff being made: the disc
	--                       is the only thing that shows the blast's exact
	--                       reach, so turn it off only where the burst is
	--                       big enough to imply it. impactRadius > 0 only.
	--   cosmeticEffectId  — optional VfxConfig.EFFECTS key attached to
	--                       each moving Part as a trail/glow. Its Sound is
	--                       a child of that Part, so it is cut off when the
	--                       shot dies — trails only, not one-shot cues.
	--   launchEffectId    — optional VfxConfig.EFFECTS key fired once at the
	--                       muzzle, on its own anchor so the shot's death
	--                       can't truncate it. Where a firing cue belongs.
	--   destroyEffectId   — optional VfxConfig.EFFECTS key for a death that
	--                       nothing else announces (wall, expiry). Defaults
	--                       to DEFAULT_DESTROY_EFFECT_ID; ignored entirely
	--                       for splash shots, which always cue themselves.
	--   consumeOnHit      — default true: the first rig the shot reaches
	--                       consumes it. False pierces — onImpact lands once
	--                       per rig and the shot flies on. Walls, shields
	--                       and expiry still end it. Forced true when
	--                       impactRadius > 0.
	projectile = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		-- Authoritative only, the same way world_spawn already was.
		--
		-- A predicted run used to spawn its own Part here and run a full
		-- swept-ray hit-detection loop against it, in parallel with the
		-- server doing the same against a different Part on a different
		-- physics timeline. Two rigid bodies, two answers, and the one the
		-- player watched was not the one that counted — which is what made
		-- a shot appear to sail 4.7 studs through a shield bubble before
		-- commit a6b94b3 papered over it.
		--
		-- Now there is one shot. The server owns it, and every client draws
		-- its own cosmetic from the broadcast below.
		if ctx.mode ~= "authoritative" then
			if ctx.onComplete then ctx.onComplete() end
			return { ok = true }
		end

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
		local impactRing:       boolean = params.impactRing ~= false
		-- Fired once at the muzzle, and deliberately NOT folded into
		-- cosmeticEffectId: that one parents its Sound to the moving Part,
		-- so the shot's own destruction cuts the sound off mid-play. A
		-- launch cue also belongs where the shot was fired from, not
		-- wherever it happens to be when it dies.
		local launchEffectId: string? = params.launchEffectId

		-- Does the shot end on the rig it hits?
		--
		-- True — the default, and what the entire roster does today — means
		-- the first rig a shot reaches consumes it. False makes it pierce:
		-- onImpact lands on that rig once, the rig stops blocking it, and it
		-- carries on to whatever is behind. Walls, shield shells and expiry
		-- still end the shot either way.
		--
		-- Forced true for splash, which is not a coherent piercing weapon: a
		-- blast that re-detonates on every rig it passes through would stack
		-- its own damage, and impactRadius already reaches past the rig that
		-- triggered it.
		local consumeOnHit: boolean = if impactRadius > 0
			then true
			else params.consumeOnHit ~= false
		-- Splash projectiles fire their impact burst on *every* detonation
		-- cause — wall, expiry, direct hit alike — so they already announce
		-- their own death and want no second cue. True whether or not the
		-- ring is drawn: the burst is the announcement, the disc is silent.
		-- Only single-target shots can die silently, so only they get this.
		local destroyEffectId: string? = if impactRadius > 0
			then nil
			else (params.destroyEffectId or DEFAULT_DESTROY_EFFECT_ID)
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

		-- Every cosmetic below goes to EVERY client, the caster included,
		-- and that is why `ctx.predictedBy` is deliberately not consulted
		-- here despite being available.
		--
		-- `predictedBy` means "that client already drew this itself". Until
		-- Stage 4 it did: the predicted run spawned its own visible shot on
		-- the frame it fired, so the broadcast had to skip the caster or
		-- they saw two. The predicted run now returns above without drawing
		-- anything, so skipping them would leave the caster staring at an
		-- invisible shot — the exact class of bug this pipeline has shipped
		-- four times.
		--
		-- Stage 6 reintroduces the exclusion for precisely the cues its
		-- prediction layer draws (the muzzle flash and cast SFX), and for
		-- nothing else.
		--
		-- Captured for the detonation closures below, which outlive this
		-- call by whole seconds and must not reach back through ctx.
		local mode = ctx.mode

		-- Resolve a projectile's impact at hitPos, then destroy the Part.
		--   victim ~= nil → something was struck directly (proximity shell,
		--                   or a swept ray that clipped its rig).
		--   victim == nil → world geometry or lifetime expiry.
		-- A splash projectile detonates either way: the blast is what deals
		-- the damage, so gating it behind a direct hit meant a Fireball
		-- landing a stud wide of an enemy — or expiring in mid-air — dealt
		-- nothing at all despite a 7-stud blast radius.
		local function detonate(part: BasePart, hitPos: Vector3, victim: Hittable?, cause: string)
			-- Did anything below already make this death audible? Drives the
			-- fallback cue at the end. Splash never reaches it (destroyEffectId
			-- is nil for impactRadius > 0), so only the direct-hit branch sets
			-- it — a single-target spec with no impactEffectId lands silently
			-- and wants the fallback.
			local cued = false
			if impactRadius > 0 then
				-- Two ways to draw a splash, and they differ only in whether
				-- the ground disc is part of it. Both put the burst at
				-- `hitPos`: spawnShockwave anchors it to the ring via
				-- cosmeticEffectId, spawnEffectAtPoint builds a throwaway
				-- anchor for it. The second path exists because a Part
				-- created this frame arrives nil on clients that haven't
				-- replicated it — which is exactly why there is a
				-- position-based primitive to fall back to.
				if impactRing then
					SkillVisuals.spawnShockwave(hitPos, impactRadius, {
						color            = impactColor,
						cosmeticEffectId = impactEffectId,
					})
				elseif impactEffectId then
					SkillVisuals.spawnEffectAtPoint(hitPos, impactEffectId)
				end
				-- collectHittables() is frame-cached, so this re-read returns
				-- the same snapshot the caller tested against — a humanoid
				-- inside proximityRadius is guaranteed to also be considered
				-- for splash.
				local struck = 0
				for _, h in collectHittables() do
					if h.hum.Parent == source then continue end -- skip caster
					if h.hum.Health <= 0 then continue end
					if (h.hrp.Position - hitPos).Magnitude <= impactRadius then
						applyImpactEffects(skill, h.hum, source, mode)
						struck += 1
					end
				end
				log:info(("SkillProjectile splash @ %s r=%.1f struck=%d cause=%s (skill=%s)"):format(
					tostring(hitPos), impactRadius, struck, cause, skill.name
				))
			elseif victim then
				-- Single-target: apply effects to the struck humanoid only.
				-- Anchor the impact burst on its HRP.
				applyImpactEffects(skill, victim.hum, source, mode)
				-- Presence in EFFECTS still gates `cued`, not just a non-nil
				-- id: a spec pointing at an entry that was never authored
				-- announces nothing, and should still fall through to the
				-- destroy cue below rather than dying silently.
				if impactEffectId and VfxConfig.EFFECTS[impactEffectId] then
					SkillVisuals.spawnEffectOn(impactEffectId, victim.hrp)
					cued = true
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

			-- The death cue is raised by every client's own
			-- CosmeticProjectile, which fires `destroyEffectId` straight from
			-- the payload. Before Stage 4 this branch existed to cover the
			-- caster, whose client skipped the broadcast because it was
			-- drawing its own shot. Nobody skips it now, so raising it here
			-- as well would simply double it for everyone.
			--
			-- `cued` still matters: it is read by the shield-block and
			-- impact paths above to decide whether this shot already
			-- announced itself.
			part:Destroy()
		end

		-- The shell is measured to the projectile's centre, so without this a
		-- fireball whose 2-stud body visibly clips the bubble — but whose
		-- centre passes outside it — flies straight through. On screen that
		-- is a shot hitting the shield and not being destroyed. Padding by
		-- the half-extent makes contact surface-to-surface, the way it looks.
		local shellPadding = math.max(sizeVec.X, sizeVec.Y, sizeVec.Z) * 0.5

		-- A projectile that reaches a shielded rig's shell is destroyed there.
		-- Nothing reaches the holder — including splash, which is why a
		-- shielded player also covers whoever is standing next to them.
		--
		-- The pool is charged a flat `SHELL_BLOCK_COST` per deflection, not
		-- the shot's damage. Deflecting is a barrier doing its job; only
		-- damage that actually lands on the body drains the pool at full
		-- value, and that path still runs through applyDamage's
		-- shieldModifier untouched.
		local function blockOnShell(part: BasePart, victim: Hittable, contact: Vector3)
			local absorbed = SkillBuffs.consumeShield(victim.hum, SkillBuffs.SHELL_BLOCK_COST)
			-- The spark that proves the bubble worked. Boss fire is
			-- server-only, so before the broadcast existed this burst was
			-- emitted on the server and rendered for nobody — the shield
			-- looked like it was doing nothing even when it was.
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
				local entry = SkillBuffs.shellEntry(from, step, h.hrp.Position, shellPadding)
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

				-- Keep simulation on the server.
				--
				-- Roblox hands network ownership of a free-moving part to the
				-- nearest player, so a shot aimed at someone ends up simulated
				-- by the very client it is about to hit. Their copy runs ahead
				-- of the server's, which means a projectile the server has
				-- already destroyed on a shield shell keeps travelling on
				-- screen — measured at up to 4.7 studs past the block point,
				-- deep inside the bubble and frequently through the body. The
				-- shield looked like it was being ignored even though nothing
				-- ever landed.
				--
				-- It is also the wrong trust boundary independent of the
				-- visuals: the client being shot at should not own the bullet.
				-- Throws on parts with no simulated assembly; a projectile
				-- that failed to set up is not worth taking the cast down.
				pcall(function()
					projectile:SetNetworkOwner(nil)
				end)

				Debris:AddItem(projectile, lifetimeSec + 1)

				-- Visual/authority split. This shot decides what happens and
				-- is never the one you see: invisible, no trail, while every
				-- client draws its own CosmeticProjectile from the broadcast.
				--
				-- The reason is that clients render server-owned parts a beat
				-- behind the server, so the real shot used to vanish ~12 studs
				-- short of a shield bubble instead of on it. Drawing the
				-- cosmetic locally on each client puts the visible shot where
				-- that client sees the block happen.
				--
				-- `predictedBy` is not sent. Nothing is drawn by prediction
				-- any more, so every client — the caster included — needs this
				-- payload. Stage 6 will send it again once its prediction
				-- layer starts drawing the muzzle cue locally.
				do
					projectile.Transparency = 1
					local remote = projectileVfxRemote()
					if remote then
						remote:FireAllClients({
							origin           = muzzlePos,
							direction        = dir,
							speed            = speed,
							size             = sizeVec,
							color            = color,
							lifetimeSec      = lifetimeSec,
							cosmeticEffectId = cosmeticEffectId,
							launchEffectId   = launchEffectId,
							proximityRadius  = proximityRadius,
							consumeOnHit     = consumeOnHit,
							-- nil for splash shots, which already announce
							-- every death server-side via the shockwave.
							destroyEffectId  = destroyEffectId,
							-- Not for playback — it tells the cosmetic whether
							-- a *direct rig hit* is already covered by the
							-- server's impact burst, so it can stay quiet for
							-- that one cause and still thud on walls.
							hasImpactCue     = impactEffectId ~= nil,
							source           = source,
						})
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

				-- Rigs this shot has already spent its effects on. Piercing
				-- only. Without it a rig sitting inside proximityRadius is
				-- re-damaged on every frame the shot is still overlapping it,
				-- which for a 3-stud radius is several frames of free hits.
				local pierced: { [Humanoid]: true } = {}

				-- Land the shot's effects on a rig and keep flying. Adding the
				-- rig to the ray filter is what physically lets it through:
				-- otherwise the very next sweep stops on the same body again.
				local function pierceThrough(victim: Hittable)
					if pierced[victim.hum] then return end
					pierced[victim.hum] = true

					applyImpactEffects(skill, victim.hum, source, mode)
					if impactEffectId then
						SkillVisuals.spawnEffectOn(impactEffectId, victim.hrp)
					end

					local rig = victim.hum.Parent
					if rig then
						local filter = rayParams.FilterDescendantsInstances
						table.insert(filter, rig)
						-- Reassigned, not mutated in place: the property returns
						-- a copy, so appending to it alone changes nothing.
						rayParams.FilterDescendantsInstances = filter
					end

					log:info(("SkillProjectile pierced %s (skill=%s)"):format(
						rig and rig.Name or "?", skill.name
					))
				end

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
							local rayVictim = hittableFromPart(rayHit.Instance, hittables)
							-- A piercing shot passes through rigs only. Anything
							-- the ray stopped on that isn't a rig is a wall, and
							-- a wall ends every shot.
							if rayVictim and not consumeOnHit then
								pierceThrough(rayVictim)
							else
								conn:Disconnect()
								detonate(projectile, rayHit.Position, rayVictim, "impact")
								return
							end
						end
					end
					lastPos = pos

					for _, h in hittables do
						if h.hum.Parent == source then continue end -- skip caster
						if pierced[h.hum] then continue end
						if (h.hrp.Position - pos).Magnitude <= proximityRadius then
							-- The shell is wider than any proximity radius in the
							-- roster, so a shielded rig is normally caught by the
							-- swept test above. This is the degenerate case: a
							-- projectile that materialised inside the shell with
							-- no step to sweep (stationary target, first frame).
							--
							-- A shell stops a piercing shot too: the bubble is a
							-- barrier, not a body, and nothing gets past it.
							if SkillBuffs.getShield(h.hum) > 0 then
								conn:Disconnect()
								blockOnShell(projectile, h, pos)
								return
							end
							if consumeOnHit then
								conn:Disconnect()
								detonate(projectile, pos, h, "proximity")
								return
							end
							pierceThrough(h)
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
		-- Authoritative only, for the same reason as projectile: a predicted
		-- run scanned the same radius against the same rigs and applied the
		-- same effects, in parallel with the server doing it. The windup ring
		-- is broadcast, so every client still sees the telegraph.
		if ctx.mode ~= "authoritative" then
			if ctx.onComplete then ctx.onComplete() end
			return { ok = true }
		end

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
				-- Reaches every client. Nothing draws this locally any more
				-- — see the note in the projectile handler.
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
				applyImpactEffects(skill, hum, source, ctx.mode)
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
	--                 placeDistanceStuds, cosmeticEffectId, riseSec.
	world_spawn = function(skill: SkillSpec, ctx: DeliveryCtx): Result
		local params = skill.deliveryParams
		local onComplete = ctx.onComplete

		if ctx.mode ~= "authoritative" then
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

		SkillVisuals.spawnBarrier(footCFrame, {
			size             = params.size,
			color            = params.color,
			lifetimeSec      = params.durationSec,
			cosmeticEffectId = params.cosmeticEffectId,
			riseSec          = params.riseSec,
		})

		-- Effects still run if a spec declares them (e.g. a future wall
		-- that also knocks back whatever it materialises through).
		local result = #skill.onImpact > 0
			and applyImpactEffects(skill, ctx.target, ctx.source, ctx.mode)
			or { ok = true }

		-- The foot, not barrier.Position: the slab is still buried mid-rise
		-- at this point, so its own CFrame would log a spot underground.
		log:info(("world_spawn: %s placed at %s (lifetime=%.1fs)"):format(
			skill.name,
			tostring(footCFrame.Position),
			(params.durationSec or WALL_DEFAULT_DURATION_SEC) :: number
		))
		if onComplete then onComplete() end
		return result
	end,
}

----------------------------------------------------------------------
-- Preconditions
----------------------------------------------------------------------
-- "Would this delivery be refused?", answered without running it.
--
-- One entry per delivery kind, mirroring the guards its handler runs
-- before it commits to anything. The split that matters is WHERE each kind
-- applies its onImpact effects:
--
--   instant / world_spawn — against ctx.target, synchronously. So their
--     effects can be checked here, and their handler's return value is the
--     effect result.
--   projectile / aoe      — against whatever the shot or the scan finds at
--     impact, which is not known yet and is usually not ctx.target at all.
--     Pre-checking their effects against ctx.target would refuse a Fireball
--     aimed at a point in space, which is legal. So they check only their
--     own precondition; a splash that lands on nobody is a miss, not a
--     refusal, and costs the caster their mana exactly as it does today.
--
-- Pure. Reads only.
local function checkImpactEffects(skill: SkillSpec, target: any, source: any?): Result
	for _, effectSpec in skill.onImpact do
		local result = SkillEffects.canApply(effectSpec, target, source)
		if not result.ok then return result end
	end
	return { ok = true }
end

SkillDelivery.preconditions = {
	instant = function(skill: SkillSpec, target: any, source: any?): Result
		return checkImpactEffects(skill, target, source)
	end,

	projectile = function(_skill: SkillSpec, target: any, _source: any?): Result
		if not resolveTargetPosition(target) then
			return { ok = false, reason = "projectile requires a target with a position" }
		end
		return { ok = true }
	end,

	-- Falls back to ctx.origin.Position when no centre is given, so there is
	-- nothing it can be missing.
	aoe = function(_skill: SkillSpec, _target: any, _source: any?): Result
		return { ok = true }
	end,

	-- Places relative to the caster when target is nil, so likewise. Its
	-- handler only runs onImpact when the spec declares any.
	world_spawn = function(skill: SkillSpec, target: any, source: any?): Result
		if #skill.onImpact > 0 then return checkImpactEffects(skill, target, source) end
		return { ok = true }
	end,
}

-- Pure precondition check for a whole skill. Takes target/source rather
-- than a DeliveryCtx because it needs no origin, no aoeCenter and no
-- completion callback — and because building a throwaway ctx just to ask a
-- question would mean inventing a `mode` for a run that isn't happening.
function SkillDelivery.canDeliver(skill: SkillSpec, target: any, source: any?): Result
	local check = SkillDelivery.preconditions[skill.delivery]
	if not check then
		return { ok = false, reason = "unknown delivery kind: " .. tostring(skill.delivery) }
	end
	return check(skill, target, source)
end

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
