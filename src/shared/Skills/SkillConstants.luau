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

-- The colour and tier of a spell currently being charged, set on the
-- caster's character Model while a colour panel is held and cleared on
-- release. `server/SpellCast/ChargeStateService` writes them from the
-- ChargeState remote; `client/Vfx/ChargeOrbController` watches them and
-- owns the orb.
--
-- Two attributes rather than one packed string because the tier is the
-- thing that animates: a client tweening the orb between sizes wants a
-- number it can lerp, and parsing "red:3" on every write to get one would
-- be a string operation on the hot path for no gain.
--
-- The same replication argument as `_frozen` and `_shield`, and it is the
-- whole reason the orb is affordable: the character is server-owned, so a
-- server-written attribute lands on every client's copy of that rig with
-- no fan-out RemoteEvent on the way out. The orb is a PvP tell — the
-- point is that your opponent can see you winding up a T4 — and that
-- costs one attribute write per tier crossing, not a broadcast per frame.
--
-- CHARGE_TIER_ATTR is 0 (or absent) while nothing is charging. A tier of
-- 0 with a colour set is a legal transient: the press has registered but
-- the charge has not reached T1.
local CHARGE_COLOR_ATTR = "_chargeColor"
local CHARGE_TIER_ATTR = "_chargeTier"

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

-- On every barrier slab `SkillVisuals.spawnBarrier` puts in the world.
-- `client/Vfx/BarrierCrumbleController` watches it and owns the rubble.
--
-- The interesting half is that the controller listens for the tag being
-- *removed*, which is what Destroy fires. The slab's death is the whole
-- trigger: `Debris` reclaims it on the server when its duration is up,
-- every client's replicated copy dies with it, and each one breaks its
-- own into falling chunks from the CFrame, Size and Color still readable
-- on the destroyed Part.
--
-- Same argument as the attributes above, one step further — the server
-- doesn't broadcast the collapse, it just deletes a thing that was
-- already replicated, and the collapse is what every client makes of
-- that. Nothing new crosses the wire for a wall expiring.
local BARRIER_TAG = "SkillBarrier"

-- When the barrier it sits on will be reclaimed, so each client can crack
-- the slab open in the seconds before it goes. Written by `spawnBarrier`,
-- read by `client/Vfx/BarrierCrumbleController`.
--
-- **A `workspace:GetServerTimeNow()` stamp, and it has to be.** This is a
-- deadline crossing the wire, and every per-VM clock is wrong for that:
-- `os.clock()` is time since that process started, so a client's reading
-- has no relationship to the server's, and `tick()`/`os.time()` drift
-- between machines. `GetServerTimeNow` is the one clock both VMs agree
-- on. The failure it avoids is silent and awful — the wall would crack on
-- a schedule that looked plausible on the machine you tested from and was
-- minutes off on everyone else's.
--
-- An absolute deadline rather than a remaining-seconds countdown, for the
-- same reason the status attributes are absolute: it replicates once and
-- stays correct, and a client that joins mid-life computes the right
-- amount of cracking from it instead of starting its own timer from zero.
local BARRIER_EXPIRES_AT = "_barrierExpiresAt"

return {
	FROZEN_ATTRIBUTE   = FROZEN_ATTRIBUTE,
	BURNING_ATTRIBUTE  = BURNING_ATTRIBUTE,
	CHARGE_COLOR_ATTR  = CHARGE_COLOR_ATTR,
	CHARGE_TIER_ATTR   = CHARGE_TIER_ATTR,
	DAMAGEABLE_TAGS    = DAMAGEABLE_TAGS,
	BARRIER_TAG        = BARRIER_TAG,
	BARRIER_EXPIRES_AT = BARRIER_EXPIRES_AT,
}
