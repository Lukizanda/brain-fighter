----------------------------------------------------------------------
-- Test: A melee swing inside reach damages a target via the sweep +
-- damage pipeline (MeleeHitDetector + HealthService.applyDamage).
--
-- Exercises the server-side swing logic without going through the
-- RemoteEvent — the remote layer is thin and tested manually.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MeleeHitDetector = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeHitDetector)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)

local REACH = 8
local WIDTH = 5
local HEIGHT = 5
local DAMAGE = 25
local OFFSET_FROM_DUMMY = 4 -- attacker stands this many studs behind dummy, facing it

return {
	name = "Melee swing damages a dummy inside reach",

	setup = function(ctx)
		assert(ctx.player, "No local player")
		local character = ctx.player.Character
		assert(character, "Player has no character")

		local dummy = workspace:FindFirstChild("TargetDummy1", true)
		assert(dummy, "TargetDummy1 missing")
		local humanoid = dummy:FindFirstChildOfClass("Humanoid")
		assert(humanoid, "Dummy has no Humanoid")

		ctx.dummy = dummy
		ctx.humanoid = humanoid
		ctx.character = character

		humanoid.Health = humanoid.MaxHealth
		ctx.initialHealth = humanoid.Health

		-- Position attacker facing the dummy, just inside reach
		local dummyPos = dummy:GetPivot().Position
		local attackerPos = dummyPos + Vector3.new(0, 0, OFFSET_FROM_DUMMY)
		character:PivotTo(CFrame.new(attackerPos, dummyPos))
	end,

	run = function(ctx)
		local hrp = ctx.character:FindFirstChild("HumanoidRootPart")
		assert(hrp, "No HRP")

		local hits = MeleeHitDetector.sweep({
			originCFrame = hrp.CFrame,
			reach = REACH,
			width = WIDTH,
			height = HEIGHT,
			attackerCharacter = ctx.character,
			hitMode = MeleeConstants.HitMode.Single,
		})

		ctx.hits = hits

		for _, hit in hits do
			applyDamage.process({
				sourcePlayer = nil,
				targetHumanoid = hit.humanoid,
				baseDamage = DAMAGE,
				damageType = DamageTypes.DamageType.Melee,
				hitZone = DamageTypes.HitZone.Torso,
				timestamp = os.clock(),
			})
		end
	end,

	verify = function(ctx)
		if #ctx.hits == 0 then
			return false, "Sweep returned no hits"
		end
		if ctx.humanoid.Health >= ctx.initialHealth then
			return false, string.format("Dummy took no damage (still %d HP)", ctx.humanoid.Health)
		end
		local delta = ctx.initialHealth - ctx.humanoid.Health
		return true, string.format("Sweep hit %d, dummy took %d damage (%d -> %d)",
			#ctx.hits, delta, ctx.initialHealth, ctx.humanoid.Health)
	end,

	teardown = function(ctx)
		if ctx.humanoid and ctx.humanoid.Parent then
			ctx.humanoid.Health = ctx.humanoid.MaxHealth
		end
	end,
}
