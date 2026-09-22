--!strict

----------------------------------------------------------------------
-- OnboardingFunnel
----------------------------------------------------------------------
-- Per-player progress through the onboarding steps, and the rule for
-- when a step is logged:
--
--   * once per player per server — a second first-pop is not news;
--   * strictly in order — step N is logged only when N-1 was. The
--     gameplay chain guarantees this for honest play (you cannot cast
--     without memorizing, or memorize without popping), so a gap only
--     ever comes from a dev cheat, and a funnel with a fabricated
--     middle step would be worse than one with a hole. A gap is
--     reported, not filled.
--
-- Pure over an injected sink; keyed by the player object, so the suite
-- can drive it with plain tables.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local AnalyticsConstants = require(script.Parent.AnalyticsConstants)

local log = Logger.new("OnboardingFunnel")

local GAP_WARN_INTERVAL_SEC = 30
local NOT_STARTED = 0

export type StepSink = {
	onboardingStep: (self: any, player: any, step: number, stepName: string, fields: any?) -> boolean,
}

export type Funnel = {
	-- Try to advance `player` to `step`. True only when the step was
	-- logged now: it is the next one and it was not logged before.
	reach: (self: Funnel, player: any, step: number) -> boolean,
	stepOf: (self: Funnel, player: any) -> number,
	forget: (self: Funnel, player: any) -> (),
}

local OnboardingFunnel = {}

function OnboardingFunnel.new(sink: StepSink): Funnel
	local reached: { [any]: number } = {}

	local funnel = {} :: Funnel

	function funnel:stepOf(player: any): number
		return reached[player] or NOT_STARTED
	end

	function funnel:reach(player: any, step: number): boolean
		local name = AnalyticsConstants.FUNNEL_NAMES[step]
		assert(name ~= nil, "OnboardingFunnel: unknown step " .. tostring(step))

		local current = reached[player] or NOT_STARTED
		if step <= current then
			return false
		end
		if step ~= current + 1 then
			log:infoThrottled(string.format("gap:%s:%d", tostring(player), step), GAP_WARN_INTERVAL_SEC,
				string.format("%s reached %s (%d) from step %d — gap, not logged",
					tostring(player), name, step, current))
			return false
		end

		if not sink:onboardingStep(player, step, name, nil) then
			-- Budget or backend refused. Leave the step unreached so the
			-- next trigger retries rather than silently losing the row.
			return false
		end
		reached[player] = step
		return true
	end

	function funnel:forget(player: any)
		reached[player] = nil
	end

	return funnel
end

return OnboardingFunnel
