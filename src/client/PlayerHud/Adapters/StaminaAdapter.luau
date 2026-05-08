----------------------------------------------------------------------
-- StaminaAdapter
----------------------------------------------------------------------
-- Binds character attributes "Stamina" + "MaxStamina" to an AttributeBar.
-- Used for sprint/dodge/block budget. Adapter is identical in shape to
-- ShieldAdapter — just different attribute names — because character
-- attributes are the universal server→client replication channel for
-- per-player gameplay stats.
----------------------------------------------------------------------

local ATTR_CURRENT = "Stamina"
local ATTR_MAX = "MaxStamina"

local StaminaAdapter = {}

export type Adapter = { destroy: (self: Adapter) -> () }

function StaminaAdapter.new(character: Model, bar: any): Adapter
	local connections: { RBXScriptConnection } = {}

	local function push()
		local cur = character:GetAttribute(ATTR_CURRENT) or 0
		local max = character:GetAttribute(ATTR_MAX) or 0
		bar:setValue(cur, max)
	end

	table.insert(connections, character:GetAttributeChangedSignal(ATTR_CURRENT):Connect(push))
	table.insert(connections, character:GetAttributeChangedSignal(ATTR_MAX):Connect(push))
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

return StaminaAdapter
