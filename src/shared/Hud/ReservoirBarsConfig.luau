----------------------------------------------------------------------
-- ReservoirBarsConfig
----------------------------------------------------------------------
-- Styling overrides for the three EnergyReservoir bars (R/G/B).
-- Geometry defaults are inherited from AttributeBarConfig where not
-- specified here.
----------------------------------------------------------------------

local ReservoirBarsConfig = {
	-- Max value shown on each bar (EnergyReservoirs.CAP_PER_COLOR)
	MAX_ENERGY = 160,

	-- Per-color bar specs: passed to AttributeBarBuilder.build() as config
	BARS = {
		{ name = "Red",   color = Color3.fromRGB(215, 65, 65)  },
		{ name = "Green", color = Color3.fromRGB(60, 185, 85)  },
		{ name = "Blue",  color = Color3.fromRGB(65, 130, 225) },
	},

	-- Geometry overrides (AttributeBarConfig defaults apply otherwise)
	BAR_WIDTH  = 180,
	BAR_HEIGHT = 10,
	SHOW_LABEL   = true,
	SHOW_NUMERIC = true,
}

return ReservoirBarsConfig
