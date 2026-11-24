--!strict

----------------------------------------------------------------------
-- BombRegistry
----------------------------------------------------------------------
-- Which BossBombs object owns which puzzle Model, so the tap service can route
-- a tap by the Model the client named. One entry per live puzzle, added when it
-- lands and removed the moment it ends or is cleared; keys
-- are weak, so a Model that is somehow dropped cannot keep an object alive.
-- Nothing here is per-arena state: the owner knows its arena.
----------------------------------------------------------------------

local BombRegistry = {}

-- The owner is typed `any` here so this module needs nothing from BossBombs
-- (which requires it).
local owners: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any

function BombRegistry.register(bomb: Model, owner: any)
	owners[bomb] = owner
end

function BombRegistry.unregister(bomb: Model)
	owners[bomb] = nil
end

-- The BossBombs that owns `bomb`, or nil.
function BombRegistry.ownerOf(bomb: Model): any?
	return owners[bomb]
end

return BombRegistry
