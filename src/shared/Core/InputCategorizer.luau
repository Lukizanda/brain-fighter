--!strict

-- Sourced from Code Samples:
-- https://create.roblox.com/docs/samples
-- https://create.roblox.com/store/asset/13595021558/Input-Categorizer

local UserInputService = game:GetService("UserInputService")

local lastInputCategoryChangedEvent = Instance.new("BindableEvent")

type ActionCallback = (string, Enum.UserInputState, InputObject) -> ...any

local InputCategory = {
	KeyboardAndMouse = "KeyboardAndMouse",
	Gamepad = "Gamepad",
	Touch = "Touch",
	Unknown = "Unknown",
}

local InputCategorizer = {
	InputCategory = InputCategory,
	lastInputCategoryChanged = lastInputCategoryChangedEvent.Event,
	_lastInputCategory = InputCategory.Unknown,
	_debugOverride = nil :: string?,
	_initialized = false,
}

-- Return the last input category (or the debug override if one is set)
function InputCategorizer.getLastInputCategory()
	return InputCategorizer._debugOverride or InputCategorizer._lastInputCategory
end

-- Debug-only: force getLastInputCategory() to return a specific category
-- regardless of real input. Fires lastInputCategoryChanged so HUD widgets
-- gated on isTouch() / category re-evaluate immediately.
function InputCategorizer.setDebugOverride(category: string)
	if InputCategorizer._debugOverride == category then return end
	InputCategorizer._debugOverride = category
	lastInputCategoryChangedEvent:Fire(category)
end

-- Clear the debug override and restore real-input behavior. Re-fires the
-- signal with the actual current category so subscribers reset cleanly.
function InputCategorizer.clearDebugOverride()
	if InputCategorizer._debugOverride == nil then return end
	InputCategorizer._debugOverride = nil
	lastInputCategoryChangedEvent:Fire(InputCategorizer._lastInputCategory)
end

-- If _lastInputCategory and inputCategory are different, set _lastInputCategory and fire lastInputCategoryChanged
function InputCategorizer._setLastInputCategory(inputCategory: string)
	if InputCategorizer._lastInputCategory ~= inputCategory then
		InputCategorizer._lastInputCategory = inputCategory
		lastInputCategoryChangedEvent:Fire(inputCategory)
	end
end

-- Return an InputCategory based on the UserInputType
function InputCategorizer._getCategoryOfInputType(inputType: Enum.UserInputType)
	if string.find(inputType.Name, "Gamepad") then
		return InputCategory.Gamepad
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return InputCategory.KeyboardAndMouse
	elseif inputType == Enum.UserInputType.Touch then
		return InputCategory.Touch
	else
		return InputCategory.Unknown
	end
end

function InputCategorizer._onInputTypeChanged(inputType: Enum.UserInputType)
	local inputCategory = InputCategorizer._getCategoryOfInputType(inputType)
	if inputCategory ~= InputCategory.Unknown then
		InputCategorizer._setLastInputCategory(inputCategory)
	end
end

-- Return a default input category based on the current peripherals
function InputCategorizer._getDefaultInputCategory()
	local lastInputType = UserInputService:GetLastInputType()
	local lastInputCategory = InputCategorizer._getCategoryOfInputType(lastInputType)

	if lastInputCategory ~= InputCategory.Unknown then
		return lastInputCategory
	end

	if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		return InputCategory.KeyboardAndMouse
	elseif UserInputService.TouchEnabled then
		return InputCategory.Touch
	elseif UserInputService.GamepadEnabled then
		return InputCategory.Gamepad
	else
		warn("No input devices detected!")
		return InputCategory.Unknown
	end
end

function InputCategorizer._initialize()
	assert(not InputCategorizer._initialized, "InputCategorizer already initialized!")

	-- Update the last category when the last inputType changes
	UserInputService.LastInputTypeChanged:Connect(InputCategorizer._onInputTypeChanged)

	-- Set the starting input category
	local defaultInputCategory = InputCategorizer._getDefaultInputCategory()
	InputCategorizer._setLastInputCategory(defaultInputCategory)

	InputCategorizer._initialized = true
end

InputCategorizer._initialize()

return InputCategorizer
