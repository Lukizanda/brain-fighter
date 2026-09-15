----------------------------------------------------------------------
-- DeathScreenBuilder
----------------------------------------------------------------------
-- View-only builder for the death overlay + respawn countdown. Contains
-- no game logic — DeathScreenGui listens for Humanoid.Died / CharacterAdded
-- and drives `show`/`hide`.
--
-- `show`/`hide` toggle the overlay's own `Visible`, never the ScreenGui's
-- `Enabled` — that property belongs to HudGate once the coordinator binds
-- it. See wiki/concepts/HudGate.md § Owners never write the gated property.
----------------------------------------------------------------------

local DeathScreenConfig = require(script.Parent.DeathScreenConfig)

export type DeathScreen = {
	screenGui: ScreenGui,
	show: (self: DeathScreen, respawnTime: number) -> (),
	hide: (self: DeathScreen) -> (),
	destroy: (self: DeathScreen) -> (),
}

local DeathScreenBuilder = {}

function DeathScreenBuilder.build(): DeathScreen
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeathScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = DeathScreenConfig.OVERLAY_COLOR
	overlay.BackgroundTransparency = DeathScreenConfig.OVERLAY_TRANSPARENCY
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = screenGui

	local countdown = Instance.new("TextLabel")
	countdown.Size = DeathScreenConfig.COUNTDOWN_SIZE
	countdown.Position = DeathScreenConfig.COUNTDOWN_POSITION
	countdown.BackgroundTransparency = 1
	countdown.TextColor3 = DeathScreenConfig.COUNTDOWN_TEXT_COLOR
	countdown.Font = DeathScreenConfig.COUNTDOWN_FONT
	countdown.TextSize = DeathScreenConfig.COUNTDOWN_TEXT_SIZE
	countdown.Text = DeathScreenConfig.ELIMINATED_TEXT
	countdown.Parent = overlay

	local deathTime: number? = nil
	local countdownTask: thread? = nil

	local handle: DeathScreen = {
		screenGui = screenGui,
		hide = function(_self)
			overlay.Visible = false
			deathTime = nil
			if countdownTask then
				task.cancel(countdownTask)
				countdownTask = nil
			end
		end,
		show = function(_self, respawnTime: number)
			overlay.Visible = true
			deathTime = os.clock()

			countdownTask = task.spawn(function()
				local remaining = respawnTime
				while remaining > 0 and overlay.Visible do
					countdown.Text = string.format("Respawning in %d...", math.ceil(remaining))
					task.wait(DeathScreenConfig.TICK_SEC)
					remaining = respawnTime - (os.clock() - (deathTime :: number))
				end
				if overlay.Visible then
					countdown.Text = "Respawning..."
				end
			end)
		end,
		destroy = function(self)
			(self :: any):hide()
			self.screenGui:Destroy()
		end,
	}

	return handle
end

return DeathScreenBuilder
