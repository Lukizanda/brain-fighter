local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local MeleeSwingController = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeSwingController)
local bindToInstanceDestroyed = require(ReplicatedStorage.Utility.bindToInstanceDestroyed)

local log = Logger.new("Sword")

local sword = script.Parent.Parent

log:info("LocalScript started")

local controller = MeleeSwingController.new(sword)

-- Dev-only: if workspace has attribute "DevAutoSwing", auto-fire one swing
-- after a short delay. Kept in place (inert unless the attribute is set)
-- because MCP lacks the RobloxScript capability to simulate mouse clicks
-- during a playtest, so this is our only way to drive a swing headlessly
-- when iterating on the swing animation or hit detection.
if workspace:GetAttribute("DevAutoSwing") then
	sword.Equipped:Connect(function()
		task.wait(0.5)
		log:info("DevAutoSwing firing")
		-- Drive the state machine the same way Tool.Activated would.
		controller.activated = true
		controller:_tryStartSwing()
	end)
end

bindToInstanceDestroyed(sword, function()
	controller:destroy()
end)
