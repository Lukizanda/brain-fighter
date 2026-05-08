----------------------------------------------------------------------
-- Test: rolodex currentIndex stays on the same logical weapon after
-- cap-overflow eviction.
----------------------------------------------------------------------
-- User-reported bug (NIM-12): after picking up a 3rd Normal weapon
-- and the oldest being evicted, the FIRST Tab press appeared to do
-- nothing — firing looked broken until a second Tab.
--
-- Root cause: WeaponRolodex's drop callback only clamped currentIndex
-- when it went out of range. When a tool BEFORE currentIndex was
-- removed, the surviving entries shifted left under the index but
-- currentIndex didn't follow — it silently pointed at the next entry.
-- The next Tab walked from this wrong slot:
--   newIndex = currentIndex + 1 → wraps → EquipTool(alreadyHeld)
-- which is a Roblox no-op (no Tool.Equipped fires), so the rolodex
-- visually "advances" but the actual equipped Tool doesn't change.
-- The user fires the SAME weapon they were already holding — looks
-- like firing is broken because they expected the freshly-picked-up
-- tool to be in their hand.
--
-- Fix: `adjustListIndexAfterRemoval` decrements currentIndex when the
-- removed idx is before it, keeping it pinned to the same logical entry.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local adjustListIndexAfterRemoval = require(ReplicatedStorage.Utility.adjustListIndexAfterRemoval)

-- Mirrors the rolodex's array operation pair so the test exercises the
-- same shape the production code goes through.
local function dropTool(weapons: { string }, currentIndex: number, name: string): number
	local idx
	for i, w in weapons do
		if w == name then
			idx = i
			break
		end
	end
	if not idx then
		return currentIndex
	end
	table.remove(weapons, idx)
	return adjustListIndexAfterRemoval(idx, currentIndex, #weapons)
end

return {
	name = "WeaponRolodex currentIndex stays on the same logical weapon after eviction",

	run = function(ctx)
		ctx.results = {}

		----------------------------------------------------------------
		-- Walk 1 (the user-reported bug):
		-- Player holds Rifle. Picks up LaserPistol → server evicts the
		-- oldest (Pistol). Rolodex must keep currentIndex on Rifle so
		-- the next Tab cycles to LaserPistol, not back to Rifle.
		----------------------------------------------------------------
		do
			local weapons = { "Pistol", "Rifle", "LaserPistol" }
			local currentIndex = 2 -- Rifle equipped

			currentIndex = dropTool(weapons, currentIndex, "Pistol")
			ctx.results.scenarioB_weapons = table.clone(weapons)
			ctx.results.scenarioB_currentIndex = currentIndex
			ctx.results.scenarioB_pointsTo = weapons[currentIndex]
		end

		----------------------------------------------------------------
		-- Walk 2: dropped tool is AFTER currentIndex — index doesn't move.
		----------------------------------------------------------------
		do
			local weapons = { "Rifle", "Pistol" }
			local currentIndex = 1 -- Rifle equipped

			currentIndex = dropTool(weapons, currentIndex, "Pistol")
			ctx.results.dropAfter_currentIndex = currentIndex
			ctx.results.dropAfter_pointsTo = weapons[currentIndex]
		end

		----------------------------------------------------------------
		-- Walk 3: dropped tool IS the equipped one. Index clamps to
		-- whatever weapon now occupies the slot (or end-of-array).
		----------------------------------------------------------------
		do
			local weapons = { "Pistol", "Rifle" }
			local currentIndex = 2 -- Rifle equipped, also the one being dropped

			currentIndex = dropTool(weapons, currentIndex, "Rifle")
			ctx.results.dropEquippedLast_currentIndex = currentIndex
			ctx.results.dropEquippedLast_pointsTo = weapons[currentIndex]
		end

		----------------------------------------------------------------
		-- Walk 4: dropped tool is FIRST and was the equipped one.
		-- idx == currentIndex, both 1. Surviving entries shift; idx is
		-- not LESS THAN currentIndex (they're equal), so no decrement.
		-- Clamp branch also doesn't fire (currentIndex==1, #weapons==1).
		-- currentIndex stays at 1 — now points to the survivor.
		----------------------------------------------------------------
		do
			local weapons = { "Rifle", "Pistol" }
			local currentIndex = 1 -- Rifle equipped

			currentIndex = dropTool(weapons, currentIndex, "Rifle")
			ctx.results.dropEquippedFirst_currentIndex = currentIndex
			ctx.results.dropEquippedFirst_pointsTo = weapons[currentIndex]
		end
	end,

	verify = function(ctx)
		local r = ctx.results
		local issues = {}

		-- Walk 1 — the user's bug: currentIndex must STILL point at Rifle.
		if r.scenarioB_pointsTo ~= "Rifle" then
			table.insert(issues, string.format(
				"NIM-12 regression: after evicting Pistol while holding Rifle, currentIndex points at %s (expected Rifle). The 3rd-tool Tab-cycle bug is back — surviving entries shifted left under currentIndex without decrementing.",
				tostring(r.scenarioB_pointsTo)))
		end
		if r.scenarioB_currentIndex ~= 1 then
			table.insert(issues, string.format(
				"Walk 1 currentIndex: expected 1, got %s", tostring(r.scenarioB_currentIndex)))
		end

		if r.dropAfter_pointsTo ~= "Rifle" then
			table.insert(issues, string.format(
				"Walk 2 (drop later tool): expected pointer at Rifle, got %s",
				tostring(r.dropAfter_pointsTo)))
		end

		if r.dropEquippedLast_pointsTo ~= "Pistol" then
			table.insert(issues, string.format(
				"Walk 3 (drop equipped last): clamp should leave currentIndex on Pistol, got %s",
				tostring(r.dropEquippedLast_pointsTo)))
		end

		if r.dropEquippedFirst_pointsTo ~= "Pistol" then
			table.insert(issues, string.format(
				"Walk 4 (drop equipped first): currentIndex should now point at Pistol, got %s",
				tostring(r.dropEquippedFirst_pointsTo)))
		end

		if #issues > 0 then
			return false, table.concat(issues, " | ")
		end
		return true, "rolodex index tracking survives idx-before-currentIndex removals"
	end,
}
