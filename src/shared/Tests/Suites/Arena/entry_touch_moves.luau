--!strict

----------------------------------------------------------------------
-- entry_touch_moves — a touch moves the character
----------------------------------------------------------------------
-- Drives `ArenaEntryService.handleTouch` with the harness player's real
-- character (the engine's Touched event adds only the `hit` part, so this
-- is the whole decision). Checks: a pad of another arena refuses, a pad of
-- the player's arena teleports to stand on the arrival part facing its look
-- direction, and an immediate second touch hits the cooldown.
--
-- NOT covered: the physical Touched signal firing from a walking character,
-- and the client drawing the depart/arrive cues (see vfx-sfx.md — that needs
-- a client view).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local PAD_HEIGHT = 600
local ARRIVAL_HEIGHT = 700
local ARRIVAL_YAW_DEG = 90
local POSITION_TOLERANCE_STUDS = 0.5
local HEADING_TOLERANCE = 0.05

return {
	name = "entry_touch_moves",

	setup = function(ctx: any)
		ctx.fx = arenaEntryFixture.new()
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

		local pad = fx:part(ArenaEntryConstants.PAD_TAG, fx.arenaId, CFrame.new(0, PAD_HEIGHT, 0))
		local otherPad = fx:part(ArenaEntryConstants.PAD_TAG, "EntryOtherArena", CFrame.new(0, PAD_HEIGHT, 0))
		local arrival = fx:part(
			ArenaEntryConstants.ARRIVAL_TAG,
			fx.arenaId,
			CFrame.new(0, ARRIVAL_HEIGHT, 0) * CFrame.Angles(0, math.rad(ARRIVAL_YAW_DEG), 0)
		)
		ctx.arrival = arrival

		ctx.wrongArena = ArenaEntryService.handleTouch(otherPad, hrp)
		ctx.afterWrong = hrp.Position
		ctx.first = ArenaEntryService.handleTouch(pad, hrp)
		ctx.hrp = hrp
		ctx.second = ArenaEntryService.handleTouch(pad, hrp)
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.entered then
			return false, "no player on the server, or the transfer failed"
		end
		local Result = ArenaEntryConstants.Result
		if ctx.wrongArena ~= Result.WrongArena then
			return false, "a pad of another arena returned " .. tostring(ctx.wrongArena)
		end
		if ctx.first ~= Result.Teleported then
			return false, "touch on the player's own arena pad returned " .. tostring(ctx.first)
		end
		if ctx.second ~= Result.Cooldown then
			return false, "an immediate second touch returned " .. tostring(ctx.second)
		end

		local arrival: BasePart = ctx.arrival
		local hrp: BasePart = ctx.hrp
		local expected = ArenaEntryService.standingCFrame(arrival)
		if (hrp.Position - expected.Position).Magnitude > POSITION_TOLERANCE_STUDS then
			return false, string.format("character at %s, wanted %s", tostring(hrp.Position), tostring(expected.Position))
		end
		local top = arrival.Position.Y + arrival.Size.Y / 2
		if hrp.Position.Y <= top then
			return false, "character is not above the arrival part's top surface"
		end
		local look = hrp.CFrame.LookVector
		local want = arrival.CFrame.LookVector
		if (Vector3.new(look.X, 0, look.Z) - Vector3.new(want.X, 0, want.Z)).Magnitude > HEADING_TOLERANCE then
			return false, "character does not face the way the arrival part faces"
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
