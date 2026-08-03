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

local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local SkillBuffs      = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
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

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt: number)
		if not projectile.Parent then
			conn:Disconnect()
			return
		end

		elapsed += dt
		if elapsed >= params.lifetimeSec then
			conn:Disconnect()
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
			conn:Disconnect()
			projectile:Destroy()
			return
		end

		pos = nextPos
		projectile.CFrame = CFrame.new(pos)
	end)
end

return CosmeticProjectile
