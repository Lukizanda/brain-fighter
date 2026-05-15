----------------------------------------------------------------------
-- LetterBlockAnimator
----------------------------------------------------------------------
-- Client-only visual animator for floating letter blocks. Bobs the
-- block on a vertical sine and slowly rotates it around its Y axis,
-- per the LetterBlock design (see wiki/systems/LetterBlock.md).
--
-- Hooked to CollectionService tag = LetterBlocks.TAG. Each block
-- gets a random phase offset on track so the arena doesn't bob in
-- unison.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

local NEAR_THRESHOLD_STUDS = 60
local FAR_THRESHOLD_STUDS  = 150
local N_BUCKETS             = 4

local BOB_AMPLITUDE_STUDS = 0.5
local BOB_PERIOD_SECONDS = 1.5
local ROTATION_DEGREES_PER_SECOND = 6

local TAU = math.pi * 2
local BOB_FREQUENCY = TAU / BOB_PERIOD_SECONDS
local ROTATION_RADIANS_PER_SECOND = math.rad(ROTATION_DEGREES_PER_SECOND)

local log = Logger.new("LetterBlockAnimator")

type State = {
	basePosition: Vector3,
	phaseOffset: number,
	rotation: number,
	bucket: number,
}

local trackedBlocks: { [Model]: State } = {}

local function track(block: Instance)
	if not block:IsA("Model") then return end
	if trackedBlocks[block] then return end
	trackedBlocks[block] = {
		basePosition = block:GetPivot().Position,
		phaseOffset = math.random() * BOB_PERIOD_SECONDS,
		rotation = 0,
		bucket = math.random(0, N_BUCKETS - 1),
	}
end

local function untrack(block: Instance)
	if not block:IsA("Model") then return end
	trackedBlocks[block] = nil
end

for _, block in ipairs(CollectionService:GetTagged(LetterBlocks.TAG)) do
	track(block)
end

CollectionService:GetInstanceAddedSignal(LetterBlocks.TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG):Connect(untrack)

local frameCount = 0

RunService.Heartbeat:Connect(function(dt)
	frameCount = (frameCount + 1) % N_BUCKETS

	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local playerPos: Vector3? = if hrp then (hrp :: BasePart).Position else nil

	local now = os.clock()
	for block, state in pairs(trackedBlocks) do
		if block.Parent then
			state.rotation = (state.rotation + ROTATION_RADIANS_PER_SECOND * dt) % TAU

			local shouldUpdate: boolean
			if playerPos then
				local dist = (state.basePosition - playerPos).Magnitude
				if dist > FAR_THRESHOLD_STUDS then
					shouldUpdate = false
				elseif dist > NEAR_THRESHOLD_STUDS then
					shouldUpdate = state.bucket == frameCount
				else
					shouldUpdate = true
				end
			else
				shouldUpdate = true
			end

			if shouldUpdate then
				local bobOffset = math.sin((now + state.phaseOffset) * BOB_FREQUENCY) * BOB_AMPLITUDE_STUDS
				block:PivotTo(
					CFrame.new(state.basePosition + Vector3.new(0, bobOffset, 0))
					* CFrame.Angles(0, state.rotation, 0)
				)
			end
		else
			trackedBlocks[block] = nil
		end
	end
end)

log:info("LetterBlockAnimator started")
