local tool = script.Parent.Parent
local handle = tool:WaitForChild("Handle")

local function updateAnchored()
	if tool.Parent == workspace then
		handle.Anchored = true
	else
		handle.Anchored = false
	end
end

tool.AncestryChanged:Connect(function()
	updateAnchored()
end)

updateAnchored()
