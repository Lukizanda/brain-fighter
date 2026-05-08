----------------------------------------------------------------------
-- Test: In Cleave mode, a swing with two targets inside the hitbox
-- registers both. In Single mode (same geometry), it registers one.
--
-- Positions two dummies side-by-side in front of the attacker so both
-- land inside a single swept box.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeleeHitDetector = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeHitDetector)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)

local REACH = 10
local WIDTH = 12 -- wide enough to cover two dummies placed ~3 studs apart on X
local HEIGHT = 8
local DUMMY_SEPARATION = 3

return {
	name = "Melee cleave hits multiple, single hits one",

	setup = function(ctx)
		assert(ctx.player, "No local player")
		local character = ctx.player.Character
		assert(character, "Player has no character")

		local dummyA = workspace:FindFirstChild("TargetDummy1", true)
		local dummyB = workspace:FindFirstChild("TargetDummy2", true)
		assert(dummyA and dummyB, "Need TargetDummy1 and TargetDummy2")

		ctx.character = character
		ctx.dummyA = dummyA
		ctx.dummyB = dummyB
		ctx.originalCFrameA = dummyA:GetPivot()
		ctx.originalCFrameB = dummyB:GetPivot()

		-- Anchor a known attacker position, place dummies 5 studs forward
		-- and 3 studs apart on the X axis so they both sit inside a wide box.
		local attackerPos = character:GetPivot().Position
		character:PivotTo(CFrame.new(attackerPos, attackerPos + Vector3.new(0, 0, -1)))
		local forward = attackerPos + Vector3.new(0, 0, -5)
		dummyA:PivotTo(CFrame.new(forward + Vector3.new(-DUMMY_SEPARATION / 2, 0, 0)))
		dummyB:PivotTo(CFrame.new(forward + Vector3.new(DUMMY_SEPARATION / 2, 0, 0)))
		task.wait(0.1) -- let physics settle after the teleport
	end,

	run = function(ctx)
		local hrp = ctx.character:FindFirstChild("HumanoidRootPart")
		assert(hrp, "No HRP")

		ctx.singleHits = MeleeHitDetector.sweep({
			originCFrame = hrp.CFrame,
			reach = REACH,
			width = WIDTH,
			height = HEIGHT,
			attackerCharacter = ctx.character,
			hitMode = MeleeConstants.HitMode.Single,
		})

		ctx.cleaveHits = MeleeHitDetector.sweep({
			originCFrame = hrp.CFrame,
			reach = REACH,
			width = WIDTH,
			height = HEIGHT,
			attackerCharacter = ctx.character,
			hitMode = MeleeConstants.HitMode.Cleave,
		})
	end,

	verify = function(ctx)
		if #ctx.singleHits ~= 1 then
			return false, string.format("Single mode: expected 1 hit, got %d", #ctx.singleHits)
		end
		if #ctx.cleaveHits ~= 2 then
			return false, string.format("Cleave mode: expected 2 hits, got %d", #ctx.cleaveHits)
		end
		return true, "Single=1, Cleave=2"
	end,

	teardown = function(ctx)
		if ctx.dummyA and ctx.dummyA.Parent and ctx.originalCFrameA then
			ctx.dummyA:PivotTo(ctx.originalCFrameA)
		end
		if ctx.dummyB and ctx.dummyB.Parent and ctx.originalCFrameB then
			ctx.dummyB:PivotTo(ctx.originalCFrameB)
		end
	end,
}
