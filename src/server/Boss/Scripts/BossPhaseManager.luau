--!strict

----------------------------------------------------------------------
-- BossPhaseManager
----------------------------------------------------------------------
-- Monitors boss HP and determines the active phase by scanning
-- typeSpec.phases. Phase resolution:
--   - Phase 1 (hpFraction=1.0) is always the starting phase.
--   - Phase N (hpFraction=X) activates when current HP/MaxHP <= X.
--   - The highest-index eligible phase wins.
--
-- With a single entry in phases the manager never transitions — the
-- scaffolding is in place for multi-phase without changing any code.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local Logger    = require(ReplicatedStorage.Shared.Core.Logger)

type PhaseSpec    = BossTypes.PhaseSpec
type BossTypeSpec = BossTypes.BossTypeSpec

local log = Logger.new("BossPhaseManager")

local BossPhaseManager = {}
BossPhaseManager.__index = BossPhaseManager

export type BossPhaseManagerInstance = {
	update: (self: BossPhaseManagerInstance) -> boolean,
	getCurrentPhaseIndex: (self: BossPhaseManagerInstance) -> number,
	getCurrentPhaseSpec: (self: BossPhaseManagerInstance) -> PhaseSpec,
	_humanoid: Humanoid,
	_typeSpec: BossTypeSpec,
	_currentIndex: number,
}

function BossPhaseManager.new(humanoid: Humanoid, typeSpec: BossTypeSpec): BossPhaseManagerInstance
	local self = setmetatable({
		_humanoid     = humanoid,
		_typeSpec     = typeSpec,
		_currentIndex = 1,
	}, BossPhaseManager)
	return (self :: any) :: BossPhaseManagerInstance
end

-- Returns true if the active phase changed this call.
function BossPhaseManager:update(): boolean
	local humanoid = self._humanoid
	if not humanoid or not humanoid.Parent then
		return false
	end

	local maxHp = humanoid.MaxHealth
	if maxHp <= 0 then
		return false
	end

	local fraction = humanoid.Health / maxHp
	local phases   = self._typeSpec.phases

	-- Scan phases from index 2 upward; highest eligible index wins.
	-- Phase 1 is always active so we start targetIndex at 1.
	local targetIndex = 1
	for i = 2, #phases do
		if fraction <= phases[i].hpFraction then
			targetIndex = i
		end
	end

	if targetIndex ~= self._currentIndex then
		local old = self._currentIndex
		self._currentIndex = targetIndex
		log:info(string.format(
			"Phase %d → %d (HP %.0f/%.0f = %.0f%%)",
			old, targetIndex,
			humanoid.Health, maxHp,
			fraction * 100
		))
		return true
	end

	return false
end

function BossPhaseManager:getCurrentPhaseIndex(): number
	return self._currentIndex
end

function BossPhaseManager:getCurrentPhaseSpec(): PhaseSpec
	return self._typeSpec.phases[self._currentIndex]
end

return BossPhaseManager
