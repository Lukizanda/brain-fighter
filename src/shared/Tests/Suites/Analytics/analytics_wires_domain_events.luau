--!strict

----------------------------------------------------------------------
-- analytics_wires_domain_events — the real reporter hears the real events
----------------------------------------------------------------------
-- Shape 2 (MultiplayerTestPattern): fire the server-side domain
-- BindableEvents by hand for the harness player and watch the REAL
-- AnalyticsReporter advance the funnel it publishes on the Player
-- (`Analytics_FunnelStep`) and count custom events (`Analytics_Events`).
-- This is the seam that drifts: a renamed event or a reporter that never
-- connected leaves every dashboard row at "joined" with clean logs.
--
-- The player already reached step 1 on join, and may have popped a
-- block before the suite ran, so every assertion is relative to where
-- the funnel stood at setup rather than to absolute numbers.
--
-- Boss damage is a PlayerDamaged whose target is a Boss-tagged rig; a
-- throwaway rig is built for it. Boss kill is a BossDefeated for an
-- arena whose roster holds the player: a throwaway NoOp session, roster
-- only, as the stage 5/6 tests do.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AnalyticsConstants = require(ServerScriptService.Server.Analytics.AnalyticsConstants)
local BossSpawner = require(ServerScriptService.Server.Boss.Scripts.BossSpawner)
local NoOpMode = require(ReplicatedStorage.Shared.GameMode.Modes.NoOpMode)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local server = ServerScriptService.Server
local blockConsumedEvent = server.BlockShoot.Events.BlockConsumed :: BindableEvent
local wordMemorizedEvent = server.Economy.Events.WordMemorized :: BindableEvent
local memorizeFizzledEvent = server.Economy.Events.MemorizeFizzled :: BindableEvent
local spellCastEvent = server.SpellCast.Events.SpellCast :: BindableEvent
local playerDamagedEvent = server.Health.Events.PlayerDamaged :: BindableEvent
local bossDefeatedEvent = ReplicatedStorage.Shared.Boss.BossEvents.BossDefeated :: BindableEvent

local Step = AnalyticsConstants.Funnel
local ATTR = AnalyticsConstants.Attributes

local TEST_ARENA = "AnalyticsTestKill"
-- BindableEvent handlers run deferred; one frame is enough, this is slack.
local SETTLE_SEC = 0.2

type Ctx = {
	player: Player?,
	anStartStep: number?,
	anStartEvents: number?,
	anSteps: { [string]: number },
	anEvents: { [string]: number },
	anRig: Model?,
}

local function stepOf(player: Player): number
	local value = player:GetAttribute(ATTR.FunnelStep)
	return if type(value) == "number" then value else 0
end

local function eventsOf(player: Player): number
	local value = player:GetAttribute(ATTR.Events)
	return if type(value) == "number" then value else 0
end

local function bossRig(): Model
	local rig = Instance.new("Model")
	rig.Name = "AnalyticsTestBoss"
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = rig
	CollectionService:AddTag(rig, BossSpawner.BOSS_TAG)
	rig.Parent = workspace
	return rig
end

return {
	name = "analytics_wires_domain_events",

	setup = function(ctx: Ctx)
		ctx.anSteps = {}
		ctx.anEvents = {}
		local player = ctx.player
		if not player then
			return
		end
		ctx.anStartStep = stepOf(player)
		ctx.anStartEvents = eventsOf(player)
	end,

	run = function(ctx: Ctx)
		local player = ctx.player
		if not player then
			return
		end

		local function snap(label: string)
			task.wait(SETTLE_SEC)
			ctx.anSteps[label] = stepOf(player)
			ctx.anEvents[label] = eventsOf(player)
		end

		blockConsumedEvent:Fire(player, "A", "red", SessionRegistry.arenaIdFor(player))
		snap("pop")

		wordMemorizedEvent:Fire(player, "CAT", { red = 3, blue = 2 })
		snap("memorize")

		memorizeFizzledEvent:Fire(player)
		snap("fizzle")

		spellCastEvent:Fire(player, "Firebolt", "red", 1, 5, "AnalyticsTestBoss")
		snap("cast")

		local rig = bossRig()
		ctx.anRig = rig
		local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		playerDamagedEvent:Fire(player, humanoid, {
			finalDamage = 1, absorbed = 0, wasLethal = false, modifiersApplied = {},
		})
		snap("bossDamage")

		local session = SessionRegistry.create(TEST_ARENA, NoOpMode)
		session:addPlayer(player)
		bossDefeatedEvent:Fire(TEST_ARENA)
		snap("bossKill")
	end,

	teardown = function(ctx: Ctx)
		if ctx.anRig then
			ctx.anRig:Destroy()
			ctx.anRig = nil
		end
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local player = ctx.player
		if not player or ctx.anStartStep == nil or ctx.anStartEvents == nil then
			return false, "no player on the server — nothing to report on"
		end
		local failures: { string } = {}
		local function expect(label: string, ok: boolean)
			if not ok then
				table.insert(failures, label)
			end
		end

		local start = ctx.anStartStep
		expect("player had reached at least joined before the suite", start >= Step.Joined)

		-- Strict-next funnel: from step s, firing 2..6 in order lands on
		-- max(s, step) at each snapshot.
		local expected = {
			pop = Step.FirstPop, memorize = Step.FirstMemorize, cast = Step.FirstCast,
			bossDamage = Step.FirstBossDamage, bossKill = Step.BossKill,
		}
		for label, step in expected do
			local want = math.max(start, step)
			local got = ctx.anSteps[label]
			expect(string.format("after %s the funnel reads %s, expected %d", label, tostring(got), want), got == want)
		end

		-- Custom events: word_memorized, memorize_fizzle, spell_cast each add one.
		local e0 = ctx.anStartEvents
		expect("pop logged no custom event (pops aggregate)", ctx.anEvents.pop == e0)
		expect("word_memorized counted", ctx.anEvents.memorize == e0 + 1)
		expect("memorize_fizzle counted", ctx.anEvents.fizzle == e0 + 2)
		expect("spell_cast counted", ctx.anEvents.cast == e0 + 3)

		if #failures > 0 then
			return false, table.concat(failures, "; ")
		end
		return true, string.format("funnel %d → %d, %d custom events", start, ctx.anSteps.bossKill, ctx.anEvents.cast - e0)
	end,
}
