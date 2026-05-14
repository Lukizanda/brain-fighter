--!strict

----------------------------------------------------------------------
-- BossAdapter
----------------------------------------------------------------------
-- Spawns and tracks a Boss target for spell combat. Phase 3 MVP: a
-- static Model with a Humanoid that SpellExecutor can damage. No AI,
-- no movement — just a big visible target the player casts spells at.
--
-- The Boss is a chunky Part with a Humanoid so the existing
-- SpellExecutor damage/heal/freeze pipeline works out of the box
-- (resolveHumanoid finds the Humanoid from the Model).
--
-- See wiki/systems/BossAdapter.md.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BossAdapter")

local DEFAULT_MAX_HEALTH = 500
local DEFAULT_SPAWN_POSITION = Vector3.new(0, 5, -30)
local DEFAULT_BODY_SIZE = Vector3.new(6, 8, 6)
local BODY_COLOR = Color3.fromHex("#7c3aed")
local DESPAWN_DELAY_SEC = 2

export type Opts = {
	maxHealth: number?,
	position: Vector3?,
	bodySize: Vector3?,
	parent: Instance?,
}

local currentBoss: Model? = nil

local defeatedEvent = Instance.new("BindableEvent")
defeatedEvent.Name = "BossAdapterDefeated"

local BossAdapter = {}

BossAdapter.defeated = defeatedEvent.Event
BossAdapter.DEFAULT_MAX_HEALTH = DEFAULT_MAX_HEALTH
BossAdapter.DEFAULT_SPAWN_POSITION = DEFAULT_SPAWN_POSITION

function BossAdapter.spawn(opts: Opts?): Model
	if currentBoss then
		log:warn("spawn() called while a boss already exists — despawning old boss")
		BossAdapter.despawn()
	end

	local o = opts or {}
	local maxHealth = o.maxHealth or DEFAULT_MAX_HEALTH
	local position = o.position or DEFAULT_SPAWN_POSITION
	local bodySize = o.bodySize or DEFAULT_BODY_SIZE
	local parent = o.parent or workspace

	local model = Instance.new("Model")
	model.Name = "Boss"

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = bodySize
	body.Anchored = true
	body.CanCollide = true
	body.CanQuery = true
	body.Color = BODY_COLOR
	body.Material = Enum.Material.Neon
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	model.PrimaryPart = body

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.Parent = model

	humanoid.Died:Connect(function()
		log:info(string.format("Boss defeated (MaxHealth=%d)", maxHealth))
		defeatedEvent:Fire()
		task.delay(DESPAWN_DELAY_SEC, function()
			if currentBoss == model then
				model:Destroy()
				currentBoss = nil
			end
		end)
	end)

	model:PivotTo(CFrame.new(position))
	model.Parent = parent
	currentBoss = model

	log:info(string.format("Boss spawned at %s (HP=%d)", tostring(position), maxHealth))
	return model
end

function BossAdapter.getTarget(): Humanoid?
	if not currentBoss then
		return nil
	end
	return currentBoss:FindFirstChildOfClass("Humanoid")
end

function BossAdapter.getModel(): Model?
	return currentBoss
end

function BossAdapter.isAlive(): boolean
	if not currentBoss then
		return false
	end
	local humanoid = currentBoss:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function BossAdapter.despawn()
	if not currentBoss then
		return
	end
	local boss = currentBoss
	currentBoss = nil
	boss:Destroy()
	log:info("Boss despawned")
end

function BossAdapter.reset(opts: Opts?)
	BossAdapter.despawn()
	return BossAdapter.spawn(opts)
end

return BossAdapter
