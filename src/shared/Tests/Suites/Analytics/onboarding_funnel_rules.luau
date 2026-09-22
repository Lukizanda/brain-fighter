--!strict

----------------------------------------------------------------------
-- onboarding_funnel_rules — once, in order, per player
----------------------------------------------------------------------
-- Pure check of OnboardingFunnel against a recording sink and two fake
-- players. Pins the three rules the dashboard depends on: a step logs
-- once per player, only as the next step (a gap is reported, not
-- filled), and one player's progress never touches another's. Also
-- pins that a refused send leaves the step unreached so the next
-- trigger retries.
----------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")

local AnalyticsConstants = require(ServerScriptService.Server.Analytics.AnalyticsConstants)
local OnboardingFunnel = require(ServerScriptService.Server.Analytics.OnboardingFunnel)

local Step = AnalyticsConstants.Funnel

type Logged = { player: any, step: number, name: string }

local function recordingSink(): (any, { Logged }, { accept: boolean })
	local logged: { Logged } = {}
	local gate = { accept = true }
	local sink = {}
	function sink:onboardingStep(player: any, step: number, name: string, _fields: any?): boolean
		if not gate.accept then
			return false
		end
		table.insert(logged, { player = player, step = step, name = name })
		return true
	end
	return sink, logged, gate
end

return {
	name = "onboarding_funnel_rules",

	verify = function(_ctx): (boolean, string?)
		local failures: { string } = {}
		local function expect(label: string, ok: boolean)
			if not ok then
				table.insert(failures, label)
			end
		end

		local sink, logged, gate = recordingSink()
		local funnel = OnboardingFunnel.new(sink)
		local a = { Name = "A" }
		local b = { Name = "B" }

		expect("fresh player is at step 0", funnel:stepOf(a) == 0)
		expect("joined logs", funnel:reach(a, Step.Joined) == true)
		expect("joined again does not log", funnel:reach(a, Step.Joined) == false)
		expect("skipping to first_memorize is a gap", funnel:reach(a, Step.FirstMemorize) == false)
		expect("gap left the step alone", funnel:stepOf(a) == Step.Joined)
		expect("first_pop logs", funnel:reach(a, Step.FirstPop) == true)
		expect("first_memorize logs after first_pop", funnel:reach(a, Step.FirstMemorize) == true)
		expect("earlier step never re-logs", funnel:reach(a, Step.FirstPop) == false)
		expect("step names match the constants",
			#logged == 3 and logged[1].name == "joined" and logged[2].name == "first_pop" and logged[3].name == "first_memorize")
		expect("player b untouched by a", funnel:stepOf(b) == 0)
		expect("player b starts at joined", funnel:reach(b, Step.Joined) == true)

		gate.accept = false
		expect("refused send returns false", funnel:reach(a, Step.FirstCast) == false)
		expect("refused send leaves the step unreached", funnel:stepOf(a) == Step.FirstMemorize)
		gate.accept = true
		expect("retry after refusal logs", funnel:reach(a, Step.FirstCast) == true)

		funnel:forget(a)
		expect("forget resets the player", funnel:stepOf(a) == 0)
		expect("forgetting a does not reset b", funnel:stepOf(b) == Step.Joined)

		local okUnknown = pcall(function()
			funnel:reach(a, 99)
		end)
		expect("unknown step asserts", okUnknown == false)

		if #failures > 0 then
			return false, table.concat(failures, "; ")
		end
		return true, string.format("%d steps logged", #logged)
	end,
}
