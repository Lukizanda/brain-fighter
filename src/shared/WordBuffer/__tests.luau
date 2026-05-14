--!strict

----------------------------------------------------------------------
-- WordBuffer smoke tests
----------------------------------------------------------------------
-- Standalone runnable: returns a function. The parent module wires the
-- result into the project TestRunner (or a dev harness) as needed.
--
--   local runTests = require(ReplicatedStorage.Shared.WordBuffer.__tests)
--   runTests()  -- throws on assertion failure
--
-- Covers: append/size/isFull, asWord uppercase, color-bag counts,
-- reorder, remove, clear, fill-to-cap rejection, and changed-signal
-- fire count over a 3-append sequence.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local WordBuffer = require(script.Parent)

local CAP = 12
local log = Logger.new("WordBuffer.tests")

local function runTests(): boolean
	local b = WordBuffer.new()
	assert(b:size() == 0, "fresh buffer should be empty")
	assert(b:isFull() == false, "fresh buffer should not be full")
	assert(b:asWord() == "", "empty buffer should stringify to empty word")

	local changes = 0
	b.changed:Connect(function()
		changes = changes + 1
	end)

	assert(b:append("F", "red") == true, "append F red should succeed")
	assert(b:append("L", "red") == true, "append L red should succeed")
	assert(b:append("A", "green") == true, "append A green should succeed")
	assert(b:size() == 3, "size should be 3 after 3 appends")
	assert(b:asWord() == "FLA", `asWord should be "FLA", got "{b:asWord()}"`)

	local bag = b:colorBag()
	assert(bag.red == 2, `colorBag.red should be 2, got {tostring(bag.red)}`)
	assert(bag.green == 1, `colorBag.green should be 1, got {tostring(bag.green)}`)
	assert(bag.blue == nil, "colorBag.blue should be absent (no blue tiles)")

	-- BindableEvent.Event is queued — signals dispatch on the next resumption.
	-- Yield once so the changes counter catches up before we assert.
	task.wait()
	assert(changes == 3, `expected 3 change fires, got {changes}`)

	-- reorder(1, 3): move F to end → ["L"-red, "A"-green, "F"-red] → "LAF"
	b:reorder(1, 3)
	assert(b:asWord() == "LAF", `reorder result should be "LAF", got "{b:asWord()}"`)

	-- remove(2): drop A → ["L"-red, "F"-red] → "LF"
	b:remove(2)
	assert(b:asWord() == "LF", `remove result should be "LF", got "{b:asWord()}"`)
	assert(b:size() == 2, "size should be 2 after remove")

	b:clear()
	assert(b:size() == 0, "size should be 0 after clear")
	assert(b:asWord() == "", "asWord should be empty after clear")

	-- Fill to cap then verify rejection
	for i = 1, CAP do
		local ok = b:append("X", "red")
		assert(ok == true, `fill append #{i} should succeed`)
	end
	assert(b:isFull(), "buffer should be full after CAP appends")
	assert(b:size() == CAP, `size should be {CAP} when full, got {b:size()}`)
	assert(b:append("Y", "red") == false, "append past cap should return false")
	assert(b:size() == CAP, "size should be unchanged after rejected append")

	-- Out-of-range guards do not throw (warn + return)
	b:remove(0)
	b:remove(CAP + 5)
	b:reorder(0, 1)
	b:reorder(1, CAP + 5)
	assert(b:size() == CAP, "out-of-range ops should not mutate")

	-- Invalid color rejected
	assert(b:append("Z", "yellow" :: any) == false, "invalid color should reject")

	b:destroy()

	log:info("[TEST PASS] WordBuffer smoke")
	return true
end

return runTests
