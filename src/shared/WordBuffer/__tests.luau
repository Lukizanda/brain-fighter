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
-- reorder, remove, clear, fill-to-cap rejection, changed-signal fire
-- count over a 3-append sequence, and removeLastMatching (the optimistic
-- append rollback — see wiki/systems/BlockShoot.md § Contested blocks).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	-- Wait a frame so the changes counter catches up before we assert.
	-- See the removeLastMatching block below for why this is Heartbeat
	-- rather than a bare task.wait().
	RunService.Heartbeat:Wait()
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

	-- Wildcard tiles: "wild" is a legal 4th color, and a star survives
	-- asWord() as a pattern rather than being uppercased away or dropped.
	local w = WordBuffer.new(CAP)
	assert(w:append("D", "red") == true, "append D red should succeed")
	assert(w:append("*", "wild" :: any) == true, "append * wild should succeed")
	assert(w:append("G", "blue") == true, "append G blue should succeed")
	assert(w:asWord() == "D*G", `asWord should be "D*G", got "{w:asWord()}"`)

	local wildTiles = w:tiles()
	assert(wildTiles[2].letter == "*", "wild tile should keep its star letter")
	assert(wildTiles[2].color == "wild", "wild tile should keep its wild color")

	local bag = w:colorBag()
	assert(bag.wild == 1, `colorBag should count 1 wild, got {tostring(bag.wild)}`)
	assert(bag.red == 1 and bag.blue == 1, "colorBag should still count reservoir colors")

	w:destroy()

	----------------------------------------------------------------------
	-- removeLastMatching — the optimistic-append rollback (5.7 stage 4)
	----------------------------------------------------------------------
	-- Each case here is a way the naive implementation ("pop the last
	-- slot") gets it wrong, so they are assertions about the *choice*, not
	-- just about the arithmetic.
	local r = WordBuffer.new()

	-- 1. Must not confiscate letters appended during the round trip. The
	--    rejected tile is the E; the A and T came after and were earned.
	r:append("E", "green")
	r:append("A", "red")
	r:append("T", "blue")
	assert(r:removeLastMatching("E", "green") == true, "should find the rejected E")
	assert(r:asWord() == "AT", `expected "AT" after rolling back E, got "{r:asWord()}"`)

	-- 2. Colour is part of the match: a same-letter tile of another colour
	--    is a different tile and must survive.
	r:clear()
	r:append("R", "blue")
	r:append("R", "red")
	assert(r:removeLastMatching("R", "blue") == true, "should match on letter AND colour")
	assert(r:size() == 1, "the other-coloured R should survive")
	assert(r:tiles()[1].color == "red", "the surviving R should be the red one")

	-- 3. Duplicates: removes exactly one, and the last of them.
	r:clear()
	r:append("S", "red")
	r:append("O", "green")
	r:append("S", "red")
	assert(r:removeLastMatching("S", "red") == true, "should remove one duplicate")
	assert(r:asWord() == "SO", `expected "SO" (last S removed), got "{r:asWord()}"`)

	-- 4. No match is a no-op, not a mistake. The player may have destroyed
	--    the tile themselves before the rejection landed; eating an
	--    innocent letter instead would be strictly worse than doing nothing.
	r:clear()
	r:append("Z", "blue")
	local before = r:asWord()
	assert(r:removeLastMatching("Q", "red") == false, "no match should report false")
	assert(r:asWord() == before, "no match must not mutate the buffer")

	-- 5. Empty buffer is safe.
	r:clear()
	assert(r:removeLastMatching("A", "red") == false, "empty buffer should report false")

	-- 6. Fires `changed` only when it actually removed something — the HUD
	--    should not redraw for a rollback that did nothing.
	r:clear()
	r:append("W", "green")
	local rollbackChanges = 0
	r.changed:Connect(function()
		rollbackChanges = rollbackChanges + 1
	end)
	assert(r:removeLastMatching("X", "red") == false, "miss")
	assert(r:removeLastMatching("W", "green") == true, "hit")
	-- Wait a frame, not `task.wait()`. BindableEvent delivery is deferred,
	-- so asserting inline reads 0 for both cases and passes the no-op check
	-- vacuously. Heartbeat is the reliable flush point: a bare `task.wait()`
	-- does not resume deferred handlers under every execution context (it
	-- does not inside an injected execute_luau chunk, which is how this
	-- suite gets run from MCP).
	RunService.Heartbeat:Wait()
	assert(rollbackChanges == 1,
		`exactly one changed fire expected — the hit, not the miss — got {rollbackChanges}`)

	r:destroy()

	log:info("[TEST PASS] WordBuffer smoke")
	return true
end

return runTests
