--!strict

----------------------------------------------------------------------
-- registry_views_agree — forPlayer / forArena / rosterOf are one truth
----------------------------------------------------------------------
-- SessionRegistry answers "where is this player" three ways: by player
-- (`forPlayer`), by arena (`forArena`, then `hasPlayer`) and by roster
-- listing (`rosterOf`). They read two tables, and a transfer writes both;
-- this test asserts the three views agree for every session after a
-- transfer, and that the queue flag behaves: set while in the lobby,
-- cleared by the transfer out.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local NoOpMode = require(ReplicatedStorage.Shared.GameMode.Modes.NoOpMode)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local TEST_ARENA = "Chunk8TestC"
local MISSING_ARENA = "Chunk8NoSuchArena"

type Ctx = {
	player: Player?,
	c8Home: SessionRegistry.Session?,
	c8HomeId: string,
	c8QueuedOk: boolean,
	c8StateQueued: any,
	c8Mismatches: { string },
	c8StateAfter: any,
	c8ArenaAfter: any,
	c8SessionArenaAfter: string?,
	c8RosterAfter: { Player }?,
}

-- Every session, three ways. A mismatch is a session where the roster
-- says one thing and the player map says another.
local function collectMismatches(player: Player): { string }
	local mismatches: { string } = {}
	local owner = SessionRegistry.forPlayer(player)

	for arenaId, session in SessionRegistry.all() do
		local roster = SessionRegistry.rosterOf(arenaId)
		local viaRoster = roster ~= nil and table.find(roster, player) ~= nil
		local viaSession = session:hasPlayer(player)
		local viaOwner = owner == session and SessionRegistry.forArena(arenaId) == owner

		if viaRoster ~= viaSession or viaSession ~= viaOwner then
			table.insert(mismatches, string.format("%s: rosterOf=%s hasPlayer=%s forPlayer=%s",
				arenaId, tostring(viaRoster), tostring(viaSession), tostring(viaOwner)))
		end
	end

	return mismatches
end

return {
	name = "registry_views_agree",

	setup = function(ctx: Ctx)
		ctx.c8Mismatches = {}
		local player = ctx.player
		if not player then
			return
		end
		local home = SessionRegistry.forPlayer(player)
		assert(home, "the harness player has no session")
		ctx.c8Home = home
		ctx.c8HomeId = home:getArenaId()
		SessionRegistry.create(TEST_ARENA, NoOpMode)
	end,

	run = function(ctx: Ctx)
		local player = ctx.player
		if not player then
			return
		end

		ctx.c8QueuedOk = SessionRegistry.setQueued(player, true)
		ctx.c8StateQueued = player:GetAttribute(Arena.STATE_ATTRIBUTE)

		SessionRegistry.transferPlayer(player, TEST_ARENA)
		ctx.c8Mismatches = collectMismatches(player)
		ctx.c8StateAfter = player:GetAttribute(Arena.STATE_ATTRIBUTE)
		ctx.c8ArenaAfter = player:GetAttribute(Arena.ID_ATTRIBUTE)
		local owner = SessionRegistry.forPlayer(player)
		ctx.c8SessionArenaAfter = owner and owner:getArenaId() or nil
		ctx.c8RosterAfter = SessionRegistry.rosterOf(TEST_ARENA)

		SessionRegistry.transferPlayer(player, ctx.c8HomeId)
	end,

	teardown = function(ctx: Ctx)
		local player = ctx.player
		if player and ctx.c8Home and SessionRegistry.forPlayer(player) ~= ctx.c8Home then
			SessionRegistry.transferPlayer(player, ctx.c8HomeId)
		end
		if player then
			SessionRegistry.setQueued(player, false)
		end
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local player = ctx.player
		if not player or not ctx.c8Home then
			return false, "no player on the server — nothing to look up"
		end

		if not ctx.c8QueuedOk then
			return false, "setQueued returned false for a player with a session"
		end
		if ctx.c8StateQueued ~= Arena.PlayerState.Queued then
			return false, string.format("PlayerState while queued in the lobby is %s", tostring(ctx.c8StateQueued))
		end

		if #ctx.c8Mismatches > 0 then
			return false, "views disagree after transfer: " .. table.concat(ctx.c8Mismatches, "; ")
		end
		if ctx.c8StateAfter ~= Arena.PlayerState.InArena then
			return false, string.format("transfer did not clear the queue flag (PlayerState=%s)", tostring(ctx.c8StateAfter))
		end
		if ctx.c8ArenaAfter ~= ctx.c8SessionArenaAfter then
			return false, string.format("ArenaId attribute (%s) disagrees with forPlayer's arena (%s)",
				tostring(ctx.c8ArenaAfter), tostring(ctx.c8SessionArenaAfter))
		end
		local roster = ctx.c8RosterAfter
		if not roster or #roster ~= 1 or roster[1] ~= player then
			return false, "rosterOf(test arena) is not exactly the transferred player"
		end

		-- Absence is nil, not an empty session.
		if SessionRegistry.forArena(MISSING_ARENA) ~= nil or SessionRegistry.rosterOf(MISSING_ARENA) ~= nil then
			return false, "a missing arena resolved to a session"
		end

		-- And the round trip put things back.
		if SessionRegistry.forPlayer(player) ~= ctx.c8Home then
			return false, "the player did not return to the home session"
		end
		if #collectMismatches(player) > 0 then
			return false, "views disagree after the transfer back"
		end

		return true, nil
	end,
}
