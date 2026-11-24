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
-- gate_keyed, trip_end, sample, fight_end. Every event carries `t`
-- (seconds) and `kind`.
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
	-- Boss damage dealt while the boss was exposed (stage 11c).
	local damageExposed = 0
	local damageTimes: { { number } } = {}
	local hitTimes: { number } = {}
	local damageTaken = 0
	local deaths = 0
	local aliveSamples, lowSamples, upSamples, safeSamples = 0, 0, 0, 0
	local towsStarted, towsStolen = 0, 0
	local healed, healedWhileDead = 0, 0
	local words, fizzles, pops = 0, 0, 0
	local premiumPops, fossilPops, kits, ledgeTrips = 0, 0, 0, 0
	-- M14 for gates: gates opened by key letters, and trips beyond a gate.
	local keyedOnPurpose, keyedByAccident = 0, 0
	local trips, tripDeaths, tripSec, tripEnergy, tripMemorized = 0, 0, 0, 0, 0
	-- Scramble bomb (opt-in mechanic): boss damage by source, bomb outcomes.
	local bombDamage, sporeDamage = 0, 0
	local bombLanded, bombEngaged, bombDefused, bombBurst, bombBurstHit, bombAbandoned = 0, 0, 0, 0, 0, 0
	local bombWrong, bombLost, bombEnergy, bombSolveDamage, bombBurstDamage, bombSolveDeaths = 0, 0, 0, 0, 0, 0
	local bombSolveSecs: { number } = {}
	-- Letter missiles: salvo and missile outcomes, damage taken from them.
	local salvos, salvoDone, salvoWrongPop, salvoHit, salvoLostSec = 0, 0, 0, 0, 0
	local missilesLaunched, missilePopOk, missilePopHarmless, missileOnPlayer, missileOther = 0, 0, 0, 0, 0
	local missileDamage, missileDeaths, missileRefused = 0, 0, 0
	-- Seekers: salvos broken (a burst), salvos the player ran from, and from
	-- first release to completion.
	local salvoBroken, salvoFled, salvoFledHit = 0, 0, 0
	local salvoDoneSecs: { number } = {}
	-- The two-phase puzzle (rest, then hatch into seekers): puzzles hatched,
	-- seekers hatched and how each one ended, damage and deaths from them,
	-- word-search seconds lost to them, accepted resting taps.
	local bombHatched, bombAccepted = 0, 0
	local seekersHatched, seekersPopped, seekersOnPlayer, seekersOnWall, seekersExpired = 0, 0, 0, 0, 0
	local seekersEndedUnknown, seekerBurstHits = 0, 0
	local seekerDamage, seekerDeaths, seekerLost = 0, 0, 0
	local puzzleSolveSecs: { number } = {} -- landing to solve

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
			if e.bomb then
				bombEnergy += e.red + e.green + e.blue
			end
			earned.red += e.red
			earned.green += e.green
			earned.blue += e.blue
		elseif kind == "salvo_start" then
			salvos += 1
		elseif kind == "salvo_end" then
			salvoLostSec += e.lost
			if e.completed then
				salvoDone += 1
				if type(e.sec) == "number" then
					table.insert(salvoDoneSecs, e.sec)
				end
			end
			if e.broken then
				salvoBroken += 1
			end
			if e.fled then
				salvoFled += 1
				if e.hit then
					salvoFledHit += 1
				end
			end
			if e.wrongPop then
				salvoWrongPop += 1
			end
			if e.hit then
				salvoHit += 1
			end
		elseif kind == "missile_launch" then
			missilesLaunched += 1
		elseif kind == "missile_pop" then
			if e.ok then
				missilePopOk += 1
			else
				missilePopHarmless += 1
			end
		elseif kind == "missile_refused" then
			missileRefused += 1
		elseif kind == "missile_end" then
			if e.how == "player" then
				missileOnPlayer += 1
			else
				missileOther += 1
			end
		elseif kind == "bomb_land" then
			bombLanded += 1
		elseif kind == "bomb_engage" then
			bombEngaged += 1
		elseif kind == "bomb_wrong" then
			bombWrong += 1
		elseif kind == "bomb_accept" then
			bombAccepted += 1
		elseif kind == "bomb_hatch" then
			-- The timer ran out: this many letters become seekers. (`lost` is
			-- the resting phase's word-search seconds when not already counted.)
			bombHatched += 1
			seekersHatched += e.seekers
			bombLost += e.lost
		elseif kind == "seeker_end" then
			-- how: popped | player | wall | expired | unknown (a recorder that
			-- cannot tell which kind of burst it saw).
			if e.how == "popped" then
				seekersPopped += 1
			elseif e.how == "player" then
				seekersOnPlayer += 1
			elseif e.how == "wall" then
				seekersOnWall += 1
			elseif e.how == "expired" then
				seekersExpired += 1
			else
				seekersEndedUnknown += 1
			end
			if e.hit then
				seekerBurstHits += 1
			end
		elseif kind == "seekers_done" then
			seekerLost += e.lost
		elseif kind == "bomb_defuse" then
			bombDefused += 1
			bombLost += e.lost
			table.insert(bombSolveSecs, e.sec)
			if type(e.sinceLand) == "number" then
				table.insert(puzzleSolveSecs, e.sinceLand)
			end
		elseif kind == "bomb_burst" then
			bombBurst += 1
			bombLost += e.lost
			if e.hit then
				bombBurstHit += 1
			end
		elseif kind == "bomb_abandon" then
			bombAbandoned += 1
			bombLost += e.lost
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
			if e.spell == "Bomb" then
				bombDamage += e.amount
			elseif e.spell == "Spore" then
				sporeDamage += e.amount
			end
			damageByTier[e.tier] += e.amount
			if e.exposed then
				damageExposed += e.amount
			end
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
			if e.source == "Missile" then
				missileDamage += e.amount
			elseif e.source == "Bomb" then
				bombBurstDamage += e.amount
			elseif e.source == "Seeker" then
				seekerDamage += e.amount
			elseif e.solving then
				bombSolveDamage += e.amount
			end
			table.insert(hitTimes, t)
		elseif kind == "death" then
			deaths += 1
			if e.source == "Missile" then
				missileDeaths += 1
			elseif e.source == "Seeker" then
				seekerDeaths += 1
			end
			if e.solving then
				bombSolveDeaths += 1
			end
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
		elseif kind == "gate_keyed" then
			if e.deliberate then
				keyedOnPurpose += 1
			else
				keyedByAccident += 1
			end
		elseif kind == "trip_end" then
			trips += 1
			tripSec += e.sec
			tripEnergy += e.energy
			tripMemorized += e.memorized
			if e.died then
				tripDeaths += 1
			end
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
		m.exposedShare = damageExposed / damageTotal
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
	m.m14_keyed = if keyedOnPurpose + keyedByAccident > 0 then 1 else 0
	m.m14_keyedAccident = if keyedByAccident > 0 then 1 else 0
	m.m14_trips = trips
	if trips > 0 then
		m.m14_tripDeaths = tripDeaths / trips
		-- Payoff: energy a second on trips against energy a second off them.
		local offSec = aliveSamples - tripSec
		local offEnergy = energy - tripMemorized
		if tripSec > 0 and offSec > 0 and offEnergy > 0 then
			m.m14_tripPayoff = (tripEnergy / tripSec) / (offEnergy / offSec)
		end
	end
	if towsStarted > 0 then
		m.m15_stealRate = towsStolen / towsStarted
	end
	m.m16_safe = safeSamples / math.max(upSamples, 1)
	if deaths > 0 then
		m.m17_winAfterDeath = if won then 1 else 0
		m.m17_healWhileDead = healedWhileDead
	end

	-- Scramble bomb columns (absent from fights without bombs).
	if damageTotal > 0 then
		m.sporeShare = sporeDamage / damageTotal
		m.bombShare = bombDamage / damageTotal
	end
	if bombLanded > 0 then
		m.bombLanded = bombLanded
		m.bombEngaged = bombEngaged
		m.bombDefused = bombDefused
		m.bombBurst = bombBurst
		m.bombBurstHit = bombBurstHit
		m.bombAbandoned = bombAbandoned
		m.bombWrong = bombWrong
		m.bombLostSec = bombLost
		m.bombEnergy = bombEnergy
		m.bombSolveDamage = bombSolveDamage
		m.bombBurstDamage = bombBurstDamage
		m.bombSolveDeaths = bombSolveDeaths
		m.bombSolveSec = median(bombSolveSecs) :: any
		-- Two-phase puzzle columns: zeros are kept so a per-fight mean counts
		-- the fights without a hatch.
		m.bombHatched = bombHatched
		m.bombAccepted = bombAccepted
		m.seekersHatched = seekersHatched
		m.seekersPopped = seekersPopped
		m.seekersOnPlayer = seekersOnPlayer
		m.seekersOnWall = seekersOnWall
		m.seekersExpired = seekersExpired
		m.seekersEndedUnknown = seekersEndedUnknown
		m.seekerBurstHits = seekerBurstHits
		m.seekerDamage = seekerDamage
		m.seekerDeaths = seekerDeaths
		m.seekerLostSec = seekerLost
		m.searchLostSec = bombLost + seekerLost
		if #puzzleSolveSecs > 0 then
			m.puzzleSolveSec = median(puzzleSolveSecs) :: any
		end
	end
	if salvos > 0 then
		m.salvos = salvos
		m.salvoDone = salvoDone
		m.salvoWrongPop = salvoWrongPop
		m.salvoHit = salvoHit
		m.salvoLostSec = salvoLostSec
		m.missiles = missilesLaunched
		m.missilePopOk = missilePopOk
		m.missilePopHarmless = missilePopHarmless
		m.missileOnPlayer = missileOnPlayer
		m.missileOther = missileOther
		m.missileRefused = missileRefused
		m.missileDamage = missileDamage
		m.missileDeaths = missileDeaths
		m.missileEnergy = bombEnergy
		m.salvoBroken = salvoBroken
		m.salvoFled = salvoFled
		m.salvoFledHit = salvoFledHit
		if #salvoDoneSecs > 0 then
			m.salvoDoneSec = median(salvoDoneSecs) :: any
		end
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
