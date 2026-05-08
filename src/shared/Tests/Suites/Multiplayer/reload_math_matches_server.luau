----------------------------------------------------------------------
-- Test: Ammo.performReload transfers min(needed, reserve) — locked-down
----------------------------------------------------------------------
-- Phase D1 hardening test for the bug class that produced "post-respawn
-- invulnerability" earlier this session: client-side reload prediction
-- diverging from the server's actual reload math, so subsequent shots
-- silently fail validateShot(ammo<=0) while the client thinks it has
-- a full magazine.
--
-- The fix (commit 22661c1) made FirearmController:startReload mirror
-- the same min(needed, reserve) math the server uses. This test pins
-- down that math in the server module so any future change to reload
-- behaviour breaks here loudly + visibly, and the client can then be
-- updated in lockstep.
--
-- We exercise three states:
--   1. Full reserve, partially-empty mag → full refill from reserve
--   2. Partial reserve (less than needed) → reserve drains to 0, mag partially fills
--   3. Empty reserve, partially-empty mag → no-op (this is the bug
--      shape that bit us — the client must NOT optimistically refill
--      to magazineSize)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ammo = require(ReplicatedStorage.Shared.Weapon.Scripts.Ammo)
local WeaponConstants = require(ReplicatedStorage.Shared.Weapon.Constants)

local function makeMockTool(magazineSize: number, ammo: number, reserve: number): Tool
	local tool = Instance.new("Tool")
	tool.Name = "ReloadMockTool"
	tool:SetAttribute(WeaponConstants.MAGAZINE_SIZE_ATTRIBUTE, magazineSize)
	tool:SetAttribute(WeaponConstants.AMMO_ATTRIBUTE, ammo)
	tool:SetAttribute(WeaponConstants.RESERVE_AMMO_ATTRIBUTE, reserve)
	-- Tool needs a parent so SetAttribute writes are observable in the
	-- same way they would be at runtime; ServerStorage avoids any
	-- player-side side-effects.
	tool.Parent = game:GetService("ServerStorage")
	return tool
end

local function ammoPair(tool: Tool): (number, number)
	return tool:GetAttribute(WeaponConstants.AMMO_ATTRIBUTE) or 0,
	       tool:GetAttribute(WeaponConstants.RESERVE_AMMO_ATTRIBUTE) or 0
end

return {
	name = "Ammo.performReload transfers min(needed, reserve)",

	run = function(ctx)
		ctx.results = {}

		----------------------------------------------------------------
		-- Case 1: full reserve, half-empty mag
		--   magazineSize=30, ammo=10, reserve=90
		--   needed=20, transfer=min(20, 90)=20
		--   expected: ammo=30, reserve=70, return=20
		----------------------------------------------------------------
		do
			local tool = makeMockTool(30, 10, 90)
			local moved = Ammo.performReload(tool)
			local a, r = ammoPair(tool)
			ctx.results.case1 = { moved = moved, ammo = a, reserve = r }
			tool:Destroy()
		end

		----------------------------------------------------------------
		-- Case 2: partial reserve (less than needed)
		--   magazineSize=30, ammo=5, reserve=8
		--   needed=25, transfer=min(25, 8)=8
		--   expected: ammo=13, reserve=0, return=8
		----------------------------------------------------------------
		do
			local tool = makeMockTool(30, 5, 8)
			local moved = Ammo.performReload(tool)
			local a, r = ammoPair(tool)
			ctx.results.case2 = { moved = moved, ammo = a, reserve = r }
			tool:Destroy()
		end

		----------------------------------------------------------------
		-- Case 3: EMPTY RESERVE — the bug shape from earlier this
		-- session. Server transfers 0; the client used to (incorrectly)
		-- jump to a full magazine, causing every subsequent shot to
		-- fail validateShot.
		--   magazineSize=30, ammo=0, reserve=0
		--   expected: ammo=0, reserve=0, return=0 — no transfer
		----------------------------------------------------------------
		do
			local tool = makeMockTool(30, 0, 0)
			local moved = Ammo.performReload(tool)
			local a, r = ammoPair(tool)
			ctx.results.case3 = { moved = moved, ammo = a, reserve = r }
			tool:Destroy()
		end
	end,

	verify = function(ctx)
		local r = ctx.results
		local issues = {}

		if r.case1.moved ~= 20 or r.case1.ammo ~= 30 or r.case1.reserve ~= 70 then
			table.insert(issues, string.format(
				"case 1 (full reserve): expected moved=20 ammo=30 reserve=70; got moved=%d ammo=%d reserve=%d",
				r.case1.moved, r.case1.ammo, r.case1.reserve))
		end
		if r.case2.moved ~= 8 or r.case2.ammo ~= 13 or r.case2.reserve ~= 0 then
			table.insert(issues, string.format(
				"case 2 (partial reserve): expected moved=8 ammo=13 reserve=0; got moved=%d ammo=%d reserve=%d",
				r.case2.moved, r.case2.ammo, r.case2.reserve))
		end
		if r.case3.moved ~= 0 or r.case3.ammo ~= 0 or r.case3.reserve ~= 0 then
			table.insert(issues, string.format(
				"case 3 (empty reserve — the post-respawn-invulnerability shape): expected moved=0 ammo=0 reserve=0; got moved=%d ammo=%d reserve=%d",
				r.case3.moved, r.case3.ammo, r.case3.reserve))
		end

		if #issues > 0 then
			return false, table.concat(issues, " | ")
		end
		return true, "all 3 reload cases match expected min(needed, reserve) math"
	end,
}
