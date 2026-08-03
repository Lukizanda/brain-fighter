--!strict

----------------------------------------------------------------------
-- spellcast_payload_validation — SpellCastServer trust checks (5.4)
----------------------------------------------------------------------
-- Covers spell resolution, caster liveness and target bounds. The
-- affordability half of 5.4 is deliberately absent: energy state lives
-- in client/PlayerSession, so there is nothing server-side to assert
-- against. See wiki/systems/SpellCastService.md § Trust model.
--
-- The green/T4 case is the one that used to bite: getSpell accepts any
-- tier in 1–4, but only red defines a T4, so the old handler pulled a
-- nil spec and then errored indexing it — killing that invocation.
----------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")

local SpellCastConstants  = require(ServerScriptService.Server.SpellCast.SpellCastConstants)
local SpellCastValidation = require(ServerScriptService.Server.SpellCast.SpellCastValidation)

local ORIGIN = Vector3.new(0, 50, 0)
local NEAR_OFFSET = Vector3.new(0, 0, 30)
local FAR_OFFSET = Vector3.new(0, 0, SpellCastConstants.MAX_TARGET_DISTANCE_STUDS + 100)

local FULL_HEALTH = 100

type Ctx = {
	created: { Instance },
	caster: Model,
	nearTarget: Model,
	farTarget: Model,
}

local function makeCharacter(ctx: Ctx, name: string, position: Vector3, health: number): Model
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Size = Vector3.one
	root.Position = position
	root.Parent = model
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = FULL_HEALTH
	humanoid.Health = health
	humanoid.Parent = model

	model.Parent = workspace
	table.insert(ctx.created, model)
	return model
end

return {
	name = "spellcast_payload_validation",

	setup = function(ctx: Ctx)
		ctx.created = {}
		ctx.caster = makeCharacter(ctx, "HardeningSpellCaster", ORIGIN, FULL_HEALTH)
		ctx.nearTarget = makeCharacter(ctx, "HardeningNearTarget", ORIGIN + NEAR_OFFSET, FULL_HEALTH)
		ctx.farTarget = makeCharacter(ctx, "HardeningFarTarget", ORIGIN + FAR_OFFSET, FULL_HEALTH)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		----------------------------------------------------------------
		-- Spell resolution
		----------------------------------------------------------------
		local spec, specReason = SpellCastValidation.resolveSpec("red", 1)
		if not spec then
			return false, string.format("rejected the legitimate red/T1: %s", tostring(specReason))
		end
		if spec.name ~= "Firebolt" then
			return false, string.format("red/T1 resolved to %s, expected Firebolt", spec.name)
		end

		local badSpells: { { any } } = {
			{ { color = "red" }, 1 },   -- table masquerading as a colour
			{ 1, 1 },                   -- number colour
			{ "purple", 1 },            -- colour outside the roster
			{ "red", "1" },             -- stringified tier
			{ "red", 0 },               -- below range
			{ "red", 99 },              -- above range
			{ "red", 1.5 },             -- fractional tier
			{ "red", 0 / 0 },           -- NaN tier
			{ "green", 4 },             -- in range, but green stops at T3
			{ "blue", 4 },              -- likewise
		}
		for _, case in badSpells do
			local got = SpellCastValidation.resolveSpec(case[1], case[2])
			if got ~= nil then
				return false, string.format(
					"accepted bogus spell %s/%s", tostring(case[1]), tostring(case[2])
				)
			end
		end
		if SpellCastValidation.resolveSpec(nil, nil) ~= nil then
			return false, "accepted a nil spell"
		end

		----------------------------------------------------------------
		-- Caster
		----------------------------------------------------------------
		local caster, casterReason = SpellCastValidation.checkCaster(ctx.caster)
		if caster ~= ctx.caster then
			return false, string.format("rejected a living caster: %s", tostring(casterReason))
		end

		if SpellCastValidation.checkCaster({ Name = "Fake" }) ~= nil then
			return false, "accepted a table caster"
		end
		if SpellCastValidation.checkCaster(nil) ~= nil then
			return false, "accepted a nil caster"
		end

		local humanoidless = Instance.new("Model")
		humanoidless.Parent = workspace
		local humanoidlessOk = SpellCastValidation.checkCaster(humanoidless)
		humanoidless:Destroy()
		if humanoidlessOk ~= nil then
			return false, "accepted a caster with no Humanoid"
		end

		local deadCaster = makeCharacter(ctx, "HardeningDeadCaster", ORIGIN, 0)
		local deadOk, deadReason = SpellCastValidation.checkCaster(deadCaster)
		if deadOk ~= nil then
			return false, "accepted a dead caster"
		end
		if deadReason ~= "caster is dead" then
			-- The service branches on this exact string to keep respawn-gap
			-- casts out of the warning log.
			return false, string.format("dead caster reason drifted to %q", tostring(deadReason))
		end

		----------------------------------------------------------------
		-- Target
		----------------------------------------------------------------
		local target, targetReason = SpellCastValidation.checkTarget(ctx.nearTarget, ctx.caster)
		if target ~= ctx.nearTarget then
			return false, string.format("rejected an in-range target: %s", tostring(targetReason))
		end

		if SpellCastValidation.checkTarget({ Name = "Boss" }, ctx.caster) ~= nil then
			return false, "accepted a table target"
		end
		if SpellCastValidation.checkTarget(nil, ctx.caster) ~= nil then
			return false, "accepted a nil target"
		end

		local loosePart = Instance.new("Part")
		loosePart.Anchored = true
		loosePart.Parent = workspace
		local loosePartOk = SpellCastValidation.checkTarget(loosePart, ctx.caster)
		loosePart:Destroy()
		if loosePartOk ~= nil then
			return false, "accepted a Part target"
		end

		if SpellCastValidation.checkTarget(ctx.farTarget, ctx.caster) ~= nil then
			return false, string.format(
				"accepted a target %d studs away (limit %d)",
				FAR_OFFSET.Magnitude,
				SpellCastConstants.MAX_TARGET_DISTANCE_STUDS
			)
		end

		return true, string.format(
			"rejected 10 bogus spells, 4 bad casters and 4 bad targets; range bound %d studs",
			SpellCastConstants.MAX_TARGET_DISTANCE_STUDS
		)
	end,

	teardown = function(ctx: Ctx)
		for _, inst in ctx.created do
			inst:Destroy()
		end
	end,
}
