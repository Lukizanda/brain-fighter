--!strict

----------------------------------------------------------------------
-- CosmeticProjectile — the *seen* projectile, never the real one.
----------------------------------------------------------------------
-- A purely local Part that flies a straight line and dies on the same
-- rules the authoritative shot does. It deals no damage, drains no pool
-- and is invisible to every raycast in the game.
--
-- Why this exists at all: the authoritative projectile is server-owned
-- and server-simulated (SkillDelivery calls SetNetworkOwner(nil) — see
-- wiki/systems/SkillPipeline.md § "why projectiles are server-simulated").
-- Clients render server-owned parts behind the server, so a shot the
-- server destroyed on a shield shell was still being drawn ~12 studs
-- short of the bubble. Measured, not guessed: closest rendered approach
-- was 17.5 studs against a shell at 5.2.
--
-- A shot's path is a straight line at constant velocity, so a client can
-- reproduce it exactly from the launch parameters alone — no correction
-- traffic, no physics. That is what makes prediction safe here: the
-- client isn't guessing at the outcome, it's evaluating the same
-- geometry against state it already has (`_shield` replicates, and the
-- bubble is drawn from it). Contact lands on the frame it looks like it
-- should.
--
-- Divergence is bounded and harmless by construction: if the client and
-- server disagree about a block, the client loses a cosmetic and the
-- server still decides who took damage.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local SkillBuffs      = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local SkillConstants  = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local SkillVisuals    = require(ReplicatedStorage.Shared.Skills.SkillVisuals)
local VfxConfig       = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local spawnEffect     = require(ReplicatedStorage.Shared.Vfx.spawnEffect)

local SHIELD_BLOCK_EFFECT_ID = "shield_block"

-- Grace on the Debris fallback, for the case where every termination
-- rule somehow misses. Purely a leak guard.
local CLEANUP_GRACE_SEC = 1

export type LaunchParams = {
	origin: Vector3,
	direction: Vector3,
	speed: number,
	size: Vector3,
	color: Color3,
	lifetimeSec: number,
	cosmeticEffectId: string?,
	-- Played once at the muzzle. Anchored to its own throwaway Part rather
	-- than to the shot, so killing the shot can't cut the sound off.
	launchEffectId: string?,
	-- The server destroys a shot that comes within this of a rig's HRP,
	-- independently of the raycast. Mirrored here or the two disagree:
	-- a 2-stud boss fireball whose centre line passes beside a player
	-- detonates and damages server-side while this copy sails on through.
	proximityRadius: number?,
	-- Whether the shot ends on the first rig it reaches. Defaults to true
	-- when absent, matching SkillDelivery. A piercing shot has to be drawn
	-- piercing or the picture contradicts the damage.
	consumeOnHit: boolean?,
	-- Played where this shot dies, so a death nothing else announces is
	-- still audible — the reason it exists is in the VfxConfig entry.
	-- Nil for splash shots: their shockwave already fires server-side on
	-- every detonation cause and replicates to everyone.
	destroyEffectId: string?,
	-- Whether the server plays an impact burst on a direct rig hit. Lets
	-- the cue stay quiet for that one cause without going quiet for the
	-- wall and expiry deaths, which is the whole point of it.
	hasImpactCue: boolean?,
	-- The firing rig, excluded from both the world ray and the shell
	-- test: the muzzle sits inside its own body, and without this every
	-- shot would die on the shooter.
	source: Instance?,
}

local CosmeticProjectile = {}

-- Every player currently carrying a live absorb pool. Players only,
-- deliberately: shields come from selfTarget spells, so no NPC or boss
-- can hold one today. If that changes, this and SkillDelivery's
-- `collectHittables` need to change together or the visual will stop
-- matching the block.
local function shieldedRoots(source: Instance?): { BasePart }
	local roots: { BasePart } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or character == source then continue end
		local pool = character:GetAttribute(HealthConstants.SHIELD_ATTRIBUTE)
		if typeof(pool) ~= "number" or (pool :: number) <= 0 then continue end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			table.insert(roots, hrp :: BasePart)
		end
	end
	return roots
end

-- Was a hand-kept mirror of SkillDelivery's list, with a comment noting
-- the two had to agree or this copy would stop on rigs the authoritative
-- shot flies past. Now they share one definition, so they can't disagree.
local DAMAGEABLE_TAGS: { string } = SkillConstants.DAMAGEABLE_TAGS

type Rig = { model: Model, hrp: BasePart }

-- Frame-level cache, for the same reason SkillDelivery keeps one: a Brain
-- volley puts 30 cosmetics in the air at once, and without this every one
-- of them re-queries CollectionService every Heartbeat.
local _rigsCache: { Rig }? = nil
RunService.Heartbeat:Connect(function()
	_rigsCache = nil
end)

-- Every live rig a shot can terminate on. Mirrors
-- SkillDelivery.collectHittables — players enumerated, everything else by
-- tag — because the proximity rule below has to measure against the same
-- set the server does. The caster is filtered at the call site, exactly as
-- the server does it, so the cache stays shared across all shots in flight.
local function collectRigs(): { Rig }
	if _rigsCache then return _rigsCache end
	local rigs: { Rig } = {}
	local seen: { [Instance]: true } = {}

	local function tryAdd(model: Instance?)
		if not model or not model:IsA("Model") then return end
		if seen[model] then return end
		local hum = (model :: Model):FindFirstChildOfClass("Humanoid")
		if not hum or (hum :: Humanoid).Health <= 0 then return end
		local hrp = (model :: Model):FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then return end
		seen[model] = true
		table.insert(rigs, { model = model :: Model, hrp = hrp :: BasePart })
	end

	for _, player in Players:GetPlayers() do
		tryAdd(player.Character)
	end
	for _, tag in DAMAGEABLE_TAGS do
		for _, inst in CollectionService:GetTagged(tag) do
			tryAdd(inst)
		end
	end
	_rigsCache = rigs
	return rigs
end

-- The rig this ray stopped on, or nil for a wall or prop. Returns the Model
-- that actually carries the Humanoid rather than the nearest Model ancestor
-- — the two differ whenever a part sits inside a nested Model (accessories,
-- tool models), and filtering the nested one would leave the rest of the
-- body still blocking the shot.
--
-- Doubles as the "is this the death the server already cued?" test, so both
-- callers agree on what counts as a rig.
local function rigFromPart(instance: Instance?): Model?
	local model = instance and instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return model end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Fire a visual-only shot. Returns immediately; the Part cleans itself up.
function CosmeticProjectile.launch(params: LaunchParams)
	local direction = params.direction
	if direction.Magnitude <= 0 then return end
	direction = direction.Unit

	local projectile = Instance.new("Part")
	projectile.Name        = "CosmeticProjectile"
	projectile.Size        = params.size
	projectile.Color       = params.color
	projectile.Material    = Enum.Material.Neon
	-- Anchored and hand-stepped rather than physics-driven: this Part is
	-- a picture of a shot, and letting the engine simulate it would let it
	-- drift from the straight line the server is actually resolving.
	projectile.Anchored    = true
	projectile.CanCollide  = false
	projectile.CanQuery    = false
	projectile.CanTouch    = false
	projectile.CastShadow  = false
	projectile.CFrame      = CFrame.new(params.origin)
	projectile.Parent      = workspace

	Debris:AddItem(projectile, params.lifetimeSec + CLEANUP_GRACE_SEC)

	-- At the muzzle, on its own anchor. Parenting this to `projectile` would
	-- tie the sound's life to the shot's: a Sound is a *child* of its anchor,
	-- so destroying the shot on impact destroys the sound mid-play.
	if params.launchEffectId then
		SkillVisuals.spawnEffectAtPoint(params.origin, params.launchEffectId)
	end

	if params.cosmeticEffectId then
		local cosmeticEffect = VfxConfig.EFFECTS[params.cosmeticEffectId]
		if cosmeticEffect then
			spawnEffect(cosmeticEffect, projectile)
		end
	end

	-- Same exclusions the authoritative shot uses, for the same reasons.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = if params.source
		then { projectile :: Instance, params.source :: Instance }
		else { projectile :: Instance }
	rayParams.IgnoreWater = true
	rayParams.RespectCanCollide = true

	local shellPadding = math.max(params.size.X, params.size.Y, params.size.Z) * 0.5
	local elapsed = 0
	local pos = params.origin
	-- Hoisted so the compound guard on the geometry branch below narrows
	-- cleanly to `string` under strict mode.
	local destroyEffectId: string? = params.destroyEffectId
	local hasImpactCue: boolean = params.hasImpactCue == true
	local proximityRadius: number = params.proximityRadius or 0
	local consumeOnHit: boolean = params.consumeOnHit ~= false
	-- Mirrors SkillDelivery's `pierced` set, for the same reason: without it
	-- a rig inside proximityRadius would be re-tested every frame the shot
	-- overlaps it, and the shot would never get past its own filter update.
	local pierced: { [Instance]: true } = {}

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt: number)
		if not projectile.Parent then
			conn:Disconnect()
			return
		end

		elapsed += dt
		if elapsed >= params.lifetimeSec then
			conn:Disconnect()
			-- Spent in mid-air. Nothing else ever announces this one.
			if destroyEffectId then
				SkillVisuals.spawnEffectAtPoint(pos, destroyEffectId)
			end
			projectile:Destroy()
			return
		end

		local step = direction * (params.speed * dt)
		if step.Magnitude <= 0 then return end
		local nextPos = pos + step

		-- Shield shells first, and nearest-wins against world geometry —
		-- mirrors the ordering in SkillDelivery so the two agree about
		-- which surface stopped the shot.
		local rayHit  = workspace:Raycast(pos, step, rayParams)
		local rayDist = if rayHit then (rayHit.Position - pos).Magnitude else math.huge

		-- Nil rather than a sentinel distance: with both defaulting to
		-- math.huge, "nearest shell is no further than nearest wall" is
		-- true when there is neither, and every shot deletes itself on
		-- its first frame.
		local shellContact: Vector3? = nil
		local shellDist = math.huge
		for _, root in shieldedRoots(params.source) do
			local entry = SkillBuffs.shellEntry(pos, step, root.Position, shellPadding)
			if entry and entry < shellDist then
				shellDist    = entry
				shellContact = pos + direction * entry
			end
		end

		if shellContact and shellDist <= rayDist then
			conn:Disconnect()
			-- The spark is the whole point of predicting locally: it lands
			-- on the bubble, on the frame the shot reaches it.
			SkillVisuals.spawnEffectAtPoint(shellContact, SHIELD_BLOCK_EFFECT_ID)
			projectile:Destroy()
			return
		end

		if rayHit then
			local struckRig = rigFromPart(rayHit.Instance)
			if struckRig and not consumeOnHit then
				-- Piercing: pass through the body and keep drawing. Filtering
				-- the rig out is what stops the next sweep catching it again.
				if not pierced[struckRig] then
					pierced[struckRig] = true
					local filter = rayParams.FilterDescendantsInstances
					table.insert(filter, struckRig)
					-- Reassigned, not mutated: the property hands back a copy.
					rayParams.FilterDescendantsInstances = filter
				end
			else
				conn:Disconnect()
				-- Stopped on geometry. Skipped only when the thing stopped was
				-- a rig the server is already playing an impact burst on, so a
				-- hit body doesn't get both cues while a wall still thuds.
				if destroyEffectId and not (hasImpactCue and struckRig) then
					SkillVisuals.spawnEffectAtPoint(rayHit.Position, destroyEffectId)
				end
				projectile:Destroy()
				return
			end
		end

		pos = nextPos
		projectile.CFrame = CFrame.new(pos)

		-- Proximity rule, checked at the new endpoint exactly as the server
		-- does it. Without this the only thing that could stop this copy was
		-- a literal centre-line ray hit, so a fireball that detonated on the
		-- server for passing within `proximityRadius` of a player kept
		-- flying here — damage landed, the shot sailed on through them.
		--
		-- No effect is played: the server owns the impact burst for a rig
		-- hit, and the shot reaching a body is the one death that is already
		-- announced.
		if proximityRadius > 0 and consumeOnHit then
			for _, rig in collectRigs() do
				if rig.model == params.source then continue end
				if (rig.hrp.Position - pos).Magnitude <= proximityRadius then
					conn:Disconnect()
					projectile:Destroy()
					return
				end
			end
		end
	end)
end

return CosmeticProjectile
