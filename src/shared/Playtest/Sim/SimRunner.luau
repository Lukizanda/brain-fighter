--!strict

----------------------------------------------------------------------
-- SimRunner
----------------------------------------------------------------------
-- Runs a batch of simulated fights per persona and returns a text
-- report. The entry point for Tier 1 of the automated playtest.
--
-- From Studio's Edit DataModel (execute_luau). Edit mode caches require
-- results across calls, so clone the folder to pick up synced code:
--
--   local folder = game.ReplicatedStorage.Shared.Playtest:Clone()
--   folder.Parent = game.ServerStorage
--   local ok, out = pcall(function()
--       return require(folder.Sim.SimRunner).run({ arenaId = "IslandReview", fights = 50 })
--   end)
--   folder:Destroy()
--   return out
--
-- See wiki/design/ai-playtest.md.
----------------------------------------------------------------------

local PlaytestMetrics = require(script.Parent.Parent.PlaytestMetrics)
local PlaytestPersonas = require(script.Parent.Parent.PlaytestPersonas)
local FightSim = require(script.Parent.FightSim)
local SimLevel = require(script.Parent.SimLevel)

local SimRunner = {}

local DEFAULT_FIGHTS = 50
-- Yield this often so Studio's main thread is not held for the batch.
local FIGHTS_PER_YIELD = 5

export type Options = {
	arenaId: string,
	fights: number?,
	personas: { string }?,
	tuning: { [string]: any }?,
	seed: number?,
	label: string?,
}

-- The columns of the report, in order: key, header, format, and whether
-- the mean (false) or the median (true) is shown.
local COLUMNS: { { any } } = {
	{ "win", "win%", "%3.0f", false, 100 },
	{ "m4_ttk", "TTK", "%4.0f", true, 1 },
	{ "m1_firstCast", "1stCast", "%4.0f", true, 1 },
	{ "m2_firstRewarding", "1stRew", "%4.0f", true, 1 },
	{ "m3_energyPerMin", "E/min", "%4.0f", false, 1 },
	{ "deaths", "deaths", "%4.1f", false, 1 },
	{ "m8_tension", "lowHP%", "%3.0f", false, 100 },
	{ "hitRate", "hit%", "%3.0f", false, 100 },
	{ "m9_burstGap", "hitGap", "%4.1f", true, 1 },
	{ "m10_deadTime", "dead", "%4.0f", true, 1 },
	{ "m5_pacing", "pace", "%4.2f", false, 1 },
	{ "m13_burst", "burst%", "%3.0f", false, 100 },
	{ "m12_t1", "T1%", "%3.0f", false, 100 },
	{ "m12_t2", "T2%", "%3.0f", false, 100 },
	{ "m12_t3", "T3%", "%3.0f", false, 100 },
	{ "m11_greenCasts", "grn%", "%3.0f", false, 100 },
	{ "m11_blueCasts", "blu%", "%3.0f", false, 100 },
	{ "m11_greenWaste", "gWaste%", "%3.0f", false, 100 },
	{ "m15_healShare", "heal%", "%3.0f", false, 100 },
	{ "m15_stealRate", "steal%", "%3.0f", false, 100 },
	{ "m16_safe", "safe%", "%3.0f", false, 100 },
	{ "m17_winAfterDeath", "winAfterDeath%", "%3.0f", false, 100 },
	{ "m14_premium", "prem%", "%3.0f", false, 100 },
	{ "m14_fossil", "fossil%", "%3.0f", false, 100 },
	{ "m14_cave", "cave%", "%3.0f", false, 100 },
	{ "m14_ledge", "ledge%", "%3.0f", false, 100 },
	{ "m14_keyed", "keyed%", "%3.0f", false, 100 },
	{ "m14_keyedAccident", "keyAcc%", "%3.0f", false, 100 },
	{ "m14_trips", "trips", "%4.1f", false, 1 },
	{ "m14_tripPayoff", "payoff", "%4.1f", false, 1 },
	{ "m14_tripDeaths", "tripDeath%", "%3.0f", false, 100 },
	{ "blockedRate", "blocked%", "%3.0f", false, 100 },
	{ "wallsBroken", "wallsBroken", "%4.1f", false, 1 },
	{ "words", "words", "%4.1f", false, 1 },
	{ "fizzles", "fizz", "%4.1f", false, 1 },
	{ "casts", "casts", "%4.1f", false, 1 },
	{ "damageTaken", "dmgIn", "%4.0f", false, 1 },
}

-- Run the batch. Returns the report text and the aggregates by persona.
function SimRunner.run(options: Options): (string, { [string]: any })
	local level = SimLevel.fromWorkspace(options.arenaId)
	local fights = options.fights or DEFAULT_FIGHTS
	local baseSeed = options.seed or 1

	local lines: { string } = {}
	table.insert(lines, string.format("== %s | arena %s | %d fights per persona | zones %d walls %d ==",
		options.label or "baseline", options.arenaId, fights, #level.zones, #level.walls))
	for _, note in level.lint do
		table.insert(lines, "lint: " .. note)
	end

	local results: { [string]: any } = {}
	local started = os.clock()
	for _, persona in PlaytestPersonas.ALL do
		if not options.personas or table.find(options.personas, persona.name) then
			local scored = {}
			for i = 1, fights do
				local result = FightSim.run(level, persona, options.tuning, baseSeed + i)
				table.insert(scored, PlaytestMetrics.compute(result.events))
				if i % FIGHTS_PER_YIELD == 0 then
					task.wait()
				end
			end
			local agg = PlaytestMetrics.aggregate(scored)
			results[persona.name] = agg
			local cells: { string } = { string.format("%-8s", persona.name) }
			for _, column in COLUMNS do
				local entry = agg[column[1]]
				if entry then
					local value = if column[4] then entry.median else entry.mean
					table.insert(cells, column[2] .. "=" .. string.format(column[3], value * column[5]))
				else
					table.insert(cells, column[2] .. "=-")
				end
			end
			table.insert(lines, table.concat(cells, " "))
		end
	end
	table.insert(lines, string.format("(%.1f s)", os.clock() - started))
	return table.concat(lines, "\n"), results
end

return SimRunner
