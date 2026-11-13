--!strict

----------------------------------------------------------------------
-- entry_no_arrival_warns — a pad with no arrival point does nothing
----------------------------------------------------------------------
-- The player is in the pad's arena and touches it, but no ArenaArrivalPoint
-- matches: the character stays where it is, the pad is marked as having
-- warned, and a second touch does not warn again.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local PAD_HEIGHT = 600
local MOVE_TOLERANCE_STUDS = 0.01

return {
	name = "entry_no_arrival_warns",

	setup = function(ctx: any)
		ctx.fx = arenaEntryFixture.new()
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not player or not root then
			return
		end
		local fx = ctx.fx
		ctx.entered = fx:enter(player)
		ArenaEntryService.resetState()
		local pad = fx:part(ArenaEntryConstants.PAD_TAG, fx.arenaId, CFrame.new(0, PAD_HEIGHT, 0))
		ctx.pad = pad

		local hrp = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		ctx.before = hrp.Position
		ctx.first = ArenaEntryService.handleTouch(pad, hrp)
		ctx.warnedAfterFirst = ArenaEntryService.hasWarned(pad)
		ctx.after = hrp.Position
		ctx.second = ArenaEntryService.handleTouch(pad, hrp)
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.entered then
			return false, "no player on the server, or the transfer failed"
		end
		local Result = ArenaEntryConstants.Result
		if ctx.first ~= Result.NoArrival or ctx.second ~= Result.NoArrival then
			return false, string.format("touch results were %s / %s, wanted no_arrival twice", tostring(ctx.first), tostring(ctx.second))
		end
		if not ctx.warnedAfterFirst then
			return false, "the pad was not marked as warned after the first touch"
		end
		if (ctx.after - ctx.before).Magnitude > MOVE_TOLERANCE_STUDS then
			return false, "the character moved although there was no arrival point"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.fx then
			ctx.fx:cleanup(ctx.player)
		end
		ArenaEntryService.resetState()
	end,
}
