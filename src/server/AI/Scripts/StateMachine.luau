--[[
	StateMachine
	------------
	Generic finite state machine for NPC decision logic.
	Each tick:
	  1. Run the current state's update fn (mutates blackboard, may queue actions)
	  2. Evaluate transition rules in order; first matching rule wins
	  3. If transitioning, run onExit (old state) then onEnter (new state)

	Designed so the entire module can be swapped for a BehaviorTree
	without touching Perception or Action layers — both expose
	the same `:tick(bb)` interface and read/write the same blackboard.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)

type Blackboard = NPCTypes.Blackboard
type StateDefinition = NPCTypes.StateDefinition
type TransitionRule = NPCTypes.TransitionRule

local log = Logger.new("StateMachine")

local StateMachine = {}
StateMachine.__index = StateMachine

export type StateMachineInstance = {
	tick: (self: StateMachineInstance, bb: Blackboard) -> (),
	getState: (self: StateMachineInstance) -> string,
	_states: { [string]: StateDefinition },
	_transitions: { [string]: { TransitionRule } },
	_currentStateName: string,
}

function StateMachine.new(
	states: { [string]: StateDefinition },
	transitions: { [string]: { TransitionRule } },
	initialState: string
): StateMachineInstance
	if not states[initialState] then
		log:warn("Initial state not found in states table:", initialState)
	end

	local self = setmetatable({
		_states = states,
		_transitions = transitions,
		_currentStateName = initialState,
	}, StateMachine)

	return (self :: any) :: StateMachineInstance
end

function StateMachine:tick(bb: Blackboard)
	local currentState = self._states[self._currentStateName]
	if not currentState then
		return
	end

	-- Mirror current state into blackboard for inspection / logging
	bb.currentState = self._currentStateName

	-- Run the state's update fn
	currentState.update(bb)

	-- Evaluate transitions for the current state
	local rules = self._transitions[self._currentStateName]
	if not rules then
		return
	end

	for _, rule in rules do
		if rule.condition(bb) then
			self:_transition(rule.to, bb)
			return
		end
	end
end

function StateMachine:_transition(toName: string, bb: Blackboard)
	local fromName = self._currentStateName
	local fromState = self._states[fromName]
	local toState = self._states[toName]

	if not toState then
		log:warn("Cannot transition to unknown state:", toName)
		return
	end

	log:info(string.format("%s: %s -> %s",
		bb.npc and bb.npc.Name or "?",
		fromName,
		toName
	))

	if fromState and fromState.onExit then
		fromState.onExit(bb)
	end

	self._currentStateName = toName
	bb.currentState = toName

	-- Expose current state as an attribute on the NPC model so tests and
	-- external systems can query it without access to the blackboard.
	if bb.npc then
		bb.npc:SetAttribute("CurrentState", toName)
	end

	if toState.onEnter then
		toState.onEnter(bb)
	end
end

function StateMachine:getState(): string
	return self._currentStateName
end

return StateMachine
