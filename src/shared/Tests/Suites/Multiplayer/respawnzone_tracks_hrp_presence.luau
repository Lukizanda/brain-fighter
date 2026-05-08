----------------------------------------------------------------------
-- Test: RespawnZoneService correctly tracks HRP presence in tagged zones
----------------------------------------------------------------------
-- Validates the C1 deliverable:
--   - isPlayerInZone(player) returns false when HRP is far outside all
--     RespawnZone-tagged volumes.
--   - isPlayerInZone(player) returns true after teleporting HRP into a
--     RespawnZone (Touched fires, presence gets recorded).
--
-- The teleport-out / teleport-in approach exercises the same Touched /
-- TouchEnded code path the live LoadoutRequestDrop gate depends on.
-- Without this test, a regression in attachZone or the HRP-name filter
-- would only surface when a player tries to drop a weapon — which is a
-- low-traffic flow easy to ship a regression in.
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
		if RespawnZoneService.isPlayerInZone(player) == expectInZone then
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
	name = "RespawnZoneService tracks HRP presence in tagged zones",

	setup = function(ctx)
		assert(ctx.player, "no local player available")

		local zone = findFirstZone()
		assert(zone, "no RespawnZone-tagged BasePart found in workspace")
		ctx.zone = zone

		local character = ctx.player.Character or ctx.player.CharacterAdded:Wait()
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		assert(hrp, "player has no HumanoidRootPart")
		ctx.hrp = hrp
	end,

	run = function(ctx)
		-- Phase 1: teleport HRP far outside every zone. Touched-state
		-- should reset to "not in any zone".
		ctx.hrp.CFrame = CFrame.new(FAR_AWAY)
		ctx.outsideSettled = waitForZoneState(ctx.player, false)
		ctx.outsideResult = RespawnZoneService.isPlayerInZone(ctx.player)

		-- Phase 2: teleport HRP into the zone's center. Touched should
		-- fire + presence should record.
		local zoneCenter = ctx.zone.Position
		ctx.hrp.CFrame = CFrame.new(zoneCenter)
		ctx.insideSettled = waitForZoneState(ctx.player, true)
		ctx.insideResult = RespawnZoneService.isPlayerInZone(ctx.player)
	end,

	verify = function(ctx)
		if not ctx.outsideSettled then
			return false, string.format("isPlayerInZone never went false within %.1fs after teleporting HRP to %s — TouchEnded didn't fire",
				TOUCH_POLL_TIMEOUT, tostring(FAR_AWAY))
		end
		if not ctx.insideSettled then
			return false, string.format("isPlayerInZone never went true within %.1fs after teleporting HRP into %s — Touched didn't fire",
				TOUCH_POLL_TIMEOUT, ctx.zone:GetFullName())
		end
		if ctx.outsideResult ~= false then
			return false, string.format("expected isPlayerInZone=false when HRP at (%s); got %s",
				tostring(FAR_AWAY), tostring(ctx.outsideResult))
		end
		if ctx.insideResult ~= true then
			return false, string.format("expected isPlayerInZone=true when HRP inside %s; got %s",
				ctx.zone:GetFullName(), tostring(ctx.insideResult))
		end
		return true, string.format("outside→%s, inside→%s",
			tostring(ctx.outsideResult), tostring(ctx.insideResult))
	end,

	teardown = function(ctx)
		-- Always restore to a SpawnLocation, never to a captured CFrame —
		-- a captured CFrame may itself have been airborne. The next test
		-- in the suite needs a stable starting position.
		TestHelpers.restoreToSafeSpawn(ctx.player)
	end,
}
