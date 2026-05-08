----------------------------------------------------------------------
-- Test: A swing whose reach falls short of the target returns no hits
-- and deals no damage. Negative test for the sweep logic.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeleeHitDetector = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeHitDetector)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)

local TOO_SHORT_REACH = 2 -- way less than the ~14 stud gap we set up
local DISTANCE_FROM_DUMMY = 14
local WIDTH = 5
local HEIGHT = 5

return {
	name = "Melee swing with reach shorter than distance finds no targets",

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

		-- Place attacker well out of reach (14 studs) but still facing the dummy
		local dummyPos = dummy:GetPivot().Position
		local attackerPos = dummyPos + Vector3.new(0, 0, DISTANCE_FROM_DUMMY)
		character:PivotTo(CFrame.new(attackerPos, dummyPos))
	end,

	run = function(ctx)
		local hrp = ctx.character:FindFirstChild("HumanoidRootPart")
		assert(hrp, "No HRP")

		ctx.hits = MeleeHitDetector.sweep({
			originCFrame = hrp.CFrame,
			reach = TOO_SHORT_REACH,
			width = WIDTH,
			height = HEIGHT,
			attackerCharacter = ctx.character,
			hitMode = MeleeConstants.HitMode.Single,
		})
	end,

	verify = function(ctx)
		if #ctx.hits ~= 0 then
			return false, string.format("Expected 0 hits, got %d", #ctx.hits)
		end
		if ctx.humanoid.Health ~= ctx.initialHealth then
			return false, "Dummy HP changed despite no hits"
		end
		return true, "No hits registered at out-of-reach distance"
	end,
}
