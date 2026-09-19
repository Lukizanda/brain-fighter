--!strict

----------------------------------------------------------------------
-- pve_round_ends_on_empty_roster — the stage-4a trap, closed
----------------------------------------------------------------------
-- Stage 4a recorded that a session left empty mid-round stays Active, and
-- said the fix belonged to the mode's win condition rather than to
-- transferPlayer. PvEBoss ends its round when the score table — whose
-- membership follows the roster exactly — is empty. This test starts a
-- PvE round with the harness player on the roster, removes them, and
-- asserts the round ends on its own.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local PvEBoss = require(ReplicatedStorage.Shared.GameMode.Modes.PvEBoss)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local RoundState = GameModeConstants.RoundState

local TEST_ARENA = "Stage5TestEmpty"
local ROUND_START_TIMEOUT_SEC = GameModeConstants.PVE_COUNTDOWN_SEC + 5
local ROUND_END_TIMEOUT_SEC = 3
local POLL_SEC = 0.1

type Ctx = {
	player: Player?,
	s5Session: SessionRegistry.Session?,
	s5ReachedActive: boolean,
	s5StateAfter: string?,
}

local function waitFor(predicate: () -> boolean, timeoutSec: number): boolean
	local deadline = os.clock() + timeoutSec
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(POLL_SEC)
	end
	return predicate()
end

return {
	name = "pve_round_ends_on_empty_roster",

	setup = function(ctx: Ctx)
		ctx.s5ReachedActive = false
		local player = ctx.player
		if not player then
			return
		end
		local session = SessionRegistry.create(TEST_ARENA, PvEBoss)
		session:addPlayer(player)
		ctx.s5Session = session
	end,

	run = function(ctx: Ctx)
		local session = ctx.s5Session
		local player = ctx.player
		if not session or not player then
			return
		end

		session:start()
		ctx.s5ReachedActive = waitFor(function()
			return session:isActive()
		end, ROUND_START_TIMEOUT_SEC)
		if not ctx.s5ReachedActive then
			return
		end

		session:removePlayer(player)

		waitFor(function()
			return session:getState() == RoundState.PostRound
		end, ROUND_END_TIMEOUT_SEC)
		ctx.s5StateAfter = session:getState()
	end,

	teardown = function(_ctx: Ctx)
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local session = ctx.s5Session
		if not ctx.player or not session then
			return false, "no player on the server — the round could never have started"
		end
		if not ctx.s5ReachedActive then
			return false, string.format("the PvE session never reached Active (state=%s)", session:getState())
		end
		if ctx.s5StateAfter ~= RoundState.PostRound then
			return false, string.format("an emptied roster left the round in %s — the stage-4a trap is still open",
				tostring(ctx.s5StateAfter))
		end
		return true, nil
	end,
}
