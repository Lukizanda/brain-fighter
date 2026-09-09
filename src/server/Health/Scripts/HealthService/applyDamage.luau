local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local DamageModifierRegistry = require(ReplicatedStorage.Shared.Health.DamageModifierRegistry)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("HealthService")

type DamageRequest = DamageTypes.DamageRequest
type DamageResult = DamageTypes.DamageResult
type HealRequest = DamageTypes.HealRequest
type HealResult = DamageTypes.HealResult

local applyDamage = {}

local refs: {
	damageFeedbackRemote: RemoteEvent,
	damageConfirmRemote: RemoteEvent,
	playerDamagedEvent: BindableEvent,
	playerEliminatedEvent: BindableEvent,
	-- May other players damage this one? Answered by the mode the victim
	-- is playing under, resolved through the victim's session by
	-- GameModeService. Injected so this module never reaches into the
	-- session tables itself.
	allowsPvPFor: (victim: Player) -> boolean,
}

function applyDamage.initialize(dependencies: typeof(refs))
	refs = dependencies
end

function applyDamage.process(request: DamageRequest): DamageResult?
	local targetHumanoid = request.targetHumanoid

	if targetHumanoid.Health <= 0 then
		return nil
	end

	-- PvP gate: player-on-player damage is allowed only when the victim's
	-- mode says so (`allowsPvP` on the mode config, resolved through the
	-- victim's session — see wiki/design/lobby.md § PvP gate). Self-damage
	-- (fall, environment) and NPC-on-player damage are never gated.
	local sourcePlayer = request.sourcePlayer
	if sourcePlayer then
		local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
		local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
		if targetPlayer and targetPlayer ~= sourcePlayer and not refs.allowsPvPFor(targetPlayer) then
			log:info(string.format("PvP blocked: %s -> %s (victim's mode has allowsPvP=false)",
				sourcePlayer.Name, targetPlayer.Name))
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
		cause = request.cause,
	}

	local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
	local sourceName = request.sourcePlayer and request.sourcePlayer.Name or "Environment"
	local targetName = targetCharacter and targetCharacter.Name or "Unknown"
	log:info(string.format(
		"%s -> %s: %d damage (base=%d, cause=%s, zone=%s, mods=%s) | HP: %d -> %d%s",
		sourceName,
		targetName,
		finalDamage,
		request.baseDamage,
		request.cause or "none",
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

	-- Announce the kill; do not schedule the respawn. GameModeService owns
	-- that, off the Humanoid's own `Died`, so a death this module never saw
	-- (a fall, a DeathHandler rig) respawns the same way as one it did.
	if wasLethal then
		refs.playerEliminatedEvent:Fire(request.sourcePlayer, targetHumanoid, result)
	end

	return result
end

-- The heal half of the sink. Heals skip the modifier chain (a shield must
-- not "absorb" a heal), fire no damage events and send no feedback; they
-- live here only so that Humanoid.Health has exactly one writer.
function applyDamage.heal(request: HealRequest): HealResult?
	local targetHumanoid = request.targetHumanoid

	if targetHumanoid.Health <= 0 then
		return nil
	end

	local healthBefore = targetHumanoid.Health
	targetHumanoid.Health = math.min(targetHumanoid.MaxHealth, healthBefore + math.max(0, request.amount))
	local healed = targetHumanoid.Health - healthBefore

	local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
	log:info(string.format(
		"%s healed %s: +%d (cause=%s) | HP: %d -> %d",
		request.sourcePlayer and request.sourcePlayer.Name or "Environment",
		targetCharacter and targetCharacter.Name or "Unknown",
		healed,
		request.cause or "none",
		healthBefore,
		targetHumanoid.Health
	))

	return { healed = healed, cause = request.cause }
end

return applyDamage
