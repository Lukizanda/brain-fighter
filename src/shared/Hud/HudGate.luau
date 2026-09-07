--!strict

----------------------------------------------------------------------
-- HudGate
----------------------------------------------------------------------
-- Suppresses HUD elements that have no meaning where the player is
-- standing. Phase 6 stage 4c — see `wiki/concepts/HudGate.md` for the
-- design and `wiki/design/lobby.md` § Player state for the policy table.
--
-- Two adapters, one policy:
--
--   HudLayoutManager:register(region, element, policy)  -- .Visible
--   HudGate.bindScreenGui(screenGui, policy)            -- .Enabled
--
-- The split exists because the HUD is already split: nine elements live
-- in HudLayoutManager's regions, six scripts own their own ScreenGui.
--
-- **A gate suppresses; it never reveals.** This is the load-bearing rule
-- in the module. `BossHudGui` hides itself until a boss spawns and
-- `DeathScreenGui` until the player dies, so a gate that wrote
-- `Enabled = true` on entering an arena would show an empty boss bar and
-- a death overlay to a living player. Instead each entry remembers what
-- its owner last asked for and the gate ANDs its policy over that:
--
--   effective = ownerWants and policyAllows
--
-- Owner intent is learned by watching the property, so no self-toggling
-- script needed editing to participate.
--
-- **Nil degrades to visible.** Before the server publishes PlayerState the
-- attribute is nil, and nil means shown — today's behaviour — never
-- hidden. Same call as `Arena.idOf` treating a missing ArenaId as
-- `Default` and `BroadcastAudience` treating an unresolved roster as
-- everyone: the degraded path lands on what already shipped, because a
-- system that fails loud is debuggable and one that fails silent is not.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)

export type Policy = "Always" | "ArenaOnly" | "LobbyOnly"

local HudGate = {}

HudGate.Policy = {
	-- Visible wherever the player is.
	Always = "Always" :: Policy,
	-- Hidden unless InArena. Round and competition chrome.
	ArenaOnly = "ArenaOnly" :: Policy,
	-- Hidden when InArena. Portal panel and queue counts.
	LobbyOnly = "LobbyOnly" :: Policy,
}

local player = Players.LocalPlayer

type Entry = {
	instance: Instance,
	property: string,
	policy: Policy,
	-- What the owning script last asked for, independent of the gate.
	ownerWants: boolean,
}

local entries: { Entry } = {}

----------------------------------------------------------------------
-- Policy evaluation
----------------------------------------------------------------------

local function policyAllows(policy: Policy): boolean
	if policy == HudGate.Policy.Always then
		return true
	end

	local state = player:GetAttribute(Arena.STATE_ATTRIBUTE)
	if state == nil then
		return true -- see § Nil degrades to visible
	end

	local inArena = state == Arena.PlayerState.InArena
	if policy == HudGate.Policy.ArenaOnly then
		return inArena
	end
	-- LobbyOnly. `Queued` is a player standing in the lobby, so it reads
	-- as lobby here; the three-way distinction only matters to the portal.
	return not inArena
end

local function apply(entry: Entry)
	local target = entry.ownerWants and policyAllows(entry.policy)
	if (entry.instance :: any)[entry.property] == target then
		return -- already right; writing would fire a pointless signal
	end
	pcall(function()
		(entry.instance :: any)[entry.property] = target
	end)
end

local function applyAll()
	-- Reverse walk so a destroyed instance can be dropped in place.
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if entry.instance.Parent == nil and not entry.instance:IsDescendantOf(game) then
			table.remove(entries, i)
		else
			apply(entry)
		end
	end
end

----------------------------------------------------------------------
-- Binding
----------------------------------------------------------------------

local function bind(instance: Instance, property: string, policy: Policy)
	local entry: Entry = {
		instance = instance,
		property = property,
		policy = policy,
		ownerWants = (instance :: any)[property],
	}
	table.insert(entries, entry)

	-- Telling the gate's own writes apart from the owner's, **without** a
	-- flag. Roblox fires property-changed signals deferred, so a flag set
	-- around the write is already cleared by the time the handler runs —
	-- the gate would read its own suppression back as the owner wanting
	-- the element hidden, and nothing would ever come back on entering an
	-- arena. That bug shipped into a playtest; this is the fix.
	--
	-- The rule instead keys off the gate's state at the time of the write:
	--   - gate open: the gate never writes, so any change is the owner's.
	--   - gate closed, value went true: only the owner does that. Record
	--     the intent and re-suppress — this is the leak the module exists
	--     to stop.
	--   - gate closed, value went false: ambiguous. Assume it was ours and
	--     preserve the owner's intent, which is the case that broke.
	--     If it really was the owner, the next write with the gate open
	--     corrects it.
	instance:GetPropertyChangedSignal(property):Connect(function()
		local value = (instance :: any)[property]
		if policyAllows(entry.policy) then
			entry.ownerWants = value
		elseif value then
			entry.ownerWants = true
			apply(entry)
		end
	end)

	instance.Destroying:Connect(function()
		local index = table.find(entries, entry)
		if index then
			table.remove(entries, index)
		end
	end)

	apply(entry)
end

-- For elements parented into a HudLayoutManager region. Called by
-- `HudLayoutManager:register`, not directly.
function HudGate.bindElement(element: GuiObject, policy: Policy)
	bind(element, "Visible", policy)
end

-- For the six scripts that build their own ScreenGui rather than
-- registering into a region.
function HudGate.bindScreenGui(screenGui: ScreenGui, policy: Policy)
	bind(screenGui, "Enabled", policy)
end

----------------------------------------------------------------------
-- Raw state, for the things that are not GuiObjects
----------------------------------------------------------------------
-- HudGate handles GuiObjects; anything else reads the state directly.

function HudGate.getState(): string?
	local state = player:GetAttribute(Arena.STATE_ATTRIBUTE)
	return type(state) == "string" and state or nil
end

function HudGate.isInArena(): boolean
	return HudGate.getState() == Arena.PlayerState.InArena
end

HudGate.stateChanged = player:GetAttributeChangedSignal(Arena.STATE_ATTRIBUTE)

HudGate.stateChanged:Connect(applyAll)

return HudGate
