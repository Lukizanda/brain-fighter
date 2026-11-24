--!strict

----------------------------------------------------------------------
-- ledger_grants_bomb_word — a defused bomb credits its word's share without touching the buffer
----------------------------------------------------------------------
-- Direct (EnergyLedger.creditWordGrant):
--   share     the ceiling rises by floor(scored energy * scale), the score
--             being MemorizeAction.scoreTiles's (floor included)
--   held      held letters and count are unchanged, and the held letters
--             still memorize afterwards
--   cap       a grant at the cap clamps at CAP_PER_COLOR, same as a memorize
--   refuses   a non-word, a non-reservoir colour and a scale outside (0, 1]
--             credit nothing
-- Through the REAL Boss BombDefused BindableEvent (needs the harness player):
--   once      one event, one grant, one WordGranted(.., "bomb")
--   nil       a nil player credits nothing and fires nothing
--   funnel    WordMemorized never fires, and the player's onboarding funnel
--             step and custom-event count do not move
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)
local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)
local AnalyticsConstants = require(ServerScriptService.Server.Analytics.AnalyticsConstants)
local EconomyConstants = require(ServerScriptService.Server.Economy.EconomyConstants)
local EnergyLedger = require(ServerScriptService.Server.Economy.EnergyLedger)

local server = ServerScriptService.Server
local bombDefusedEvent = server.Boss.Events.BombDefused :: BindableEvent
local wordGrantedEvent = server.Economy.Events.WordGranted :: BindableEvent
local wordMemorizedEvent = server.Economy.Events.WordMemorized :: BindableEvent

local PLAYER = 1005
local WORD = "CAT"
local COLOR = "red"
local OTHER_COLOR = "blue"
local ARENA = "LedgerGrantTest"
local HALF = 0.5
local OVER_SCALE = 1.5
local NEAR_CAP_GAP = 1
-- BindableEvent handlers run deferred; see ledger_resets_on_round_start.
local SIGNAL_SETTLE_SEC = 0.2

type Ctx = {
	player: Player?,
	grantGranted: { { word: string, source: string, amounts: { [string]: number } } },
	grantMemorized: number,
	grantStartStep: number,
	grantStartEvents: number,
	grantConns: { RBXScriptConnection },
	-- The player's ceiling right after the real event, read in run: verify's
	-- direct checks call EnergyLedger.reset(), which wipes every account.
	grantCredited: number,
}

local function tilesOf(word: string, color: string): { { letter: string, color: string } }
	local tiles = {}
	for i = 1, #word do
		table.insert(tiles, { letter = string.sub(word, i, i), color = color })
	end
	return tiles
end

local function attr(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

return {
	name = "ledger_grants_bomb_word",

	setup = function(ctx: Ctx)
		EnergyLedger.reset()
		ctx.grantGranted = {}
		ctx.grantMemorized = 0
		ctx.grantConns = {
			wordGrantedEvent.Event:Connect(function(_player: Player, word: string, amounts: { [string]: number }, source: string)
				table.insert(ctx.grantGranted, { word = word, source = source, amounts = amounts })
			end),
			wordMemorizedEvent.Event:Connect(function()
				ctx.grantMemorized += 1
			end),
		}
		local player = ctx.player
		if player then
			ctx.grantStartStep = attr(player, AnalyticsConstants.Attributes.FunnelStep)
			ctx.grantStartEvents = attr(player, AnalyticsConstants.Attributes.Events)
		end
	end,

	teardown = function(ctx: Ctx)
		for _, conn in ctx.grantConns do
			conn:Disconnect()
		end
		EnergyLedger.reset()
	end,

	run = function(ctx: Ctx)
		local player = ctx.player
		if not player then
			return
		end
		-- Phase A of verify's real-event checks, driven here so the signals
		-- settle before verify reads them. Nil player first: it must not
		-- credit anyone or fire anything.
		bombDefusedEvent:Fire(nil, WORD, COLOR, ARENA, #WORD)
		task.wait(SIGNAL_SETTLE_SEC)
		ctx.grantGranted = {}
		EnergyLedger.reset()

		-- The sixth argument is the boss type's scale, as BossBombs sends it.
		bombDefusedEvent:Fire(player, WORD, COLOR, ARENA, #WORD, HALF)
		task.wait(SIGNAL_SETTLE_SEC)
		ctx.grantCredited = EnergyLedger.snapshot(player.UserId).ceiling[COLOR] or 0
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local scored = MemorizeAction.scoreTiles(tilesOf(WORD, COLOR) :: any)
		if not scored then
			return false, WORD .. " does not score; the fixture word is wrong"
		end
		local full = scored.energyByColor[COLOR] or 0
		local expectedShare = math.floor(full * HALF)
		if expectedShare <= 0 then
			return false, "the fixture word's half share is zero; the test would be vacuous"
		end

		----------------------------------------------------------------
		-- 1. Share: floor(scored * scale), added to the ceiling.
		----------------------------------------------------------------
		EnergyLedger.reset()
		local verdict = EnergyLedger.creditWordGrant(PLAYER, WORD, COLOR, HALF)
		if not verdict.ok or not verdict.energyByColor then
			return false, "a real word was refused: " .. tostring(verdict.reason)
		end
		if verdict.energyByColor[COLOR] ~= expectedShare then
			return false, string.format("grant returned %s, expected floor(%d * %s) = %d",
				tostring(verdict.energyByColor[COLOR]), full, tostring(HALF), expectedShare)
		end
		local ceiling = EnergyLedger.snapshot(PLAYER).ceiling
		if (ceiling[COLOR] or 0) ~= expectedShare then
			return false, string.format("ceiling %s is %s, expected %d", COLOR, tostring(ceiling[COLOR]), expectedShare)
		end
		if (ceiling[OTHER_COLOR] or 0) ~= 0 then
			return false, "a one-colour word raised another colour's ceiling"
		end

		----------------------------------------------------------------
		-- 2. Held letters and count are unchanged, and still memorize.
		----------------------------------------------------------------
		EnergyLedger.reset()
		for i = 1, #WORD do
			EnergyLedger.creditBlock(PLAYER, string.sub(WORD, i, i), COLOR)
		end
		local before = EnergyLedger.snapshot(PLAYER)
		EnergyLedger.creditWordGrant(PLAYER, WORD, COLOR, HALF)
		local after = EnergyLedger.snapshot(PLAYER)
		if after.heldCount ~= before.heldCount then
			return false, string.format("a grant moved the held count %d -> %d", before.heldCount, after.heldCount)
		end
		local memorized = EnergyLedger.reportMemorize(PLAYER, tilesOf(WORD, COLOR), false)
		if not memorized.ok then
			return false, "the held letters no longer memorized after a grant: " .. tostring(memorized.reason)
		end
		local afterMemorize = EnergyLedger.snapshot(PLAYER).ceiling[COLOR] or 0
		if afterMemorize ~= math.min(expectedShare + full, EnergyReservoirs.CAP_PER_COLOR) then
			return false, string.format("grant then memorize left %d, expected the sum clamped at the cap", afterMemorize)
		end

		----------------------------------------------------------------
		-- 3. A grant at the cap clamps, and energy past it is lost.
		----------------------------------------------------------------
		EnergyLedger.reset()
		EnergyLedger.devSetCeiling(PLAYER, COLOR, EnergyReservoirs.CAP_PER_COLOR - NEAR_CAP_GAP)
		EnergyLedger.creditWordGrant(PLAYER, WORD, COLOR, HALF)
		if (EnergyLedger.snapshot(PLAYER).ceiling[COLOR] or 0) ~= EnergyReservoirs.CAP_PER_COLOR then
			return false, "a grant near the cap did not clamp at CAP_PER_COLOR"
		end
		EnergyLedger.creditWordGrant(PLAYER, WORD, COLOR, HALF)
		if (EnergyLedger.snapshot(PLAYER).ceiling[COLOR] or 0) ~= EnergyReservoirs.CAP_PER_COLOR then
			return false, "a grant at the cap moved the ceiling"
		end

		----------------------------------------------------------------
		-- 4. Bad input credits nothing.
		----------------------------------------------------------------
		EnergyLedger.reset()
		local bad = {
			{ "XQZXQ", COLOR, HALF, "a non-word" },
			{ WORD, "wild", HALF, "a wild colour" },
			{ WORD, COLOR, 0, "scale 0" },
			{ WORD, COLOR, OVER_SCALE, "a scale above the max" },
			{ WORD, COLOR, 0 / 0, "a NaN scale" },
		}
		for _, case in bad do
			local got = EnergyLedger.creditWordGrant(PLAYER, case[1] :: string, case[2] :: string, case[3] :: number)
			if got.ok then
				return false, "accepted " .. (case[4] :: string)
			end
		end
		if (EnergyLedger.snapshot(PLAYER).ceiling[COLOR] or 0) ~= 0 then
			return false, "a refused grant still credited"
		end

		----------------------------------------------------------------
		-- 5. The real event (needs the harness player).
		----------------------------------------------------------------
		local player = ctx.player
		if not player then
			return true, "ledger checks passed; no player, real-event checks skipped"
		end

		-- The event above carried HALF, and the grant uses the event's scale
		-- (not the boss type's, which is tuning and changes).
		local scale = HALF
		local expectedEvent = math.floor(full * scale)

		if #ctx.grantGranted ~= 1 then
			return false, string.format("one BombDefused fired %d WordGranted events (nil-player event included, expected 1 total)", #ctx.grantGranted)
		end
		local granted = ctx.grantGranted[1]
		if granted.source ~= EconomyConstants.GRANT_SOURCE_BOMB or granted.word ~= WORD then
			return false, string.format("WordGranted carried (%s, %s)", granted.word, granted.source)
		end
		local credited = ctx.grantCredited or 0
		if credited ~= expectedEvent then
			return false, string.format("one event credited %d, expected exactly one grant of %d", credited, expectedEvent)
		end
		if ctx.grantMemorized ~= 0 then
			return false, "a grant fired WordMemorized " .. ctx.grantMemorized .. " times"
		end
		if attr(player, AnalyticsConstants.Attributes.FunnelStep) ~= ctx.grantStartStep then
			return false, "a grant advanced the onboarding funnel"
		end
		if attr(player, AnalyticsConstants.Attributes.Events) ~= ctx.grantStartEvents then
			return false, "a grant was reported as a custom analytics event"
		end

		return true, string.format("share %d of %d, one event one grant", expectedShare, full)
	end,
}
