--!strict

----------------------------------------------------------------------
-- ArenaEntryConstants
----------------------------------------------------------------------
-- Vocabulary and tuning of the one-way arena entry teleporter. See
-- wiki/design/boss-arena.md § Entry: teleporter, no bridge — the two tag
-- names here ARE that contract.
----------------------------------------------------------------------

local ArenaEntryConstants = {}

-- A BasePart in the ready room. A living player of the pad's arena who
-- touches it is moved to an arrival point.
ArenaEntryConstants.PAD_TAG = "ArenaEntryPad"

-- A BasePart on the island. Pad and arrival match by `Arena.idOf`.
ArenaEntryConstants.ARRIVAL_TAG = "ArenaArrivalPoint"

-- One touch is one teleport: Touched fires once per colliding limb, and the
-- player is still standing on the arrival pad's neighbourhood a moment after.
ArenaEntryConstants.COOLDOWN_SEC = 2

-- Distance from the arrival part's top surface to the HumanoidRootPart
-- centre. An R15 default rig stands about this high (HipHeight + half the
-- root part), so the character lands on its feet rather than in the part.
ArenaEntryConstants.STAND_OFFSET_STUDS = 3

-- Minimum flattened length of a part's look vector below which it has no
-- usable heading (a part facing straight up or down).
ArenaEntryConstants.MIN_HEADING_LENGTH = 0.001

-- VfxConfig.EFFECTS keys, played through VfxBroadcast at a point.
ArenaEntryConstants.Vfx = {
	Depart = "impact_shield", -- blue shimmer where the player left
	Arrive = "impact_buff",   -- green burst where they land
}

-- What `handleTouch` reports. Strings so a test failure reads on its own.
ArenaEntryConstants.Result = {
	Teleported = "teleported",
	NotAPlayer = "not_a_player",
	Dead = "dead",
	WrongArena = "wrong_arena",
	Cooldown = "cooldown",
	NoArrival = "no_arrival",
}

return ArenaEntryConstants
