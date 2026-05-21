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
--
-- Tier costs pinned to SpellRegistry.TIER_COSTS = { 5, 10, 20, 40 }
-- (wiki/design/gameplay-loop.md § "Spell tier thresholds"). If those
-- numbers move, the threshold-edge cases below need to move with them.
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
		"getSpell red T2 = Fireball (cost 10, auto)",
		function()
			local s = SpellRegistry.getSpell("red", 2)
			expectEq(s.name, "Fireball", "Fireball.name")
			expectEq(s.cost, 10, "Fireball.cost")
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
		"listAffordable red 4 -> empty (below T1=5)",
		function()
			expectLen(SpellRegistry.listAffordableSpells("red", 4), 0, "red@4")
		end,
	},
	{
		"listAffordable red 5 -> [Firebolt]",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 5)
			expectLen(r, 1, "red@5 length")
			expectEq(r[1].name, "Firebolt", "red@5[1].name")
		end,
	},
	{
		"listAffordable red 10 -> [Firebolt, Fireball] (tier-ascending)",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 10)
			expectLen(r, 2, "red@10 length")
			expectEq(r[1].name, "Firebolt", "red@10[1].name")
			expectEq(r[2].name, "Fireball", "red@10[2].name")
		end,
	},
	{
		"listAffordable red 20 -> 3 entries (through Inferno)",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 20)
			expectLen(r, 3, "red@20 length")
			expectEq(r[1].name, "Firebolt", "red@20[1].name")
			expectEq(r[2].name, "Fireball", "red@20[2].name")
			expectEq(r[3].name, "Inferno", "red@20[3].name")
		end,
	},
	{
		"listAffordable red 40 -> 4 entries (Volley unlocks)",
		function()
			local r = SpellRegistry.listAffordableSpells("red", 40)
			expectLen(r, 4, "red@40 length")
			expectEq(r[4].name, "Volley", "red@40[4].name")
		end,
	},
	{
		"listAffordable red 160 -> 4 entries (cap doesn't add more)",
		function()
			expectLen(SpellRegistry.listAffordableSpells("red", 160), 4, "red@160 length")
		end,
	},
	{
		"listAffordable green 10 -> [Mend, Stone Wall]",
		function()
			local r = SpellRegistry.listAffordableSpells("green", 10)
			expectLen(r, 2, "green@10 length")
			expectEq(r[1].name, "Mend", "green@10[1].name")
			expectEq(r[2].name, "Stone Wall", "green@10[2].name")
		end,
	},
	{
		"getSpell red 5 errors (only 4 tiers exist)",
		function()
			expectThrows(function()
				SpellRegistry.getSpell("red", 5)
			end, "tier 5")
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
