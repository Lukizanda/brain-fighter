--!strict

----------------------------------------------------------------------
-- SkillConstants
----------------------------------------------------------------------
-- Names shared between the systems that *write* skill state and the
-- client controllers that *render* it. They live here rather than next
-- to either side because a typo on one end fails silently: the writer
-- sets an attribute nobody watches, or the watcher waits on one nobody
-- sets, and in both cases the visual simply never appears.
----------------------------------------------------------------------

-- Set on a frozen rig's character Model while the freeze is active, and
-- cleared when it lifts. `SkillEffects.handlers.freeze` writes it;
-- `client/Vfx/FreezeVfxController` watches it and owns the ice shards.
--
-- An attribute rather than a direct call into FreezeVfx, for the same
-- reason `_shield` is one: it replicates. The status is authored on the
-- server and every client's copy of the character carries it, so the
-- shards appear for everyone without a broadcast, and a late joiner sees
-- an already-frozen boss because the value is there when they arrive.
local FROZEN_ATTRIBUTE = "_frozen"

-- Set on a rig that is currently on fire, and cleared when the flames go
-- out. `SkillEffects.handlers.burn` writes it; `client/Vfx/InfernoVfxController`
-- watches it and owns every flame, the Highlight and the light.
--
-- Purely a render flag today: `burn` deals no damage and applies no
-- debuff, so nothing in the gameplay layer reads this. That is deliberate
-- rather than an oversight — Inferno's whole 50%-of-MaxHP payload lands in
-- its `damage` entry on the same frame, and a burn that also ticked would
-- be a balance change smuggled in behind a VFX pass. The flag exists as
-- the seam: a real fire DoT later becomes a handler that reads this
-- instead of a second status invented from scratch.
--
-- Same replication argument as `_frozen`: the server writes it on the
-- character Model, so every client draws the same burning boss without a
-- broadcast, and a late joiner sees an already-burning rig because the
-- value is simply there when they arrive.
local BURNING_ATTRIBUTE = "_burning"

-- CollectionService tags whose Models carry a Humanoid and can therefore
-- be targeted by a skill. Player characters are NOT tagged — they're
-- enumerated through `Players` instead.
--
-- Shared so the set can't drift: `SkillDelivery` uses it to decide what a
-- projectile can hit, and the status-VFX controllers (`FreezeVfxController`,
-- `InfernoVfxController`) use it to decide whose status attributes to
-- watch. If those lists disagreed, the rigs in the gap would be freezable
-- and burnable but never draw shards or flames.
local DAMAGEABLE_TAGS: { string } = { "Damageable", "NPC", "Boss" }

return {
	FROZEN_ATTRIBUTE  = FROZEN_ATTRIBUTE,
	BURNING_ATTRIBUTE = BURNING_ATTRIBUTE,
	DAMAGEABLE_TAGS   = DAMAGEABLE_TAGS,
}
