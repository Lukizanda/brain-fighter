local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InputCategorizer = require(ReplicatedStorage.Shared.Core.InputCategorizer)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local TouchControlBuilder = require(ReplicatedStorage.Shared.Hud.TouchControlBuilder)

local WeaponTouchInputController = {}
WeaponTouchInputController.__index = WeaponTouchInputController

function WeaponTouchInputController.new(weapon: Tool)
	-- Code-driven touch controls (replaces the Studio-built TouchGui)
	local touchHandle = TouchControlBuilder.build()
	touchHandle.gui.Visible = false
	HudLayoutManager:register(HudConstants.TOUCH_CONTROLS_REGION, touchHandle.gui)

	local self = {
		weapon = weapon,
		touchHandle = touchHandle,
		enabled = false,
		connections = {},
		reloadCallback = nil :: (() -> ())?,
		shootInputObject = nil :: InputObject?,
	}
	setmetatable(self, WeaponTouchInputController)
	return self
end

function WeaponTouchInputController:enableTouchInput()
	self.touchHandle.gui.Visible = true
	-- Since we're going to be manually activating the weapon with a gui button, we disable the default tool activation
	self.weapon.ManualActivationOnly = true
end

function WeaponTouchInputController:disableTouchInput()
	self.touchHandle.gui.Visible = false
	self.weapon.ManualActivationOnly = false
end

function WeaponTouchInputController:onReloadButtonInput(inputObject: InputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if self.reloadCallback then
		self.reloadCallback()
	end
end

function WeaponTouchInputController:onShootButtonInput(inputObject: InputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- Save this inputObject as the current object being held to shoot. InputObjects are persistent as long
	-- as the user's finger stays down, so we can check later to see if this input has stopped.
	self.shootInputObject = inputObject
	self.weapon:Activate()
end

-- Since the user may swipe off of the shoot button by aiming around, we need to listen to all input ended
-- events in order to check when they actually stop holding the shoot button.
function WeaponTouchInputController:onInputEnded(inputObject: InputObject)
	if self.shootInputObject == inputObject then
		self.shootInputObject = nil
		self.weapon:Deactivate()
	end
end

function WeaponTouchInputController:setReloadCallback(callback: () -> ())
	self.reloadCallback = callback
end

function WeaponTouchInputController:enable()
	if self.enabled then
		return
	end

	self.enabled = true

	table.insert(
		self.connections,
		InputCategorizer.lastInputCategoryChanged:Connect(function(lastInputCategory)
			self:onLastInputCategoryChanged(lastInputCategory)
		end)
	)

	table.insert(
		self.connections,
		self.touchHandle.shootButton.InputBegan:Connect(function(inputObject: InputObject)
			-- Change events will fire even though we're listening to InputBegan, we need to ignore those
			if inputObject.UserInputState == Enum.UserInputState.Change then
				return
			end
			self:onShootButtonInput(inputObject)
		end)
	)

	table.insert(
		self.connections,
		self.touchHandle.reloadButton.InputBegan:Connect(function(inputObject: InputObject)
			-- Change events will fire even though we're listening to InputBegan, we need to ignore those
			if inputObject.UserInputState == Enum.UserInputState.Change then
				return
			end
			self:onReloadButtonInput(inputObject)
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(inputObject: InputObject)
			self:onInputEnded(inputObject)
		end)
	)

	local lastInputCategory = InputCategorizer.getLastInputCategory()
	self:onLastInputCategoryChanged(lastInputCategory)
end

function WeaponTouchInputController:disable()
	if not self.enabled then
		return
	end

	self.enabled = false
	self:disableTouchInput()
	disconnectAndClear(self.connections)
end

function WeaponTouchInputController:onLastInputCategoryChanged(lastInputCategory)
	if lastInputCategory == InputCategorizer.InputCategory.Touch then
		self:enableTouchInput()
	else
		self:disableTouchInput()
	end
end

function WeaponTouchInputController:destroy()
	self:disable()
	self.touchHandle:destroy()
end

return WeaponTouchInputController
