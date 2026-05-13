local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)

local function canPlayerDamageHumanoid(player: Player, taggedHumanoid: Humanoid): boolean
	if taggedHumanoid.Health <= 0 then
		return false
	end

	local taggedCharacter = taggedHumanoid.Parent
	local taggedPlayer = Players:GetPlayerFromCharacter(taggedCharacter)
	-- If the player tagged a non-player humanoid then allow damage
	if not taggedPlayer then
		return true
	end

	-- PvP gate: when disabled, players can never damage other players.
	-- NPC targets (taggedPlayer == nil) are unaffected and remain damageable.
	if not GameConfig.PLAYER_VS_PLAYER_ENABLED then
		return false
	end

	if player.Neutral or taggedPlayer.Neutral then
		-- If either player is neutral (i.e. not on a team) then allow damage
		return true
	else
		-- Only allow damage if the players are not on the same team
		return player.Team ~= taggedPlayer.Team
	end
end

return canPlayerDamageHumanoid
