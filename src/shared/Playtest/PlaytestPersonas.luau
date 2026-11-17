--!strict

----------------------------------------------------------------------
-- PlaytestPersonas
----------------------------------------------------------------------
-- The six bot players of the automated playtest, as numbers a script
-- can act on. Authored by the designer pass of 2026-11-17 and pinned to
-- wiki/design/ai-playtest.md § Personas; change them there first.
--
-- Read by the fight simulator (Sim/FightSim) and, later, by the real
-- in-Studio bot, so both play the same people.
--
-- Dev tooling: no game system requires this module.
----------------------------------------------------------------------

local PlaytestPersonas = {}

export type CastChoice = { color: string, tier: number }
export type CastContext = {
	mana: { [string]: number },
	hp: number,
	shield: number,
	bossAmped: boolean,
	bossHp: number,
	can: (color: string, tier: number) -> boolean,
}

export type Persona = {
	name: string,
	tapsPerSec: number,
	vocabSize: number,
	minLen: number,
	maxLen: number,
	typicalLen: number,
	lengthWeights: { [number]: number },
	-- Words the persona considers per search; stands for search skill.
	candidates: number,
	searchBaseSec: number,
	searchPerLetterSec: number,
	invalidRate: number,
	-- Share of words spelled toward a wanted colour.
	colorAware: number,
	colorWants: (mana: { [string]: number }) -> { [string]: number },
	usesWild: boolean,
	goGates: number,
	goCave: number,
	station: "roam" | "overlook",
	distMin: number,
	distMax: number,
	-- Chance, each time a standing spot is picked, of standing behind a rock.
	coverUse: number,
	reactChance: number,
	reactDelaySec: number,
	stealTow: number,
	chooseCast: (ctx: CastContext) -> CastChoice?,
}

local T1, T2, T3 = 1, 2, 3
local MEND_AT_HP = 40
local SANCTUARY_AT_HP_AVERAGE = 25
local SANCTUARY_AT_HP_STRONG = 30

local function evenWants(_mana: { [string]: number }): { [string]: number }
	return { red = 1, green = 1, blue = 1 }
end

-- Mostly red, some green to stay alive.
local function averageWants(_mana: { [string]: number }): { [string]: number }
	return { red = 3, green = 1, blue = 1 }
end

-- Red and blue, whichever is further from a T3.
local function comboWants(mana: { [string]: number }): { [string]: number }
	if mana.blue < mana.red then
		return { blue = 1 }
	end
	return { red = 1 }
end

local function healIfHurt(ctx: CastContext, sanctuaryAt: number?): CastChoice?
	if sanctuaryAt and ctx.hp <= sanctuaryAt and ctx.can("green", T3) then
		return { color = "green", tier = T3 }
	end
	if ctx.hp <= MEND_AT_HP and ctx.can("green", T1) then
		return { color = "green", tier = T1 }
	end
	return nil
end

-- Taps the first thing that lights up.
local function castNovice(ctx: CastContext): CastChoice?
	local heal = healIfHurt(ctx, nil)
	if heal then
		return heal
	end
	if ctx.can("red", T1) then
		return { color = "red", tier = T1 }
	end
	if ctx.can("blue", T1) then
		return { color = "blue", tier = T1 }
	end
	return nil
end

-- Fireball at 10, Inferno when 20 is already banked.
local function castAverage(ctx: CastContext): CastChoice?
	local heal = healIfHurt(ctx, SANCTUARY_AT_HP_AVERAGE)
	if heal then
		return heal
	end
	if ctx.can("red", T3) then
		return { color = "red", tier = T3 }
	end
	if ctx.can("red", T2) then
		return { color = "red", tier = T2 }
	end
	-- Standing where a Fireball cannot reach: hold out for the Inferno.
	if ctx.can("blue", T1) and ctx.mana.blue >= 10 then
		return { color = "blue", tier = T1 }
	end
	return nil
end

-- Saves for the top tier and opens with Stasis when it can.
local function castStrong(ctx: CastContext): CastChoice?
	local heal = healIfHurt(ctx, SANCTUARY_AT_HP_STRONG)
	if heal then
		return heal
	end
	if ctx.bossAmped and ctx.can("red", T3) then
		return { color = "red", tier = T3 }
	end
	if ctx.can("blue", T3) and ctx.can("red", T3) then
		return { color = "blue", tier = T3 }
	end
	if ctx.can("red", T3) and ctx.mana.blue < 10 then
		return { color = "red", tier = T3 }
	end
	return nil
end

local function castRusher(ctx: CastContext): CastChoice?
	if ctx.can("red", T1) then
		return { color = "red", tier = T1 }
	end
	if ctx.can("blue", T1) then
		return { color = "blue", tier = T1 }
	end
	return nil
end

-- Stasis then Inferno, nothing else.
local function castCombo(ctx: CastContext): CastChoice?
	if ctx.bossAmped and ctx.can("red", T3) then
		return { color = "red", tier = T3 }
	end
	if ctx.can("blue", T3) and ctx.can("red", T3) then
		return { color = "blue", tier = T3 }
	end
	return nil
end

local novice: Persona = {
	name = "Novice",
	tapsPerSec = 0.8,
	vocabSize = 1000,
	minLen = 3,
	maxLen = 5,
	typicalLen = 4,
	lengthWeights = { [3] = 45, [4] = 45, [5] = 10 },
	candidates = 8,
	searchBaseSec = 12,
	searchPerLetterSec = 3,
	invalidRate = 0.25,
	colorAware = 0,
	colorWants = evenWants,
	usesWild = false,
	goGates = 0,
	goCave = 0,
	station = "roam",
	distMin = 40,
	distMax = 90,
	coverUse = 0.2,
	reactChance = 0.3,
	reactDelaySec = 1.2,
	stealTow = 0.1,
	chooseCast = castNovice,
}

local average: Persona = {
	name = "Average",
	tapsPerSec = 1.6,
	vocabSize = 6000,
	minLen = 3,
	maxLen = 7,
	typicalLen = 5,
	lengthWeights = { [3] = 15, [4] = 35, [5] = 30, [6] = 15, [7] = 5 },
	candidates = 25,
	searchBaseSec = 6,
	searchPerLetterSec = 1.5,
	invalidRate = 0.10,
	colorAware = 0.3,
	colorWants = averageWants,
	usesWild = true,
	goGates = 0,
	goCave = 0.3,
	station = "roam",
	distMin = 60,
	distMax = 100,
	coverUse = 0.5,
	reactChance = 0.6,
	reactDelaySec = 0.7,
	stealTow = 0.4,
	chooseCast = castAverage,
}

local strong: Persona = {
	name = "Strong",
	tapsPerSec = 3.0,
	vocabSize = 80000,
	minLen = 4,
	maxLen = 9,
	typicalLen = 6,
	lengthWeights = { [4] = 15, [5] = 30, [6] = 30, [7] = 15, [8] = 7, [9] = 3 },
	candidates = 80,
	searchBaseSec = 3,
	searchPerLetterSec = 0.7,
	invalidRate = 0.02,
	colorAware = 0.7,
	colorWants = comboWants,
	usesWild = true,
	goGates = 0.5,
	goCave = 0.8,
	station = "roam",
	distMin = 70,
	distMax = 110,
	coverUse = 0.8,
	reactChance = 0.9,
	reactDelaySec = 0.4,
	stealTow = 0.8,
	chooseCast = castStrong,
}

local turtle: Persona = table.clone(average)
turtle.name = "Turtle"
turtle.station = "overlook"
turtle.goCave = 0
turtle.stealTow = 0.6
turtle.reactChance = 0
turtle.coverUse = 0

local rusher: Persona = table.clone(average)
rusher.name = "Rusher"
rusher.distMin = 10
rusher.distMax = 25
rusher.goCave = 0.5
rusher.reactChance = 0.1
rusher.coverUse = 0
rusher.reactDelaySec = 0.8
rusher.stealTow = 0.2
rusher.chooseCast = castRusher

local combo: Persona = table.clone(strong)
combo.name = "Combo"
combo.colorAware = 0.9
combo.goGates = 0
combo.goCave = 1
combo.coverUse = 0.7
combo.distMin = 80
combo.distMax = 120
combo.chooseCast = castCombo

PlaytestPersonas.ALL = { novice, average, strong, turtle, rusher, combo }

function PlaytestPersonas.byName(name: string): Persona?
	for _, persona in PlaytestPersonas.ALL do
		if persona.name == name then
			return persona
		end
	end
	return nil
end

return PlaytestPersonas
