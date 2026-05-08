local HealthConstants = {
	DEFAULT_MAX_HEALTH = 100,
	RESPAWN_TIME = 5,

	HEADSHOT_MULTIPLIER = 2.0,
	TORSO_MULTIPLIER = 1.0,
	LIMB_MULTIPLIER = 0.75,

	INVINCIBILITY_DURATION = 0.1,

	ARMOR_ATTRIBUTE = "_armor",
	SHIELD_ATTRIBUTE = "_shield",

	HEAD_PARTS = { "Head" },
	TORSO_PARTS = { "UpperTorso", "LowerTorso" },

	DAMAGEABLE_TAG = "Damageable",
	MAX_HEALTH_ATTRIBUTE = "maxHealth",
	RESPAWN_TIME_ATTRIBUTE = "respawnTime",

	----------------------------------------------------------------------
	-- Health Bar Layout
	----------------------------------------------------------------------
	-- Controls where the player health bar appears on screen.
	-- Change this value to reposition the HUD element.
	--
	-- Available presets:
	--   "BottomLeft"    — left side, above hotbar (Fortnite/PUBG style)
	--   "BottomCenter"  — centered, above weapon GUI
	--   "TopCenter"     — thin bar across the top of the screen
	--   "Integrated"    — stacked above the weapon panel (bottom-right)
	----------------------------------------------------------------------
	HEALTH_BAR_LAYOUT = "BottomLeft",
}

return HealthConstants
