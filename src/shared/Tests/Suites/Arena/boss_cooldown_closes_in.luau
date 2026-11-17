--!strict

----------------------------------------------------------------------
-- boss_cooldown_closes_in — with stopRange < attackRange, Cooldown keeps walking
----------------------------------------------------------------------
-- MODULE LEVEL (UNRUN at authoring time): BossStates' Cooldown update on a
-- stand-in rig, ticked by hand. Whether the boss is walking or standing is
-- read off who owns its facing, because that is the single-owner rule the
-- change has to respect (wiki/systems/Boss.md § State Machine):
--
--   * walking  -> the Humanoid steers, so the facing constraint is not engaged;
--   * standing -> `continuousFacing` engages Actions.FaceTarget's constraint.
--
-- Cases (target between stopRange and attackRange unless noted):
--   A. stopRange set, target beyond it   -> walking (no facing constraint).
--   B. stopRange set, target inside it   -> standing (facing constraint on).
--   C. no stopRange, same distance as A  -> standing, as before the change.
--
-- NOT covered: the path the walk follows. A bare test arena has no navmesh,
-- so only the decision to walk is observable here, not the distance covered.
----------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")

local BossStates = require(ServerScriptService.Server.Boss.Scripts.BossStates)

local TEST_ALTITUDE = 900
local ATTACK_RANGE = 150
local STOP_RANGE = 70
local BEYOND_STOP_DISTANCE = 110
local INSIDE_STOP_DISTANCE = 40
local FACING_CONSTRAINT_NAME = "AIFacingAlign"
local TICKS = 3

type Case = {
	label: string,
	stopRange: number?,
	distance: number,
	expectFacing: boolean,
}

local CASES: { Case } = {
	{ label = "beyond stopRange walks", stopRange = STOP_RANGE, distance = BEYOND_STOP_DISTANCE, expectFacing = false },
	{ label = "inside stopRange stands", stopRange = STOP_RANGE, distance = INSIDE_STOP_DISTANCE, expectFacing = true },
	{ label = "no stopRange stands", stopRange = nil, distance = BEYOND_STOP_DISTANCE, expectFacing = true },
}

local function makeRig(name: string, x: number): (Model, Humanoid, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CFrame = CFrame.new(x, TEST_ALTITUDE, 0)
	root.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	return model, humanoid, root
end

return {
	name = "boss_cooldown_closes_in",

	setup = function(ctx: any)
		ctx.failure = nil
	end,

	run = function(ctx: any)
		local states = BossStates.build()
		local cooldown = states[BossStates.State.Cooldown]

		for _, case in CASES do
			local bossModel, humanoid, root = makeRig("CooldownTestBoss", 0)
			local targetModel, _targetHumanoid, targetRoot = makeRig("CooldownTestTarget", case.distance)
			ctx.models = ctx.models or {}
			table.insert(ctx.models, bossModel)
			table.insert(ctx.models, targetModel)

			local spec: any = {
				attackRange = ATTACK_RANGE,
				stopRange = case.stopRange,
				continuousFacing = true,
			}
			local bb: any = {
				npc = bossModel,
				humanoid = humanoid,
				humanoidRootPart = root,
				targetRootPart = targetRoot,
				nearestPlayer = true,
				distanceToNearest = case.distance,
				bossTypeSpec = spec,
				cooldownStart = os.clock(),
			}

			for _ = 1, TICKS do
				cooldown.update(bb)
				task.wait()
			end

			local align = root:FindFirstChild(FACING_CONSTRAINT_NAME)
			local facing = align ~= nil and (align :: AlignOrientation).Enabled
			if facing ~= case.expectFacing then
				ctx.failure = string.format(
					"%s: facing constraint %s, expected %s",
					case.label,
					tostring(facing),
					tostring(case.expectFacing)
				)
				return
			end
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		for _, model in ctx.models or {} do
			model:Destroy()
		end
	end,
}
