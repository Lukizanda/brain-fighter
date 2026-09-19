--!strict

----------------------------------------------------------------------
-- RoundTimerBuilder
----------------------------------------------------------------------
-- View-only builder for the round state / timer strip. Contains no remote
-- wiring — RoundTimerGui listens to GameStateChanged and calls one of the
-- `show*` methods per payload.
----------------------------------------------------------------------

local RoundOutcomeCopy = require(script.Parent.RoundOutcomeCopy)
local RoundTimerConfig = require(script.Parent.RoundTimerConfig)

export type RoundTimer = {
	screenGui: ScreenGui,
	-- Whether the strip is on screen at all. A session whose mode runs no
	-- clock never puts a "0:00" up.
	setVisible: (self: RoundTimer, visible: boolean) -> (),
	showWaiting: (self: RoundTimer) -> (),
	showCountdown: (self: RoundTimer, secondsLeft: number) -> (),
	showActive: (self: RoundTimer, secondsLeft: number) -> (),
	showPostRound: (self: RoundTimer, outcome: string?, winnerName: string?, secondsToNext: number) -> (),
	destroy: (self: RoundTimer) -> (),
}

local SECONDS_PER_MINUTE = 60

local RoundTimerBuilder = {}

local function formatClock(seconds: number): string
	local mins = math.floor(seconds / SECONDS_PER_MINUTE)
	local secs = math.floor(seconds % SECONDS_PER_MINUTE)
	return string.format("%d:%02d", mins, secs)
end

function RoundTimerBuilder.build(): RoundTimer
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoundTimerGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local container = Instance.new("Frame")
	container.Name = "TimerContainer"
	container.Size = RoundTimerConfig.CONTAINER_SIZE
	container.Position = RoundTimerConfig.CONTAINER_POSITION
	container.AnchorPoint = RoundTimerConfig.CONTAINER_ANCHOR
	container.BackgroundColor3 = RoundTimerConfig.CONTAINER_COLOR
	container.BackgroundTransparency = RoundTimerConfig.CONTAINER_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false -- until a payload with a time limit arrives
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = RoundTimerConfig.CONTAINER_CORNER_RADIUS
	corner.Parent = container

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = RoundTimerConfig.TIMER_SIZE
	timerLabel.Position = RoundTimerConfig.TIMER_POSITION
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = RoundTimerConfig.WAITING_TEXT
	timerLabel.TextColor3 = RoundTimerConfig.WAITING_COLOR
	timerLabel.TextSize = RoundTimerConfig.TIMER_TEXT_SIZE
	timerLabel.Font = RoundTimerConfig.TIMER_FONT
	timerLabel.Parent = container

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Size = RoundTimerConfig.SUB_SIZE
	subLabel.Position = RoundTimerConfig.SUB_POSITION
	subLabel.BackgroundTransparency = 1
	subLabel.Text = ""
	subLabel.TextColor3 = RoundTimerConfig.SUB_COLOR
	subLabel.TextSize = RoundTimerConfig.SUB_TEXT_SIZE
	subLabel.Font = RoundTimerConfig.SUB_FONT
	subLabel.Parent = container

	local handle: RoundTimer = {
		screenGui = screenGui,

		setVisible = function(_self, visible: boolean)
			container.Visible = visible
		end,

		showWaiting = function(_self)
			timerLabel.Text = RoundTimerConfig.WAITING_TEXT
			timerLabel.TextColor3 = RoundTimerConfig.WAITING_COLOR
			subLabel.Text = ""
		end,

		showCountdown = function(_self, secondsLeft: number)
			timerLabel.Text = string.format(RoundTimerConfig.COUNTDOWN_FORMAT, math.ceil(secondsLeft))
			timerLabel.TextColor3 = RoundTimerConfig.COUNTDOWN_COLOR
			subLabel.Text = RoundTimerConfig.COUNTDOWN_SUB_TEXT
		end,

		showActive = function(_self, secondsLeft: number)
			timerLabel.Text = formatClock(secondsLeft)
			subLabel.Text = ""
			if secondsLeft <= RoundTimerConfig.DANGER_AT_SEC then
				timerLabel.TextColor3 = RoundTimerConfig.DANGER_COLOR
			elseif secondsLeft <= RoundTimerConfig.WARN_AT_SEC then
				timerLabel.TextColor3 = RoundTimerConfig.WARN_COLOR
			else
				timerLabel.TextColor3 = RoundTimerConfig.ACTIVE_COLOR
			end
		end,

		showPostRound = function(_self, outcome: string?, winnerName: string?, secondsToNext: number)
			-- The card carries the outcome title; the strip names the
			-- winner when there is one and otherwise repeats the title.
			if winnerName then
				timerLabel.Text = RoundOutcomeCopy.winnerLineFor(outcome, winnerName)
			else
				timerLabel.Text = RoundOutcomeCopy.titleFor(outcome)
			end
			timerLabel.TextColor3 = RoundTimerConfig.POST_ROUND_COLOR
			subLabel.Text = string.format(RoundTimerConfig.NEXT_ROUND_FORMAT, math.ceil(secondsToNext))
		end,

		destroy = function(self)
			self.screenGui:Destroy()
		end,
	}

	return handle
end

return RoundTimerBuilder
