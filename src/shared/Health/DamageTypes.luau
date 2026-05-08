local DamageTypes = {}

DamageTypes.DamageType = {
	Bullet = "Bullet",
	Explosion = "Explosion",
	Melee = "Melee",
	Fall = "Fall",
	Environmental = "Environmental",
	DOT = "DOT",
}

DamageTypes.HitZone = {
	Head = "Head",
	Torso = "Torso",
	Limb = "Limb",
}

export type DamageRequest = {
	sourcePlayer: Player?,
	targetHumanoid: Humanoid,
	baseDamage: number,
	damageType: string,
	hitZone: string?,
	sourceWeapon: Tool?,
	timestamp: number,
	metadata: { [string]: any }?,
}

export type DamageResult = {
	finalDamage: number,
	absorbed: number,
	wasLethal: boolean,
	hitZone: string?,
	modifiersApplied: { string },
}

return DamageTypes
