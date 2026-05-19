----------------------------------------------------------------------
-- PlayerHudConfig
----------------------------------------------------------------------
-- Declarative list of attribute bars to render for the local player.
-- Adding a new stat means: write one adapter + add one row here.
--
-- Adapter resolution uses `script.Parent.Adapters.<Name>` so this file
-- doesn't need to know where it's mounted. PlayerHudConfig is required
-- from PlayerHud/init.client.luau, so `script.Parent` = PlayerHud.
----------------------------------------------------------------------

local Adapters = script.Parent:WaitForChild("Adapters")
local HealthAdapter = require(Adapters.HealthAdapter)
-- Shield + Stamina are disabled until their gameplay sources exist (no
-- shield regen, no stamina drain). Uncomment the require + the matching
-- bar entry below to re-enable.
-- local ShieldAdapter = require(Adapters.ShieldAdapter)
-- local StaminaAdapter = require(Adapters.StaminaAdapter)

export type BarEntry = {
	name: string,
	adapter: any, -- .new(character, bar) -> { destroy() }
	color: Color3,
	warningColor: Color3?,
	criticalColor: Color3?,
}

local PlayerHudConfig = {
	region = "BottomCenter", -- HudLayoutManager region; bars stack vertically here

	-- Order matters: first entry = highest on screen (furthest from eye).
	-- Keep critical bars (Health) at the bottom, less-urgent above visually,
	-- so combat-focus glances land on Health first.
	bars = {
		-- {
		-- 	name = "Stamina",
		-- 	adapter = StaminaAdapter,
		-- 	color = Color3.fromRGB(255, 200, 80),
		-- },
		-- {
		-- 	name = "Shield",
		-- 	adapter = ShieldAdapter,
		-- 	color = Color3.fromRGB(100, 150, 255),
		-- 	warningColor = Color3.fromRGB(80, 120, 220),
		-- 	criticalColor = Color3.fromRGB(60, 80, 180),
		-- },
		{
			name = "Health",
			adapter = HealthAdapter,
			color = Color3.fromRGB(80, 200, 80),
			warningColor = Color3.fromRGB(220, 180, 40),
			criticalColor = Color3.fromRGB(210, 60, 60),
		},
	} :: { BarEntry },
}

return PlayerHudConfig
