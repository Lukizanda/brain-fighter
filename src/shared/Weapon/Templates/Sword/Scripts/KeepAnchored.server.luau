-- Keeps the Sword Handle anchored while the Tool sits in Workspace
-- (on pedestal / dropped); unanchors when picked up into a character/backpack.
local tool = script.Parent.Parent
local handle = tool:WaitForChild("Handle")

local function updateAnchored()
	handle.Anchored = tool.Parent == workspace
end

tool.AncestryChanged:Connect(updateAnchored)
updateAnchored()
