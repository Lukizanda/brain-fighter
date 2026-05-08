----------------------------------------------------------------------
-- Test: LoadoutRequestDrop is rejected outside respawn zones
----------------------------------------------------------------------
-- Validates the C2-server-gate deliverable end-to-end:
--   - When the player is OUTSIDE every RespawnZone, calling the drop
--     handler returns (false, "Drop only in your spawn room") AND the
--     equipped Tool survives.
--   - When the player is INSIDE a RespawnZone, the drop handler
--     returns (true, nil) and the equipped Tool is destroyed.
--
-- The test invokes the drop handler via the `_G.LoadoutService_tryDrop`
-- exposure. RemoteEvent:FireServer is client-only, so a server-side
-- test cannot trigger LoadoutRequestDrop the way a real client does;
-- the global is a deliberate seam for this test (and any future drop-
-- related regression checks).
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RespawnZoneService = require(ServerScriptService.Server.Loadout.RespawnZoneService)
local TestHelpers = require(ReplicatedStorage.Shared.Tests.Helpers.restoreToSafeSpawn)

local FAR_AWAY = Vector3.new(0, 9000, 0)
local TOUCH_POLL_INTERVAL = 0.1
local TOUCH_POLL_TIMEOUT = 2.5 -- seconds

-- Roblox doesn't always fire TouchEnded promptly when HRP CFrame-jumps
-- away from a long-resting contact; same trap on the entry side. Poll
-- the presence map until it reflects the expected state instead of
-- waiting a fixed delay (was 0.5s, flaky for the early-suite case
-- where HRP has been resting on SpawnLocation since game start).
local function waitForZoneState(player: Player, expectInZone: boolean): boolean
	local deadline = os.clock() + TOUCH_POLL_TIMEOUT
	while os.clock() < deadline do
		if RespawnZoneService.isPlayerInZone(player, player.Team) == expectInZone then
			return true
		end
		task.wait(TOUCH_POLL_INTERVAL)
	end
	return false
end

local function findFirstZone(): BasePart?
	for _, instance in CollectionService:GetTagged("RespawnZone") do
		if instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

return {
	name = "LoadoutRequestDrop is zone-gated server-side",

	setup = function(ctx)
		assert(ctx.player, "no local player available")
		assert(_G.LoadoutService_tryDrop, "LoadoutService didn't expose tryDrop on _G")

		local zone = findFirstZone()
		assert(zone, "no RespawnZone-tagged BasePart found in workspace")
		ctx.zone = zone

		local character = ctx.player.Character or ctx.player.CharacterAdded:Wait()
		local hum = character:WaitForChild("Humanoid", 5)
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		assert(hum and hrp, "player missing Humanoid or HumanoidRootPart")
		ctx.hum = hum
		ctx.hrp = hrp

		-- Equip a real Loadout Tool. Server-side parenting fires the
		-- standard Backpack.ChildAdded → registerNormal chain.
		local backpack = ctx.player:FindFirstChildOfClass("Backpack")
		assert(backpack, "player has no Backpack")
		-- Tear down anything left from prior tests
		for _, t in backpack:GetChildren() do if t:IsA("Tool") then t:Destroy() end end
		for _, t in character:GetChildren() do if t:IsA("Tool") then t:Destroy() end end

		local templates = ReplicatedStorage.Shared.Weapon.Templates
		local clone = templates.Rifle:Clone()
		clone.Parent = backpack
		ctx.tool = clone
		task.wait(0.5) -- LoadoutService onToolAdded settle
		hum:EquipTool(clone)
		task.wait(0.3)
		assert(character:FindFirstChildOfClass("Tool") == clone,
			"failed to equip the test Tool")
	end,

	run = function(ctx)
		-- Phase 1: out of zone → expect rejection
		ctx.hrp.CFrame = CFrame.new(FAR_AWAY)
		ctx.outsideZoneSettled = waitForZoneState(ctx.player, false)
		ctx.outsideOk, ctx.outsideReason = _G.LoadoutService_tryDrop(ctx.player)
		ctx.toolAliveAfterReject = ctx.tool.Parent ~= nil

		-- Phase 2: inside zone → expect success (destroys the tool)
		ctx.hrp.CFrame = CFrame.new(ctx.zone.Position)
		ctx.insideZoneSettled = waitForZoneState(ctx.player, true)
		ctx.insideOk, ctx.insideReason = _G.LoadoutService_tryDrop(ctx.player)
		ctx.toolDestroyedAfterAccept = ctx.tool.Parent == nil
	end,

	verify = function(ctx)
		if not ctx.outsideZoneSettled then
			return false, string.format("isPlayerInZone never went false within %.1fs after teleporting HRP to %s — TouchEnded didn't fire (RespawnZoneService bug or Roblox CFrame-jump quirk)",
				TOUCH_POLL_TIMEOUT, tostring(FAR_AWAY))
		end
		if not ctx.insideZoneSettled then
			return false, string.format("isPlayerInZone never went true within %.1fs after teleporting HRP into the zone — Touched didn't fire",
				TOUCH_POLL_TIMEOUT)
		end
		if ctx.outsideOk ~= false then
			return false, string.format("outside-zone tryDrop returned ok=%s reason=%s — expected false",
				tostring(ctx.outsideOk), tostring(ctx.outsideReason))
		end
		if ctx.outsideReason ~= "Drop only in your spawn room" then
			return false, string.format("outside-zone reason was %q, expected %q",
				tostring(ctx.outsideReason), "Drop only in your spawn room")
		end
		if not ctx.toolAliveAfterReject then
			return false, "tool was destroyed during rejection (should have been preserved)"
		end
		if ctx.insideOk ~= true then
			return false, string.format("inside-zone tryDrop returned ok=%s reason=%s — expected true",
				tostring(ctx.insideOk), tostring(ctx.insideReason))
		end
		if not ctx.toolDestroyedAfterAccept then
			return false, "tool survived inside-zone drop (expected destruction)"
		end
		return true, "outside→reject (tool preserved); inside→accept (tool destroyed)"
	end,

	teardown = function(ctx)
		-- Always restore to a SpawnLocation, never to a captured CFrame —
		-- a captured CFrame may itself have been airborne. The next test
		-- in the suite needs a stable starting position.
		TestHelpers.restoreToSafeSpawn(ctx.player)
		-- Tool may have been destroyed by phase 2; that's expected.
	end,
}
