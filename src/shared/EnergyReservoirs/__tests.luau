--!strict

--[[
	EnergyReservoirs smoke tests.

	Self-contained — not part of the TestRunner suite system. Either require
	this module manually (from MCP execute_luau or the command bar) or call
	`require(... .__tests).run()` from another harness. All asserts use
	`error(...)` so a failed run prints a useful stack with the failed
	scenario name.

	Signal-fire scenarios call `task.wait()` between the operation and the
	post-fire assertion because Roblox runs BindableEvent connections in
	Deferred mode by default — handlers don't observe the new state until
	the next resumption cycle. See the wiki page for details.

	Usage:
		require(ReplicatedStorage.Shared.EnergyReservoirs.__tests).run()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local M = {}

local function fail(scenario: string, message: string): never
	error(string.format("[EnergyReservoirs.__tests] %s — %s", scenario, message), 2)
end

local function assertEq(scenario: string, name: string, actual: any, expected: any)
	if actual ~= expected then
		fail(scenario, string.format("%s: expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

function M.run()
	print("[EnergyReservoirs.__tests] starting")

	-- Initial state
	do
		local r = EnergyReservoirs.new()
		assertEq("initial state", "red",   r:get("red"),   0)
		assertEq("initial state", "green", r:get("green"), 0)
		assertEq("initial state", "blue",  r:get("blue"),  0)
		r:destroy()
	end

	-- add fires changed once, only for the touched color
	do
		local r = EnergyReservoirs.new()
		local changes: { string } = {}
		r.changed:Connect(function(color)
			table.insert(changes, color)
		end)

		r:add("red", 25)
		assertEq("add(red, 25)", "value",              r:get("red"),    25)
		assertEq("add(red, 25)", "green untouched",    r:get("green"),  0)
		assertEq("add(red, 25)", "blue untouched",     r:get("blue"),   0)
		task.wait() -- drain deferred BindableEvent handlers before observing
		assertEq("add(red, 25)", "changes fired",      #changes,        1)
		assertEq("add(red, 25)", "changes[1]",         changes[1],      "red")

		r:destroy()
	end

	-- add caps at CAP_PER_COLOR
	do
		local r = EnergyReservoirs.new()
		r:add("red", 200)
		assertEq("add overflow caps", "value", r:get("red"), EnergyReservoirs.CAP_PER_COLOR)
		r:destroy()
	end

	-- add at cap doesn't double-fire
	do
		local r = EnergyReservoirs.new()
		local fires = 0
		r.changed:Connect(function() fires += 1 end)

		r:add("red", EnergyReservoirs.CAP_PER_COLOR) -- fires
		r:add("red", 50)                              -- already capped → no-op
		task.wait()
		assertEq("add then add-at-cap", "fires total", fires, 1)
		assertEq("add then add-at-cap", "still capped", r:get("red"), EnergyReservoirs.CAP_PER_COLOR)
		r:destroy()
	end

	-- add(0) and add(-n) are no-ops
	do
		local r = EnergyReservoirs.new()
		local fires = 0
		r.changed:Connect(function() fires += 1 end)

		r:add("red", 0)
		r:add("red", -10)
		task.wait()
		assertEq("add non-positive", "fires", fires, 0)
		assertEq("add non-positive", "value", r:get("red"), 0)
		r:destroy()
	end

	-- canAfford boundary
	do
		local r = EnergyReservoirs.new()
		r:add("red", 50)
		assertEq("canAfford boundary", "50 >= 50", r:canAfford("red", 50), true)
		assertEq("canAfford boundary", "50 >= 49", r:canAfford("red", 49), true)
		assertEq("canAfford boundary", "50 >= 51", r:canAfford("red", 51), false)
		r:destroy()
	end

	-- drain success
	do
		local r = EnergyReservoirs.new()
		r:add("red", 50)
		task.wait() -- drain the add's deferred fire so it doesn't bleed into the next assertion

		local changes: { string } = {}
		r.changed:Connect(function(color) table.insert(changes, color) end)

		local ok = r:drain("red", 30)
		assertEq("drain success", "returned", ok, true)
		assertEq("drain success", "value", r:get("red"), 20)
		task.wait()
		assertEq("drain success", "fired once",        #changes,    1)
		assertEq("drain success", "fired with color",  changes[1],  "red")
		r:destroy()
	end

	-- drain failure leaves state untouched and does not fire
	do
		local r = EnergyReservoirs.new()
		r:add("red", 50)
		task.wait()

		local fires = 0
		r.changed:Connect(function() fires += 1 end)

		local ok = r:drain("red", 200)
		assertEq("drain insufficient", "returned",        ok,             false)
		assertEq("drain insufficient", "value untouched", r:get("red"),   50)
		task.wait()
		assertEq("drain insufficient", "no fire", fires, 0)
		r:destroy()
	end

	-- snapshot is a defensive copy
	do
		local r = EnergyReservoirs.new()
		r:add("red", 10)
		r:add("green", 20)
		r:add("blue", 30)

		local snap = r:snapshot()
		assertEq("snapshot", "red",   snap.red,   10)
		assertEq("snapshot", "green", snap.green, 20)
		assertEq("snapshot", "blue",  snap.blue,  30)

		-- mutate the snapshot; verify the reservoir is unaffected
		snap.red = 999
		assertEq("snapshot is defensive", "live red", r:get("red"), 10)
		r:destroy()
	end

	-- The exact scenario from the task brief, end-to-end. `task.wait()`s
	-- inserted around the signal-observation points to accommodate Deferred
	-- BindableEvent firing — the value/return assertions remain synchronous
	-- as the brief intends.
	do
		local r = EnergyReservoirs.new()
		assert(r:get("red") == 0)
		assert(r:get("green") == 0)
		assert(r:get("blue") == 0)

		local changes: { string } = {}
		r.changed:Connect(function(color) table.insert(changes, color) end)

		r:add("red", 25)
		assert(r:get("red") == 25)
		task.wait()
		assert(#changes == 1 and changes[1] == "red")
		assert(r:get("green") == 0)

		local cap = EnergyReservoirs.CAP_PER_COLOR
		r:add("red", cap + 100)
		assert(r:get("red") == cap) -- overflow clamps to the cap

		assert(r:canAfford("red", cap) == true)
		assert(r:canAfford("red", cap + 1) == false)

		assert(r:drain("red", 30) == true)
		assert(r:get("red") == cap - 30)
		task.wait()

		local changesBefore = #changes
		assert(r:drain("red", cap + 100) == false)
		assert(r:get("red") == cap - 30)
		task.wait()
		assert(#changes == changesBefore)

		local snap = r:snapshot()
		assert(snap.red == cap - 30 and snap.green == 0 and snap.blue == 0)

		r:destroy()
	end

	-- Unknown color rejects with a descriptive error
	do
		local r = EnergyReservoirs.new()
		local ok, err = pcall(function() r:add("purple", 10) end)
		assertEq("unknown color rejects", "pcall ok", ok, false)
		if not string.find(tostring(err), "unknown color") then
			fail("unknown color rejects", "error message missing 'unknown color': " .. tostring(err))
		end
		r:destroy()
	end

	print("[EnergyReservoirs.__tests] all scenarios passed")
	return true
end

return M
