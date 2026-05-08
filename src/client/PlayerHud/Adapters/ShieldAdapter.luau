----------------------------------------------------------------------
-- ShieldAdapter
----------------------------------------------------------------------
-- Binds `character:GetAttribute("Shield")` and `"MaxShield"` to an
-- AttributeBar. Shield is a regenerable secondary health pool (like
-- Destiny 2 / Halo). Character attributes replicate server→client for
-- free, so no custom RemoteEvent needed.
--
-- If the attributes don't exist yet (gameplay not wired), the bar
-- shows 0/0 and remains visible but empty. When the server starts
-- setting the attribute, the bar animates up without any UI changes.
----------------------------------------------------------------------

local ATTR_CURRENT = "Shield"
local ATTR_MAX = "MaxShield"

local ShieldAdapter = {}

export type Adapter = { destroy: (self: Adapter) -> () }

function ShieldAdapter.new(character: Model, bar: any): Adapter
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

return ShieldAdapter
