--!strict

----------------------------------------------------------------------
-- Telegraph (boss pose layer)
----------------------------------------------------------------------
-- Stage 11b — a body tell per attack from PendingAttack / WindupEndsAt, and leaning toward EatingAt
-- (wiki/design/boss-movement.md). See PoseTypes for the contract: write
-- only into `pose`; own any instances you make in attach/detach.
--
-- Stub: does nothing until its stage is built.
----------------------------------------------------------------------

local PoseTypes = require(script.Parent.PoseTypes)

local layer: PoseTypes.Layer = {
	name = "Telegraph",
	attach = function(_model: Model): any
		return {}
	end,
	apply = function(_state: any, _ctx: PoseTypes.Context, _pose: PoseTypes.Pose) end,
	detach = function(_state: any) end,
}

return layer
