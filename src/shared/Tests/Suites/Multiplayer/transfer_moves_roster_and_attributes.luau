--!strict

----------------------------------------------------------------------
-- transfer_moves_roster_and_attributes — SessionRegistry.transferPlayer
----------------------------------------------------------------------
-- A transfer is a roster move plus the two Player attributes every client
-- reads (`ArenaId`, `PlayerState`). Both halves have to move together:
-- the HUD gate, LobbyService's occupancy counts and the portal validator
-- all key on the attributes, while broadcasts and scores key on the
-- roster. This test moves the harness player into a throwaway arena and
-- back, checking both halves at each end.
--
-- Uses the real `transferPlayer`, so the character is pivoted to the test
-- arena's spawn and back to a lobby pad. That is the behaviour, not a
-- side effect to avoid.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local NoOpMode = require(ReplicatedStorage.Shared.GameMode.Modes.NoOpMode)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local TEST_ARENA = "Chunk8TestB"

type Snapshot = {
	session: SessionRegistry.Session?,
	inTest: boolean,
	inHome: boolean,
	arenaAttr: any,
	stateAttr: any,
}

type Ctx = {
	player: Player?,
	c8Home: SessionRegistry.Session?,
	c8HomeId: string,
	c8Test: SessionRegistry.Session?,
	c8OutOk: boolean,
	c8BackOk: boolean,
	c8Out: Snapshot?,
	c8Back: Snapshot?,
}

local function snapshot(player: Player, home: SessionRegistry.Session, test: SessionRegistry.Session): Snapshot
	return {
		session = SessionRegistry.forPlayer(player),
		inTest = test:hasPlayer(player),
		inHome = home:hasPlayer(player),
		arenaAttr = player:GetAttribute(Arena.ID_ATTRIBUTE),
		stateAttr = player:GetAttribute(Arena.STATE_ATTRIBUTE),
	}
end

return {
	name = "transfer_moves_roster_and_attributes",

	setup = function(ctx: Ctx)
		local player = ctx.player
		if not player then
			return
		end
		local home = SessionRegistry.forPlayer(player)
		assert(home, "the harness player has no session")
		ctx.c8Home = home
		ctx.c8HomeId = home:getArenaId()
		ctx.c8Test = SessionRegistry.create(TEST_ARENA, NoOpMode)
	end,

	run = function(ctx: Ctx)
		local player = ctx.player
		local home = ctx.c8Home
		local test = ctx.c8Test
		if not player or not home or not test then
			return
		end

		ctx.c8OutOk = SessionRegistry.transferPlayer(player, TEST_ARENA)
		ctx.c8Out = snapshot(player, home, test)

		ctx.c8BackOk = SessionRegistry.transferPlayer(player, ctx.c8HomeId)
		ctx.c8Back = snapshot(player, home, test)
	end,

	teardown = function(ctx: Ctx)
		local player = ctx.player
		if player and ctx.c8Home and SessionRegistry.forPlayer(player) ~= ctx.c8Home then
			SessionRegistry.transferPlayer(player, ctx.c8HomeId)
		end
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local player = ctx.player
		local home = ctx.c8Home
		local test = ctx.c8Test
		local out = ctx.c8Out
		local back = ctx.c8Back
		if not player or not home or not test or not out or not back then
			return false, "no player on the server — nothing to transfer"
		end

		if not ctx.c8OutOk then
			return false, "transferPlayer into the test arena returned false"
		end
		if out.session ~= test then
			return false, "after the transfer out, forPlayer does not return the test session"
		end
		if not out.inTest or out.inHome then
			return false, string.format("roster after transfer out: inTest=%s inHome=%s",
				tostring(out.inTest), tostring(out.inHome))
		end
		if out.arenaAttr ~= TEST_ARENA then
			return false, string.format("ArenaId attribute after transfer out is %s", tostring(out.arenaAttr))
		end
		-- NoOp runs rounds, so being in its session is InArena.
		if out.stateAttr ~= Arena.PlayerState.InArena then
			return false, string.format("PlayerState after transfer out is %s", tostring(out.stateAttr))
		end

		if not ctx.c8BackOk then
			return false, "transferPlayer back home returned false"
		end
		if back.session ~= home then
			return false, "after the transfer back, forPlayer does not return the home session"
		end
		if back.inTest or not back.inHome then
			return false, string.format("roster after transfer back: inTest=%s inHome=%s",
				tostring(back.inTest), tostring(back.inHome))
		end
		if back.arenaAttr ~= ctx.c8HomeId then
			return false, string.format("ArenaId attribute after transfer back is %s", tostring(back.arenaAttr))
		end
		if back.stateAttr ~= Arena.PlayerState.InLobby then
			return false, string.format("PlayerState after transfer back is %s", tostring(back.stateAttr))
		end

		return true, nil
	end,
}
