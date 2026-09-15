----------------------------------------------------------------------
-- GameStateBuilder
----------------------------------------------------------------------
-- View-only builder for the end-of-round results overlay (winner + top
-- players + next-round countdown). Contains no remote wiring —
-- GameStateGui listens to GameStateChanged / ScoreUpdate and drives the
-- handle.
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local GameStateConfig = require(script.Parent.GameStateConfig)

export type ScoreEntry = {
	kills: number,
	deaths: number,
	assists: number,
	playerName: string,
}

export type GameState = {
	screenGui: ScreenGui,
	isShown: (self: GameState) -> boolean,
	show: (self: GameState) -> (),
	hide: (self: GameState) -> (),
	setWinner: (self: GameState, winnerName: string?) -> (),
	setNextRoundText: (self: GameState, text: string) -> (),
	setScores: (self: GameState, scores: { [number]: ScoreEntry }, localUserId: number) -> (),
	destroy: (self: GameState) -> (),
}

local GameStateBuilder = {}

function GameStateBuilder.build(): GameState
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameStateGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = GameStateConfig.OVERLAY_COLOR
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = screenGui

	local centerFrame = Instance.new("Frame")
	centerFrame.Name = "CenterFrame"
	centerFrame.Size = GameStateConfig.CENTER_SIZE
	centerFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	centerFrame.BackgroundColor3 = GameStateConfig.CENTER_COLOR
	centerFrame.BackgroundTransparency = GameStateConfig.CENTER_TRANSPARENCY
	centerFrame.BorderSizePixel = 0
	centerFrame.Parent = overlay
	Instance.new("UICorner", centerFrame).CornerRadius = GameStateConfig.CENTER_CORNER_RADIUS

	local centerLayout = Instance.new("UIListLayout")
	centerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	centerLayout.Padding = GameStateConfig.CENTER_LIST_PADDING
	centerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	centerLayout.Parent = centerFrame

	local centerPadding = Instance.new("UIPadding")
	centerPadding.PaddingTop = GameStateConfig.CENTER_PADDING
	centerPadding.PaddingBottom = GameStateConfig.CENTER_PADDING
	centerPadding.PaddingLeft = GameStateConfig.CENTER_PADDING
	centerPadding.PaddingRight = GameStateConfig.CENTER_PADDING
	centerPadding.Parent = centerFrame

	local roundOverLabel = Instance.new("TextLabel")
	roundOverLabel.Size = UDim2.new(1, 0, 0, 30)
	roundOverLabel.BackgroundTransparency = 1
	roundOverLabel.Text = GameStateConfig.ROUND_OVER_TEXT
	roundOverLabel.TextColor3 = GameStateConfig.ROUND_OVER_COLOR
	roundOverLabel.TextSize = GameStateConfig.ROUND_OVER_TEXT_SIZE
	roundOverLabel.Font = Enum.Font.GothamBold
	roundOverLabel.LayoutOrder = 1
	roundOverLabel.Parent = centerFrame

	local winnerLabel = Instance.new("TextLabel")
	winnerLabel.Size = UDim2.new(1, 0, 0, 28)
	winnerLabel.BackgroundTransparency = 1
	winnerLabel.Text = ""
	winnerLabel.TextColor3 = GameStateConfig.WINNER_COLOR
	winnerLabel.TextSize = GameStateConfig.WINNER_TEXT_SIZE
	winnerLabel.Font = Enum.Font.GothamBold
	winnerLabel.LayoutOrder = 2
	winnerLabel.Parent = centerFrame

	local topPlayersFrame = Instance.new("Frame")
	topPlayersFrame.Size = UDim2.new(1, 0, 0, GameStateConfig.TOP_PLAYERS_HEIGHT)
	topPlayersFrame.BackgroundTransparency = 1
	topPlayersFrame.LayoutOrder = 3
	topPlayersFrame.Parent = centerFrame

	local topPlayersLayout = Instance.new("UIListLayout")
	topPlayersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topPlayersLayout.Padding = GameStateConfig.TOP_PLAYERS_LIST_PADDING
	topPlayersLayout.Parent = topPlayersFrame

	local nextRoundLabel = Instance.new("TextLabel")
	nextRoundLabel.Size = UDim2.new(1, 0, 0, 24)
	nextRoundLabel.BackgroundTransparency = 1
	nextRoundLabel.Text = ""
	nextRoundLabel.TextColor3 = GameStateConfig.NEXT_ROUND_TEXT_COLOR
	nextRoundLabel.TextSize = GameStateConfig.NEXT_ROUND_TEXT_SIZE
	nextRoundLabel.Font = Enum.Font.Gotham
	nextRoundLabel.LayoutOrder = 4
	nextRoundLabel.Parent = centerFrame

	local currentScores: { [number]: ScoreEntry } = {}
	local currentLocalUserId = 0

	local function refreshTopPlayers()
		for _, child in topPlayersFrame:GetChildren() do
			if child:IsA("Frame") then child:Destroy() end
		end

		local sorted = {}
		for userId, data in currentScores do
			table.insert(sorted, { userId = userId, data = data })
		end
		table.sort(sorted, function(a, b) return a.data.kills > b.data.kills end)

		local maxShow = math.min(#sorted, GameStateConfig.TOP_PLAYERS_MAX_SHOWN)
		for rank = 1, maxShow do
			local entry = sorted[rank]
			local data = entry.data
			local isLocal = entry.userId == currentLocalUserId

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, GameStateConfig.TOP_PLAYERS_ROW_HEIGHT)
			row.BackgroundColor3 = isLocal and GameStateConfig.ROW_LOCAL_COLOR or GameStateConfig.ROW_OTHER_COLOR
			row.BackgroundTransparency = GameStateConfig.ROW_TRANSPARENCY
			row.BorderSizePixel = 0
			row.LayoutOrder = rank
			row.Parent = topPlayersFrame
			Instance.new("UICorner", row).CornerRadius = GameStateConfig.ROW_CORNER_RADIUS

			local rankLabel = Instance.new("TextLabel")
			rankLabel.Size = UDim2.new(0.1, 0, 1, 0)
			rankLabel.BackgroundTransparency = 1
			rankLabel.Text = "#" .. rank
			rankLabel.TextColor3 = rank == 1 and GameStateConfig.RANK_FIRST_COLOR or GameStateConfig.RANK_OTHER_COLOR
			rankLabel.TextSize = GameStateConfig.RANK_TEXT_SIZE
			rankLabel.Font = Enum.Font.GothamBold
			rankLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.5, 0, 1, 0)
			nameLabel.Position = UDim2.new(0.1, 0, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = data.playerName
			nameLabel.TextColor3 = isLocal and GameStateConfig.NAME_LOCAL_COLOR or GameStateConfig.NAME_OTHER_COLOR
			nameLabel.TextSize = GameStateConfig.NAME_TEXT_SIZE
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = row

			local statsLabel = Instance.new("TextLabel")
			statsLabel.Size = UDim2.new(0.4, 0, 1, 0)
			statsLabel.Position = UDim2.new(0.6, 0, 0, 0)
			statsLabel.BackgroundTransparency = 1
			statsLabel.Text = string.format("%d K / %d D / %d A", data.kills, data.deaths, data.assists)
			statsLabel.TextColor3 = GameStateConfig.STATS_TEXT_COLOR
			statsLabel.TextSize = GameStateConfig.STATS_TEXT_SIZE
			statsLabel.Font = Enum.Font.Gotham
			statsLabel.Parent = row
		end
	end

	local handle: GameState = {
		screenGui = screenGui,
		isShown = function(_self)
			return overlay.Visible
		end,
		show = function(_self)
			overlay.Visible = true
			overlay.BackgroundTransparency = 1
			TweenService:Create(overlay, TweenInfo.new(GameStateConfig.SHOW_HIDE_TWEEN_SEC), {
				BackgroundTransparency = GameStateConfig.OVERLAY_SHOWN_TRANSPARENCY,
			}):Play()
			refreshTopPlayers()
		end,
		hide = function(_self)
			local tween = TweenService:Create(overlay, TweenInfo.new(GameStateConfig.SHOW_HIDE_TWEEN_SEC), { BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			overlay.Visible = false
		end,
		setWinner = function(_self, winnerName: string?)
			winnerLabel.Text = winnerName and ("Winner: " .. winnerName) or GameStateConfig.NO_WINNER_TEXT
		end,
		setNextRoundText = function(_self, text: string)
			nextRoundLabel.Text = text
		end,
		setScores = function(_self, scores: { [number]: ScoreEntry }, localUserId: number)
			currentScores = scores
			currentLocalUserId = localUserId
			if overlay.Visible then
				refreshTopPlayers()
			end
		end,
		destroy = function(self)
			self.screenGui:Destroy()
		end,
	}

	return handle
end

return GameStateBuilder
