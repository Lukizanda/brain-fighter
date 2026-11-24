--!strict

----------------------------------------------------------------------
-- EnergyGrantReceiver
----------------------------------------------------------------------
-- Adds a server-computed word grant (the scramble bomb's defuse) to the
-- local reservoirs.
--
-- The server has already raised its ledger ceiling by these exact
-- amounts (EconomyService, which sends them only after crediting), and
-- both sides clamp at EnergyReservoirs.CAP_PER_COLOR, so energy lost to
-- the cap is lost identically. The amounts come over the wire rather than
-- being recomputed here so the two sides cannot score a word differently.
--
-- The word buffer is deliberately untouched: a grant is not a memorize.
-- `reservoirs:add` fires `.changed`, which is what updates the spell HUD.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local PlayerSession = require(script.Parent.PlayerSession)

local log = Logger.new("EnergyGrantReceiver")

local wordGrantedRemote = ReplicatedStorage.Shared.Economy.Remotes.WordGranted :: RemoteEvent

wordGrantedRemote.OnClientEvent:Connect(function(energyByColor: any, word: any)
	if typeof(energyByColor) ~= "table" then
		return
	end

	local reservoirs = PlayerSession.get().energyReservoirs
	local changes: { string } = {}
	for color, amount in energyByColor :: { [any]: any } do
		if typeof(color) == "string" and Colors.isSpellColor(color) and typeof(amount) == "number" then
			local before = reservoirs:get(color :: any)
			reservoirs:add(color :: any, amount)
			table.insert(changes, string.format("%s +%d: %d -> %d", color, amount, before, reservoirs:get(color :: any)))
		end
	end

	log:info(string.format("word grant %s (%s)", tostring(word), table.concat(changes, ", ")))
end)
