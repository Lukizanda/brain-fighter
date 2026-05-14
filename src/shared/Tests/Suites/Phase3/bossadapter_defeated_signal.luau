local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossAdapter = require(ReplicatedStorage.Shared.BossAdapter)

local TEST_HP = 50

return {
	name = "BossAdapter fires defeated signal when Boss HP reaches 0",

	setup = function(ctx)
		ctx.boss = BossAdapter.spawn({
			maxHealth = TEST_HP,
			position = Vector3.new(0, 50, -70),
		})
		ctx.defeatedFired = false
		ctx.conn = BossAdapter.defeated:Connect(function()
			ctx.defeatedFired = true
		end)
	end,

	run = function(ctx)
		local humanoid = BossAdapter.getTarget()
		if humanoid then
			humanoid.Health = 0
		end
		task.wait(0.2)
	end,

	verify = function(ctx)
		if not ctx.defeatedFired then
			return false, "defeated signal did not fire after setting Health to 0"
		end
		if BossAdapter.isAlive() then
			return false, "isAlive() still true after defeat"
		end
		return true, "defeated signal fired, isAlive() = false"
	end,

	teardown = function(ctx)
		if ctx.conn then
			ctx.conn:Disconnect()
		end
		BossAdapter.despawn()
	end,
}
