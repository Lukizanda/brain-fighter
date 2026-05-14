local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossAdapter = require(ReplicatedStorage.Shared.BossAdapter)

local TEST_HP = 200
local TEST_POS = Vector3.new(0, 50, -50)

return {
	name = "BossAdapter spawns with correct health and provides target",

	setup = function(ctx)
		ctx.boss = BossAdapter.spawn({
			maxHealth = TEST_HP,
			position = TEST_POS,
		})
	end,

	verify = function(ctx)
		if not ctx.boss or not ctx.boss.Parent then
			return false, "Boss Model not in workspace"
		end

		local target = BossAdapter.getTarget()
		if not target then
			return false, "getTarget() returned nil"
		end
		if not target:IsA("Humanoid") then
			return false, "getTarget() returned non-Humanoid"
		end
		if target.MaxHealth ~= TEST_HP then
			return false, string.format("MaxHealth expected %d, got %d", TEST_HP, target.MaxHealth)
		end
		if target.Health ~= TEST_HP then
			return false, string.format("Health expected %d, got %d", TEST_HP, target.Health)
		end
		if not BossAdapter.isAlive() then
			return false, "isAlive() returned false for a live boss"
		end

		local model = BossAdapter.getModel()
		if model ~= ctx.boss then
			return false, "getModel() did not return the spawned Model"
		end

		return true, string.format("Boss spawned at %s with %d HP", tostring(TEST_POS), TEST_HP)
	end,

	teardown = function(_ctx)
		BossAdapter.despawn()
	end,
}
