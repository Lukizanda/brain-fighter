--!strict

----------------------------------------------------------------------
-- TrainingDummyGui
----------------------------------------------------------------------
-- Puts a health readout over every rig tagged `TrainingDummy` and pops a
-- damage number on it whenever its health moves. Phase 6 polish: the hub
-- dummy is where a player finds out what an attack spell is worth, and a
-- Humanoid losing health silently told them nothing.
--
-- No remote in the read path. `Humanoid.Health` replicates on its own, so
-- the delta between two replicated values *is* the damage — the same
-- number `applyDamage` computed, without a second wire to keep in step.
-- One consequence worth knowing: two hits inside a single replication
-- batch arrive as one change and read as one combined number. For a
-- practice target that is the honest total, and a spell that ticks shows
-- its ticks, so it is left alone.
--
-- Death is not special-cased away. The rig explodes (DeathHandler) and
-- respawns as a fresh clone, which arrives through the same tag signal
-- as the original and gets a new readout.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local TrainingDummyBuilder = require(ReplicatedStorage.Shared.Hud.TrainingDummyBuilder)

local log = Logger.new("TrainingDummyGui")

-- The rig replicates a piece at a time, so the Humanoid and the part the
-- readout hangs from may not be there on the frame the tag arrives.
local PART_WAIT_SEC = 10

type Entry = {
	readout: TrainingDummyBuilder.TrainingDummyReadout,
	connections: { RBXScriptConnection },
}

local entries: { [Model]: Entry } = {}

local function detach(rig: Model)
	local entry = entries[rig]
	if not entry then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.readout:destroy()
	entries[rig] = nil
end

local function attach(rig: Model)
	if entries[rig] then
		return
	end

	local humanoid = rig:WaitForChild("Humanoid", PART_WAIT_SEC) :: Humanoid?
	if not humanoid then
		log:warn(string.format("%s has no Humanoid after %ds - no readout", rig.Name, PART_WAIT_SEC))
		return
	end

	local anchor = rig:WaitForChild("Head", PART_WAIT_SEC) :: BasePart?
	if not anchor or not anchor:IsA("BasePart") then
		log:warn(string.format("%s has no Head after %ds - no readout", rig.Name, PART_WAIT_SEC))
		return
	end

	-- The rig can be untagged or destroyed while the waits above are
	-- running, and a second `attach` can win the race in the meantime.
	if entries[rig] or not rig.Parent or not CollectionService:HasTag(rig, HealthConstants.TRAINING_DUMMY_TAG) then
		return
	end

	local readout = TrainingDummyBuilder.build(anchor)
	readout.gui.Parent = anchor
	readout:setHealth(humanoid.Health, humanoid.MaxHealth)
	readout:setVisible(humanoid.Health > 0)

	local lastHealth = humanoid.Health

	local connections = {
		humanoid.HealthChanged:Connect(function(health: number)
			local delta = lastHealth - health
			lastHealth = health

			readout:setHealth(health, humanoid.MaxHealth)
			readout:popDelta(delta)
			-- The corpse is about to go transparent and blow apart; a bar
			-- reading 0 / 100 floating over the debris is not a readout.
			readout:setVisible(health > 0)
		end),

		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			readout:setHealth(humanoid.Health, humanoid.MaxHealth)
		end),

		rig.AncestryChanged:Connect(function(_, parent: Instance?)
			if not parent then
				detach(rig)
			end
		end),
	}

	entries[rig] = { readout = readout, connections = connections }
	log:info(string.format("Readout attached to %s (%d/%d HP)",
		rig.Name, humanoid.Health, humanoid.MaxHealth))
end

local function onTagged(instance: Instance)
	if not instance:IsA("Model") then
		log:warn(string.format("%s tag on non-Model: %s (%s)",
			HealthConstants.TRAINING_DUMMY_TAG, instance.Name, instance.ClassName))
		return
	end
	-- `attach` waits on replication, so it must not block the signal.
	task.spawn(attach, instance)
end

local function onUntagged(instance: Instance)
	if instance:IsA("Model") then
		detach(instance)
	end
end

CollectionService:GetInstanceAddedSignal(HealthConstants.TRAINING_DUMMY_TAG):Connect(onTagged)
CollectionService:GetInstanceRemovedSignal(HealthConstants.TRAINING_DUMMY_TAG):Connect(onUntagged)

for _, instance in CollectionService:GetTagged(HealthConstants.TRAINING_DUMMY_TAG) do
	onTagged(instance)
end

log:info("Initialized")
