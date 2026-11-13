--!strict

----------------------------------------------------------------------
-- entry_matches_by_arena — pad-to-arrival matching by ArenaId
----------------------------------------------------------------------
-- `pickArrival` returns only arrival points of the pad's arena, can reach
-- every one of several, treats an unattributed point as the Default arena,
-- and finds a point tagged after the service booted.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local ARENA_A = "EntryMatchA"
local ARENA_B = "EntryMatchB"
local PICK_ATTEMPTS = 60
local PICK_SEED = 7
local SPACING = 50

return {
	name = "entry_matches_by_arena",

	run = function(ctx: any)
		ctx.fx = arenaEntryFixture.new()
	end,

	verify = function(ctx: any): (boolean, string?)
		local fx = ctx.fx
		local tag = ArenaEntryConstants.ARRIVAL_TAG
		local a1 = fx:part(tag, ARENA_A, CFrame.new(0, 500, 0))
		local a2 = fx:part(tag, ARENA_A, CFrame.new(SPACING, 500, 0))
		local b1 = fx:part(tag, ARENA_B, CFrame.new(0, 500, SPACING))

		local random = Random.new(PICK_SEED)
		local seen: { [BasePart]: boolean } = {}
		for _ = 1, PICK_ATTEMPTS do
			local picked = ArenaEntryService.pickArrival(ARENA_A, random)
			if picked ~= a1 and picked ~= a2 then
				return false, "pickArrival(A) returned a point that is not one of A's"
			end
			seen[picked :: BasePart] = true
		end
		if not seen[a1] or not seen[a2] then
			return false, "with two arrival points in A, one was never picked"
		end

		if ArenaEntryService.pickArrival(ARENA_B, random) ~= b1 then
			return false, "pickArrival(B) did not return B's only point"
		end
		if ArenaEntryService.pickArrival("EntryMatchNone", random) ~= nil then
			return false, "an arena with no arrival point got one"
		end

		-- No ArenaId attribute means the Default arena, as everywhere else.
		local bare = fx:part(tag, ARENA_A, CFrame.new(0, 500, -SPACING))
		bare:SetAttribute(Arena.ID_ATTRIBUTE, nil)
		local pickedDefault = ArenaEntryService.pickArrival(Arena.DEFAULT_ID, random)
		if pickedDefault ~= bare then
			-- A real Default arrival may exist in the scene by now; accept it
			-- only if it is a different tagged part of the Default arena.
			if not pickedDefault or Arena.idOf(pickedDefault) ~= Arena.DEFAULT_ID then
				return false, "an unattributed arrival point did not match the Default arena"
			end
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.fx then
			ctx.fx:cleanup(nil)
		end
	end,
}
