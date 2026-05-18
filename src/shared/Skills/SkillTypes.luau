--!strict

----------------------------------------------------------------------
-- SkillTypes
----------------------------------------------------------------------
-- Pure data types for the unified skill pipeline.
-- No behavior, no context-specific fields. Used by SpellRegistry,
-- BossConfig, SkillEffects, SkillDelivery, SpellExecutor,
-- and BossStates.
----------------------------------------------------------------------

export type EffectSpec = {
	kind: string,       -- "damage" | "heal" | "freeze" | "knockup" | "shield" | "wall" | ...
	[string]: any,      -- free-form params per kind
}

export type DeliveryCtx = {
	origin: CFrame,         -- where the delivery starts from
	target: any?,           -- Humanoid | Model | BasePart | Vector3 | nil
	aoeCenter: Vector3?,    -- override for AoE center; defaults to origin.Position
	source: Instance?,      -- the caster (Humanoid parent Model or Boss Model)
	onComplete: (() -> ())?, -- called when the delivery fully resolves (async attacks)
}

export type SkillSpec = {
	name: string,                       -- "FireballVolley", "GroundSlam", "Spark", …
	delivery: string,                   -- "instant" | "projectile" | "aoe" | "world_spawn"
	deliveryParams: { [string]: any },  -- handler-specific params
	onImpact: { EffectSpec },           -- effects applied on landing
	minRange: number?,                  -- if set, skill is only selected when distanceToNearest <= minRange
	windupVfx: string?,                 -- telegraph shown during AttackPrep: "aoe_indicator" | "charge_glow"
	windupAnimId: string?,              -- animation asset ID played on the boss during AttackPrep
	vfxName: string?,                   -- future hook; ignored until VfxController ships
	sfxName: string?,                   -- future hook; ignored until SFX module ships
}

return {}  -- types-only module
