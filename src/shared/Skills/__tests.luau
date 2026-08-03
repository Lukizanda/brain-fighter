--!strict

----------------------------------------------------------------------
-- Skills __tests — interrupt, freeze, shield and buff registries
----------------------------------------------------------------------
-- Smoke tests for the cast-token registry: begin/finish lifecycle,
-- cancelCastsBy, silence/unsilence, and the Phase 5.1 death-cleanup
-- hooks (Humanoid.Died / Destroying purge both registries so a
-- mid-cast death can't leak entries).
--
-- Phase 5.2 adds the defensive layer: the shield absorb pool (granted by
-- Skills, drained by Health's DamageModifierRegistry) and timed stat
-- buffs (the damageAmp behind Stasis).
--
-- Run from an MCP/console harness:
--   require(game.ReplicatedStorage.Shared.Skills.__tests).run()
--
-- The Died scenario needs a running simulation (the humanoid state
-- machine doesn't step at edit time) — run during a playtest.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageModifierRegistry = require(ReplicatedStorage.Shared.Health.DamageModifierRegistry)
local DamageTypes            = require(ReplicatedStorage.Shared.Health.DamageTypes)
local SkillBuffs             = require(ReplicatedStorage.Shared.Skills.SkillBuffs)
local SkillEffects           = require(ReplicatedStorage.Shared.Skills.SkillEffects)
local SkillInterrupt         = require(ReplicatedStorage.Shared.Skills.SkillInterrupt)

-- Died is asynchronous (state machine transition); poll up to this long.
local DIED_TIMEOUT_SEC = 2
local DIED_POLL_SEC = 0.05
-- The place runs deferred signal behavior: Died/Destroying handlers run
-- at the next resumption point, never synchronously. Every post-event
-- assert must poll, briefly, rather than check inline.
local PURGE_TIMEOUT_SEC = 1

local function pollUntil(predicate: () -> boolean, timeoutSec: number): boolean
	local deadline = os.clock() + timeoutSec
	while not predicate() and os.clock() < deadline do
		task.wait(DIED_POLL_SEC)
	end
	return predicate()
end

local M = {}

local function fail(scenario: string, message: string)
	error(string.format("[Skills.__tests] %s — %s", scenario, message), 2)
end

local function makeDummy(): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = "SkillInterruptTestDummy"
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.Parent = workspace
	return model, humanoid
end

-- Kill via Health=0. A rig-less dummy never reaches the Dead state (so
-- Died won't fire — verified empirically, even with ChangeState), but
-- the cleanup hooks also watch HealthChanged <= 0, which is
-- rig-independent and is what this exercises. Real character deaths
-- fire both.
local function killDummy(humanoid: Humanoid)
	humanoid.Health = 0
end

function M.run()
	print("[Skills.__tests] starting")

	-- 1. begin → live tokens; cancelCastsBy flips every active token.
	do
		local model, humanoid = makeDummy()
		local t1 = SkillInterrupt.begin(humanoid)
		local t2 = SkillInterrupt.begin(humanoid)
		if t1.cancelled or t2.cancelled then
			fail("cancelCastsBy", "fresh tokens should start live")
		end
		SkillInterrupt.cancelCastsBy(humanoid)
		if not (t1.cancelled and t2.cancelled) then
			fail("cancelCastsBy", "should cancel every active token")
		end
		model:Destroy()
	end
	print("[Skills.__tests] cancelCastsBy ok")

	-- 2. finish removes the token; a later cancel must not flip it.
	do
		local model, humanoid = makeDummy()
		local t = SkillInterrupt.begin(humanoid)
		SkillInterrupt.finish(humanoid, t)
		SkillInterrupt.cancelCastsBy(humanoid)
		if t.cancelled then
			fail("finish", "finished token should be out of cancel's reach")
		end
		model:Destroy()
	end
	print("[Skills.__tests] finish ok")

	-- 3. silence pre-cancels new tokens; unsilence restores.
	do
		local model, humanoid = makeDummy()
		SkillInterrupt.silence(humanoid)
		local silencedToken = SkillInterrupt.begin(humanoid)
		if not silencedToken.cancelled then
			fail("silence", "token started under silence should be born cancelled")
		end
		SkillInterrupt.unsilence(humanoid)
		local liveToken = SkillInterrupt.begin(humanoid)
		if liveToken.cancelled then
			fail("silence", "token after unsilence should be live")
		end
		model:Destroy()
	end
	print("[Skills.__tests] silence/unsilence ok")

	-- 4. Destroying purges both registries: active tokens get cancelled
	-- and the silence flag drops (a fresh begin comes back live).
	do
		local model, humanoid = makeDummy()
		local t = SkillInterrupt.begin(humanoid)
		SkillInterrupt.silence(humanoid)
		model:Destroy()
		if not pollUntil(function() return t.cancelled end, PURGE_TIMEOUT_SEC) then
			fail("destroying", "active token should be cancelled on Destroying")
		end
		local afterPurge = SkillInterrupt.begin(humanoid)
		if afterPurge.cancelled then
			fail("destroying", "silence flag should be purged on Destroying")
		end
		-- The destroyed humanoid got re-tracked by the probe begin; clear it.
		SkillInterrupt.cancelCastsBy(humanoid)
	end
	print("[Skills.__tests] destroying-purge ok")

	-- 5. Died purges the same way (freeze/death race in a boss fight).
	do
		local model, humanoid = makeDummy()
		local t = SkillInterrupt.begin(humanoid)
		SkillInterrupt.silence(humanoid)
		killDummy(humanoid)
		if not pollUntil(function() return t.cancelled end, DIED_TIMEOUT_SEC) then
			fail("died", "active token should be cancelled on death (Health <= 0)")
		end
		local afterPurge = SkillInterrupt.begin(humanoid)
		if afterPurge.cancelled then
			fail("died", "silence flag should be purged on Died")
		end
		SkillInterrupt.cancelCastsBy(humanoid)
		model:Destroy()
	end
	print("[Skills.__tests] died-purge ok")

	-- 6. Freeze/death race: a humanoid that dies mid-freeze must not
	-- leak its _freezeState entry (the 5.1 [H] fix).
	do
		local model, humanoid = makeDummy()
		local res = SkillEffects.apply({ kind = "freeze", durationSec = 30 } :: any, humanoid)
		if not res.ok then
			fail("freeze-death", "freeze apply should succeed: " .. tostring(res.reason))
		end
		if not SkillEffects.isFrozen(humanoid) then
			fail("freeze-death", "humanoid should be tracked while frozen")
		end
		killDummy(humanoid)
		if not pollUntil(function() return not SkillEffects.isFrozen(humanoid) end, DIED_TIMEOUT_SEC) then
			fail("freeze-death", "freeze state should purge on death (Health <= 0)")
		end
		local afterDeath = SkillInterrupt.begin(humanoid)
		if afterDeath.cancelled then
			fail("freeze-death", "freeze's silence should be purged on Died")
		end
		SkillInterrupt.cancelCastsBy(humanoid)
		model:Destroy()
	end
	print("[Skills.__tests] freeze-death-race ok")

	-- 7. Freeze despawn race: destroying the character mid-freeze purges
	-- synchronously via Humanoid.Destroying.
	do
		local model, humanoid = makeDummy()
		SkillEffects.apply({ kind = "freeze", durationSec = 30 } :: any, humanoid)
		if not SkillEffects.isFrozen(humanoid) then
			fail("freeze-despawn", "humanoid should be tracked while frozen")
		end
		model:Destroy()
		if not pollUntil(function() return not SkillEffects.isFrozen(humanoid) end, PURGE_TIMEOUT_SEC) then
			fail("freeze-despawn", "freeze state should purge on Destroying")
		end
	end
	print("[Skills.__tests] freeze-despawn-race ok")

	-- 8. Shield grants an absorb pool that DamageModifierRegistry actually
	-- drains. This is the whole point of storing it as the `_shield`
	-- attribute rather than in a Skills-local table — if these two ever
	-- stop agreeing on where the pool lives, the shield silently stops
	-- working and nothing else notices.
	do
		local model, humanoid = makeDummy()
		local granted = SkillEffects.apply({ kind = "shield", amount = 40 } :: any, humanoid)
		if not granted.ok then
			fail("shield-absorb", "shield apply should succeed: " .. tostring(granted.reason))
		end
		if SkillBuffs.getShield(humanoid) ~= 40 then
			fail("shield-absorb", "pool should read 40, got " .. tostring(SkillBuffs.getShield(humanoid)))
		end

		local finalDamage = DamageModifierRegistry.resolve({
			sourcePlayer   = nil,
			targetHumanoid = humanoid,
			baseDamage     = 25,
			damageType     = DamageTypes.DamageType.Bullet,
			hitZone        = DamageTypes.HitZone.Torso,
			timestamp      = os.clock(),
		} :: any)
		if finalDamage ~= 0 then
			fail("shield-absorb", "25 damage into a 40 pool should reach Health as 0, got " .. tostring(finalDamage))
		end
		if SkillBuffs.getShield(humanoid) ~= 15 then
			fail("shield-absorb", "pool should be 15 after absorbing 25, got " .. tostring(SkillBuffs.getShield(humanoid)))
		end
		model:Destroy()
	end
	print("[Skills.__tests] shield-absorb ok")

	-- 9. Shield stacks additively (Sanctuary layered on Shield) and purges
	-- on death. The pool has no expiry timer, so death cleanup is the only
	-- thing standing between it and an indefinite leak.
	do
		local model, humanoid = makeDummy()
		SkillEffects.apply({ kind = "shield", amount = 40 } :: any, humanoid)
		SkillEffects.apply({ kind = "shield", amount = 40 } :: any, humanoid)
		if SkillBuffs.getShield(humanoid) ~= 80 then
			fail("shield-purge", "two 40 pools should stack to 80, got " .. tostring(SkillBuffs.getShield(humanoid)))
		end
		killDummy(humanoid)
		if not pollUntil(function() return SkillBuffs.getShield(humanoid) == 0 end, DIED_TIMEOUT_SEC) then
			fail("shield-purge", "shield pool should clear on death (Health <= 0)")
		end
		model:Destroy()
	end
	print("[Skills.__tests] shield-purge ok")

	-- 10. A damageAmp buff multiplies damage dealt TO the target — Stasis's
	-- actual payload. Before 5.2 the registry declared the multiplier and
	-- the freeze handler quietly ignored it.
	do
		local model, humanoid = makeDummy()
		humanoid.MaxHealth = 100
		humanoid.Health = 100

		SkillEffects.apply({ kind = "damage", amount = 10 } :: any, humanoid)
		if humanoid.Health ~= 90 then
			fail("damage-amp", "unbuffed 10 damage should leave 90, got " .. tostring(humanoid.Health))
		end

		local buffed = SkillEffects.apply(
			{ kind = "buff", buffKind = "damageAmp", magnitude = 2.0, durationSec = 30 } :: any,
			humanoid
		)
		if not buffed.ok then
			fail("damage-amp", "buff apply should succeed: " .. tostring(buffed.reason))
		end
		SkillEffects.apply({ kind = "damage", amount = 10 } :: any, humanoid)
		if humanoid.Health ~= 70 then
			fail("damage-amp", "2x-amped 10 damage should leave 70, got " .. tostring(humanoid.Health))
		end
		model:Destroy()
	end
	print("[Skills.__tests] damage-amp ok")

	-- 11. Buffs expire. Expiry is lazy (evaluated on read), so this also
	-- covers the read path clearing the entry rather than leaking it.
	do
		local model, humanoid = makeDummy()
		SkillEffects.apply(
			{ kind = "buff", buffKind = "damageAmp", magnitude = 2.0, durationSec = 0.2 } :: any,
			humanoid
		)
		if not SkillBuffs.hasBuff(humanoid, "damageAmp") then
			fail("buff-expiry", "buff should be live immediately after apply")
		end
		if not pollUntil(function() return not SkillBuffs.hasBuff(humanoid, "damageAmp") end, DIED_TIMEOUT_SEC) then
			fail("buff-expiry", "buff should lapse after its duration")
		end
		if SkillBuffs.damageAmp(humanoid) ~= 1.0 then
			fail("buff-expiry", "lapsed buff should read back as 1.0 amp")
		end
		model:Destroy()
	end
	print("[Skills.__tests] buff-expiry ok")

	print("[Skills.__tests] all scenarios passed")
end

return M
