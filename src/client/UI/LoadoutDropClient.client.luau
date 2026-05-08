----------------------------------------------------------------------
-- LoadoutDropClient
----------------------------------------------------------------------
-- Phase 3C client-side drop UX:
--   1. Bind G via ContextActionService → fire LoadoutRequestDrop.
--   2. Listen for LoadoutDropRejected → show a 2-second fading toast in
--      the bottom-center HUD region with the server-supplied reason.
--
-- The server is the source of truth on whether a drop is allowed
-- (zone-gated by RespawnZoneService). Mirroring zone presence client-
-- side would duplicate the Touched/TouchEnded bookkeeping for the sake
-- of saving one ~50ms round-trip; the cost isn't worth it for a single-
-- key action. Round-trip latency is well below human perception of
-- "instant feedback" for a key-down event.
----------------------------------------------------------------------

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LoadoutDropClient")

local DROP_KEY = Enum.KeyCode.G
local DROP_ACTION_NAME = "LoadoutDrop"
local TOAST_VISIBLE_DURATION = 2 -- seconds the toast stays at full opacity
local TOAST_FADE_DURATION = 0.4
local TOAST_BG_COLOR = Color3.fromRGB(20, 20, 25)
local TOAST_BG_ALPHA = 0.25
local TOAST_TEXT_COLOR = Color3.fromRGB(255, 220, 120)

local localPlayer = Players.LocalPlayer
local requestDrop = ReplicatedStorage.Shared.Loadout.Remotes.LoadoutRequestDrop
local dropRejected = ReplicatedStorage.Shared.Loadout.Remotes.LoadoutDropRejected

----------------------------------------------------------------------
-- Toast container — registered once with HudLayoutManager.
-- Each toast adds a child Frame that fades itself out and self-destructs.
----------------------------------------------------------------------
local toastStack = Instance.new("Frame")
toastStack.Name = "LoadoutDropToastStack"
toastStack.Size = UDim2.new(1, 0, 0, 0)
toastStack.AutomaticSize = Enum.AutomaticSize.Y
toastStack.BackgroundTransparency = 1

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 4)
layout.Parent = toastStack

HudLayoutManager:register("BottomCenter", toastStack)

local function showToast(message: string)
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.Size = UDim2.new(0, 0, 0, 28)
	toast.BackgroundColor3 = TOAST_BG_COLOR
	toast.BackgroundTransparency = TOAST_BG_ALPHA
	toast.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = toast

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = toast

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.TextSize = 14
	label.Text = message
	label.TextColor3 = TOAST_TEXT_COLOR
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.5
	label.Parent = toast

	toast.Parent = toastStack

	task.delay(TOAST_VISIBLE_DURATION, function()
		if not toast.Parent then
			return
		end
		local tweenInfo = TweenInfo.new(TOAST_FADE_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		TweenService:Create(toast, tweenInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, tweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(TOAST_FADE_DURATION, function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Input + remote wiring
----------------------------------------------------------------------
local function onDropAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		requestDrop:FireServer()
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(DROP_ACTION_NAME, onDropAction, false, DROP_KEY)
ContextActionService:SetTitle(DROP_ACTION_NAME, "Drop")

dropRejected.OnClientEvent:Connect(function(reason: string?)
	-- Only surface user-actionable rejections. "no equipped weapon" /
	-- "no character" reasons aren't worth a UI nudge — the player
	-- already knows.
	if typeof(reason) ~= "string" or reason == "" then
		return
	end
	if reason:match("^Drop") then
		showToast(reason)
	end
end)

log:info("Initialized")
