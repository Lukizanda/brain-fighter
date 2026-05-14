--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local log = Logger.new("BlockSpawnerService")

BlockSpawner.start()
log:info("BlockSpawnerService ready")
