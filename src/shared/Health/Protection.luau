--!strict

----------------------------------------------------------------------
-- Protection
----------------------------------------------------------------------
-- Time-boxed invulnerability for a character. Owned by Health: whether a
-- hit lands is a damage rule, and `applyDamage.process` is the one path every
-- hit takes, so it asks `isActive` and drops the hit. Whoever *grants* the
-- window (today HealthService, off ArenaEntryService's `PlayerEntered`) never
-- touches Humanoid.Health.
--
-- The window is one character attribute holding the
-- `workspace:GetServerTimeNow()` instant it closes. Nothing counts it down,
-- so an expired window needs no cleanup, and the client reads the same value
-- to draw its cue (server time is the only clock both VMs share).
--
-- `grant` is the attribute's only writer.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)

local ATTRIBUTE = HealthConstants.PROTECTED_UNTIL_ATTRIBUTE

local Protection = {}

-- The instant the character's window closes, or nil when it has none.
function Protection.closesAt(character: Instance): number?
	local value = character:GetAttribute(ATTRIBUTE)
	if typeof(value) == "number" then
		return value :: number
	end
	return nil
end

-- Is the character inside a protection window? `now` is injectable for tests.
function Protection.isActive(character: Instance, now: number?): boolean
	local closesAt = Protection.closesAt(character)
	if closesAt == nil then
		return false
	end
	return (now or workspace:GetServerTimeNow()) < closesAt
end

-- Open (or extend) a window of `durationSec` from now. A window never
-- shortens: a grant that would close earlier than the one already running is
-- ignored. Returns the instant the window now closes.
function Protection.grant(character: Instance, durationSec: number): number
	local closesAt = workspace:GetServerTimeNow() + durationSec
	local existing = Protection.closesAt(character)
	if existing ~= nil and existing > closesAt then
		return existing
	end
	character:SetAttribute(ATTRIBUTE, closesAt)
	return closesAt
end

return Protection
