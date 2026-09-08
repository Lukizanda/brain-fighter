--!strict

----------------------------------------------------------------------
-- VfxController — the prediction layer
----------------------------------------------------------------------
-- Draws the caster's cast cue on the frame they cast, and nothing else.
--
-- This is the only thing in the game that reacts to a cast before the
-- server has confirmed it, and it is why a spell feels instant: the burst
-- lands ~0.4ms after the tap, with no round trip. Everything else about a
-- cast — damage, status, the projectile, and the impact cue at the target
-- — happens on the authoritative run and comes back over the one
-- server→client lane (VfxBroadcast → WorldVfxController), one RTT later.
--
-- Nothing is drawn at the target from here. An impact is a claim about
-- what happened, and this signal fires before anything has; a mispredicted
-- cosmetic on the caster expires unnoticed, a mispredicted hit marker tells
-- the player they hit something they didn't. The full contract for a
-- `SpellResolved` listener is on the signal itself in CastAction.
--
-- The server raises the same cast cue for everyone else with
-- `drawnLocallyBy` = this client, so the caster sees it exactly once. That
-- exclusion only holds because the draw here is unconditional for every
-- cast the client relays — keep it that way.
--
-- Listens on the `SpellResolved` BindableEvent instance rather than
-- requiring CastAction, so this presentation script never pulls the
-- executor chain (SpellExecutor → SkillDelivery → SkillEffects) into a
-- VM that has no use for it.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger       = require(ReplicatedStorage.Shared.Core.Logger)
local SkillVisuals = require(ReplicatedStorage.Shared.Skills.SkillVisuals)

local log         = Logger.new("VfxController")
local LocalPlayer = Players.LocalPlayer

local spellResolved = ReplicatedStorage.Shared.CastAction
	:WaitForChild("Remotes")
	:WaitForChild("SpellResolved") :: BindableEvent

-- Where the cast burst is drawn from. Casts originate at the caster's
-- chest while hands are empty (Phase 5.7 deleted the Spelling Staff); if
-- a cosmetic prop lands, give it an attachment and resolve it here.
local function resolveCastAnchor(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp :: BasePart else nil
end

spellResolved.Event:Connect(function(
	spec   : any,  -- SpellRegistry.Spec (typed loosely to avoid the require)
	_caster: any,
	_target: any
)
	local character = LocalPlayer.Character
	if not character then return end
	local anchor = resolveCastAnchor(character)
	if not anchor then return end

	SkillVisuals.spawnCastCue(spec.color, spec.tier, anchor)
	log:infoThrottled("cast_vfx", 2, string.format("cast cue: %s t%d @ %s", tostring(spec.color), spec.tier, anchor.Name))
end)

log:info("ready")
