local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local DamageModifierRegistry = require(ReplicatedStorage.Shared.Health.DamageModifierRegistry)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("HealthService")

type DamageRequest = DamageTypes.DamageRequest
type DamageResult = DamageTypes.DamageResult

local applyDamage = {}

local refs: {
	damageFeedbackRemote: RemoteEvent,
	damageConfirmRemote: RemoteEvent,
	playerDamagedEvent: BindableEvent,
	playerEliminatedEvent: BindableEvent,
	pendingRespawns: { [Player]: number },
}

function applyDamage.initialize(dependencies: typeof(refs))
	refs = dependencies
end

function applyDamage.process(request: DamageRequest): DamageResult?
	local targetHumanoid = request.targetHumanoid

	if targetHumanoid.Health <= 0 then
		return nil
	end

	-- PvP gate: when disabled, any player-on-player damage drops silently.
	-- Self-damage (fall, environment) and NPC-on-player damage stay
	-- enabled. Sits ahead of the team friendly-fire branch so the gate is
	-- authoritative even if a future caller sets up teams without flipping
	-- PLAYER_VS_PLAYER_ENABLED.
	local sourcePlayer = request.sourcePlayer
	if sourcePlayer and not GameConfig.PLAYER_VS_PLAYER_ENABLED then
		local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
		local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
		if targetPlayer and targetPlayer ~= sourcePlayer then
			log:info(string.format("PvP blocked: %s -> %s (PLAYER_VS_PLAYER_ENABLED=false)",
				sourcePlayer.Name, targetPlayer.Name))
			return nil
		end
	end

	-- Friendly-fire filter. Same-team player damage drops silently here so
	-- the damage modifiers, score events, and death feedback never fire.
	-- FFA modes leave both players Neutral, so the equality check below
	-- never matches and FFA damage flows through untouched. Self-damage
	-- (sourcePlayer == targetPlayer) is allowed — fall damage and similar
	-- still kill you. Environment damage (sourcePlayer == nil) is allowed.
	if sourcePlayer and sourcePlayer.Team and not sourcePlayer.Neutral then
		local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
		local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
		if targetPlayer
			and targetPlayer ~= sourcePlayer
			and not targetPlayer.Neutral
			and targetPlayer.Team == sourcePlayer.Team
		then
			log:info(string.format("FF blocked: %s -> %s (both on team %s)",
				sourcePlayer.Name, targetPlayer.Name, sourcePlayer.Team.Name))
			return nil
		end
	end

	local finalDamage, absorbed, modifiersApplied = DamageModifierRegistry.resolve(request)

	local healthBefore = targetHumanoid.Health
	targetHumanoid.Health = math.max(0, targetHumanoid.Health - finalDamage)
	local wasLethal = targetHumanoid.Health <= 0

	local result: DamageResult = {
		finalDamage = finalDamage,
		absorbed = absorbed,
		wasLethal = wasLethal,
		hitZone = request.hitZone,
		modifiersApplied = modifiersApplied,
	}

	local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
	local sourceName = request.sourcePlayer and request.sourcePlayer.Name or "Environment"
	local targetName = targetCharacter and targetCharacter.Name or "Unknown"
	log:info(string.format(
		"%s -> %s: %d damage (base=%d, zone=%s, mods=%s) | HP: %d -> %d%s",
		sourceName,
		targetName,
		finalDamage,
		request.baseDamage,
		request.hitZone or "none",
		#modifiersApplied > 0 and table.concat(modifiersApplied, ",") or "none",
		healthBefore,
		targetHumanoid.Health,
		wasLethal and " [ELIMINATED]" or ""
	))

	refs.playerDamagedEvent:Fire(request.sourcePlayer, targetHumanoid, result)

	-- Send feedback to the victim
	local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then
		local attackerPosition = nil
		if request.sourcePlayer and request.sourcePlayer.Character then
			local hrp = request.sourcePlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				attackerPosition = hrp.Position
			end
		end
		refs.damageFeedbackRemote:FireClient(targetPlayer, {
			attackerPosition = attackerPosition,
			damageType = request.damageType,
			finalDamage = finalDamage,
			hitZone = request.hitZone,
			wasLethal = wasLethal,
		})
	end

	-- Send confirmation to the attacker
	if request.sourcePlayer then
		refs.damageConfirmRemote:FireClient(request.sourcePlayer, {
			finalDamage = finalDamage,
			wasHeadshot = request.hitZone == DamageTypes.HitZone.Head,
			wasLethal = wasLethal,
		})
	end

	if wasLethal then
		refs.playerEliminatedEvent:Fire(request.sourcePlayer, targetHumanoid, result)

		if targetPlayer then
			refs.pendingRespawns[targetPlayer] = os.clock()
		end
	end

	return result
end

return applyDamage
