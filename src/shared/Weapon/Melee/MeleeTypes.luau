----------------------------------------------------------------------
-- MeleeTypes
----------------------------------------------------------------------
-- Shared type definitions for the melee weapon pipeline.
----------------------------------------------------------------------

local MeleeTypes = {}

export type HitMode = "Single" | "Cleave"

export type SwingPhase = "Unequipped" | "Idle" | "Windup" | "Active" | "Recovery"

-- Per-weapon configuration, typically applied via Tool attributes or
-- declared in a weapon archetype module.
export type MeleeArchetype = {
	name: string,
	damage: number,
	reach: number, -- studs in front of handle
	hitboxWidth: number, -- studs left/right of the swing axis
	hitboxHeight: number, -- studs up/down
	windupSeconds: number,
	activeSeconds: number,
	recoverySeconds: number,
	cooldownSeconds: number, -- minimum gap between swings (measured from Active start)
	hitMode: HitMode,
	animationId: string?, -- optional swing animation
}

-- Payload the client sends to the server to request a swing validation.
-- Minimal — the server re-derives the hitbox from the weapon's state.
export type SwingRequest = {
	weapon: Tool,
	clientTime: number, -- os.clock() when the client entered Active
}

-- Result of a single hit detection sweep on the server.
export type HitResult = {
	humanoid: Humanoid,
	rootPart: BasePart,
	distance: number,
}

return MeleeTypes
