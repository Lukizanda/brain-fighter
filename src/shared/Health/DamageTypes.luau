local DamageTypes = {}

DamageTypes.DamageType = {
	Bullet = "Bullet",
	Explosion = "Explosion",
	Melee = "Melee",
	Fall = "Fall",
	Environmental = "Environmental",
	DOT = "DOT",
	Spell = "Spell",
}

DamageTypes.HitZone = {
	Head = "Head",
	Torso = "Torso",
	Limb = "Limb",
}

-- Cause ids for callers that have no skill. A skill's cause is its
-- `SkillSpec.name` ("Firebolt", "GroundSlam"), passed through by
-- SkillDelivery. The kill feed prints the cause verbatim.
DamageTypes.Cause = {
	DeathZone = "death_zone",
	Unknown = "Unknown",
}

export type DamageRequest = {
	sourcePlayer: Player?,
	targetHumanoid: Humanoid,
	baseDamage: number,
	damageType: string,
	hitZone: string?,
	sourceWeapon: Tool?,
	timestamp: number,
	-- What dealt the damage: a skill name, a `Cause` id, or a weapon
	-- name. Carried onto `DamageResult` so the kill feed can credit it
	-- without inspecting the attacker's equipped Tool.
	cause: string?,
	metadata: { [string]: any }?,
}

export type DamageResult = {
	finalDamage: number,
	absorbed: number,
	wasLethal: boolean,
	hitZone: string?,
	modifiersApplied: { string },
	cause: string?,
}

export type HealRequest = {
	sourcePlayer: Player?,
	targetHumanoid: Humanoid,
	amount: number,
	cause: string?,
}

export type HealResult = {
	healed: number,
	cause: string?,
}

-- The one object allowed to write `Humanoid.Health` outside spawn-init.
-- `applyDamage` implements it on the server and hands it to
-- `SkillEffects.setDamageSink`. There is no client implementation, which
-- is the point: a predicted run has nowhere to put damage.
export type DamageSink = {
	process: (DamageRequest) -> DamageResult?,
	heal: (HealRequest) -> HealResult?,
}

return DamageTypes
