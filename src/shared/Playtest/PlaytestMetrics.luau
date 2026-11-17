--!strict

----------------------------------------------------------------------
-- PlaytestMetrics
----------------------------------------------------------------------
-- Turns one fight's event log into the fun metrics of
-- wiki/design/ai-playtest.md § Metric matrix (M1..M17), and averages a
-- set of fights. The log may come from the simulator or from the real
-- bot's recorder: both write the same event kinds, so both are scored
-- by this one module.
--
-- Event kinds read here: boss_spawn, pop, memorize, fizzle, cast,
-- boss_damage, player_damage, player_heal, player_shield, death,
-- reenter, tow_start, tow_eaten, tow_stolen, kit_taken, excursion_end,
-- sample, fight_end. Every event carries `t` (seconds) and `kind`.
--
-- Dev tooling: no game system requires this module.
----------------------------------------------------------------------

local PlaytestMetrics = {}

-- M2: what counts as a rewarding cast.
local REWARDING_DAMAGE_FRACTION = 0.15
local REWARDING_SURVIVAL_HP = 30
local REWARDING_DAMAGE_WINDOW_SEC = 1
-- M8: "low health".
local TENSION_HP = 30
-- M9: damage events closer than this are one burst.
local BURST_GAP_SEC = 1.5
-- M13: the burst window.
local BURST_WINDOW_SEC = 5
-- M5: the pacing midpoint.
local HALF_HEALTH = 0.5

local ACTIVITY: { [string]: boolean } = {
	pop = true, memorize = true, cast = true, player_damage = true, boss_damage = true, tow_stolen = true,
}
local FREEZING_SPELLS: { [string]: boolean } = { ["Frost Nip"] = true, Stasis = true }

export type Metrics = { [string]: number }

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local mid = (#sorted + 1) / 2
	return (sorted[math.floor(mid)] + sorted[math.ceil(mid)]) / 2
end

-- Score one fight. Metrics that did not occur (no cast, no win) are
-- absent rather than zero, so an average is over fights where they did.
function PlaytestMetrics.compute(events: { [number]: { [string]: any } }): Metrics
	local m: Metrics = {}
	local t0: number? = nil
	local firstCast: number? = nil
	local firstRewarding: number? = nil
	local halfAt: number? = nil
	local endAt = 0
	local won = false

	local energy = 0
	local earned = { red = 0, green = 0, blue = 0 }
	local spent = { red = 0, green = 0, blue = 0 }
	local casts = { red = 0, green = 0, blue = 0 }
	local castCount = 0
	local damageByTier = { 0, 0, 0 }
	local damageTotal = 0
	local damageTimes: { { number } } = {}
	local hitTimes: { number } = {}
	local damageTaken = 0
	local deaths = 0
	local aliveSamples, lowSamples, upSamples, safeSamples = 0, 0, 0, 0
	local towsStarted, towsStolen = 0, 0
	local healed, healedWhileDead = 0, 0
	local words, fizzles, pops = 0, 0, 0
	local premiumPops, fossilPops, kits, ledgeTrips = 0, 0, 0, 0

	-- M10 bookkeeping: the longest quiet stretch while in the arena.
	local lastActivity: number? = nil
	local deadTime = 0
	local function touch(t: number)
		if lastActivity then
			deadTime = math.max(deadTime, t - lastActivity)
		end
		lastActivity = t
	end

	local pendingCast: any = nil

	for _, e in events do
		local t: number = e.t
		local kind: string = e.kind
		if kind == "boss_spawn" then
			t0 = t0 or t
			lastActivity = t
		end
		if t0 and ACTIVITY[kind] then
			touch(t)
		end

		if kind == "pop" then
			pops += 1
			if e.fossil then
				fossilPops += 1
			elseif typeof(e.zone) == "string" and e.zone:find("Premium") then
				premiumPops += 1
			end
		elseif kind == "memorize" then
			words += 1
			energy += e.red + e.green + e.blue
			earned.red += e.red
			earned.green += e.green
			earned.blue += e.blue
		elseif kind == "fizzle" then
			fizzles += 1
		elseif kind == "cast" then
			castCount += 1
			casts[e.color] += 1
			spent[e.color] += e.cost
			if t0 and not firstCast then
				firstCast = t - t0
			end
			pendingCast = e
			if t0 and not firstRewarding and FREEZING_SPELLS[e.spell] and e.bossState == "AttackPrep" then
				firstRewarding = t - t0
			end
		elseif kind == "boss_damage" then
			damageTotal += e.amount
			damageByTier[e.tier] += e.amount
			table.insert(damageTimes, { t, e.amount })
			if not halfAt and e.bossHp <= HALF_HEALTH and t0 then
				halfAt = t - t0
			end
			if t0 and not firstRewarding and pendingCast and t - pendingCast.t <= REWARDING_DAMAGE_WINDOW_SEC
				and e.amount >= REWARDING_DAMAGE_FRACTION then
				firstRewarding = t - t0
			end
		elseif kind == "player_heal" or kind == "player_shield" then
			if t0 and not firstRewarding and e.amount >= REWARDING_SURVIVAL_HP then
				firstRewarding = t - t0
			end
		elseif kind == "player_damage" then
			damageTaken += e.amount
			table.insert(hitTimes, t)
		elseif kind == "death" then
			deaths += 1
			lastActivity = nil
		elseif kind == "reenter" then
			lastActivity = if t0 then t else nil
		elseif kind == "tow_start" then
			towsStarted += 1
		elseif kind == "tow_stolen" then
			towsStolen += 1
		elseif kind == "tow_eaten" then
			healed += e.healed
			if not e.playerAlive then
				healedWhileDead += e.healed
			end
		elseif kind == "kit_taken" then
			kits += 1
		elseif kind == "excursion_end" then
			ledgeTrips += 1
		elseif kind == "sample" then
			if e.alive then
				aliveSamples += 1
				if e.hp <= TENSION_HP then
					lowSamples += 1
				end
				if e.bossUp then
					upSamples += 1
					if e.canHitBoss and not e.bossCanHit then
						safeSamples += 1
					end
				end
			end
		elseif kind == "fight_end" then
			endAt = t
			won = e.outcome == "win"
			if e.shots and e.shots > 0 then
				m.hitRate = e.shotsHit / e.shots
				m.blockedRate = e.shotsBlocked / e.shots
			end
			m.wallsBroken = e.wallsBroken or 0
		end
	end

	local aliveMin = math.max(aliveSamples, 1) / 60

	m.win = if won then 1 else 0
	m.deaths = deaths
	m.m1_firstCast = firstCast :: any
	m.m2_firstRewarding = firstRewarding :: any
	m.m3_energyPerMin = energy / aliveMin
	if won and t0 then
		m.m4_ttk = endAt - t0
		if halfAt then
			m.m5_pacing = halfAt / math.max(endAt - t0, 1)
		end
	end
	m.m8_tension = lowSamples / math.max(aliveSamples, 1)

	-- M9: gaps between bursts of damage taken.
	local gaps: { number } = {}
	local lastBurst: number? = nil
	local lastHit: number? = nil
	for _, t in hitTimes do
		if not lastHit or t - lastHit > BURST_GAP_SEC then
			if lastBurst then
				table.insert(gaps, t - lastBurst)
			end
			lastBurst = t
		end
		lastHit = t
	end
	m.m9_burstGap = median(gaps) :: any
	m.m10_deadTime = deadTime

	if castCount > 0 then
		m.m11_redCasts = casts.red / castCount
		m.m11_greenCasts = casts.green / castCount
		m.m11_blueCasts = casts.blue / castCount
	end
	if earned.green > 0 then
		m.m11_greenWaste = 1 - math.min(1, spent.green / earned.green)
	end
	if damageTotal > 0 then
		m.m12_t1 = damageByTier[1] / damageTotal
		m.m12_t2 = damageByTier[2] / damageTotal
		m.m12_t3 = damageByTier[3] / damageTotal
		m.m15_healShare = healed / damageTotal
	end

	-- M13: the heaviest 5 seconds.
	local burst = 0
	for i, entry in damageTimes do
		local sum = 0
		for j = i, #damageTimes do
			if damageTimes[j][1] - entry[1] > BURST_WINDOW_SEC then
				break
			end
			sum += damageTimes[j][2]
		end
		burst = math.max(burst, sum)
	end
	m.m13_burst = burst

	m.m14_premium = if premiumPops > 0 then 1 else 0
	m.m14_fossil = if fossilPops > 0 then 1 else 0
	m.m14_cave = if kits > 0 then 1 else 0
	m.m14_ledge = if ledgeTrips > 0 then 1 else 0
	if towsStarted > 0 then
		m.m15_stealRate = towsStolen / towsStarted
	end
	m.m16_safe = safeSamples / math.max(upSamples, 1)
	if deaths > 0 then
		m.m17_winAfterDeath = if won then 1 else 0
		m.m17_healWhileDead = healedWhileDead
	end

	m.damageTaken = damageTaken
	m.damageDealt = damageTotal
	m.words = words
	m.fizzles = fizzles
	m.pops = pops
	m.casts = castCount
	return m
end

-- Mean of each metric over the fights where it occurred, plus the count.
function PlaytestMetrics.aggregate(fights: { Metrics }): { [string]: { mean: number, median: number, n: number } }
	local buckets: { [string]: { number } } = {}
	for _, metrics in fights do
		for key, value in metrics do
			local bucket = buckets[key]
			if not bucket then
				bucket = {}
				buckets[key] = bucket
			end
			table.insert(bucket, value)
		end
	end
	local out = {}
	for key, values in buckets do
		local sum = 0
		for _, v in values do
			sum += v
		end
		out[key] = { mean = sum / #values, median = median(values) :: number, n = #values }
	end
	return out
end

return PlaytestMetrics
