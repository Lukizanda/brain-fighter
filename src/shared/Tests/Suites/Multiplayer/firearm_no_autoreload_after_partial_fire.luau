----------------------------------------------------------------------
-- Test: state machine — firing one shot then releasing trigger
-- must NOT auto-transition into Reloading.
----------------------------------------------------------------------
-- This is the integration version of `should_reload_only_when_empty_with_reserve`:
-- exercises the full state-machine flow with a controller subclass that
-- mirrors FirearmController:onEnterIdle's "auto-reload-if-shouldReload"
-- branch — the call site that exhibits the user-reported bug.
--
-- Walk:
--   1. Construct a Tool with attributes (mag=10, reserve=30, alive humanoid).
--   2. Equip — state becomes Idle (onEnterIdle runs, ammo is full,
--      shouldReload should be false, stays in Idle).
--   3. Activate — state becomes Firing.
--   4. Decrement ammo (simulating one shot fired).
--   5. Deactivate — onExitFiring runs, then transitionTo(Idle), which
--      runs onEnterIdle. Pre-fix: shouldReload returned true (ammo<mag),
--      so the state machine transitioned into Reloading and the player
--      saw a phantom reload after every trigger release. Post-fix:
--      shouldReload returns false (ammo>0), state stays Idle.
--
-- The TestFirearmController subclass mirrors FirearmController's
-- onEnterIdle exactly so the test exercises the actual buggy branch.
-- We deliberately do NOT subclass through FirearmController itself
-- because that module reaches into LocalPlayer / Workspace.CurrentCamera
-- on require, which doesn't exist server-side.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponController = require(ReplicatedStorage.Shared.Weapon.Scripts.WeaponController)
local WeaponConstants = require(ReplicatedStorage.Shared.Weapon.Constants)

local WS = WeaponController.WeaponState

----------------------------------------------------------------------
-- TestFirearmController — minimal subclass that mirrors the
-- FirearmController:onEnterIdle branch we want to exercise.
----------------------------------------------------------------------
local TestFirearmController = setmetatable({}, WeaponController)
TestFirearmController.__index = TestFirearmController

function TestFirearmController.new(weapon: Tool)
	local self = WeaponController.new(weapon, { autoInitialize = false })
	setmetatable(self, TestFirearmController)
	return self
end

function TestFirearmController:onEnterIdle()
	-- Mirrors FirearmController:onEnterIdle's auto-reload branch.
	-- Camera + cameraController calls are stripped (test doesn't need them).
	if self.activated and self:canShoot() then
		self:transitionTo(WS.Firing)
	elseif self:shouldReload() then
		self:transitionTo(WS.Reloading)
	end
end

-- Stub out reload-side effects: the base startReload is a no-op stub,
-- and we don't want to fire the reload remote during tests. The state
-- transition into Reloading is the signal we want to detect.
function TestFirearmController:onEnterReloading()
	self.reloading = true
end

----------------------------------------------------------------------
-- Test scaffolding — build a Model{Humanoid, Tool} so equip() can
-- discover the humanoid via FindFirstChildOfClass.
----------------------------------------------------------------------
local function makeArmedCharacter(magazineSize: number, ammo: number, reserve: number)
	local model = Instance.new("Model")
	model.Name = "TestRig_FirearmAutoreload"

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Parent = model

	local tool = Instance.new("Tool")
	tool.Name = "TestPistol"
	tool:SetAttribute(WeaponConstants.MAGAZINE_SIZE_ATTRIBUTE, magazineSize)
	tool:SetAttribute(WeaponConstants.AMMO_ATTRIBUTE, ammo)
	tool:SetAttribute(WeaponConstants.RESERVE_AMMO_ATTRIBUTE, reserve)
	tool:SetAttribute(WeaponConstants.RELOADING_ATTRIBUTE, false)
	tool.Parent = model

	model.Parent = workspace
	return model, tool
end

return {
	name = "Firearm state machine — fire->stop must not auto-transition into Reloading",

	run = function(ctx)
		ctx.results = {}

		----------------------------------------------------------------
		-- Walk 1: fire ONE shot then release. Pre-fix the state
		-- machine ends in Reloading; post-fix it ends in Idle.
		----------------------------------------------------------------
		do
			local model, tool = makeArmedCharacter(10, 10, 30)
			local controller = TestFirearmController.new(tool)

			controller:equip()
			ctx.results.afterEquipState = controller:getState()

			controller:activate()
			ctx.results.afterActivateState = controller:getState()

			-- Simulate a single shot
			controller.ammo -= 1

			controller:deactivate()
			ctx.results.afterDeactivateState = controller:getState()
			ctx.results.afterDeactivateAmmo = controller.ammo

			model:Destroy()
		end

		----------------------------------------------------------------
		-- Walk 2: empty the mag, then trigger release should auto-reload.
		-- This is the *desired* auto-reload case. After the fix the
		-- state machine should transition Idle -> Reloading because
		-- shouldReload is true (ammo == 0, reserve > 0).
		----------------------------------------------------------------
		do
			local model, tool = makeArmedCharacter(10, 10, 30)
			local controller = TestFirearmController.new(tool)

			controller:equip()
			controller:activate()
			-- Drain the mag
			controller.ammo = 0
			controller:deactivate()
			ctx.results.emptyMag_afterDeactivateState = controller:getState()

			model:Destroy()
		end

		----------------------------------------------------------------
		-- Walk 3: empty mag AND empty reserve, deactivate. The state
		-- machine MUST NOT transition into Reloading — there's nothing
		-- to pull from, the server would reject the reload, and the
		-- player would be locked out of shooting for the reload-time
		-- duration for nothing.
		----------------------------------------------------------------
		do
			local model, tool = makeArmedCharacter(10, 10, 0)
			local controller = TestFirearmController.new(tool)

			controller:equip()
			controller:activate()
			controller.ammo = 0
			controller:deactivate()
			ctx.results.noReserve_afterDeactivateState = controller:getState()

			model:Destroy()
		end
	end,

	verify = function(ctx)
		local r = ctx.results
		local issues = {}

		-- Walk 1
		if r.afterEquipState ~= WS.Idle then
			table.insert(issues, string.format(
				"after equip: expected state %s, got %s", WS.Idle, tostring(r.afterEquipState)))
		end
		if r.afterActivateState ~= WS.Firing then
			table.insert(issues, string.format(
				"after activate: expected state %s, got %s", WS.Firing, tostring(r.afterActivateState)))
		end
		if r.afterDeactivateState ~= WS.Idle then
			table.insert(issues, string.format(
				"after firing 1 shot then deactivating: expected state %s (no auto-reload), got %s. This is the user-reported bug — releasing the trigger triggers a phantom reload because shouldReload returns true on `ammo < magazineSize`.",
				WS.Idle, tostring(r.afterDeactivateState)))
		end
		if r.afterDeactivateAmmo ~= 9 then
			table.insert(issues, string.format(
				"after firing 1 shot: expected ammo 9, got %s (test scaffolding bug, not production code)",
				tostring(r.afterDeactivateAmmo)))
		end

		-- Walk 2
		if r.emptyMag_afterDeactivateState ~= WS.Reloading then
			table.insert(issues, string.format(
				"empty-mag deactivate: expected state %s (auto-reload kicks in), got %s. shouldReload must still trigger when ammo == 0 and reserve > 0.",
				WS.Reloading, tostring(r.emptyMag_afterDeactivateState)))
		end

		-- Walk 3
		if r.noReserve_afterDeactivateState ~= WS.Idle then
			table.insert(issues, string.format(
				"empty-mag empty-reserve deactivate: expected state %s (no reload — server would reject), got %s. shouldReload must require reserve > 0.",
				WS.Idle, tostring(r.noReserve_afterDeactivateState)))
		end

		if #issues > 0 then
			return false, table.concat(issues, " | ")
		end
		return true, "fire->stop stays Idle; empty-mag auto-reloads only when reserve has rounds"
	end,
}
