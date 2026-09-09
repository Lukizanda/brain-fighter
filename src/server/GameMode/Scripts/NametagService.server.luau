----------------------------------------------------------------------
-- NametagService
----------------------------------------------------------------------
-- Attaches a BillboardGui carrying the player's name to each character so
-- who-is-who reads at a glance during play. Server-driven so the nametag
-- replicates to every viewer; PlayerToHideFrom is set to the nametag's
-- owner so the local player doesn't see their own name.
--
-- Re-fires on every CharacterAdded (the old nametag dies with the old
-- head). One neutral colour: the team tint this used to carry went with
-- the rest of the team plumbing in refactor chunk 8.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("NametagService")

local OFFSET_Y = 3.2 -- studs above the head pivot
local TEXT_SIZE = 14
local MAX_DISTANCE = 200 -- studs; beyond this the nametag fades out (engine-managed)
local NAME_COLOR = Color3.fromRGB(220, 220, 220)
-- Seconds to let the Head parent before looking it up on CharacterAdded.
local HEAD_SETTLE_SEC = 0.1
-- Seconds to wait for a Head on a character that has none yet.
local HEAD_WAIT_SEC = 5

local function buildNametag(player: Player): BillboardGui
	local bbg = Instance.new("BillboardGui")
	bbg.Name = "Nametag"
	bbg.Size = UDim2.new(0, 200, 0, 30)
	bbg.StudsOffset = Vector3.new(0, OFFSET_Y, 0)
	bbg.AlwaysOnTop = false -- hide behind walls; combat reads need LOS
	bbg.MaxDistance = MAX_DISTANCE
	bbg.PlayerToHideFrom = player

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = TEXT_SIZE
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = player.Name
	label.TextColor3 = NAME_COLOR
	label.Parent = bbg

	return bbg
end

local function attachNametag(player: Player, character: Model)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", HEAD_WAIT_SEC)
	if not head then
		return
	end
	local existing = head:FindFirstChild("Nametag")
	if existing then
		existing:Destroy()
	end
	local bbg = buildNametag(player)
	bbg.Parent = head
end

local function watchPlayer(player: Player)
	if player.Character then
		attachNametag(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character: Model)
		task.wait(HEAD_SETTLE_SEC)
		attachNametag(player, character)
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(watchPlayer, player)
end
Players.PlayerAdded:Connect(watchPlayer)

log:info("Initialized")
