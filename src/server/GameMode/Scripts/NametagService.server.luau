----------------------------------------------------------------------
-- NametagService
----------------------------------------------------------------------
-- Attaches a team-coloured BillboardGui to each player's character so
-- teammate-vs-enemy reads at a glance during play. Server-driven so the
-- nametag replicates to every viewer; PlayerToHideFrom is set to the
-- nametag's owner so the local player doesn't see their own name.
--
-- Re-fires on every CharacterAdded (the old nametag dies with the old
-- head) and on Player.Team changes (covers a future menu pick-team
-- flow without losing the colour).
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("NametagService")

local OFFSET_Y = 3.2 -- studs above the head pivot
local TEXT_SIZE = 14
local MAX_DISTANCE = 200 -- studs; beyond this the nametag fades out (engine-managed)
local NEUTRAL_COLOR = Color3.fromRGB(220, 220, 220)

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
	-- Teams gate: when TEAMS_ENABLED is off the nametag stays neutral
	-- coloured even if a Team was set externally. The explicit gate is
	-- here so flipping the flag doesn't require re-spawning every player.
	label.TextColor3 = if GameConfig.TEAMS_ENABLED and player.Team
		then player.Team.TeamColor.Color
		else NEUTRAL_COLOR
	label.Parent = bbg

	return bbg
end

local function attachNametag(player: Player, character: Model)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
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
	player.CharacterAdded:Connect(function(character)
		-- Brief wait so Head is parented before we look it up.
		task.wait(0.1)
		attachNametag(player, character)
	end)
	-- Future: pick-your-team menu / party rebalance flips Player.Team
	-- mid-round; recolour without waiting for a respawn.
	player:GetPropertyChangedSignal("Team"):Connect(function()
		if player.Character then
			attachNametag(player, player.Character)
		end
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(watchPlayer, player)
end
Players.PlayerAdded:Connect(watchPlayer)

log:info("Initialized")
