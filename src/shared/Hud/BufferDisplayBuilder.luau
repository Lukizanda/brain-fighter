----------------------------------------------------------------------
-- BufferDisplayBuilder
----------------------------------------------------------------------
-- Horizontal row of letter tiles showing the current WordBuffer state.
-- Empty slots show a dim placeholder. Purely visual.
--
-- Returned handle:
--   .gui             Frame to register with HudLayoutManager
--   :setTiles(t)     update display from a WordBuffer:tiles() snapshot
--   :destroy()       clean up
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defaults = require(ReplicatedStorage.Shared.Hud.BufferDisplayConfig)

export type Tile = { letter: string, color: string }

export type Handle = {
	gui: Frame,
	setTiles: (self: Handle, tiles: { Tile }) -> (),
	destroy: (self: Handle) -> (),
}

local BufferDisplayBuilder = {}

local function makeTileCell(): (Frame, TextLabel)
	local cell = Instance.new("Frame")
	cell.Size = UDim2.new(0, Defaults.TILE_SIZE, 0, Defaults.TILE_SIZE)
	cell.BackgroundColor3 = Defaults.EMPTY_COLOR
	cell.BackgroundTransparency = Defaults.EMPTY_TRANSPARENCY
	cell.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
	corner.Parent = cell

	local label = Instance.new("TextLabel")
	label.Name = "Letter"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Defaults.TEXT_FONT
	label.TextSize = Defaults.TEXT_SIZE
	label.TextColor3 = Defaults.EMPTY_TEXT_COLOR
	label.TextStrokeTransparency = Defaults.TEXT_STROKE_TRANSPARENCY
	label.Text = Defaults.EMPTY_TEXT
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = cell

	return cell, label
end

function BufferDisplayBuilder.build(): Handle
	local cap = Defaults.CAP
	local cellWidth = Defaults.TILE_SIZE
	local gap = Defaults.TILE_GAP
	local totalWidth = cellWidth * cap + gap * (cap - 1)

	local container = Instance.new("Frame")
	container.Name = "BufferDisplay"
	container.Size = UDim2.new(0, totalWidth, 0, Defaults.TILE_SIZE)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local cells: { Frame } = {}
	local labels: { TextLabel } = {}

	for i = 1, cap do
		local cell, label = makeTileCell()
		cell.LayoutOrder = i
		cell.Parent = container
		cells[i] = cell
		labels[i] = label
	end

	local handle = { gui = container } :: Handle

	function handle:setTiles(tiles: { Tile })
		for i = 1, cap do
			local tile = tiles[i]
			local cell = cells[i]
			local label = labels[i]
			if tile then
				local tileColor = Defaults.TILE_COLORS[tile.color]
					or Defaults.TILE_COLORS.blue
				cell.BackgroundColor3 = tileColor
				cell.BackgroundTransparency = Defaults.TILE_TRANSPARENCY
				label.Text = string.upper(tile.letter)
				label.TextColor3 = Defaults.TEXT_COLOR
			else
				cell.BackgroundColor3 = Defaults.EMPTY_COLOR
				cell.BackgroundTransparency = Defaults.EMPTY_TRANSPARENCY
				label.Text = Defaults.EMPTY_TEXT
				label.TextColor3 = Defaults.EMPTY_TEXT_COLOR
			end
		end
	end

	function handle:destroy()
		container:Destroy()
	end

	return handle
end

return BufferDisplayBuilder
