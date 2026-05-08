local ServerScriptService = game:GetService("ServerScriptService")

local validateInstance = require(ServerScriptService.Server.Utility.TypeValidation.validateInstance)
local validateNumber = require(ServerScriptService.Server.Utility.TypeValidation.validateNumber)
local validateCFrame = require(ServerScriptService.Server.Utility.TypeValidation.validateCFrame)
local validateSimpleTable = require(ServerScriptService.Server.Utility.TypeValidation.validateSimpleTable)

local function taggedValidator(instance: any): boolean
	return validateInstance(instance, "Humanoid")
end

local function validateShootArguments(
	timestamp: number,
	blaster: Tool,
	origin: CFrame,
	tagged: { [string]: Humanoid }
): boolean
	if not validateNumber(timestamp) then
		return false
	end
	if not validateInstance(blaster, "Tool") then
		return false
	end
	if not validateCFrame(origin) then
		return false
	end
	if not validateSimpleTable(tagged, "string", taggedValidator) then
		return false
	end

	return true
end

return validateShootArguments
