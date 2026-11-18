--!strict

----------------------------------------------------------------------
-- PoseTypes
----------------------------------------------------------------------
-- The contract between BossPuppet and its pose layers
-- (wiki/design/boss-movement.md). Each frame the puppet resets a Pose to
-- neutral, hands it to every layer in order (Telegraph, Exposed,
-- Ceremony), then draws the body from the base motion plus the Pose. A
-- later layer sees and may override an earlier one's values.
--
-- Layers never write a joint, a mesh Scale or the hit flash themselves:
-- the puppet is their one writer. A layer may create and own its own
-- client-only instances (a ground shadow, ward plates) in `attach` and
-- must remove them in `detach`.
----------------------------------------------------------------------

local PoseTypes = {}

export type Context = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	dt: number,
	clock: number,      -- os.clock(), for local animation phase
	serverNow: number,  -- workspace:GetServerTimeNow(), for published times
	speed: number,      -- ground speed, studs a second
	state: string?,     -- CurrentState
	alive: boolean,
}

export type Pose = {
	-- Multiplies the idle motion (bob, breathing, stem sway, lean); 0 holds
	-- the body still while layers pose it.
	motionScale: number,
	-- Applied to the brain after hover and lean (lift, recoil, tilt).
	rootOffset: CFrame,
	-- Radians each lobe swings outward on its hinge; 0 = closed.
	lobeOpen: number,
	-- Multiplies the lobes' mesh scale (squash and stretch).
	lobeScale: Vector3,
	stemOffset: CFrame,
	-- Overrides where the eyes look (world point), and turns them after.
	eyeTarget: Vector3?,
	eyeOffset: CFrame,
	-- Ignore the eye clamp (for a spin or a stare).
	eyeUnclamped: boolean,
	coreLightScale: number,
	coreLightColor: Color3?,
	neuronRadiusScale: number,
	neuronSpeedScale: number,
	neuronHeightOffset: number,
	-- 0 = synapses at rest, 1 = blazing.
	synapseGlow: number,
	-- A tint over the whole body when no hit flash is showing.
	tint: Color3?,
	tintAlpha: number,  -- 0 = none, 1 = solid
}

export type Layer = {
	name: string,
	-- Called once per boss; returns the layer's own per-boss state.
	attach: (model: Model) -> any,
	apply: (state: any, ctx: Context, pose: Pose) -> (),
	detach: (state: any) -> (),
}

function PoseTypes.neutral(): Pose
	return {
		motionScale = 1,
		rootOffset = CFrame.identity,
		lobeOpen = 0,
		lobeScale = Vector3.one,
		stemOffset = CFrame.identity,
		eyeTarget = nil,
		eyeOffset = CFrame.identity,
		eyeUnclamped = false,
		coreLightScale = 1,
		coreLightColor = nil,
		neuronRadiusScale = 1,
		neuronSpeedScale = 1,
		neuronHeightOffset = 0,
		synapseGlow = 0,
		tint = nil,
		tintAlpha = 0,
	}
end

return PoseTypes
