-- WeaponStateMachine Module
-- A generic state machine for managing weapon states

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("WeaponStateMachine")

local WeaponStateMachine = {}
WeaponStateMachine.__index = WeaponStateMachine

-- State enum (will be defined by the weapon controller)
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

function WeaponStateMachine.new(
	states: { [string]: string },
	config: {
		initialState: string,
		onEnter: { [string]: (any) -> () }?,
		onExit: { [string]: (any) -> () }?,
		onTransition: ((any, string, string) -> ())?,
		controller: any?,
	}
): any
	local self = {
		states = states,
		currentState = config.initialState,
		onEnter = config.onEnter or {},
		onExit = config.onExit or {},
		onTransition = config.onTransition or nil,
		controller = config.controller,
	}
	setmetatable(self, WeaponStateMachine)
	return self
end

function WeaponStateMachine:transitionTo(newState: string): boolean
	if self.currentState == newState then
		return false
	end

	local oldState = self.currentState

	-- Log exit
	log:info(` Exit: {oldState} -> Enter: {newState}`)

	-- Call onExit for the current state
	if self.onExit[oldState] then
		log:info(`   onExit({oldState})`)
		self.onExit[oldState](self.controller)
	end

	-- Call onTransition callback if provided
	if self.onTransition then
		self.onTransition(self.controller, oldState, newState)
	end

	-- Update state
	self.currentState = newState

	-- Call onEnter for the new state
	if self.onEnter[newState] then
		log:info(`   onEnter({newState})`)
		self.onEnter[newState](self.controller)
	end

	return true
end

function WeaponStateMachine:getCurrentState(): string
	return self.currentState
end

function WeaponStateMachine:isInState(state: string): boolean
	return self.currentState == state
end

return WeaponStateMachine
