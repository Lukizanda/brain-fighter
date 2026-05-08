--!strict

--[[
	Logger — shared logging utility with throttled output support.

	Usage:
		local Logger = require(path.to.Logger)
		local log = Logger.new("Locomotion")

		log:info("State changed:", oldState, "->", newState)
		log:warn("Missing animation for state:", state)
		log:error("Failed to find HumanoidRootPart")
		log:infoThrottled("frameData", 60, "Position:", pos)
]]

local Logger = {}
Logger.__index = Logger

export type Logger = typeof(setmetatable({} :: {
	prefix: string,
	_throttleCounts: { [string]: number },
}, Logger))

function Logger.new(systemName: string): Logger
	local self = setmetatable({}, Logger)
	self.prefix = `[{systemName}]`
	self._throttleCounts = {}
	return self
end

function Logger:info(...: any)
	print(self.prefix, ...)
end

function Logger:warn(...: any)
	warn(self.prefix, ...)
end

function Logger:error(...: any)
	warn(self.prefix, "ERROR:", ...)
end

function Logger:infoThrottled(key: string, interval: number, ...: any)
	local count = (self._throttleCounts[key] or 0) + 1
	self._throttleCounts[key] = count
	if count % interval == 0 then
		print(self.prefix, ...)
	end
end

function Logger:warnThrottled(key: string, interval: number, ...: any)
	local count = (self._throttleCounts[key] or 0) + 1
	self._throttleCounts[key] = count
	if count % interval == 0 then
		warn(self.prefix, ...)
	end
end

function Logger:resetThrottle(key: string)
	self._throttleCounts[key] = nil
end

return Logger
