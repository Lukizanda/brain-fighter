--!strict

----------------------------------------------------------------------
-- predicted_run_writes_nothing — the client/server boundary, pinned
----------------------------------------------------------------------
-- The load-bearing invariant of Phase 5.6: a run with
-- `mode = "predicted"` may not write gameplay state or put objects in the
-- world. Only the authoritative run does that.
--
-- Worth an automated test rather than a playtest note, because breaking it
-- is invisible. Both runs used to apply every effect, and it looked
-- correct the whole time — a client's write to a server-owned rig only
-- changes that client's copy and replication puts the real value back a
-- moment later. Nothing in a playtest reads as wrong until two
-- simulations disagree, which is rare and non-deterministic. So the check
-- has to be a direct assertion on state, not an observation of behaviour.
--
-- Structure: every spell is cast TWICE against fresh rigs — once
-- predicted, once authoritative — and the assertions run in both
-- directions:
--
--   predicted     → nothing moved
--   authoritative → everything moved
--
-- The second half is not decoration. Without it this suite passes
-- perfectly against a registry where the spells do nothing at all, or a
-- SkillEffects that early-returns unconditionally. "Nothing happened" is
-- only meaningful next to proof that something was supposed to.
--
-- Covers: instant damage and its `_burning` render flag (Inferno), freeze
-- + its `_frozen` render flag (Frost Nip), the shield pool (Shield), and
-- projectile Part creation (Fireball).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local SpellExecutor  = require(ReplicatedStorage.Shared.SpellExecutor)
local SpellRegistry  = require(ReplicatedStorage.Shared.SpellRegistry)

local START_HEALTH   = 100
local START_SPEED    = 16
local PROJECTILE_PART_NAME = "SkillProjectile"
-- Well clear of the arena, so a shot in flight can't stop on level
-- geometry and the count stays deterministic.
local TEST_ALTITUDE_Y = 600
-- Caster-to-target separation. Non-zero is not cosmetic: the handler takes
-- `(targetPos - muzzlePos).Unit`, and two rigs at the same point make that
-- a zero-length vector, which yields a NaN direction and no usable shot.
-- The first draft of this suite put both rigs at the origin and the
-- positive control below is what caught it.
local TEST_SEPARATION_STUDS = 60
-- Long enough for the Part to exist, short enough that it is still in
-- flight when counted.
local SETTLE_SEC = 0.15

type Snapshot = {
	health: number,
	walkSpeed: number,
	frozen: boolean,
	burning: boolean,
	shield: number,
	projectiles: number,
}

type Ctx = {
	predicted: Snapshot?,
	authoritative: Snapshot?,
	rigs: { Model },
}

local function countProjectiles(): number
	local n = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == PROJECTILE_PART_NAME then n += 1 end
	end
	return n
end

local function makeRig(name: string, at: Vector3): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = START_HEALTH
	hum.Health    = START_HEALTH
	hum.WalkSpeed = START_SPEED
	hum.Parent = model
	local hrp = Instance.new("Part")
	hrp.Name      = "HumanoidRootPart"
	hrp.Anchored  = true
	hrp.CanCollide = false
	hrp.Transparency = 1
	hrp.CFrame    = CFrame.new(at)
	hrp.Parent = model
	model.Parent = workspace
	return model, hum
end

-- Cast the four spells in `mode` against fresh rigs and report what moved.
local function runTrial(mode: string, ctx: Ctx): Snapshot
	-- Offset each trial's pair so the predicted and authoritative runs
	-- can't interact through splash or proximity.
	local lane = if mode == "predicted" then 0 else TEST_SEPARATION_STUDS * 2
	local casterModel, casterHum = makeRig(
		"PredGuard_Caster_" .. mode,
		Vector3.new(lane, TEST_ALTITUDE_Y, 0)
	)
	local targetModel, targetHum = makeRig(
		"PredGuard_Target_" .. mode,
		Vector3.new(lane, TEST_ALTITUDE_Y, TEST_SEPARATION_STUDS)
	)
	table.insert(ctx.rigs, casterModel)
	table.insert(ctx.rigs, targetModel)

	local run = { mode = mode :: any }
	local projectilesBefore = countProjectiles()

	-- Inferno (red T3): instant, fraction-of-MaxHP damage + the `_burning`
	-- render flag. The flag clears itself after INFERNO_BURN_SEC (3 s),
	-- which is far longer than SETTLE_SEC, so it is still up when the
	-- snapshot is taken.
	SpellExecutor.cast(SpellRegistry.getSpell("red", 3), casterHum, targetHum, run)
	-- Frost Nip (blue T1): instant, freeze — WalkSpeed 0 + `_frozen` flag.
	SpellExecutor.cast(SpellRegistry.getSpell("blue", 1), casterHum, targetHum, run)
	-- Shield (blue T2): self-cast, grants the absorb pool on the caster.
	SpellExecutor.cast(SpellRegistry.getSpell("blue", 2), casterHum, nil, run)
	-- Fireball (red T2): projectile — does it put a Part in the world?
	SpellExecutor.cast(SpellRegistry.getSpell("red", 2), casterHum, targetHum, run)

	task.wait(SETTLE_SEC)

	local shield = casterModel:GetAttribute("_shield")
	return {
		health      = targetHum.Health,
		walkSpeed   = targetHum.WalkSpeed,
		frozen      = targetModel:GetAttribute(SkillConstants.FROZEN_ATTRIBUTE) == true,
		burning     = targetModel:GetAttribute(SkillConstants.BURNING_ATTRIBUTE) == true,
		shield      = if typeof(shield) == "number" then shield :: number else 0,
		projectiles = countProjectiles() - projectilesBefore,
	}
end

return {
	name = "predicted_run_writes_nothing",

	setup = function(ctx: Ctx)
		ctx.rigs = {}
		ctx.predicted     = runTrial("predicted", ctx)
		ctx.authoritative = runTrial("authoritative", ctx)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local p = ctx.predicted :: Snapshot
		local a = ctx.authoritative :: Snapshot

		-- 1. The predicted run must have changed nothing.
		if p.health ~= START_HEALTH then
			return false, ("predicted run dealt damage: health %d -> %s"):format(START_HEALTH, tostring(p.health))
		end
		if p.walkSpeed ~= START_SPEED then
			return false, ("predicted run froze the target: WalkSpeed %d -> %s"):format(START_SPEED, tostring(p.walkSpeed))
		end
		if p.frozen then
			return false, "predicted run set the _frozen render flag"
		end
		if p.burning then
			return false, "predicted run set the _burning render flag"
		end
		if p.shield ~= 0 then
			return false, ("predicted run granted a shield pool of %d"):format(p.shield)
		end
		if p.projectiles ~= 0 then
			return false, ("predicted run spawned %d projectile Part(s) into the world"):format(p.projectiles)
		end

		-- 2. Positive control: the same casts authoritatively must move all
		--    of it, or clause 1 proved nothing.
		if a.health >= START_HEALTH then
			return false, ("authoritative run dealt no damage (health %s) — spells are inert, so the "
				.. "predicted assertions above are vacuous"):format(tostring(a.health))
		end
		if a.walkSpeed ~= 0 or not a.frozen then
			return false, ("authoritative run did not freeze (WalkSpeed %s, frozen %s) — freeze "
				.. "assertions above are vacuous"):format(tostring(a.walkSpeed), tostring(a.frozen))
		end
		if not a.burning then
			return false, "authoritative run did not set the _burning render flag — the burn "
				.. "assertion above is vacuous"
		end
		if a.shield <= 0 then
			return false, "authoritative run granted no shield — shield assertion above is vacuous"
		end
		if a.projectiles <= 0 then
			return false, "authoritative run spawned no projectile — projectile assertion above is vacuous"
		end

		return true, ("predicted wrote nothing; authoritative wrote health=%d walkSpeed=%d frozen=%s burning=%s shield=%d projectiles=%d")
			:format(a.health, a.walkSpeed, tostring(a.frozen), tostring(a.burning), a.shield, a.projectiles)
	end,

	teardown = function(ctx: Ctx)
		for _, rig in ctx.rigs or {} do
			rig:Destroy()
		end
	end,
}
