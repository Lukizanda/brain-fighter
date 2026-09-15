----------------------------------------------------------------------
-- DamageFeedbackGui
----------------------------------------------------------------------
-- Full-screen red flash when the local player takes damage. Reads from
-- the server-broadcast DamageFeedback remote (already populated by
-- HealthService). Intentionally **not** tied to any attribute bar — it
-- reacts to the damage event, not the Health value change, so it fires
-- even on shield/armor hits once those damage types are wired.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local DamageFeedbackBuilder = require(ReplicatedStorage.Shared.Hud.DamageFeedbackBuilder)

local log = Logger.new("DamageFeedback")

local player = Players.LocalPlayer
local damageFeedbackRemote = ReplicatedStorage.Shared.Health.Remotes.DamageFeedback

local handle = DamageFeedbackBuilder.build()
handle.screenGui.DisplayOrder = HudConstants.LAYERS.Feedback -- above attribute bars, below death screen
handle.screenGui.Parent = player:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
HudGate.bindScreenGui(handle.screenGui, HudGate.Policy.ArenaOnly)
HudLayoutManager:attachScale(handle.screenGui)

damageFeedbackRemote.OnClientEvent:Connect(function(data: { [string]: any })
	handle:flash(data.finalDamage or 0)

	log:info(string.format("Took %d %s damage%s",
		data.finalDamage or 0,
		data.damageType or "Unknown",
		data.wasLethal and " [LETHAL]" or ""
	))
end)

log:info("Initialized")
