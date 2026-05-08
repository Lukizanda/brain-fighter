----------------------------------------------------------------------
-- BuffTrayBuilder
----------------------------------------------------------------------
-- Horizontal row of active-buff icons for the local player. Each icon
-- shows the buff's icon asset, stack count (if >1), and a countdown
-- bar for remaining duration.
--
-- This is SCAFFOLD ONLY — the gameplay buff system (where buffs come
-- from, how they apply effects, how they expire) isn't built yet. The
-- tray exposes an API the future Buff system can push into:
--
--   tray:addBuff(id, info)          -- info = { icon, duration, stacks, polarity }
--   tray:updateBuff(id, info)       -- refresh remaining time / stacks
--   tray:removeBuff(id)
--
-- A future BuffAdapter will listen to server-pushed events (RemoteEvent,
-- character attribute map, or child Buff instances under the character)
-- and call these methods.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Hud.BuffIconConfig)

export type Polarity = "Buff" | "Debuff" | "Neutral"

export type BuffInfo = {
	icon: string?,        -- rbxassetid URL; if nil, tray shows a colored rectangle
	duration: number?,    -- total seconds; if nil, icon has no countdown
	appliedAt: number?,   -- os.clock() when applied; derived if nil
	stacks: number?,      -- >1 shows a stack count badge
	polarity: Polarity?,  -- border color category; default "Buff"
}

export type Handle = {
	gui: Frame,
	addBuff: (self: Handle, id: string, info: BuffInfo) -> (),
	updateBuff: (self: Handle, id: string, info: BuffInfo) -> (),
	removeBuff: (self: Handle, id: string) -> (),
	destroy: (self: Handle) -> (),
}

local BuffTrayBuilder = {}

local function borderColorFor(polarity: Polarity?): Color3
	if polarity == "Debuff" then
		return Config.DEBUFF_BORDER_COLOR
	elseif polarity == "Neutral" then
		return Config.NEUTRAL_BORDER_COLOR
	end
	return Config.BUFF_BORDER_COLOR
end

-- Build a single icon frame. Returned table holds refs for updateBuff.
type IconWidgets = {
	frame: Frame,
	stroke: UIStroke,
	iconImage: ImageLabel,
	countdownFill: Frame,
	stackText: TextLabel,
	info: BuffInfo,
}

local function buildIcon(info: BuffInfo): IconWidgets
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, Config.ICON_SIZE, 0, Config.ICON_SIZE)
	frame.BackgroundColor3 = Config.BACKGROUND_COLOR
	frame.BackgroundTransparency = Config.BACKGROUND_TRANSPARENCY
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Config.CORNER_RADIUS)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Config.BORDER_THICKNESS
	stroke.Color = borderColorFor(info.polarity)
	stroke.Parent = frame

	local iconImage = Instance.new("ImageLabel")
	iconImage.Size = UDim2.new(1, -4, 1, -4)
	iconImage.Position = UDim2.new(0, 2, 0, 2)
	iconImage.BackgroundTransparency = 1
	iconImage.Image = info.icon or ""
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Parent = frame

	local countdownFill = Instance.new("Frame")
	countdownFill.AnchorPoint = Vector2.new(0, 1)
	countdownFill.Position = UDim2.new(0, 0, 1, 0)
	countdownFill.Size = UDim2.new(1, 0, 0, Config.COUNTDOWN_BAR_HEIGHT)
	countdownFill.BackgroundColor3 = Config.COUNTDOWN_BAR_COLOR
	countdownFill.BackgroundTransparency = Config.COUNTDOWN_BAR_TRANSPARENCY
	countdownFill.BorderSizePixel = 0
	countdownFill.Visible = info.duration ~= nil
	countdownFill.Parent = frame

	local stackText = Instance.new("TextLabel")
	stackText.AnchorPoint = Vector2.new(1, 1)
	stackText.Position = UDim2.new(1, -2, 1, -Config.COUNTDOWN_BAR_HEIGHT - 2)
	stackText.Size = UDim2.new(0, 16, 0, 14)
	stackText.BackgroundTransparency = 1
	stackText.Font = Config.STACK_FONT
	stackText.TextSize = Config.STACK_TEXT_SIZE
	stackText.TextColor3 = Config.STACK_TEXT_COLOR
	stackText.TextStrokeTransparency = Config.STACK_STROKE_TRANSPARENCY
	stackText.TextXAlignment = Enum.TextXAlignment.Right
	stackText.TextYAlignment = Enum.TextYAlignment.Bottom
	stackText.Text = if info.stacks and info.stacks > 1 then tostring(info.stacks) else ""
	stackText.Parent = frame

	return {
		frame = frame,
		stroke = stroke,
		iconImage = iconImage,
		countdownFill = countdownFill,
		stackText = stackText,
		info = info,
	}
end

function BuffTrayBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "BuffTray"
	container.Size = UDim2.new(0, 0, 0, Config.ICON_SIZE)
	container.AutomaticSize = Enum.AutomaticSize.X
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Config.ICON_SPACING)
	layout.Parent = container

	local icons: { [string]: IconWidgets } = {}
	local heartbeatConn: RBXScriptConnection? = nil

	-- Tick the countdown fill for any buff with a duration.
	local function tickCountdowns()
		local now = os.clock()
		for _, widgets in icons do
			local info = widgets.info
			if info.duration and info.appliedAt then
				local elapsed = now - info.appliedAt
				local remaining = math.max(0, info.duration - elapsed)
				local fraction = remaining / info.duration
				widgets.countdownFill.Size = UDim2.new(fraction, 0, 0, Config.COUNTDOWN_BAR_HEIGHT)
			end
		end
	end

	local function ensureHeartbeat()
		if heartbeatConn then return end
		heartbeatConn = RunService.Heartbeat:Connect(tickCountdowns)
	end

	local function stopHeartbeatIfEmpty()
		if next(icons) == nil and heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end

	local handle = { gui = container } :: Handle

	function handle:addBuff(id: string, info: BuffInfo)
		if icons[id] then
			-- Refresh if already present
			handle:updateBuff(id, info)
			return
		end
		info.appliedAt = info.appliedAt or os.clock()
		local widgets = buildIcon(info)
		widgets.frame.Parent = container
		icons[id] = widgets
		ensureHeartbeat()
	end

	function handle:updateBuff(id: string, info: BuffInfo)
		local widgets = icons[id]
		if not widgets then
			handle:addBuff(id, info)
			return
		end
		-- Merge: keep previous appliedAt unless a new one is given
		info.appliedAt = info.appliedAt or widgets.info.appliedAt or os.clock()
		widgets.info = info
		widgets.stroke.Color = borderColorFor(info.polarity)
		widgets.iconImage.Image = info.icon or ""
		widgets.countdownFill.Visible = info.duration ~= nil
		widgets.stackText.Text = if info.stacks and info.stacks > 1 then tostring(info.stacks) else ""
	end

	function handle:removeBuff(id: string)
		local widgets = icons[id]
		if not widgets then return end
		widgets.frame:Destroy()
		icons[id] = nil
		stopHeartbeatIfEmpty()
	end

	function handle:destroy()
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		container:Destroy()
	end

	return handle
end

return BuffTrayBuilder
