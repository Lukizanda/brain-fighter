----------------------------------------------------------------------
-- ScoreboardBuilder
----------------------------------------------------------------------
-- View-only builder for the Tab-to-open scoreboard. Contains no input or
-- remote wiring — ScoreboardGui owns the toggle key and the ScoreUpdate
-- remote, and calls `setVisible` / `setScores`.
----------------------------------------------------------------------

local ScoreboardConfig = require(script.Parent.ScoreboardConfig)

export type ScoreEntry = {
	kills: number,
	deaths: number,
	assists: number,
	playerName: string,
}

export type Scoreboard = {
	screenGui: ScreenGui,
	setVisible: (self: Scoreboard, visible: boolean) -> (),
	setScores: (self: Scoreboard, scores: { [number]: ScoreEntry }, localUserId: number) -> (),
	destroy: (self: Scoreboard) -> (),
}

local ScoreboardBuilder = {}

function ScoreboardBuilder.build(): Scoreboard
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScoreboardGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local dimmer = Instance.new("Frame")
	dimmer.Name = "Dimmer"
	dimmer.Size = UDim2.new(1, 0, 1, 0)
	dimmer.BackgroundColor3 = ScoreboardConfig.DIMMER_COLOR
	dimmer.BackgroundTransparency = ScoreboardConfig.DIMMER_TRANSPARENCY
	dimmer.BorderSizePixel = 0
	dimmer.Visible = false
	dimmer.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "ScoreboardPanel"
	panel.Size = ScoreboardConfig.PANEL_SIZE
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = ScoreboardConfig.PANEL_COLOR
	panel.BackgroundTransparency = ScoreboardConfig.PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = ScoreboardConfig.PANEL_CORNER_RADIUS
	panelCorner.Parent = panel

	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = UDim.new(0, 8)
	panelPadding.PaddingBottom = UDim.new(0, 8)
	panelPadding.PaddingLeft = UDim.new(0, 12)
	panelPadding.PaddingRight = UDim.new(0, 12)
	panelPadding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = ScoreboardConfig.TITLE_TEXT
	title.TextColor3 = ScoreboardConfig.TITLE_COLOR
	title.TextSize = ScoreboardConfig.TITLE_TEXT_SIZE
	title.Font = ScoreboardConfig.TITLE_FONT
	title.Parent = panel

	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "Header"
	headerFrame.Size = UDim2.new(1, 0, 0, ScoreboardConfig.HEADER_HEIGHT)
	headerFrame.Position = UDim2.new(0, 0, 0, 34)
	headerFrame.BackgroundColor3 = ScoreboardConfig.HEADER_BG_COLOR
	headerFrame.BackgroundTransparency = ScoreboardConfig.HEADER_BG_TRANSPARENCY
	headerFrame.BorderSizePixel = 0
	headerFrame.Parent = panel
	Instance.new("UICorner", headerFrame).CornerRadius = ScoreboardConfig.HEADER_CORNER_RADIUS

	local xOffset = 0
	for i, headerText in ScoreboardConfig.HEADERS do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(ScoreboardConfig.COLUMN_WIDTHS[i], 0, 1, 0)
		label.Position = UDim2.new(xOffset, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = headerText
		label.TextColor3 = ScoreboardConfig.HEADER_TEXT_COLOR
		label.TextSize = ScoreboardConfig.HEADER_TEXT_SIZE
		label.Font = ScoreboardConfig.HEADER_FONT
		label.Parent = headerFrame
		xOffset += ScoreboardConfig.COLUMN_WIDTHS[i]
	end

	local rowsScroll = Instance.new("ScrollingFrame")
	rowsScroll.Name = "Rows"
	rowsScroll.Size = UDim2.new(1, 0, 1, -72)
	rowsScroll.Position = UDim2.new(0, 0, 0, 70)
	rowsScroll.BackgroundTransparency = 1
	rowsScroll.BorderSizePixel = 0
	rowsScroll.ScrollBarThickness = 4
	rowsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	rowsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rowsScroll.Parent = panel

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, 2)
	rowsLayout.Parent = rowsScroll

	local function refreshRows(scores: { [number]: ScoreEntry }, localUserId: number)
		for _, child in rowsScroll:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local sorted = {}
		for userId, data in scores do
			table.insert(sorted, { userId = userId, data = data })
		end
		table.sort(sorted, function(a, b)
			return a.data.kills > b.data.kills
		end)

		for rank, entry in sorted do
			local data = entry.data
			local isLocal = entry.userId == localUserId

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, ScoreboardConfig.ROW_HEIGHT)
			row.BackgroundColor3 = isLocal and ScoreboardConfig.ROW_LOCAL_COLOR or ScoreboardConfig.ROW_OTHER_COLOR
			row.BackgroundTransparency = isLocal and ScoreboardConfig.ROW_LOCAL_TRANSPARENCY or ScoreboardConfig.ROW_OTHER_TRANSPARENCY
			row.BorderSizePixel = 0
			row.LayoutOrder = rank
			row.Parent = rowsScroll
			Instance.new("UICorner", row).CornerRadius = ScoreboardConfig.ROW_CORNER_RADIUS

			local kd = data.deaths > 0 and string.format("%.1f", data.kills / data.deaths) or tostring(data.kills)
			local values = { data.playerName, tostring(data.kills), tostring(data.deaths), tostring(data.assists), kd }
			local textColor = isLocal and ScoreboardConfig.ROW_LOCAL_TEXT_COLOR or ScoreboardConfig.ROW_OTHER_TEXT_COLOR

			local x = 0
			for i, value in values do
				local label = Instance.new("TextLabel")
				label.Size = UDim2.new(ScoreboardConfig.COLUMN_WIDTHS[i], 0, 1, 0)
				label.Position = UDim2.new(x, 0, 0, 0)
				label.BackgroundTransparency = 1
				label.Text = value
				label.TextColor3 = textColor
				label.TextSize = ScoreboardConfig.ROW_TEXT_SIZE
				label.Font = i == 1 and ScoreboardConfig.ROW_NAME_FONT or ScoreboardConfig.ROW_VALUE_FONT
				label.TextXAlignment = i == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
				label.Parent = row

				if i == 1 then
					local padding = Instance.new("UIPadding")
					padding.PaddingLeft = ScoreboardConfig.ROW_NAME_PADDING_LEFT
					padding.Parent = label
				end

				x += ScoreboardConfig.COLUMN_WIDTHS[i]
			end
		end
	end

	local lastScores: { [number]: ScoreEntry } = {}
	local lastLocalUserId = 0

	local handle: Scoreboard = {
		screenGui = screenGui,
		setVisible = function(_self, visible: boolean)
			dimmer.Visible = visible
			panel.Visible = visible
			if visible then
				refreshRows(lastScores, lastLocalUserId)
			end
		end,
		setScores = function(_self, scores: { [number]: ScoreEntry }, localUserId: number)
			lastScores = scores
			lastLocalUserId = localUserId
			if panel.Visible then
				refreshRows(scores, localUserId)
			end
		end,
		destroy = function(self)
			self.screenGui:Destroy()
		end,
	}

	return handle
end

return ScoreboardBuilder
