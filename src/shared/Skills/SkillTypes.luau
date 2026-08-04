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
	kind: string,       -- "damage" | "heal" | "freeze" | "knockup" | "shield" | "buff"
	[string]: any,      -- free-form params per kind
}

-- Which of the two runs of a cast this is.
--
-- The caster's client runs the whole pipeline and then the server runs it
-- again (see wiki/design/client-server-boundary.md). Both runs reach the
-- same handlers, so a handler that needs to know which one it is has had
-- to re-derive it from RunService:IsServer(), or from "is the source a
-- player character". This field says it outright, set once at the entry
-- point instead of inferred at each branch.
--
--   "authoritative" — the run whose results are real. Owns hit detection,
--                     damage, and every status write. Server today.
--   "predicted"     — the caster's local run, for immediate feedback.
--                     May only write things that client already owns.
--
-- Stage 1 of the migration only *carries* this; nothing reads it yet and
-- every existing IsServer() guard is untouched.
export type DeliveryMode = "authoritative" | "predicted"

-- Which of the two runs of a cast this is, and who — if anyone — already
-- ran it as a prediction.
--
-- `predictedBy` is only meaningful on an authoritative run: it is the
-- UserId of the client whose predicted run already drew this cast's
-- cosmetics on the frame it fired, so the broadcast has to skip them or
-- they see two of everything. It is nil when nothing predicted this cast
-- — boss fire, NPC fire, anything the server originates. A predicted run
-- never carries one, because it *is* the prediction.
--
-- This is a fact, not an inference. The authoritative run learns it from
-- the remote it was woken by (SpellCastService knows which player fired,
-- and SpellMenuGui only relays a cast its predicted run already accepted),
-- rather than guessing from "is the source a player character".
export type RunContext = {
	mode: DeliveryMode,
	predictedBy: number?,
}

export type DeliveryCtx = {
	origin: CFrame,         -- where the delivery starts from
	target: any?,           -- Humanoid | Model | BasePart | Vector3 | nil
	aoeCenter: Vector3?,    -- override for AoE center; defaults to origin.Position
	source: Instance?,      -- the caster (Humanoid parent Model or Boss Model)
	mode: DeliveryMode,     -- authoritative run, or the caster's predicted one
	predictedBy: number?,   -- UserId that already drew this locally; see RunContext
	onComplete: (() -> ())?, -- called when the delivery fully resolves (async attacks)
}

export type DeliveryKind = "instant" | "projectile" | "aoe" | "world_spawn"

export type SkillSpec = {
	name: string,                       -- "FireballVolley", "GroundSlam", "Firebolt", …
	delivery: DeliveryKind,
	deliveryParams: { [string]: any },  -- handler-specific params
	onImpact: { EffectSpec },           -- effects applied on landing
	minRange: number?,                  -- if set, skill is only selected when distanceToNearest <= minRange
	windupVfx: string?,                 -- telegraph shown during AttackPrep: "aoe_indicator" | "charge_glow"
	windupAnimId: string?,              -- animation asset ID played on the boss during AttackPrep
	vfxName: string?,                   -- future hook; ignored until VfxController ships
	sfxName: string?,                   -- future hook; ignored until SFX module ships
}

return {}  -- types-only module
