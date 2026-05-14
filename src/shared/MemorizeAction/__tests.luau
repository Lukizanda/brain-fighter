--!strict

----------------------------------------------------------------------
-- MemorizeAction smoke tests
----------------------------------------------------------------------
-- Self-contained — exposes `M.run()` which throws on any assertion
-- failure and prints `[MemorizeAction.__tests] all scenarios passed`
-- on success.
--
-- Covers the four scenarios from NIM-6:
--   1. Empty buffer → fizzle "empty"; buffer + reservoirs unchanged.
--   2. Invalid word "XYZ" → fizzle "invalid"; buffer preserved.
--   3. Valid mono-color "FIRE" → reservoirs.red += 7; buffer cleared.
--   4. Valid mixed-color "FLAME" → red=12, green=3 split; buffer
--      cleared; reservoirs accumulate on top of pre-existing state.
--
-- These tests stay synchronous (no `task.wait`) because MemorizeAction
-- itself only calls synchronous methods — we don't connect to the
-- buffer or reservoir `.changed` signals here.
--
-- Usage:
--   require(ReplicatedStorage.Shared.MemorizeAction.__tests).run()
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)
local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local M = {}

function M.run()
	print("[MemorizeAction.__tests] starting")

	-- 1. Empty buffer fizzles with reason="empty"; no state mutation.
	do
		local b = WordBuffer.new()
		local r = EnergyReservoirs.new()
		local res = MemorizeAction.tryMemorize(b, r)
		assert(res.ok == false, "empty: ok should be false")
		assert(res.reason == "empty", `empty: reason should be "empty", got {tostring(res.reason)}`)
		assert(res.word == nil, "empty: word should be nil")
		assert(res.energyByColor == nil, "empty: energyByColor should be nil")
		assert(b:size() == 0, "empty: buffer should remain empty")
		assert(r:get("red") == 0, "empty: reservoir.red should remain 0")
		assert(r:get("green") == 0, "empty: reservoir.green should remain 0")
		assert(r:get("blue") == 0, "empty: reservoir.blue should remain 0")
		b:destroy()
		r:destroy()
	end

	-- 2. Invalid word "XYZ" fizzles with reason="invalid"; buffer is preserved.
	do
		local b = WordBuffer.new()
		local r = EnergyReservoirs.new()
		b:append("X", "red")
		b:append("Y", "red")
		b:append("Z", "red")

		local res = MemorizeAction.tryMemorize(b, r)
		assert(res.ok == false, "invalid: ok should be false")
		assert(res.reason == "invalid", `invalid: reason should be "invalid", got {tostring(res.reason)}`)
		assert(b:size() == 3, `invalid: buffer should be preserved at size 3, got {b:size()}`)
		assert(b:asWord() == "XYZ", `invalid: buffer word should still be "XYZ", got "{b:asWord()}"`)
		assert(r:get("red") == 0, "invalid: no energy deposited")
		b:destroy()
		r:destroy()
	end

	-- 3. Valid mono-color word "FIRE" (all red).
	-- Energy = 7 per the pinned worked-example in gameplay-loop.md.
	do
		local b = WordBuffer.new()
		local r = EnergyReservoirs.new()
		for _, l in ipairs({ "F", "I", "R", "E" }) do
			b:append(l, "red")
		end

		local res = MemorizeAction.tryMemorize(b, r)
		assert(res.ok == true, "FIRE: ok should be true")
		assert(res.reason == nil, "FIRE: reason should be nil")
		assert(res.word == "FIRE", `FIRE: word should be "FIRE", got "{tostring(res.word)}"`)
		assert(res.energyByColor ~= nil, "FIRE: energyByColor should be present")
		local split = res.energyByColor :: { [string]: number }
		assert(split.red == 7, `FIRE: split.red should be 7, got {tostring(split.red)}`)
		assert(split.green == nil, "FIRE: split.green should be absent")
		assert(split.blue == nil, "FIRE: split.blue should be absent")
		assert(b:size() == 0, "FIRE: buffer should be cleared")
		assert(r:get("red") == 7, `FIRE: reservoir.red should be 7, got {r:get("red")}`)
		assert(r:get("green") == 0, "FIRE: green untouched")
		assert(r:get("blue") == 0, "FIRE: blue untouched")
		b:destroy()
		r:destroy()
	end

	-- 4. Valid mixed-color word "FLAME": F-L-M red, A-E green.
	-- Pinned split: red=12, green=3 (sums to 15). Verify the reservoir
	-- ADDS to its pre-existing value (not replaces).
	do
		local b = WordBuffer.new()
		local r = EnergyReservoirs.new()
		r:add("red", 5) -- pre-existing red reservoir state
		local redBefore = r:get("red")

		b:append("F", "red")
		b:append("L", "red")
		b:append("A", "green")
		b:append("M", "red")
		b:append("E", "green")

		local res = MemorizeAction.tryMemorize(b, r)
		assert(res.ok == true, "FLAME: ok should be true")
		assert(res.word == "FLAME", `FLAME: word should be "FLAME", got "{tostring(res.word)}"`)
		local split = res.energyByColor :: { [string]: number }
		assert(split.red == 12, `FLAME: split.red should be 12, got {tostring(split.red)}`)
		assert(split.green == 3, `FLAME: split.green should be 3, got {tostring(split.green)}`)
		assert(split.blue == nil, "FLAME: split.blue should be absent")
		assert(b:size() == 0, "FLAME: buffer should be cleared")
		assert(r:get("red") == redBefore + 12, `FLAME: reservoir.red should be {redBefore + 12}, got {r:get("red")}`)
		assert(r:get("green") == 3, `FLAME: reservoir.green should be 3, got {r:get("green")}`)
		assert(r:get("blue") == 0, "FLAME: blue untouched")
		b:destroy()
		r:destroy()
	end

	print("[MemorizeAction.__tests] all scenarios passed")
	return true
end

return M
