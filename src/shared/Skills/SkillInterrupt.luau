--!strict

----------------------------------------------------------------------
-- SkillInterrupt
----------------------------------------------------------------------
-- Per-Humanoid registry of "active cast tokens". A token is a tiny
-- mutable record that async delivery handlers (projectile, aoe) check
-- before scheduling more work. Effects that interrupt the caster
-- (currently: freeze) flip every token belonging to the target,
-- aborting any task.delay callbacks the target had pending.
--
-- Scope: only gates *future* scheduled work. Already-launched
-- projectiles run on RunService.Heartbeat and are independent of the
-- token. That matches the design call ("freeze stops new shots; in-
-- flight ones keep flying").
--
-- Lives in Shared so client- and server-side delivery paths share the
-- same registry semantics, but practically the registry is per-VM:
-- bosses cast server-side, players cast client-side, and the freeze
-- handler that triggers cancellation runs in the same VM as the
-- delivery it interrupts.
----------------------------------------------------------------------

export type CastToken = { cancelled: boolean }

local _active: { [Humanoid]: { CastToken } } = {}

-- Humanoids whose currently-active interrupt window (freeze, future
-- stun/silence) covers them. While silenced, `begin` returns a token
-- pre-marked `cancelled=true` so any task.delay callbacks gated on the
-- token bail out without spawning work. Caller is responsible for
-- pairing every `silence` with an `unsilence` when the effect ends.
local _silenced: { [Humanoid]: boolean } = {}

local function resolveHumanoid(target: any): Humanoid?
	if typeof(target) ~= "Instance" then return nil end
	local inst = target :: Instance
	if inst:IsA("Humanoid") then return inst :: Humanoid end
	if inst:IsA("Model") then return (inst :: Model):FindFirstChildOfClass("Humanoid") end
	return nil
end

local SkillInterrupt = {}

-- Register a new cast token for `caster`. Returns the token even when
-- no humanoid is resolvable, so callers can use the same token-check
-- code path unconditionally. Untracked tokens simply never get
-- cancelled by anyone.
function SkillInterrupt.begin(caster: Instance?): CastToken
	local token: CastToken = { cancelled = false }
	local h = resolveHumanoid(caster)
	if not h then return token end
	-- New casts started during an active silence window are born cancelled,
	-- so a frozen boss can still cycle through its Attack state without
	-- actually spawning projectiles.
	if _silenced[h] then token.cancelled = true end
	local list = _active[h]
	if not list then
		list = {}
		_active[h] = list
	end
	table.insert(list, token)
	return token
end

-- Remove a token from the registry (delivery completed naturally).
-- Idempotent — safe to call on a token that was already cancelled.
function SkillInterrupt.finish(caster: Instance?, token: CastToken)
	local h = resolveHumanoid(caster)
	if not h then return end
	local list = _active[h]
	if not list then return end
	for i, t in list do
		if t == token then
			table.remove(list, i)
			break
		end
	end
	if #list == 0 then _active[h] = nil end
end

-- Cancel every active cast belonging to `target`. Used by freeze (and
-- any future stun/silence effect) to abort pending scheduled work.
function SkillInterrupt.cancelCastsBy(target: any)
	local h = resolveHumanoid(target)
	if not h then return end
	local list = _active[h]
	if not list then return end
	for _, token in list do
		token.cancelled = true
	end
	_active[h] = nil
end

-- Mark `target` as silenced for the lifetime of an interrupt effect.
-- New `begin` calls for this humanoid will return pre-cancelled tokens
-- until `unsilence` runs.
function SkillInterrupt.silence(target: any)
	local h = resolveHumanoid(target)
	if not h then return end
	_silenced[h] = true
end

function SkillInterrupt.unsilence(target: any)
	local h = resolveHumanoid(target)
	if not h then return end
	_silenced[h] = nil
end

return SkillInterrupt
