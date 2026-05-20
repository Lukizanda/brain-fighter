--!strict
----------------------------------------------------------------------
-- BufferDisplayBuilder
----------------------------------------------------------------------
-- Horizontal row of letter tiles showing the current WordBuffer state.
-- Empty slots show a dim placeholder.
--
-- Interaction (when onReorder is provided):
--   Tap-to-swap  — tap a tile to select (gold border); tap another to
--                  swap positions; tap same tile or empty slot cancels.
--   Drag-to-reorder — drag a tile; semi-transparent ghost follows the
--                  cursor; dropping over a target tile reorders them.
--   Both modes work on mouse and touch; drop triggers a snap-flash.
--
-- Returned handle:
--   .gui             Frame to register with HudLayoutManager
--   :setTiles(t)     update display from a WordBuffer:tiles() snapshot
--   :destroy()       clean up
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Defaults = require(ReplicatedStorage.Shared.Hud.BufferDisplayConfig)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BufferDisplay")

-- ── Interaction constants ─────────────────────────────────────────
local DRAG_THRESHOLD_PX = 8
local GHOST_TRANSPARENCY = 0.45
local GHOST_ZINDEX = 20
local SELECTION_STROKE_NAME = "SelectionStroke"
local SELECTION_STROKE_COLOR = Color3.fromRGB(255, 215, 0)
local SELECTION_STROKE_THICKNESS = 2
local SNAP_FLASH_DURATION = 0.18
local PULSE_STROKE_NAME      = "MindFullPulseStroke"
local VALID_WORD_STROKE_NAME = "ValidWordStroke"

export type Tile = { letter: string, color: string }

export type BuildOptions = {
	onReorder: ((fromIdx: number, toIdx: number) -> ())?,
	onRemove: ((idx: number) -> ())?,
}

export type Handle = {
	gui: Frame,
	setTiles: (self: Handle, tiles: { Tile }) -> (),
	popTile: (self: Handle, idx: number) -> (),
	setMindFullPulse: (self: Handle, active: boolean) -> (),
	setValidWordGlow: (self: Handle, active: boolean) -> (),
	playMemorizeOk: (self: Handle) -> (),
	playMemorizeFail: (self: Handle) -> (),
	destroy: (self: Handle) -> (),
}

local BufferDisplayBuilder = {}

local function makeTileCell(): (Frame, TextLabel)
	local cell = Instance.new("Frame")
	cell.Size = UDim2.new(0, Defaults.TILE_WIDTH, 0, Defaults.TILE_HEIGHT)
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

function BufferDisplayBuilder.build(options: BuildOptions?): Handle
	local onReorder = options and options.onReorder or nil
	local onRemove = options and options.onRemove or nil

	local cap = Defaults.CAP
	local cellWidth = Defaults.TILE_WIDTH
	local gap = Defaults.TILE_GAP
	local totalWidth = cellWidth * cap + gap * (cap - 1)

	local container = Instance.new("Frame")
	container.Name = "BufferDisplay"
	container.Size = UDim2.new(0, totalWidth, 0, Defaults.TILE_HEIGHT)
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

	-- ── Interaction state ─────────────────────────────────────────
	local currentTiles: { Tile } = {}
	local selectedIdx: number? = nil
	local dragFrom: number? = nil
	local dragStartPos: Vector2? = nil
	local isDragging = false
	local dragGhost: Frame? = nil
	local connections: { RBXScriptConnection } = {}
	local pulseStrokeTweens: { Tween } = {}
	local validWordStrokeTweens: { Tween } = {}

	-- ── Helpers ───────────────────────────────────────────────────

	local function clearSelectionStroke()
		for i = 1, cap do
			local s = cells[i]:FindFirstChild(SELECTION_STROKE_NAME)
			if s then s:Destroy() end
		end
	end

	local function setSelectionHighlight(idx: number?)
		clearSelectionStroke()
		if idx and currentTiles[idx] then
			local stroke = Instance.new("UIStroke")
			stroke.Name = SELECTION_STROKE_NAME
			stroke.Color = SELECTION_STROKE_COLOR
			stroke.Thickness = SELECTION_STROKE_THICKNESS
			stroke.Parent = cells[idx]
		end
	end

	local function snapFlash(idx: number)
		local cell = cells[idx]
		local origTrans = cell.BackgroundTransparency
		cell.BackgroundTransparency = 0
		local tween = TweenService:Create(
			cell,
			TweenInfo.new(SNAP_FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = origTrans }
		)
		tween:Play()
	end

	local function destroyGhost()
		if dragGhost then
			dragGhost:Destroy()
			dragGhost = nil
		end
	end

	local function cancelAll()
		selectedIdx = nil
		dragFrom = nil
		dragStartPos = nil
		isDragging = false
		destroyGhost()
		clearSelectionStroke()
	end

	local function getCellIndexAtPos(screenPos: Vector2): number?
		for i = 1, cap do
			local ap = cells[i].AbsolutePosition
			local as_ = cells[i].AbsoluteSize
			if
				screenPos.X >= ap.X
				and screenPos.X <= ap.X + as_.X
				and screenPos.Y >= ap.Y
				and screenPos.Y <= ap.Y + as_.Y
			then
				return i
			end
		end
		return nil
	end

	-- Center the ghost on the cursor.
	-- Ghost Position.Offset is in ScreenGui UI-space (pre-UIScale). The ghost's
	-- visual half-size in screen pixels = TILE_W/H * scale, so dividing through
	-- gives the clean form below, which avoids reading AbsoluteSize before the
	-- first layout pass has rendered the ghost.
	local function moveGhost(ghost: Frame, screenPos: Vector2)
		local screenGui = HudLayoutManager:getScreenGui()
		local uiScaleObj = screenGui:FindFirstChildWhichIsA("UIScale")
		local scale = if uiScaleObj then uiScaleObj.Scale else 1
		local sgAbsPos = screenGui.AbsolutePosition
		ghost.Position = UDim2.fromOffset(
			(screenPos.X - sgAbsPos.X) / scale - Defaults.TILE_WIDTH / 2,
			(screenPos.Y - sgAbsPos.Y) / scale - Defaults.TILE_HEIGHT / 2
		)
	end

	local function createGhost(fromIdx: number): Frame
		local src = cells[fromIdx]
		local ghost = Instance.new("Frame")
		ghost.Name = "DragGhost"
		ghost.Size = UDim2.fromOffset(Defaults.TILE_WIDTH, Defaults.TILE_HEIGHT)
		ghost.BackgroundColor3 = src.BackgroundColor3
		ghost.BackgroundTransparency = GHOST_TRANSPARENCY
		ghost.BorderSizePixel = 0
		ghost.ZIndex = GHOST_ZINDEX

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		corner.Parent = ghost

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Letter"
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Defaults.TEXT_FONT
		lbl.TextSize = Defaults.TEXT_SIZE
		lbl.TextColor3 = Defaults.TEXT_COLOR
		lbl.TextStrokeTransparency = Defaults.TEXT_STROKE_TRANSPARENCY
		lbl.Text = labels[fromIdx].Text
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.ZIndex = GHOST_ZINDEX
		lbl.Parent = ghost

		ghost.Parent = HudLayoutManager:getScreenGui()
		return ghost
	end

	-- ── Per-cell input: record which tile the gesture started on ──
	for i = 1, cap do
		local idx = i
		local conn = cells[i].InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			if dragFrom ~= nil then
				return
			end
			dragFrom = idx
			dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
			isDragging = false
			log:info(string.format("InputBegan cell %d", idx))
		end)
		table.insert(connections, conn)
	end

	-- ── Global: move ghost while dragging ─────────────────────────
	local inputChangedConn = UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragFrom == nil then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if not isDragging then
			local startPos = dragStartPos
			if startPos and (pos - startPos).Magnitude >= DRAG_THRESHOLD_PX then
				if currentTiles[dragFrom] then
					isDragging = true
					dragGhost = createGhost(dragFrom)
					moveGhost(dragGhost, pos)
					log:info(string.format("Drag started cell %d", dragFrom))
				else
					dragFrom = nil
				end
			end
		else
			if dragGhost then
				moveGhost(dragGhost, pos)
			end
		end
	end)
	table.insert(connections, inputChangedConn)

	-- ── Global: commit or cancel on release ───────────────────────
	local inputEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragFrom == nil then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local endPos = Vector2.new(input.Position.X, input.Position.Y)
		local fromIdx = dragFrom :: number

		if isDragging then
			-- ── Drag path ────────────────────────────────────────
			destroyGhost()
			dragFrom = nil
			dragStartPos = nil
			isDragging = false
			local targetIdx = getCellIndexAtPos(endPos)
			if targetIdx and targetIdx ~= fromIdx and currentTiles[fromIdx] and onReorder then
				onReorder(fromIdx, targetIdx)
				snapFlash(targetIdx)
				log:info(string.format("Drag reorder %d → %d", fromIdx, targetIdx))
			end
		else
			-- ── Tap path ─────────────────────────────────────────
			dragFrom = nil
			dragStartPos = nil
			local tappedIdx = fromIdx

			if not currentTiles[tappedIdx] then
				-- Empty slot — cancel any pending selection
				cancelAll()
				log:info("Tapped empty slot, cancelled")
				return
			end

			if selectedIdx == nil then
				selectedIdx = tappedIdx
				setSelectionHighlight(tappedIdx)
				log:info(string.format("Selected cell %d", tappedIdx))
			elseif selectedIdx == tappedIdx then
				local removeIdx = selectedIdx :: number
				cancelAll()
				if onRemove then
					onRemove(removeIdx)
					log:info(string.format("Tap destroy cell %d", removeIdx))
				end
			else
				local fromSel = selectedIdx :: number
				cancelAll()
				if onReorder then
					onReorder(fromSel, tappedIdx)
					snapFlash(tappedIdx)
					log:info(string.format("Tap swap %d → %d", fromSel, tappedIdx))
				end
			end
		end
	end)
	table.insert(connections, inputEndedConn)

	-- ── Handle ────────────────────────────────────────────────────
	local handle = { gui = container } :: Handle

	function handle:setTiles(tiles: { Tile })
		-- Update cached snapshot used by interaction code
		currentTiles = {}
		for i, t in tiles do
			currentTiles[i] = t
		end

		for i = 1, cap do
			local tile = tiles[i]
			local cell = cells[i]
			local label = labels[i]
			if tile then
				local tileColor = Defaults.TILE_COLORS[tile.color] or Defaults.TILE_COLORS.blue
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

		-- Re-apply selection stroke after visual reset (the stroke is a child
		-- Instance and survives BackgroundColor3 changes, but explicitly re-sync
		-- in case the tile at selectedIdx became empty after a remove).
		if selectedIdx then
			setSelectionHighlight(selectedIdx)
		end
	end

	function handle:popTile(idx: number)
		local cell = cells[idx]
		if not cell then return end
		local scaleInst = cell:FindFirstChildOfClass("UIScale")
		if not scaleInst then
			scaleInst = Instance.new("UIScale")
			scaleInst.Parent = cell
		end
		scaleInst.Scale = Defaults.POP_SCALE
		TweenService:Create(scaleInst, Defaults.POP_TWEEN, { Scale = 1 }):Play()
	end

	function handle:setMindFullPulse(active: boolean)
		for _, t in pulseStrokeTweens do
			t:Cancel()
		end
		table.clear(pulseStrokeTweens)
		for i = 1, cap do
			local s = cells[i]:FindFirstChild(PULSE_STROKE_NAME)
			if active then
				if not s then
					local newStroke = Instance.new("UIStroke")
					newStroke.Name = PULSE_STROKE_NAME
					newStroke.Color = Defaults.PULSE_STROKE_COLOR
					newStroke.Parent = cells[i]
					s = newStroke
				end
				local t = TweenService:Create(s :: UIStroke, Defaults.PULSE_TWEEN, { Transparency = 0.5 })
				t:Play()
				table.insert(pulseStrokeTweens, t)
			elseif s then
				s:Destroy()
			end
		end
	end

	function handle:setValidWordGlow(active: boolean)
		for _, t in validWordStrokeTweens do t:Cancel() end
		table.clear(validWordStrokeTweens)

		for i = 1, cap do
			local cell = cells[i]
			local tile = currentTiles[i]

			if active and tile then
				local s = cell:FindFirstChild(VALID_WORD_STROKE_NAME)
				if not s then
					local newStroke = Instance.new("UIStroke")
					newStroke.Name = VALID_WORD_STROKE_NAME
					newStroke.Color = Defaults.VALID_WORD_STROKE_COLOR
					newStroke.Thickness = Defaults.VALID_WORD_STROKE_THICKNESS
					newStroke.Parent = cell
					s = newStroke
				end
				local strokeTween = TweenService:Create(s :: UIStroke, Defaults.VALID_WORD_STROKE_PULSE, { Transparency = 0.5 })
				strokeTween:Play()
				table.insert(validWordStrokeTweens, strokeTween)
			else
				local s = cell:FindFirstChild(VALID_WORD_STROKE_NAME)
				if s then s:Destroy() end
			end
		end
	end

	function handle:playMemorizeOk()
		for i = 1, cap do
			if currentTiles[i] then
				TweenService:Create(cells[i], Defaults.MEMORIZE_FADE, { BackgroundTransparency = 1 }):Play()
				TweenService:Create(labels[i], Defaults.MEMORIZE_FADE, { TextTransparency = 1 }):Play()
			end
		end
		task.delay(Defaults.MEMORIZE_FADE.Time, function()
			if not container.Parent then return end
			handle:setTiles({})
			for i = 1, cap do
				labels[i].TextTransparency = 0
			end
		end)
	end

	function handle:playMemorizeFail()
		for i = 1, cap do
			if currentTiles[i] then
				local origColor = cells[i].BackgroundColor3
				TweenService:Create(cells[i], Defaults.REJECT_TWEEN, { BackgroundColor3 = Defaults.REJECT_COLOR }):Play()
				task.delay(Defaults.REJECT_TWEEN.Time, function()
					if cells[i] and cells[i].Parent then
						TweenService:Create(cells[i], Defaults.REJECT_TWEEN, { BackgroundColor3 = origColor }):Play()
					end
				end)
			end
		end
		local origPos = container.Position
		local shakeStep = Defaults.SHAKE_DURATION_SEC / (Defaults.SHAKE_CYCLES * 2)
		task.spawn(function()
			for _ = 1, Defaults.SHAKE_CYCLES do
				if not container.Parent then return end
				container.Position = UDim2.new(
					origPos.X.Scale, origPos.X.Offset + Defaults.SHAKE_OFFSET_PX,
					origPos.Y.Scale, origPos.Y.Offset
				)
				task.wait(shakeStep)
				if not container.Parent then return end
				container.Position = UDim2.new(
					origPos.X.Scale, origPos.X.Offset - Defaults.SHAKE_OFFSET_PX,
					origPos.Y.Scale, origPos.Y.Offset
				)
				task.wait(shakeStep)
			end
			if container.Parent then
				container.Position = origPos
			end
		end)
	end

	function handle:destroy()
		cancelAll()
		for _, t in pulseStrokeTweens do t:Cancel() end
		table.clear(pulseStrokeTweens)
		for _, t in validWordStrokeTweens do t:Cancel() end
		table.clear(validWordStrokeTweens)
		for _, conn in connections do conn:Disconnect() end
		table.clear(connections)
		container:Destroy()
	end

	return handle
end

return BufferDisplayBuilder
