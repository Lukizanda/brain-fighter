----------------------------------------------------------------------
-- HealthAdapter
----------------------------------------------------------------------
-- Binds a character's Humanoid.Health + MaxHealth to an AttributeBar
-- handle. Responsibilities:
--   • push current/max into the bar on every change
--   • push initial values on attach so the bar isn't blank pre-damage
--   • clean up its signal connections on destroy
--
-- Not responsible for: bar construction, damage feedback flashes,
-- death screen. Those live in other files.
----------------------------------------------------------------------

local HealthAdapter = {}

export type Adapter = {
	destroy: (self: Adapter) -> (),
}

function HealthAdapter.new(character: Model, bar: any): Adapter
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	local connections: { RBXScriptConnection } = {}

	local function push()
		bar:setValue(humanoid.Health, humanoid.MaxHealth)
	end

	table.insert(connections, humanoid:GetPropertyChangedSignal("Health"):Connect(push))
	table.insert(connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(push))
	push()

	local adapter = {} :: Adapter
	function adapter:destroy()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end
	return adapter
end

return HealthAdapter
