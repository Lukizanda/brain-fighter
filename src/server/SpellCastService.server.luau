--!strict

----------------------------------------------------------------------
-- SpellCastService
----------------------------------------------------------------------
-- Receives SpellCastServer remote fires from clients and applies
-- spell effects server-side. This is necessary because Humanoid.Health
-- writes on a client-side LocalScript do not replicate to the server
-- for server-owned characters (boss, NPCs). The client executes the
-- full spell locally for VFX / energy drain, then fires this remote
-- so the server actually applies the damage/freeze to the target.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger        = require(ReplicatedStorage.Shared.Core.Logger)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)

local log = Logger.new("SpellCastService")

local spellCastRemote = ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer :: RemoteEvent

spellCastRemote.OnServerEvent:Connect(function(player: Player, color: any, tier: any, target: any)
	local specOk, specOrErr = pcall(SpellRegistry.getSpell, color, tier)
	if not specOk then
		log:warn(string.format("%s sent invalid spell %s/%s", player.Name, tostring(color), tostring(tier)))
		return
	end
	local spec = specOrErr :: SpellRegistry.Spec

	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		log:warn(string.format("%s sent non-Model target: %s", player.Name, tostring(target)))
		return
	end
	local targetModel = target :: Model

	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local character = player.Character
	if not character then return end

	log:info(string.format("%s cast %s on %s (server apply)", player.Name, spec.name, targetModel.Name))
	SpellExecutor.cast(spec, character, targetModel)
end)

log:info("SpellCastService ready")
