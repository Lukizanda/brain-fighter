--!strict

----------------------------------------------------------------------
-- SpellRegistry smoke tests
----------------------------------------------------------------------
-- Pure-Luau asserts — no Roblox instances required. Invoke via
-- execute_luau in a playtest, e.g.:
--
--   local M = require(game.ReplicatedStorage.Shared.SpellRegistry.__tests)
--   local passed, failed = M.runAll()
--
-- Logs "[TEST PASS]" / "[TEST FAIL]" lines so output is parseable.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SpellRegistry.Tests")

local M = {}

local function expectEq(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("[%s] expected %s, got %s", label, tostring(expected), tostring(actual)),
			2
		)
	end
end

local function expectLen(t: { any }, n: number, label: string)
	if #t ~= n then
		error(string.format("[%s] expected length %d, got %d", label, n, #t), 2)
	end
end

local function expectThrows(fn: () -> any, label: string)
	local ok = pcall(fn)
	if ok then
		error(string.format("[%s] expected error but call succeeded", label), 2)
	end
end

local cases: { { any } } = {
	{
		"getSpell red T2 = Fireball (cost 30, auto)",
		function()
			local s = SpellRegistry.getSpell("red", 2)
			expectEq(s.name, "Fireball", "Fireball.name")
			expectEq(s.cost, 30, "Fireball.cost")
			expectEq(s.targetingMode, "auto", "Fireball.targetingMode")
		end,
	},
	{
		"getSpell green T2 = Stone Wall (placement)",
		function()
			local s = SpellRegistry.getSpell("green", 2)
			expectEq(s.name, "Stone Wall", "StoneWall.name")
			expectEq(s.targetingMode, "placement", "StoneWall.targetingMode")
		end,
	},
	{
		"getSpell blue T1 = Frost Nip",
		function()
			local s = SpellRegistry.getSpell("blue", 1)
			expectEq(s.name, "Frost Nip", "FrostNip.name")
		end,
	},
	{
		"listAffordable red 0 -> empty",
		function()
			expectLen(SpellRegistry.listAffordableSpells("red", 0), 0, "red@0")
		end,
	},
	{
		"listAffordable red 9 -> empty (below T1)",
		function()
			expectLen(SpellRegistry.listAffordableSpells("red", 9), 0, "red@9")
		end,
	},
	{
		"listAffordable red 10 -> [Spark]",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 10)
			expectLen(r, 1, "red@10 length")
			expectEq(r[1].name, "Spark", "red@10[1].name")
		end,
	},
	{
		"listAffordable red 30 -> [Spark, Fireball] (tier-ascending)",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 30)
			expectLen(r, 2, "red@30 length")
			expectEq(r[1].name, "Spark", "red@30[1].name")
			expectEq(r[2].name, "Fireball", "red@30[2].name")
		end,
	},
	{
		"listAffordable red 80 -> 3 entries",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 80)
			expectLen(r, 3, "red@80 length")
			expectEq(r[1].name, "Spark", "red@80[1].name")
			expectEq(r[2].name, "Fireball", "red@80[2].name")
			expectEq(r[3].name, "Inferno", "red@80[3].name")
		end,
	},
	{
		"listAffordable red 160 -> 3 entries (cap doesn't add more)",
		function()
			expectLen(SpellRegistry.listAffordableSpells("red", 160), 3, "red@160 length")
		end,
	},
	{
		"listAffordable green 30 -> [Mend, Stone Wall]",
		function()
			local r = SpellRegistry.listAffordableSpells("green", 30)
			expectLen(r, 2, "green@30 length")
			expectEq(r[1].name, "Mend", "green@30[1].name")
			expectEq(r[2].name, "Stone Wall", "green@30[2].name")
		end,
	},
	{
		"getSpell red 4 errors",
		function()
			expectThrows(function()
				SpellRegistry.getSpell("red", 4)
			end, "tier 4")
		end,
	},
	{
		"getSpell yellow 1 errors",
		function()
			expectThrows(function()
				SpellRegistry.getSpell("yellow" :: any, 1)
			end, "color yellow")
		end,
	},
}

function M.runAll(): (number, number)
	local passed, failed = 0, 0
	for _, case in cases do
		local label = case[1] :: string
		local fn = case[2] :: () -> ()
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			log:info(string.format("[TEST PASS] %s", label))
		else
			failed += 1
			log:warn(string.format("[TEST FAIL] %s — %s", label, tostring(err)))
		end
	end
	log:info(string.format("[SPELLREGISTRY TESTS] %d passed, %d failed", passed, failed))
	return passed, failed
end

return M
