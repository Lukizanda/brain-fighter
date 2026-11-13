--!strict

----------------------------------------------------------------------
-- protect_on_entry — arriving on the island opens a protection window
----------------------------------------------------------------------
-- A real teleport through `ArenaEntryService.handleTouch` is announced, and
-- Health's listener (HealthService) opens a window of
-- `ARRIVAL_PROTECTION_SEC` on the arriving character. Then a real hit on
-- that character through `applyDamage.process` is dropped.
--
-- NOT covered: the client cue (the bubble drawn off `_protectedUntil`) needs
-- a client view; see vfx-sfx.md.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaEntryConstants = require(ReplicatedStorage.Shared.Arena.ArenaEntryConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Protection = require(ReplicatedStorage.Shared.Health.Protection)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local arenaEntryFixture = require(ReplicatedStorage.Shared.Tests.Helpers.arenaEntryFixture)

local PAD_HEIGHT = 600
local ARRIVAL_HEIGHT = 700
local HIT = 5
-- Slack for the event delivery and the server clock between grant and read.
local WINDOW_TOLERANCE_SEC = 0.5

return {
	name = "protect_on_entry",

	setup = function(ctx: any)
		ctx.fx = arenaEntryFixture.new()
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		local character = player and player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player or not character or not hrp or not hrp:IsA("BasePart") or not humanoid then
			return
		end
		local fx = ctx.fx
		ctx.entered = fx:enter(player)
		ArenaEntryService.resetState()

		-- Not protected before the teleport.
		ctx.activeBefore = Protection.isActive(character)

		local pad = fx:part(ArenaEntryConstants.PAD_TAG, fx.arenaId, CFrame.new(0, PAD_HEIGHT, 0))
		fx:part(ArenaEntryConstants.ARRIVAL_TAG, fx.arenaId, CFrame.new(0, ARRIVAL_HEIGHT, 0))

		ctx.touch = ArenaEntryService.handleTouch(pad, hrp)
		task.wait()
		task.wait()

		ctx.activeAfter = Protection.isActive(character)
		local closesAt = Protection.closesAt(character)
		ctx.remaining = if closesAt then closesAt - workspace:GetServerTimeNow() else nil

		ctx.healthBefore = humanoid.Health
		ctx.result = applyDamage.process({
			sourcePlayer = nil,
			targetHumanoid = humanoid,
			baseDamage = HIT,
			damageType = DamageTypes.DamageType.Spell,
			hitZone = DamageTypes.HitZone.Torso,
			timestamp = os.clock(),
			cause = "FireballVolley",
		})
		ctx.healthAfter = humanoid.Health
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.entered then
			return false, "no player on the server, or the transfer failed"
		end
		if ctx.activeBefore then
			return false, "the player was already protected before the teleport"
		end
		if ctx.touch ~= ArenaEntryConstants.Result.Teleported then
			return false, "the touch returned " .. tostring(ctx.touch)
		end
		if not ctx.activeAfter then
			return false, "no protection window after a teleport (is HealthService listening to PlayerEntered?)"
		end
		local expected = HealthConstants.ARRIVAL_PROTECTION_SEC
		if ctx.remaining == nil or ctx.remaining > expected or ctx.remaining < expected - WINDOW_TOLERANCE_SEC then
			return false, string.format("%s s left in the window, expected about %d", tostring(ctx.remaining), expected)
		end
		if ctx.result ~= nil or ctx.healthAfter ~= ctx.healthBefore then
			return false, string.format("a hit on the arrived player was not dropped (health %s -> %s)",
				tostring(ctx.healthBefore), tostring(ctx.healthAfter))
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.fx then
			-- Also clears the protection attribute off the harness character.
			ctx.fx:cleanup(ctx.player)
		end
		ArenaEntryService.resetState()
	end,
}
