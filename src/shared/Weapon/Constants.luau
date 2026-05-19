local Constants = {
	RAY_EXCLUDE_TAG = "RayExclude",
	NON_STATIC_TAG = "NonStatic",
	-- Rate of fire is stored as rounds per minute; divide by this to get seconds between shots
	SECONDS_PER_MINUTE = 60,

	-- Loadout / category attributes (see docs/loadout-system-plan.md).
	-- CATEGORY_ATTRIBUTE: "Normal" for any Primary/Secondary weapon, "Special"
	-- for team-unique ability slots.
	-- SPECIAL_ID_ATTRIBUTE: only set when Category == Special; identifies which
	-- ability this is (e.g. "Shield", "Beam", "SwarmMissiles") for the team
	-- uniqueness check in LoadoutService.
	-- ICON_ATTRIBUTE: optional rbxthumb://type=Asset&id=... URL; falls back to
	-- tool name text in the Rolodex.
	CATEGORY_ATTRIBUTE = "WeaponCategory",
	SPECIAL_ID_ATTRIBUTE = "SpecialId",
	ICON_ATTRIBUTE = "WeaponIcon",
	-- Set on a Special Tool by its server runtime when the ability goes on
	-- cooldown. Value is a workspace:GetServerTimeNow() timestamp — the
	-- moment the ability becomes usable again. 0 / nil means ready. The
	-- Rolodex watches this to drive the Special card's cooldown overlay.
	COOLDOWN_END_ATTRIBUTE = "_cooldownEnd",
	Category = {
		Normal = "Normal",
		Special = "Special",
	},

	FIRE_MODE = {
		SEMI = "Semi",
		AUTO = "Auto",
	},
	AMMO_ATTRIBUTE = "_ammo",
	RELOADING_ATTRIBUTE = "_reloading",
	RESERVE_AMMO_ATTRIBUTE = "_reserveAmmo", -- spare rounds beyond current magazine
	STARTING_RESERVE_AMMO_ATTRIBUTE = "startingReserveAmmo", -- seed value on spawn
	PICKUP_AMMO_BONUS_ATTRIBUTE = "pickupAmmoBonus", -- reserve added on same-type pickup
	MAX_RESERVE_AMMO_ATTRIBUTE = "maxReserveAmmo", -- cap on _reserveAmmo
	DAMAGE_ATTRIBUTE = "damage",
	FIRE_MODE_ATTRIBUTE = "fireMode",
	MAGAZINE_SIZE_ATTRIBUTE = "magazineSize",
	RANGE_ATTRIBUTE = "range",
	RATE_OF_FIRE_ATTRIBUTE = "rateOfFire",
	RELOAD_TIME_ATTRIBUTE = "reloadTime",
	RAYS_PER_SHOT_ATTRIBUTE = "raysPerShot",
	RAY_RADIUS_ATTRIBUTE = "rayRadius",
	SPREAD_ATTRIBUTE = "spread",
	VIEW_MODEL_ATTRIBUTE = "viewModel",
	RECOIL_MIN_ATTRIBUTE = "recoilMin",
	RECOIL_MAX_ATTRIBUTE = "recoilMax",
	UNANCHORED_IMPULSE_FORCE_ATTRIBUTE = "unanchoredImpulseForce",
	AIM_ASSIST_RANGE_ATTRIBUTE = "aimAssistRange",
	AIM_ASSIST_FOV_ATTRIBUTE = "aimAssistFov",
	AIM_ASSIST_FRICTION_STRENGTH_ATTRIBUTE = "aimAssistFrictionStrength",
	AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE = "aimAssistTrackingStrength",
	AIM_ASSIST_CENTERING_STRENGTH_ATTRIBUTE = "aimAssistCenteringStrength",

	KEYBOARD_RELOAD_KEY_CODE = Enum.KeyCode.R,
	GAMEPAD_RELOAD_KEY_CODE = Enum.KeyCode.ButtonX,

	-- UI scaling lives in src/shared/Hud/HudConstants.luau (REFERENCE_HEIGHT, MIN_SCALE)

	HITMARKER_SOUND_DELAY = 0.1,

	-- Aim assist
	AIM_ASSIST_BIND_NAME_START = "AimAssistStart",
	AIM_ASSIST_BIND_NAME_APPLY = "AimAssistApply",
	AIM_ASSIST_TARGET_TAG = "Target",

	AIM_ASSIST_DEADZONE = 0.1,
	AIM_ASSIST_INACTIVITY = 0.1,
	AIM_ASSIST_MIN_RANGE = 10,

	-- View model
	VIEW_MODEL_BIND_NAME = "WeaponViewModel",
	VIEW_MODEL_OFFSET = CFrame.new(0.9, -1.3, -1.3),
	VIEW_MODEL_BOBBING_SPEED = 0.4,
	VIEW_MODEL_BOBBING_AMOUNT = 0.05,
	VIEW_MODEL_BOBBING_TRANSITION_SPEED = 10,
	VIEW_MODEL_RELOAD_FADE_TIME = 0.1,
	-- Recoil
	RECOIL_BIND_NAME = "Recoiler",
	RECOIL_STOP_SPEED = 10,
	RECOIL_ZOOM_RETURN_SPEED = 20,
	RECOIL_DEFAULT_FOV = 70,
	-- VFX
	LASER_BEAM_VISUAL_SPEED = 200,
	-- IK
	IK_TARGET_DISTANCE = 20,
	IK_AIM_OFFSET = 1,
	IK_PASSIVE_WEIGHT = 0.3, -- subtle aim tracking when not firing
	IK_ACTIVE_WEIGHT = 1, -- full aim lock when firing
}

return Constants
