--!strict

----------------------------------------------------------------------
-- entry_link_routes — several pad-to-island routes inside one arena
----------------------------------------------------------------------
-- An `EntryLink` attribute splits one arena's arrival points into routes:
-- a pad's link reaches only arrival points with the same link, and no link
-- reaches only the points without one. A blank link counts as none.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local ARENA = "EntryLinkArena"
local LINK_A = "RouteA"
local LINK_B = "RouteB"
local PICK_ATTEMPTS = 40
local PICK_SEED = 11
local SPACING = 50

return {
	name = "entry_link_routes",

	run = function(ctx: any)
		ctx.fx = arenaEntryFixture.new()
	end,

	verify = function(ctx: any): (boolean, string?)
		local fx = ctx.fx
		local tag = ArenaEntryConstants.ARRIVAL_TAG
		local attribute = ArenaEntryConstants.LINK_ATTRIBUTE

		local plain = fx:part(tag, ARENA, CFrame.new(0, 500, 0))
		local blank = fx:part(tag, ARENA, CFrame.new(SPACING, 500, 0))
		blank:SetAttribute(attribute, "")
		local routeA = fx:part(tag, ARENA, CFrame.new(0, 500, SPACING))
		routeA:SetAttribute(attribute, LINK_A)
		local routeB = fx:part(tag, ARENA, CFrame.new(SPACING, 500, SPACING))
		routeB:SetAttribute(attribute, LINK_B)

		local random = Random.new(PICK_SEED)
		for _ = 1, PICK_ATTEMPTS do
			if ArenaEntryService.pickArrival(ARENA, random, LINK_A) ~= routeA then
				return false, "a pad linked to RouteA reached a point that is not RouteA's"
			end
			if ArenaEntryService.pickArrival(ARENA, random, LINK_B) ~= routeB then
				return false, "a pad linked to RouteB reached a point that is not RouteB's"
			end
			local unlinked = ArenaEntryService.pickArrival(ARENA, random, nil)
			if unlinked ~= plain and unlinked ~= blank then
				return false, "a pad with no link reached a linked arrival point"
			end
		end
		if ArenaEntryService.pickArrival(ARENA, random, "RouteNone") ~= nil then
			return false, "a link with no arrival point got one"
		end

		-- linkOf is what handleTouch reads off the pad.
		if ArenaEntryService.linkOf(routeA) ~= LINK_A or ArenaEntryService.linkOf(plain) ~= nil
			or ArenaEntryService.linkOf(blank) ~= nil then
			return false, "linkOf misread a link, a missing link or a blank link"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.fx then
			ctx.fx:cleanup(nil)
		end
	end,
}
