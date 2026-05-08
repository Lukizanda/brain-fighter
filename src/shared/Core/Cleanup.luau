--!strict

--[[
	Cleanup — standardized resource cleanup mixin.

	Usage:
		local Cleanup = require(path.to.Cleanup)

		function MyClass.new()
			local self = setmetatable({}, MyClass)
			Cleanup.init(self)
			return self
		end

		-- During setup:
		self:addCleanup(connection)           -- RBXScriptConnection
		self:addCleanup(instance)             -- Instance (calls :Destroy())
		self:addCleanup(function() ... end)   -- Custom function
		self:addCleanup(track)                -- AnimationTrack (calls :Stop() then :Destroy())

		-- During teardown:
		self:destroy()  -- Runs all cleanups in reverse order, then clears the list
]]

local Cleanup = {}

function Cleanup.init(self: any)
	self._cleanups = {} :: { any }
	self._destroyed = false
end

function Cleanup.addCleanup(self: any, item: any)
	if self._destroyed then
		warn("[Cleanup] Attempted to add cleanup after destroy")
		return
	end
	table.insert(self._cleanups, item)
end

function Cleanup.destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true

	local cleanups = self._cleanups
	for i = #cleanups, 1, -1 do
		local item = cleanups[i]
		local itemType = typeof(item)

		if itemType == "function" then
			item()
		elseif itemType == "RBXScriptConnection" then
			item:Disconnect()
		elseif itemType == "Instance" then
			item:Destroy()
		elseif itemType == "table" then
			if typeof(item.Disconnect) == "function" then
				item:Disconnect()
			elseif typeof(item.Destroy) == "function" then
				item:Destroy()
			elseif typeof(item.Stop) == "function" then
				item:Stop()
			end
		end

		cleanups[i] = nil
	end
end

function Cleanup.isDestroyed(self: any): boolean
	return self._destroyed == true
end

return Cleanup
