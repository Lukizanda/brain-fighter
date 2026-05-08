----------------------------------------------------------------------
-- Test: WeaponController:shouldReload() — auto-reload predicate
----------------------------------------------------------------------
-- The user reported: "the weapon reloads automatically whenever we
-- stop firing." Root cause: shouldReload returned true whenever
-- `ammo < magazineSize`, so after firing one shot and releasing the
-- trigger, FirearmController:onEnterIdle's `elseif self:shouldReload()`
-- branch transitioned to Reloading.
--
-- shouldReload is the *auto-trigger* predicate (used by onEnterIdle
-- and the AUTO post-loop branch). It must mean "the weapon should
-- reload itself without the player asking" — i.e. mag fully empty AND
-- there's reserve to pull from. canReload() is the separate "user
-- can manually reload" predicate.
--
-- Cases:
--   1. Full mag                 -> false (nothing to reload)
--   2. Partial mag, has reserve -> false (player still has ammo)
--   3. Empty mag, has reserve   -> true  (auto-reload UX nicety)
--   4. Empty mag, empty reserve -> false (would be a no-op reload)
--   5. Mid-reload               -> false (don't double-trigger)
--   6. Unequipped               -> false (no weapon held)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WeaponController = require(ReplicatedStorage.Shared.Weapon.Scripts.WeaponController)
local WeaponConstants = require(ReplicatedStorage.Shared.Weapon.Constants)

local function makeMockTool(magazineSize: number, reserve: number): Tool
	local tool = Instance.new("Tool")
	tool.Name = "ShouldReloadMockTool"
	tool:SetAttribute(WeaponConstants.MAGAZINE_SIZE_ATTRIBUTE, magazineSize)
	tool:SetAttribute(WeaponConstants.AMMO_ATTRIBUTE, magazineSize)
	tool:SetAttribute(WeaponConstants.RESERVE_AMMO_ATTRIBUTE, reserve)
	tool.Parent = ServerStorage
	return tool
end

local function makeController(tool: Tool, fields: {
	equipped: boolean?,
	ammo: number?,
	magazineSize: number?,
	reloading: boolean?,
})
	local controller = WeaponController.new(tool, { autoInitialize = false })
	controller.equipped = fields.equipped == true
	controller.ammo = fields.ammo or 0
	controller.magazineSize = fields.magazineSize or 10
	controller.reloading = fields.reloading == true
	return controller
end

return {
	name = "WeaponController:shouldReload — auto-reload only when mag empty and reserve > 0",

	run = function(ctx)
		ctx.results = {}

		-- Case 1: full mag, has reserve -> false
		do
			local tool = makeMockTool(10, 30)
			local c = makeController(tool, { equipped = true, ammo = 10, magazineSize = 10, reloading = false })
			ctx.results.case1_full_mag = c:shouldReload()
			tool:Destroy()
		end

		-- Case 2: partial mag (the user's bug — fired one shot)
		do
			local tool = makeMockTool(10, 30)
			local c = makeController(tool, { equipped = true, ammo = 9, magazineSize = 10, reloading = false })
			ctx.results.case2_partial_mag = c:shouldReload()
			tool:Destroy()
		end

		-- Case 3: empty mag with reserve -> true (auto-reload kicks in)
		do
			local tool = makeMockTool(10, 30)
			local c = makeController(tool, { equipped = true, ammo = 0, magazineSize = 10, reloading = false })
			ctx.results.case3_empty_with_reserve = c:shouldReload()
			tool:Destroy()
		end

		-- Case 4: empty mag, no reserve -> false (no-op reload)
		do
			local tool = makeMockTool(10, 0)
			local c = makeController(tool, { equipped = true, ammo = 0, magazineSize = 10, reloading = false })
			ctx.results.case4_empty_no_reserve = c:shouldReload()
			tool:Destroy()
		end

		-- Case 5: mid-reload -> false (don't re-trigger)
		do
			local tool = makeMockTool(10, 30)
			local c = makeController(tool, { equipped = true, ammo = 0, magazineSize = 10, reloading = true })
			ctx.results.case5_mid_reload = c:shouldReload()
			tool:Destroy()
		end

		-- Case 6: not equipped -> false
		do
			local tool = makeMockTool(10, 30)
			local c = makeController(tool, { equipped = false, ammo = 0, magazineSize = 10, reloading = false })
			ctx.results.case6_unequipped = c:shouldReload()
			tool:Destroy()
		end
	end,

	verify = function(ctx)
		local r = ctx.results
		local issues = {}

		if r.case1_full_mag ~= false then
			table.insert(issues, "case 1 (full mag): expected false, got " .. tostring(r.case1_full_mag))
		end
		if r.case2_partial_mag ~= false then
			table.insert(issues, string.format(
				"case 2 (partial mag — the user's auto-reload-on-fire-stop bug): expected false, got %s. shouldReload must require ammo == 0, not ammo < magazineSize.",
				tostring(r.case2_partial_mag)))
		end
		if r.case3_empty_with_reserve ~= true then
			table.insert(issues, "case 3 (empty mag with reserve): expected true, got " .. tostring(r.case3_empty_with_reserve))
		end
		if r.case4_empty_no_reserve ~= false then
			table.insert(issues, string.format(
				"case 4 (empty mag, no reserve): expected false, got %s. shouldReload must require reserve > 0 to avoid kicking off a reload the server's validateReload will reject.",
				tostring(r.case4_empty_no_reserve)))
		end
		if r.case5_mid_reload ~= false then
			table.insert(issues, "case 5 (mid-reload): expected false, got " .. tostring(r.case5_mid_reload))
		end
		if r.case6_unequipped ~= false then
			table.insert(issues, "case 6 (unequipped): expected false, got " .. tostring(r.case6_unequipped))
		end

		if #issues > 0 then
			return false, table.concat(issues, " | ")
		end
		return true, "shouldReload predicate matches auto-reload UX contract"
	end,
}
