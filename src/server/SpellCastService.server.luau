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
--
-- Target-less casts relay too (Phase 5.2). A self-buff has to land on
-- the server because `applyDamage` reads the shield pool there, and
-- Stone Wall has to spawn there because a client-side Part can't block
-- the server-owned boss. Those arrive with target = nil and resolve
-- against the caster's own character.
--
-- Phase 5.4 hardening. The remote now enforces:
--   1. the spell is one SpellRegistry actually defines, resolved from
--      type-guarded arguments rather than a bare pcall;
--   2. the caster is a living character still in the world;
--   3. a named target is a real Model in the world, within the range
--      the client's auto-targeter could have locked it at;
--   4. the player is inside a cast token budget.
--
-- Still client-trusted: AFFORDABILITY. Energy lives entirely in
-- client/PlayerSession — the server has no reservoir, and no way to
-- build one without mirroring the whole memorize chain
-- (LetterBlock → WordBuffer → Dictionary → EnergyEconomy). Item 4 is a
-- flood guard, not a price check. Closing this properly is an
-- architecture decision, tracked in
-- wiki/systems/SpellCastService.md § Trust model.
--
-- Every rejection drops the request and logs; nothing throws, so one
-- malformed payload can never take the handler down for other players.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger        = require(ReplicatedStorage.Shared.Core.Logger)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)

local SpellCastConstants  = require(script.Parent.SpellCast.SpellCastConstants)
local SpellCastValidation = require(script.Parent.SpellCast.SpellCastValidation)
local RateLimiter         = require(script.Parent.Utility.RateLimiter)

local log = Logger.new("SpellCastService")

local spellCastRemote = ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer :: RemoteEvent

local castLimiter = RateLimiter.new(
	SpellCastConstants.CAST_BURST_CAPACITY,
	SpellCastConstants.CAST_REFILL_PER_SEC
)

-- One log budget token per player+reason, so the first instance of each
-- rejection is always reported while a looping client cannot flood the
-- output. Deliberately not Logger:warnThrottled — its interval is a
-- call count, so a single probe would leave no trace at all.
local rejectionLogBudget = RateLimiter.new(1, 1 / SpellCastConstants.REJECTION_LOG_THROTTLE_SEC)

local function reject(player: Player, reason: string)
	local key = string.format("%d:%s", player.UserId, reason)
	if rejectionLogBudget:consume(key) then
		log:warn(string.format("rejected SpellCast from %s — %s", player.Name, reason))
	end
end

spellCastRemote.OnServerEvent:Connect(function(player: Player, color: any, tier: any, target: any)
	if not castLimiter:consume(player) then
		reject(player, "rate limit")
		return
	end

	local spec, specReason = SpellCastValidation.resolveSpec(color, tier)
	if not spec then
		reject(player, specReason or "invalid spell")
		return
	end

	local character, casterReason = SpellCastValidation.checkCaster(player.Character)
	if not character then
		-- A cast arriving during the respawn gap is ordinary, so this
		-- stays quiet unless the payload itself was malformed.
		if casterReason ~= "caster is dead" then
			reject(player, casterReason or "invalid caster")
		end
		return
	end

	-- Self-buffs and placement spells legitimately arrive with no target.
	-- Anything else must name a living Model, or it's a malformed fire.
	if target == nil then
		if SpellRegistry.needsEnemyTarget(spec) then
			reject(player, string.format("%s sent with no target", spec.name))
			return
		end
		log:info(string.format("%s cast %s on self (server apply)", player.Name, spec.name))
		SpellExecutor.cast(spec, character, nil)
		return
	end

	local targetModel, targetReason = SpellCastValidation.checkTarget(target, character)
	if not targetModel then
		reject(player, targetReason or "invalid target")
		return
	end

	-- Liveness last, and silent: a target dying between the client's
	-- lock and this handler is ordinary play, not an exploit.
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	log:info(string.format("%s cast %s on %s (server apply)", player.Name, spec.name, targetModel.Name))
	SpellExecutor.cast(spec, character, targetModel)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	castLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info("SpellCastService ready — spell, caster, target and rate validation active")
