--[[
	NPCTypes
	--------
	Type definitions shared across the NPC system.

	The Blackboard is the contract between Perception, Decision (state machine
	or future BT), and Action layers. Lock this schema early — both phases of
	the decision layer must read/write the same fields.
]]

-- ============================================================
-- Action result enum (string union)
-- ============================================================
export type ActionResult = "Running" | "Success" | "Failure"

-- ============================================================
-- Blackboard
-- ============================================================
-- Per-NPC state shared between Perception, Decision, and Action layers.
-- Anything one layer needs to communicate to another goes here.
export type Blackboard = {
	-- Identity / refs
	npc: Model,
	humanoid: Humanoid,
	humanoidRootPart: BasePart,
	weapon: Tool?, -- equipped weapon Tool, if any (for visual muzzle position)

	-- Perception output (written by Perception layer)
	nearestPlayer: Player?,
	distanceToNearest: number,
	canSeeTarget: boolean,
	targetHumanoid: Humanoid?, -- cached humanoid of nearestPlayer's character
	targetRootPart: BasePart?, -- cached HRP of nearestPlayer's character (for raycasting)

	-- Decision output (written by Decision layer, read by Action layer)
	currentState: string,
	targetPos: Vector3?,

	-- Action state (written by Action layer)
	currentPath: { Vector3 }?,
	currentWaypointIndex: number,
	moveStartTime: number,
	lastShotTime: number, -- os.clock() of last shot fired, for rate-of-fire throttling

	-- Animation tracks (loaded on spawn, reused across states)
	animations: { [string]: AnimationTrack }, -- keyed by name: "walk", "idle", "shoot"
}

-- ============================================================
-- State definition
-- ============================================================
-- A state is a pair of pure functions over the blackboard.
-- onEnter runs once on transition into this state.
-- update runs every tick — may set bb.targetPos and queue actions.
export type StateDefinition = {
	name: string,
	onEnter: ((bb: Blackboard) -> ())?,
	onExit: ((bb: Blackboard) -> ())?,
	update: (bb: Blackboard) -> (),
}

-- ============================================================
-- Transition rule
-- ============================================================
-- Transitions are evaluated each tick after the current state's update.
-- The first rule whose condition returns true wins.
export type TransitionRule = {
	to: string,
	condition: (bb: Blackboard) -> boolean,
}

-- ============================================================
-- Archetype
-- ============================================================
-- An archetype is a complete NPC configuration: rig, stats, behavior.
-- Reusable across multiple NPC instances of the same type.
export type AnimationSet = {
	walk: string?,
	idle: string?,
	shoot: string?,
	aim: string?, -- held pose during Combat (arms raised with weapon)
}

export type Archetype = {
	name: string,
	templateName: string, -- key into ServerStorage.AIWorldData.Rigs
	walkSpeed: number,
	initialState: string,
	weaponTemplateName: string?, -- key into ReplicatedStorage.Shared.Weapon.Templates
	animations: AnimationSet?, -- rbxassetid:// strings for walk/idle/shoot
	states: { [string]: StateDefinition },
	transitions: { [string]: { TransitionRule } }, -- keyed by state name
}

return nil
