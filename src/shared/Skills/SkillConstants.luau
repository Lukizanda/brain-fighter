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

-- CollectionService tags whose Models carry a Humanoid and can therefore
-- be targeted by a skill. Player characters are NOT tagged — they're
-- enumerated through `Players` instead.
--
-- Shared so the set can't drift: `SkillDelivery` uses it to decide what a
-- projectile can hit, and `FreezeVfxController` uses it to decide whose
-- freeze attribute to watch. If those two lists disagreed, the rigs in
-- the gap would be freezable but never draw shards.
local DAMAGEABLE_TAGS: { string } = { "Damageable", "NPC", "Boss" }

return {
	FROZEN_ATTRIBUTE = FROZEN_ATTRIBUTE,
	DAMAGEABLE_TAGS  = DAMAGEABLE_TAGS,
}
