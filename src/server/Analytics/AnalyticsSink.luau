--!strict

----------------------------------------------------------------------
-- AnalyticsSink
----------------------------------------------------------------------
-- The one place that talks to Roblox's AnalyticsService. Every call is
-- budgeted, pcall-wrapped and counted, so the reporter above it can
-- treat "log this" as fire-and-forget and a probe can ask how many
-- events actually left the server.
--
-- The backend is injectable: the live script hands in the engine
-- service, the suite hands in a recorder. Nothing here knows what a
-- funnel step means — that is OnboardingFunnel's job.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local AnalyticsConstants = require(script.Parent.AnalyticsConstants)
local RateLimiter = require(script.Parent.Parent.Utility.RateLimiter)

local log = Logger.new("AnalyticsSink")

export type Fields = { [string]: string }

export type Backend = {
	onboardingStep: (player: Player, step: number, stepName: string, fields: Fields?) -> (),
	custom: (player: Player, eventName: string, value: number, fields: Fields?) -> (),
}

export type Counts = { sent: number, dropped: number, failed: number }

export type Sink = {
	onboardingStep: (self: Sink, player: Player, step: number, stepName: string, fields: Fields?) -> boolean,
	custom: (self: Sink, player: Player, eventName: string, value: number, fields: Fields?) -> boolean,
	counts: (self: Sink) -> Counts,
}

local AnalyticsSink = {}

-- The engine service, reached lazily so a test VM without it still
-- loads this module.
function AnalyticsSink.engineBackend(): Backend
	local service = game:GetService("AnalyticsService") :: any
	return {
		onboardingStep = function(player, step, stepName, fields)
			service:LogOnboardingFunnelStepEvent(player, step, stepName, fields)
		end,
		custom = function(player, eventName, value, fields)
			service:LogCustomEvent(player, eventName, value, fields)
		end,
	}
end

function AnalyticsSink.new(backend: Backend?, budget: any?): Sink
	local resolvedBackend = backend or AnalyticsSink.engineBackend()
	local limiter = budget or RateLimiter.new(AnalyticsConstants.SEND_BURST, AnalyticsConstants.SEND_PER_SEC)
	local counts: Counts = { sent = 0, dropped = 0, failed = 0 }

	local function send(label: string, call: () -> ()): boolean
		if not limiter:consume(AnalyticsConstants.BUDGET_KEY) then
			counts.dropped += 1
			log:warnThrottled("budget", AnalyticsConstants.DROP_WARN_INTERVAL_SEC,
				string.format("send budget exhausted — dropped %s (%d dropped so far)", label, counts.dropped))
			return false
		end
		local ok, err = pcall(call)
		if not ok then
			counts.failed += 1
			log:warnThrottled("failed:" .. label, AnalyticsConstants.DROP_WARN_INTERVAL_SEC,
				string.format("%s failed: %s", label, tostring(err)))
			return false
		end
		counts.sent += 1
		return true
	end

	local sink = {} :: Sink

	function sink:onboardingStep(player: Player, step: number, stepName: string, fields: Fields?): boolean
		return send("funnel " .. stepName, function()
			resolvedBackend.onboardingStep(player, step, stepName, fields)
		end)
	end

	function sink:custom(player: Player, eventName: string, value: number, fields: Fields?): boolean
		return send("event " .. eventName, function()
			resolvedBackend.custom(player, eventName, value, fields)
		end)
	end

	function sink:counts(): Counts
		return { sent = counts.sent, dropped = counts.dropped, failed = counts.failed }
	end

	return sink
end

return AnalyticsSink
