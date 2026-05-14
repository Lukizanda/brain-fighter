--!strict

--[[
	MindFullManager smoke tests.

	Self-contained — not part of the TestRunner suite system. Invoke from
	MCP execute_luau or the command bar:

		require(ReplicatedStorage.Shared.MindFullManager.__tests).run()

	`task.wait()` calls bracket every buffer mutation that is expected to
	produce a transition signal — both WordBuffer.changed and the manager's
	own mindFull / mindFreed are backed by BindableEvents firing in Roblox's
	Deferred mode, so handlers don't observe new state until the next
	resumption cycle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MindFullManager = require(ReplicatedStorage.Shared.MindFullManager)
local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)

local M = {}

local function fail(scenario: string, message: string): never
	error(string.format("[MindFullManager.__tests] %s — %s", scenario, message), 2)
end

local function assertEq(scenario: string, name: string, actual: any, expected: any)
	if actual ~= expected then
		fail(scenario, string.format("%s: expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

function M.run()
	print("[MindFullManager.__tests] starting")

	-- Brief-aligned end-to-end: fill to cap, reject 13th, free one, refill,
	-- destroy. Asserts the exact transition counts the brief pins.
	do
		local buffer = WordBuffer.new()
		local mgr = MindFullManager.new(buffer)

		local fullFires, freedFires = 0, 0
		mgr.mindFull:Connect(function()
			fullFires = fullFires + 1
		end)
		mgr.mindFreed:Connect(function()
			freedFires = freedFires + 1
		end)

		assertEq("initial", "isMindFull", mgr:isMindFull(), false)

		-- Fill 11 tiles — no transition.
		for _ = 1, 11 do
			assert(buffer:append("X", "red") == true, "11-fill append should succeed")
		end
		task.wait()
		assertEq("pre-cap", "fullFires", fullFires, 0)
		assertEq("pre-cap", "freedFires", freedFires, 0)
		assertEq("pre-cap", "isMindFull", mgr:isMindFull(), false)

		-- 12th tile — rising edge fires mindFull exactly once.
		assert(buffer:append("X", "red") == true, "12th append should succeed")
		task.wait()
		assertEq("hit cap", "fullFires", fullFires, 1)
		assertEq("hit cap", "isMindFull", mgr:isMindFull(), true)

		-- 13th append — WordBuffer returns false and does NOT fire .changed,
		-- so no spurious transition.
		local appended = buffer:append("X", "red")
		task.wait()
		assertEq("over cap", "append return", appended, false)
		assertEq("over cap", "fullFires unchanged", fullFires, 1)
		assertEq("over cap", "freedFires unchanged", freedFires, 0)

		-- Remove one — falling edge fires mindFreed.
		buffer:remove(1)
		task.wait()
		assertEq("free one", "freedFires", freedFires, 1)
		assertEq("free one", "isMindFull", mgr:isMindFull(), false)

		-- Refill back to cap — second rising edge.
		assert(buffer:append("X", "red") == true, "refill append should succeed")
		task.wait()
		assertEq("refill", "fullFires", fullFires, 2)
		assertEq("refill", "isMindFull", mgr:isMindFull(), true)

		-- Destroy and confirm signals stop firing.
		mgr:destroy()
		buffer:remove(1)
		task.wait()
		assertEq("post-destroy", "freedFires frozen", freedFires, 1)

		buffer:destroy()
	end

	-- Non-cap mutations within a non-full buffer should never fire transitions.
	do
		local buffer = WordBuffer.new()
		local mgr = MindFullManager.new(buffer)

		local fires = 0
		mgr.mindFull:Connect(function() fires = fires + 1 end)
		mgr.mindFreed:Connect(function() fires = fires + 1 end)

		buffer:append("A", "red")
		buffer:append("B", "green")
		buffer:reorder(1, 2)
		buffer:remove(1)
		task.wait()
		assertEq("no-cap churn", "no transitions", fires, 0)

		mgr:destroy()
		buffer:destroy()
	end

	-- clear() from full → empty is one falling edge (one buffer.changed fire).
	do
		local buffer = WordBuffer.new()
		local mgr = MindFullManager.new(buffer)

		local fullFires, freedFires = 0, 0
		mgr.mindFull:Connect(function() fullFires = fullFires + 1 end)
		mgr.mindFreed:Connect(function() freedFires = freedFires + 1 end)

		for _ = 1, 12 do
			buffer:append("X", "blue")
		end
		task.wait()
		assertEq("clear from full", "fullFires", fullFires, 1)

		buffer:clear()
		task.wait()
		assertEq("clear from full", "freedFires", freedFires, 1)
		assertEq("clear from full", "isMindFull", mgr:isMindFull(), false)

		mgr:destroy()
		buffer:destroy()
	end

	-- Construction over an already-full buffer must NOT fire a phantom
	-- mindFull on the first subsequent buffer.changed. Seed _wasFull = true
	-- so the first observed transition is genuinely a falling edge.
	do
		local buffer = WordBuffer.new()
		for _ = 1, 12 do
			buffer:append("X", "green")
		end
		assert(buffer:isFull(), "pre-condition: buffer should be full")

		local mgr = MindFullManager.new(buffer)
		assertEq("born-full", "isMindFull", mgr:isMindFull(), true)

		local fullFires, freedFires = 0, 0
		mgr.mindFull:Connect(function() fullFires = fullFires + 1 end)
		mgr.mindFreed:Connect(function() freedFires = freedFires + 1 end)

		-- A no-op change against a buffer-already-full does not happen
		-- (append returns false without firing). Remove one to confirm the
		-- first observed transition is a falling edge.
		buffer:remove(1)
		task.wait()
		assertEq("born-full → remove", "fullFires", fullFires, 0)
		assertEq("born-full → remove", "freedFires", freedFires, 1)

		mgr:destroy()
		buffer:destroy()
	end

	print("[MindFullManager.__tests] all scenarios passed")
	return true
end

return M
