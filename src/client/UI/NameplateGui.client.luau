--!strict

----------------------------------------------------------------------
-- NameplateGui
----------------------------------------------------------------------
-- Puts a nameplate — name, health bar, damage numbers — over every
-- combatant the local player can look at: every *other* player, and
-- every rig tagged `TrainingDummy`.
--
-- Both go through the same builder on purpose. The hub dummy is the only
-- safe place to learn what an attack spell is worth, so it has to teach
-- the display a real opponent will show; a dummy with its own bespoke
-- readout would be teaching the wrong lesson. Treating "player" and
-- "training dummy" as two kinds of combatant is what keeps them honest.
--
-- Replaces `NametagService` (server, name only). One plate, one owner:
-- two BillboardGuis fighting over the same head is exactly the split the
-- Single Ownership rule exists to stop, and the health half has to be
-- client-side anyway — see below.
--
-- No remote in the read path. `Humanoid.Health` replicates on its own, so
-- the delta between two replicated values *is* the damage — the same
-- number `applyDamage` computed, without a second wire to keep in step.
-- One consequence worth knowing: two hits inside a single replication
-- batch arrive as one change and read as one combined number. For a
-- practice target that is the honest total, and a spell that ticks shows
-- its ticks, so it is left alone.
--
-- The local player gets no plate — they have the HUD health bar, and the
-- old nametag hid itself from its owner for the same reason.
--
-- Nothing here runs per frame. The plate is sized in studs, so the engine
-- shrinks it with its rig and it stays proportionate at any range without
-- the camera being tracked at all — see `NameplateConfig`.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NameplateBuilder = require(ReplicatedStorage.Shared.Hud.NameplateBuilder)

local log = Logger.new("NameplateGui")

local localPlayer = Players.LocalPlayer

-- A rig replicates a piece at a time, so the Humanoid and the part the
-- plate hangs from may not be there on the frame we first hear about it.
local PART_WAIT_SEC = 10
-- Player-facing name for a non-player rig. Without one the plate would
-- read "TargetDummy", which is an instance name, not a label.
local LABEL_ATTRIBUTE = "NameplateLabel"

type Entry = {
	plate: NameplateBuilder.Nameplate,
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
	entry.plate:destroy()
	entries[rig] = nil
end

local function attach(rig: Model, name: string)
	if entries[rig] then
		return
	end

	local humanoid = rig:WaitForChild("Humanoid", PART_WAIT_SEC) :: Humanoid?
	if not humanoid then
		log:warn(string.format("%s has no Humanoid after %ds - no nameplate", rig.Name, PART_WAIT_SEC))
		return
	end

	local anchor = rig:WaitForChild("Head", PART_WAIT_SEC) :: BasePart?
	if not anchor or not anchor:IsA("BasePart") then
		log:warn(string.format("%s has no Head after %ds - no nameplate", rig.Name, PART_WAIT_SEC))
		return
	end

	-- The rig can be destroyed while the waits above are running, and a
	-- second `attach` can win the race in the meantime.
	if entries[rig] or not rig.Parent then
		return
	end

	local plate = NameplateBuilder.build(anchor)
	plate.gui.Parent = anchor
	plate:setName(name)
	plate:setHealth(humanoid.Health, humanoid.MaxHealth)
	plate:setVisible(humanoid.Health > 0)

	local lastHealth = humanoid.Health

	local connections = {
		humanoid.HealthChanged:Connect(function(health: number)
			local delta = lastHealth - health
			lastHealth = health

			plate:setHealth(health, humanoid.MaxHealth)
			plate:popDelta(delta)
			-- A corpse is about to go transparent, or blow apart; a bar
			-- reading 0 / 100 over the debris is not a readout.
			plate:setVisible(health > 0)
		end),

		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			plate:setHealth(humanoid.Health, humanoid.MaxHealth)
		end),

		rig.AncestryChanged:Connect(function(_, parent: Instance?)
			if not parent then
				detach(rig)
			end
		end),
	}

	entries[rig] = { plate = plate, connections = connections }
	log:info(string.format("Nameplate attached to %s (%d/%d HP)", name, humanoid.Health, humanoid.MaxHealth))
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end

	local function onCharacter(character: Model)
		task.spawn(attach, character, player.Name)
	end

	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(detach)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

----------------------------------------------------------------------
-- Training dummies
----------------------------------------------------------------------

local function onDummyTagged(instance: Instance)
	if not instance:IsA("Model") then
		log:warn(string.format("%s tag on non-Model: %s (%s)",
			HealthConstants.TRAINING_DUMMY_TAG, instance.Name, instance.ClassName))
		return
	end
	local label = instance:GetAttribute(LABEL_ATTRIBUTE)
	local name = if type(label) == "string" and label ~= "" then label else instance.Name
	-- `attach` waits on replication, so it must not block the signal.
	task.spawn(attach, instance, name)
end

local function onDummyUntagged(instance: Instance)
	if instance:IsA("Model") then
		detach(instance)
	end
end

CollectionService:GetInstanceAddedSignal(HealthConstants.TRAINING_DUMMY_TAG):Connect(onDummyTagged)
CollectionService:GetInstanceRemovedSignal(HealthConstants.TRAINING_DUMMY_TAG):Connect(onDummyUntagged)

for _, instance in CollectionService:GetTagged(HealthConstants.TRAINING_DUMMY_TAG) do
	onDummyTagged(instance)
end

log:info("Initialized")
