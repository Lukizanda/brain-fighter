--!strict

----------------------------------------------------------------------
-- Exposed (boss pose layer)
----------------------------------------------------------------------
-- Stage 11c — the core-open stuck window and the ward-break stagger, from ExposedUntil / StunnedUntil
-- (wiki/design/boss-movement.md). See PoseTypes for the contract: write
-- only into `pose`; own any instances you make in attach/detach.
--
-- Stub: does nothing until its stage is built.
----------------------------------------------------------------------

local PoseTypes = require(script.Parent.PoseTypes)

local layer: PoseTypes.Layer = {
	name = "Exposed",
	attach = function(_model: Model): any
		return {}
	end,
	apply = function(_state: any, _ctx: PoseTypes.Context, _pose: PoseTypes.Pose) end,
	detach = function(_state: any) end,
}

return layer
