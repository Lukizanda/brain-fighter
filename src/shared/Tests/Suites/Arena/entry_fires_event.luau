--!strict

----------------------------------------------------------------------
-- entry_fires_event — a teleport is announced on PlayerEntered
----------------------------------------------------------------------
-- Drives `ArenaEntryService.handleTouch` with the harness player's real
-- character and listens to the real `PlayerEntered` BindableEvent. A
-- successful teleport fires it once with `(player, arenaId)`; a refused
-- touch (a pad of another arena) and a touch swallowed by the cooldown fire
-- nothing.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local playerEnteredEvent = ReplicatedStorage.Shared.Arena.ArenaEvents.PlayerEntered :: BindableEvent

local PAD_HEIGHT = 600
local ARRIVAL_HEIGHT = 700

return {
	name = "entry_fires_event",

	setup = function(ctx: any)
		ctx.fx = arenaEntryFixture.new()
		ctx.fired = {}
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		local character = player and player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not player or not hrp or not hrp:IsA("BasePart") then
			return
		end
		local fx = ctx.fx
		ctx.entered = fx:enter(player)
		ArenaEntryService.resetState()

		ctx.connection = playerEnteredEvent.Event:Connect(function(who: any, arenaId: any)
			table.insert(ctx.fired, { player = who, arenaId = arenaId })
		end)

		local pad = fx:part(ArenaEntryConstants.PAD_TAG, fx.arenaId, CFrame.new(0, PAD_HEIGHT, 0))
		local otherPad = fx:part(ArenaEntryConstants.PAD_TAG, "EntryOtherArena", CFrame.new(0, PAD_HEIGHT, 0))
		fx:part(ArenaEntryConstants.ARRIVAL_TAG, fx.arenaId, CFrame.new(0, ARRIVAL_HEIGHT, 0))

		ctx.refused = ArenaEntryService.handleTouch(otherPad, hrp)
		task.wait()
		ctx.firedAfterRefusal = #ctx.fired

		ctx.first = ArenaEntryService.handleTouch(pad, hrp)
		ctx.second = ArenaEntryService.handleTouch(pad, hrp)
		-- The event may be delivered deferred; give it a frame.
		task.wait()
		task.wait()
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.entered then
			return false, "no player on the server, or the transfer failed"
		end
		local Result = ArenaEntryConstants.Result
		if ctx.refused ~= Result.WrongArena or ctx.first ~= Result.Teleported or ctx.second ~= Result.Cooldown then
			return false, string.format("touch results were %s / %s / %s, expected wrong_arena / teleported / cooldown",
				tostring(ctx.refused), tostring(ctx.first), tostring(ctx.second))
		end
		if ctx.firedAfterRefusal ~= 0 then
			return false, "a refused touch fired PlayerEntered"
		end
		if #ctx.fired ~= 1 then
			return false, string.format("PlayerEntered fired %d times for one teleport plus a cooldown touch, expected 1", #ctx.fired)
		end
		local event = ctx.fired[1]
		if event.player ~= ctx.player then
			return false, "PlayerEntered carried a different player"
		end
		if event.arenaId ~= ctx.fx.arenaId then
			return false, string.format("PlayerEntered carried arena %s, expected %s", tostring(event.arenaId), ctx.fx.arenaId)
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.connection then
			ctx.connection:Disconnect()
		end
		if ctx.fx then
			ctx.fx:cleanup(ctx.player)
		end
		ArenaEntryService.resetState()
	end,
}
