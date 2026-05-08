--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local WeaponStateMachine = require(script.Parent.WeaponStateMachine.WeaponStateMachine)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)

local WeaponController = {}
WeaponController.__index = WeaponController

-- Default weapon state machine states
export type WeaponState = {
	Unequipped: string,
	Idle: string,
	Firing: string,
	Reloading: string,
	Sprinting: string,
	Aiming: string,
	AimingFiring: string,
	AimingReloading: string,
}

local WeaponState = {
	Unequipped = "Unequipped",
	Idle = "Idle",
	Firing = "Firing",
	Reloading = "Reloading",
	Sprinting = "Sprinting",
	Aiming = "Aiming",
	AimingFiring = "AimingFiring",
	AimingReloading = "AimingReloading",
}

WeaponController.WeaponState = WeaponState

function WeaponController.new(
	weapon: Tool,
	config: {
		states: { [string]: string }?,
		initialState: string?,
		autoInitialize: boolean?,
	}
)
	local states = config.states or WeaponState
	local initialState = config.initialState or WeaponState.Unequipped

	local self = {
		weapon = weapon,

		-- Weapon state variables
		activated = false, -- fire button held
		equipped = false,
		shooting = false,
		reloading = false,
		sprinting = false,
		aiming = false,

		-- Ammo system
		ammo = weapon:GetAttribute(Constants.AMMO_ATTRIBUTE) or 0,
		magazineSize = weapon:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE) or 30,

		-- Connections and tasks
		connections = {},
		reloadTask = nil,
		shootTask = nil,

		-- Humanoid reference
		humanoid = nil,
	}
	setmetatable(self, WeaponController)

	-- Create state machine
	self.stateMachine = WeaponStateMachine.new(states, {
		initialState = initialState,
		onEnter = {
			[WeaponState.Idle] = function(controller)
				controller:onEnterIdle()
			end,
			[WeaponState.Firing] = function(controller)
				controller:onEnterFiring()
			end,
			[WeaponState.Reloading] = function(controller)
				controller:onEnterReloading()
			end,
			[WeaponState.Unequipped] = function(controller)
				controller:onEnterUnequipped()
			end,
			[WeaponState.Sprinting] = function(controller)
				controller:onEnterSprinting()
			end,
			[WeaponState.Aiming] = function(controller)
				controller:onEnterAiming()
			end,
			[WeaponState.AimingFiring] = function(controller)
				controller:onEnterAimingFiring()
			end,
			[WeaponState.AimingReloading] = function(controller)
				controller:onEnterAimingReloading()
			end,
		},
		onExit = {
			[WeaponState.Firing] = function(controller)
				controller:onExitFiring()
			end,
			[WeaponState.Reloading] = function(controller)
				controller:onExitReloading()
			end,
			[WeaponState.Sprinting] = function(controller)
				controller:onExitSprinting()
			end,
			[WeaponState.Aiming] = function(controller)
				controller:onExitAiming()
			end,
			[WeaponState.AimingFiring] = function(controller)
				controller:onExitAimingFiring()
			end,
			[WeaponState.AimingReloading] = function(controller)
				controller:onExitAimingReloading()
			end,
		},
		onTransition = function(controller, oldState, newState)
			controller:onTransition(oldState, newState)
		end,
		controller = self,
	})

	if config.autoInitialize then
		self:initialize()
	end

	return self
end

-- ============================================
-- STATE MACHINE CALLBACKS (Override in subclasses)
-- ============================================

function WeaponController:onEnterIdle()
	-- Override in subclass
end

function WeaponController:onEnterFiring()
	-- Override in subclass
end

function WeaponController:onEnterReloading()
	-- Override in subclass
end

function WeaponController:onEnterUnequipped()
	self:cleanup()
end

function WeaponController:onEnterSprinting()
	-- Override in subclass
end

function WeaponController:onEnterAiming()
	-- Override in subclass
end

function WeaponController:onEnterAimingFiring()
	-- Override in subclass
end

function WeaponController:onEnterAimingReloading()
	-- Override in subclass
end

function WeaponController:onExitFiring()
	self.shooting = false
	self.shootTask = nil
end

function WeaponController:onExitReloading()
	if self.reloadTask then
		task.cancel(self.reloadTask)
		self.reloadTask = nil
	end
end

function WeaponController:onExitSprinting()
	-- Override in subclass
end

function WeaponController:onExitAiming()
	-- Override in subclass
end

function WeaponController:onExitAimingFiring()
	self.shooting = false
	self.shootTask = nil
end

function WeaponController:onExitAimingReloading()
	if self.reloadTask then
		task.cancel(self.reloadTask)
		self.reloadTask = nil
	end
end

function WeaponController:onTransition(oldState: string, newState: string)
	-- Override in subclass for custom transition logic
end

-- ============================================
-- STATE MACHINE HELPERS
-- ============================================

function WeaponController:getState(): string
	return self.stateMachine:getCurrentState()
end

function WeaponController:isInState(state: string): boolean
	return self.stateMachine:isInState(state)
end

function WeaponController:transitionTo(state: string): boolean
	return self.stateMachine:transitionTo(state)
end

-- ============================================
-- WEAPON ACTIONS (Override in subclasses)
-- ============================================

function WeaponController:shoot()
	-- Override in subclass
end

function WeaponController:startReload()
	-- Override in subclass
end

-- ============================================
-- WEAPON HELPERS
-- ============================================

function WeaponController:isHumanoidAlive(): boolean
	return self.humanoid and self.humanoid.Health > 0
end

function WeaponController:canShoot(): boolean
	return self:isHumanoidAlive() and self.equipped and self.ammo > 0 and not self.reloading
end

function WeaponController:canReload(): boolean
	local magazineSize = self.weapon:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
	-- Reserve must have rounds to pull from, otherwise the server-side
	-- validateReload will silently reject and the magazine never refills.
	local reserve = self.weapon:GetAttribute(Constants.RESERVE_AMMO_ATTRIBUTE) or 0
	return self:isHumanoidAlive() and self.equipped and self.ammo < magazineSize and reserve > 0 and not self.reloading
end

-- shouldReload is the *auto-trigger* predicate consumed by FirearmController
-- (onEnterIdle + the AUTO post-loop branch). It must mean "the weapon should
-- reload itself without the player asking" — mag fully empty AND there's
-- reserve to pull from. The looser `ammo < magazineSize` check used to live
-- here and produced a phantom reload after every trigger release, since
-- firing one shot already satisfies it.
function WeaponController:shouldReload()
	local reserve = self.weapon:GetAttribute(Constants.RESERVE_AMMO_ATTRIBUTE) or 0
	return self.equipped and self.ammo <= 0 and reserve > 0 and not self.reloading
end

-- ============================================
-- INPUT HANDLERS
-- ============================================

function WeaponController:activate()
	if not self.activated then
		self.activated = true

		if self:isInState(WeaponState.Idle) and self:canShoot() then
			self:transitionTo(WeaponState.Firing)
		elseif self:isInState(WeaponState.Aiming) and self:canShoot() then
			self:transitionTo(WeaponState.AimingFiring)
		end
	end
end

function WeaponController:deactivate()
	if self.activated then
		self.activated = false

		if self:isInState(WeaponState.Firing) then
			self:transitionTo(WeaponState.Idle)
		elseif self:isInState(WeaponState.AimingFiring) then
			self:transitionTo(WeaponState.Aiming)
		end
	end
end

function WeaponController:reload()
	if self:isInState(WeaponState.Idle) or self:isInState(WeaponState.Firing) then
		self:transitionTo(WeaponState.Reloading)
	elseif self:isInState(WeaponState.Aiming) or self:isInState(WeaponState.AimingFiring) then
		self:transitionTo(WeaponState.AimingReloading)
	end
end

function WeaponController:startSprinting()
	if not self.sprinting then
		self.sprinting = true

		if
			self:isInState(WeaponState.Idle)
			or self:isInState(WeaponState.Aiming)
			or self:isInState(WeaponState.Firing)
			or self:isInState(WeaponState.AimingFiring)
		then
			self:transitionTo(WeaponState.Sprinting)
		end
	end
end

function WeaponController:stopSprinting()
	if self.sprinting then
		self.sprinting = false

		if self:isInState(WeaponState.Sprinting) then
			if self.aiming then
				self:transitionTo(WeaponState.Aiming)
			else
				self:transitionTo(WeaponState.Idle)
			end
		end
	end
end

function WeaponController:startAiming()
	if not self.aiming then
		self.aiming = true

		if self:isInState(WeaponState.Idle) then
			self:transitionTo(WeaponState.Aiming)
		elseif self:isInState(WeaponState.Firing) then
			self:transitionTo(WeaponState.AimingFiring)
		elseif self:isInState(WeaponState.Reloading) then
			self:transitionTo(WeaponState.AimingReloading)
		end
	end
end

function WeaponController:stopAiming()
	if self.aiming then
		self.aiming = false

		if self:isInState(WeaponState.Aiming) then
			self:transitionTo(WeaponState.Idle)
		elseif self:isInState(WeaponState.AimingFiring) then
			self:transitionTo(WeaponState.Firing)
		elseif self:isInState(WeaponState.AimingReloading) then
			self:transitionTo(WeaponState.Reloading)
		end
	end
end

-- ============================================
-- EQUIP/UNEQUIP
-- ============================================

function WeaponController:equip()
	if not self.equipped then
		self.equipped = true

		-- Resync ammo and reloading values
		self.ammo = self.weapon:GetAttribute(Constants.AMMO_ATTRIBUTE) or 0
		self.reloading = self.weapon:GetAttribute(Constants.RELOADING_ATTRIBUTE) or false
		self.magazineSize = self.weapon:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE) or 30

		-- Keep track of the humanoid
		self.humanoid = self.weapon.Parent:FindFirstChildOfClass("Humanoid")

		-- Transition to Idle state
		self:transitionTo(WeaponState.Idle)
	end
end

function WeaponController:unequip()
	if self.equipped then
		self.equipped = false

		-- Force deactivate when unequipping
		self.activated = false
		self.sprinting = false
		self.aiming = false

		-- Transition to Unequipped state (this will handle cleanup)
		self:transitionTo(WeaponState.Unequipped)
	end
end

-- ============================================
-- CLEANUP
-- ============================================

function WeaponController:cleanup()
	-- Cancel any running tasks
	if self.reloadTask then
		task.cancel(self.reloadTask)
		self.reloadTask = nil
	end

	self.shootTask = nil
	self.shooting = false
	self.reloading = false
	self.activated = false
	self.sprinting = false
	self.aiming = false
end

function WeaponController:disable()
	self:unequip()
	self:cleanup()
end

-- ============================================
-- INITIALIZATION
-- ============================================

function WeaponController:initialize()
	table.insert(
		self.connections,
		self.weapon.Equipped:Connect(function()
			self:equip()
		end)
	)
	table.insert(
		self.connections,
		self.weapon.Unequipped:Connect(function()
			self:unequip()
		end)
	)
	table.insert(
		self.connections,
		self.weapon.Activated:Connect(function()
			self:activate()
		end)
	)
	table.insert(
		self.connections,
		self.weapon.Deactivated:Connect(function()
			self:deactivate()
		end)
	)
end

function WeaponController:destroy()
	self:disable()
	disconnectAndClear(self.connections)
end

return WeaponController
