----------------------------------------------------------------------
-- ReservoirBarsBuilder
----------------------------------------------------------------------
-- Three stacked energy bars (red / green / blue). Reuses
-- AttributeBarBuilder for each color; this module stacks them and
-- exposes a single `:setEnergy(snapshot)` update call.
--
-- Returned handle:
--   .gui               Frame to register with HudLayoutManager
--   :setEnergy(snap)   push EnergyReservoirs:snapshot() to all bars
--   :destroy()         clean up all bars
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defaults            = require(ReplicatedStorage.Shared.Hud.ReservoirBarsConfig)
local AttributeBarBuilder = require(ReplicatedStorage.Shared.Hud.AttributeBarBuilder)
local AttributeBarConfig  = require(ReplicatedStorage.Shared.Hud.AttributeBarConfig)

export type Snapshot = { red: number, green: number, blue: number }

export type Handle = {
	gui: Frame,
	setEnergy: (self: Handle, snapshot: Snapshot) -> (),
	destroy: (self: Handle) -> (),
}

-- Map bar label → snapshot key
local COLOR_KEY: { [string]: string } = {
	Red   = "red",
	Green = "green",
	Blue  = "blue",
}

local ReservoirBarsBuilder = {}

function ReservoirBarsBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "ReservoirBars"
	container.Size = UDim2.new(0, Defaults.BAR_WIDTH, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, AttributeBarConfig.BAR_SPACING)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local bars: { [string]: AttributeBarBuilder.Handle } = {}

	for i, spec in Defaults.BARS do
		local barHandle = AttributeBarBuilder.build({
			name        = spec.name,
			color       = spec.color,
			width       = Defaults.BAR_WIDTH,
			height      = Defaults.BAR_HEIGHT,
			showLabel   = Defaults.SHOW_LABEL,
			showNumeric = Defaults.SHOW_NUMERIC,
		})
		barHandle.gui.LayoutOrder = i
		barHandle.gui.Parent = container
		bars[spec.name] = barHandle
	end

	local handle = { gui = container } :: Handle

	local lastEnergy: { [string]: number } = { red = 0, green = 0, blue = 0 }

	function handle:setEnergy(snapshot: Snapshot)
		for _, spec in Defaults.BARS do
			local key = COLOR_KEY[spec.name]
			local energy: number = (snapshot :: any)[key] or 0
			local prev: number = (lastEnergy :: any)[key] or 0
			local delta = energy - prev
			local bar = bars[spec.name]

			bar:setValue(energy, Defaults.MAX_ENERGY)

			if delta >= AttributeBarConfig.GAIN_SWEEP_DELTA_MIN then
				bar:playGainSweep()
			elseif delta <= -AttributeBarConfig.DRAIN_DELTA_MIN then
				bar:playDrainRipple()
			end

			if energy >= Defaults.MAX_ENERGY and prev < Defaults.MAX_ENERGY then
				bar:setCapGlow(true)
			elseif energy < Defaults.MAX_ENERGY and prev >= Defaults.MAX_ENERGY then
				bar:setCapGlow(false)
			end

			;(lastEnergy :: any)[key] = energy
		end
	end

	function handle:destroy()
		for _, bar in bars do
			bar:destroy()
		end
		container:Destroy()
	end

	return handle
end

return ReservoirBarsBuilder
