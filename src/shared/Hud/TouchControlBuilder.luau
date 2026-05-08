----------------------------------------------------------------------
-- TouchControlBuilder
----------------------------------------------------------------------
local TouchControlConfig = require(script.Parent.TouchControlConfig)

local TouchControlBuilder = {}

function TouchControlBuilder.build(configOverrides: { [string]: any }?)
	local config = TouchControlConfig
	if configOverrides then
		config = table.clone(TouchControlConfig)
		for k, v in configOverrides do
			config[k] = v
		end
	end

	local container = Instance.new("Frame")
	container.Name = "TouchControls"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local shootButton = Instance.new("ImageButton")
	shootButton.Name = "ShootButton"
	shootButton.Size = config.SHOOT_SIZE
	shootButton.Position = config.SHOOT_POSITION
	shootButton.BackgroundColor3 = config.SHOOT_COLOR
	shootButton.BackgroundTransparency = config.SHOOT_TRANSPARENCY
	shootButton.BorderSizePixel = 0
	shootButton.Image = ""
	shootButton.Parent = container

	local shootCorner = Instance.new("UICorner")
	shootCorner.CornerRadius = config.SHOOT_CORNER_RADIUS
	shootCorner.Parent = shootButton

	local reloadButton = Instance.new("ImageButton")
	reloadButton.Name = "ReloadButton"
	reloadButton.Size = config.RELOAD_SIZE
	reloadButton.Position = config.RELOAD_POSITION
	reloadButton.BackgroundColor3 = config.RELOAD_COLOR
	reloadButton.BackgroundTransparency = config.RELOAD_TRANSPARENCY
	reloadButton.BorderSizePixel = 0
	reloadButton.Image = ""
	reloadButton.Parent = container

	local reloadCorner = Instance.new("UICorner")
	reloadCorner.CornerRadius = config.RELOAD_CORNER_RADIUS
	reloadCorner.Parent = reloadButton

	local reloadLabel = Instance.new("TextLabel")
	reloadLabel.Name = "Label"
	reloadLabel.Size = UDim2.fromScale(1, 1)
	reloadLabel.BackgroundTransparency = 1
	reloadLabel.Font = config.RELOAD_FONT
	reloadLabel.TextSize = config.RELOAD_TEXT_SIZE
	reloadLabel.TextColor3 = config.RELOAD_TEXT_COLOR
	reloadLabel.Text = config.RELOAD_LABEL
	reloadLabel.Parent = reloadButton

	local handle = {}
	handle.gui = container
	handle.shootButton = shootButton
	handle.reloadButton = reloadButton

	function handle:destroy()
		container:Destroy()
	end

	return handle
end

return TouchControlBuilder
