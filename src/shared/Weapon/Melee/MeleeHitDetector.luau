----------------------------------------------------------------------
-- MeleeHitDetector
----------------------------------------------------------------------
-- Pure hit-detection helper for melee swings. Server-authoritative:
-- call from the server once per swing (or per substep within the
-- Active window) to find Humanoids inside a swept box in front of
-- the attacker.
--
-- Not a state machine and not a damage-applier — just returns hits.
-- The caller decides when to fire, what mode to use, and how to apply
-- damage (usually via HealthService.applyDamage).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeleeTypes = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeTypes)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("MeleeHitDetector")

type HitMode = MeleeTypes.HitMode
type HitResult = MeleeTypes.HitResult

export type SweepParams = {
	originCFrame: CFrame, -- center of the front face of the hitbox (usually attacker HRP + lookVector)
	reach: number,
	width: number,
	height: number,
	attackerCharacter: Model, -- excluded from hits (can't hit self)
	hitMode: HitMode,
	alreadyHit: { [Humanoid]: true }?, -- dedup set, mutated by this function
}

local MeleeHitDetector = {}

-- Build the OverlapParams once per call. We could cache per-attacker,
-- but swings are infrequent enough that construction cost is negligible.
local function buildOverlapParams(attackerCharacter: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	params.MaxParts = 0 -- no limit; we filter by humanoid below
	return params
end

-- Run one sweep. Returns a list of HitResults (empty if nothing hit).
-- Mutates `sweep.alreadyHit` to prevent the same humanoid from being
-- counted twice in a single swing (across substeps or cleave targets).
function MeleeHitDetector.sweep(sweep: SweepParams): { HitResult }
	local alreadyHit = sweep.alreadyHit or {}

	-- Box center: half the reach forward of the origin
	local boxCFrame = sweep.originCFrame * CFrame.new(0, 0, -sweep.reach * 0.5)
	local boxSize = Vector3.new(sweep.width, sweep.height, sweep.reach)

	local parts = workspace:GetPartBoundsInBox(
		boxCFrame,
		boxSize,
		buildOverlapParams(sweep.attackerCharacter)
	)

	local results: { HitResult } = {}
	for _, part in parts do
		-- Walk up to the Model and find its Humanoid
		local model = part:FindFirstAncestorOfClass("Model")
		if not model then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		if alreadyHit[humanoid] then
			continue
		end

		local rootPart = humanoid.RootPart or model:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		local distance = (rootPart.Position - sweep.originCFrame.Position).Magnitude
		alreadyHit[humanoid] = true

		table.insert(results, {
			humanoid = humanoid,
			rootPart = rootPart,
			distance = distance,
		})

		-- Single-target mode stops at the first valid hit
		if sweep.hitMode == MeleeConstants.HitMode.Single then
			break
		end
	end

	if #results > 0 then
		log:infoThrottled("melee_sweep_hit", 0.5, string.format(
			"hits=%d mode=%s reach=%.1f", #results, sweep.hitMode, sweep.reach))
	end

	return results
end

-- Helper: build origin CFrame from an attacker's HumanoidRootPart looking forward.
-- Handy default — you can also pass a custom CFrame (e.g. from a weapon handle)
-- to MeleeHitDetector.sweep directly.
function MeleeHitDetector.originFromCharacter(character: Model): CFrame?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	return hrp.CFrame
end

return MeleeHitDetector
