----------------------------------------------------------------------
-- adjustListIndexAfterRemoval
----------------------------------------------------------------------
-- Pure helper: given a sequential-array index that referred to a logical
-- entry, plus the index of an entry that was just removed from the same
-- array, return the new index that still points to the same logical
-- entry (or clamps to the end if the array shrank).
--
-- Used by the WeaponRolodex's drop callback: when a tool BEFORE the
-- currently-displayed one is evicted (cap-overflow kills the oldest
-- while the player holds the newer), the surviving entries shift left
-- under the index. Without decrementing, the rolodex's currentIndex
-- silently desyncs and the next Tab cycles from the wrong slot.
--
-- Args:
--   removedIdx — index that was removed (1-based)
--   currentIndex — index that points at the logical "current" entry
--   newLength — array length AFTER removal
--
-- Returns the new currentIndex.
----------------------------------------------------------------------

local function adjustListIndexAfterRemoval(removedIdx: number, currentIndex: number, newLength: number): number
	if removedIdx < currentIndex then
		return currentIndex - 1
	elseif currentIndex > newLength then
		return math.max(1, newLength)
	end
	return currentIndex
end

return adjustListIndexAfterRemoval
