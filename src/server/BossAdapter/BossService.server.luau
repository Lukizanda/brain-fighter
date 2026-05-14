--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BossAdapter = require(ReplicatedStorage.Shared.BossAdapter)

local log = Logger.new("BossService")

BossAdapter.spawn()

BossAdapter.defeated:Connect(function()
	log:info("Boss defeated — respawning in 5s")
	task.delay(5, function()
		BossAdapter.reset()
	end)
end)

log:info("BossService ready")
