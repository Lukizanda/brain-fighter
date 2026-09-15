--!strict

----------------------------------------------------------------------
-- BossHudBuilder
----------------------------------------------------------------------
-- View-only builder for the boss health bar + phase indicator. Contains
-- no remote wiring — BossHudGui listens to BossHealthChanged /
-- BossPhaseChanged and drives the handle.
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local BossHudConfig = require(script.Parent.BossHudConfig)

export type BossHud = {
	screenGui: ScreenGui,
	phaseLabel: TextLabel,
	setHealthFraction: (self: BossHud, fraction: number) -> (),
	setPhase: (self: BossHud, phaseIndex: number) -> (),
	setShown: (self: BossHud, shown: boolean) -> (),
	destroy: (self: BossHud) -> (),
}

local BossHudBuilder = {}

function BossHudBuilder.build(): BossHud
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BossHudGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local container = Instance.new("Frame")
	container.Name = "BossHud"
	container.Size = BossHudConfig.CONTAINER_SIZE
	container.Position = BossHudConfig.CONTAINER_POSITION
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.BackgroundColor3 = BossHudConfig.CONTAINER_COLOR
	container.BackgroundTransparency = BossHudConfig.CONTAINER_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false -- hidden until boss spawns
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = BossHudConfig.CORNER_RADIUS
	corner.Parent = container

	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = BossHudConfig.TOP_ROW_SIZE
	topRow.Position = BossHudConfig.TOP_ROW_POSITION
	topRow.BackgroundTransparency = 1
	topRow.Parent = container

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -60, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = BossHudConfig.NAME_COLOR
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextScaled = true
	nameLabel.Font = BossHudConfig.NAME_FONT
	nameLabel.Text = BossHudConfig.NAME_TEXT
	nameLabel.Parent = topRow

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "PhaseLabel"
	phaseLabel.Size = BossHudConfig.PHASE_SIZE
	phaseLabel.Position = BossHudConfig.PHASE_POSITION
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.TextColor3 = BossHudConfig.PHASE_COLOR
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Right
	phaseLabel.TextScaled = true
	phaseLabel.Font = BossHudConfig.PHASE_FONT
	phaseLabel.Text = BossHudConfig.PHASE_TEXT_DEFAULT
	phaseLabel.Visible = false -- hidden by default; toggled by the coordinator's debug hotkey
	phaseLabel.Parent = topRow

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = BossHudConfig.BAR_BG_SIZE
	barBg.Position = BossHudConfig.BAR_BG_POSITION
	barBg.BackgroundColor3 = BossHudConfig.BAR_BG_COLOR
	barBg.BorderSizePixel = 0
	barBg.ClipsDescendants = true
	barBg.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = BossHudConfig.BAR_CORNER_RADIUS
	barCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = BossHudConfig.BAR_FILL_COLOR
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = BossHudConfig.BAR_CORNER_RADIUS
	fillCorner.Parent = barFill

	local handle: BossHud = {
		screenGui = screenGui,
		phaseLabel = phaseLabel,
		setHealthFraction = function(_self, fraction: number)
			local clamped = math.clamp(fraction, 0, 1)
			TweenService:Create(barFill, BossHudConfig.BAR_TWEEN, {
				Size = UDim2.new(clamped, 0, 1, 0),
			}):Play()
		end,
		setPhase = function(_self, phaseIndex: number)
			local label = BossHudConfig.PHASE_LABELS[phaseIndex] or tostring(phaseIndex)
			phaseLabel.Text = "Phase " .. label
		end,
		setShown = function(_self, shown: boolean)
			container.Visible = shown
		end,
		destroy = function(self)
			self.screenGui:Destroy()
		end,
	}

	return handle
end

return BossHudBuilder
