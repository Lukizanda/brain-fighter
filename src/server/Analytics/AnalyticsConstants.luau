--!strict

----------------------------------------------------------------------
-- AnalyticsConstants
----------------------------------------------------------------------
-- Names and numbers for the Phase 5.4 analytics: the onboarding funnel
-- steps, the custom event names, the custom-field keys Roblox accepts,
-- and the send budget. Everything the dashboard will show by name is
-- declared here once, so a renamed step cannot drift between the code
-- that logs it and the page that reads it (wiki/systems/Analytics.md).
----------------------------------------------------------------------

local AnalyticsConstants = {}

-- The onboarding funnel mirrors the Phase 5.4 cold-player milestone:
-- a player with no instructions completes shoot → memorize → cast →
-- boss damage in their first session. Steps are logged strictly in
-- order and once per player per server (see OnboardingFunnel).
AnalyticsConstants.Funnel = {
	Joined = 1,
	FirstPop = 2,
	FirstMemorize = 3,
	FirstCast = 4,
	FirstBossDamage = 5,
	BossKill = 6,
}

local FUNNEL_NAMES: { [number]: string } = {
	[1] = "joined",
	[2] = "first_pop",
	[3] = "first_memorize",
	[4] = "first_cast",
	[5] = "first_boss_damage",
	[6] = "boss_kill",
}
AnalyticsConstants.FUNNEL_NAMES = FUNNEL_NAMES

-- Custom (loop-health) events. Per-occurrence events are the rare ones
-- (a word, a cast); block pops are aggregated per player and flushed
-- on leave, because forty blocks popping in a minute would eat the
-- server's whole send budget on the least interesting signal.
AnalyticsConstants.Event = {
	WordMemorized = "word_memorized", -- value = energy credited
	MemorizeFizzle = "memorize_fizzle", -- value = 1
	SpellCast = "spell_cast", -- value = energy cost
	RoundPlayed = "round_played", -- value = 1, per roster member at RoundEnded
	BlocksPopped = "blocks_popped", -- value = pops this server session, on leave
	SessionLength = "session_length", -- value = seconds, on leave
}

-- Roblox allows up to three custom fields per event, keyed by
-- Enum.AnalyticsCustomFieldKeys. Resolved through the enum when it
-- exists so a renamed key fails loudly at boot rather than silently
-- dropping a field; the string fallback is the documented name.
local function fieldKey(index: number): string
	local fallback = string.format("customField%02d", index)
	local ok, name = pcall(function()
		return ((Enum :: any).AnalyticsCustomFieldKeys)[string.format("CustomField%02d", index)].Name
	end)
	return if ok and type(name) == "string" then name else fallback
end

AnalyticsConstants.Field = {
	One = fieldKey(1),
	Two = fieldKey(2),
	Three = fieldKey(3),
}

-- Roblox rate-limits analytics to 120 events per minute per server plus
-- a per-player allowance. Stay under it with a token bucket: a burst
-- for a busy round end, then ninety a minute sustained. Dropped events
-- are counted, never queued — late analytics is worse than none.
AnalyticsConstants.SEND_BURST = 60
AnalyticsConstants.SEND_PER_SEC = 1.5
AnalyticsConstants.BUDGET_KEY = "server"

-- Player attributes the reporter publishes so a probe (or a curious
-- designer) can watch the funnel without a dashboard.
AnalyticsConstants.Attributes = {
	FunnelStep = "Analytics_FunnelStep",
	Events = "Analytics_Events",
}

-- One warning per this long when the budget drops events.
AnalyticsConstants.DROP_WARN_INTERVAL_SEC = 30

return AnalyticsConstants
