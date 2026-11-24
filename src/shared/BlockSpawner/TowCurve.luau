--!strict

----------------------------------------------------------------------
-- TowCurve
----------------------------------------------------------------------
-- The one definition of how a snapping tow travels, so the server (which
-- moves the block) and the client (which draws it from server time) cannot
-- drift. Fraction of the way = (elapsed / duration) ^ TowConstants.SNAP_POWER:
-- an ease-in that starts slow and arrives at full speed.
----------------------------------------------------------------------

local TowConstants = require(script.Parent.TowConstants)

local TowCurve = {}

-- How far along the snap is, 0..1, `elapsedSec` into a snap of `durationSec`.
-- A snap of no length is already complete.
function TowCurve.fraction(elapsedSec: number, durationSec: number): number
	if durationSec <= 0 then
		return 1
	end
	return math.clamp(elapsedSec / durationSec, 0, 1) ^ TowConstants.SNAP_POWER
end

-- Where a block that started the snap at `from` is at `nowSec`, heading for
-- `target`, the snap running from `snapAt` to `arriveAt`.
function TowCurve.position(from: Vector3, target: Vector3, nowSec: number, snapAt: number, arriveAt: number): Vector3
	return from:Lerp(target, TowCurve.fraction(nowSec - snapAt, arriveAt - snapAt))
end

return TowCurve
