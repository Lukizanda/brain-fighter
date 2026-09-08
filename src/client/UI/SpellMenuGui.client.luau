--!strict
----------------------------------------------------------------------
-- SpellMenuGui
----------------------------------------------------------------------
-- Mounts the three-color spell panel at BottomRight and turns the
-- press-hold-release gesture on it into a cast.
--
-- The builder owns the gesture and picks the tier (see
-- wiki/systems/ChargeCast.md); this script owns the presentation around
-- it: the local charge orb, the ChargeState relay that lets other players
-- see it, the fired flash and the fizzle sound.
--
-- The cast itself is not here. `castRequested` is forwarded to
-- SpellCastController's `RequestCast` BindableFunction, which resolves
-- the target, runs CastAction and relays to the server, and hands back
-- whether the spell went out. The HUD never touches a remote or picks an
-- enemy — it draws what it is told (refactor chunk 7, F21).
--
-- The mana drain is CastAction's and happens exactly once for exactly one
-- tier, at release. Nothing is reserved on the way in, so a cancelled
-- charge costs nothing and there is no refund path to get wrong.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager  = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local SpellMenuBuilder  = require(ReplicatedStorage.Shared.Hud.SpellMenuBuilder)
local SpellRegistry     = require(ReplicatedStorage.Shared.SpellRegistry)
local VfxConfig         = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local ChargeOrbVfx      = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.ChargeOrbVfx)
local PlayerSession     = require(script.Parent.Parent.PlayerSession)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)

local chargeStateRemote = ReplicatedStorage.Shared.SpellCast.Remotes.ChargeState :: RemoteEvent

-- The cast seam. SpellCastController answers `(color, tier)` with
-- `{ ok, name?, reason? }` — see its header.
local requestCast = script.Parent.Parent
	:WaitForChild("SpellCastController")
	:WaitForChild("RequestCast") :: BindableFunction

local log = Logger.new("SpellMenuGui")

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId       = VfxConfig.SFX.fizzle
fizzleSound.Volume        = 1
fizzleSound.PlaybackSpeed = VfxConfig.SFX.FIZZLE_PLAYBACK_SPEED
fizzleSound.Parent        = SoundService

local player = Players.LocalPlayer
local session = PlayerSession.get()
local menu = SpellMenuBuilder.build()

menu.gui.LayoutOrder = 1
HudLayoutManager:register("BottomRight", menu.gui, HudGate.Policy.Always)

-- Render initial state
menu:setReservoirs(session.energyReservoirs:snapshot())

session.energyReservoirs.changed:Connect(function()
	menu:setReservoirs(session.energyReservoirs:snapshot())
end)

----------------------------------------------------------------------
-- Charge lifecycle
----------------------------------------------------------------------
-- `chargingCharacter` is the rig the current charge was raised on, held
-- rather than re-read from player.Character, so a respawn mid-charge
-- tears the orb off the rig that actually has one instead of writing to
-- whatever rig happens to be current when the release arrives.
local chargingCharacter: Model? = nil

-- Highest tier this colour can pay for right now. The builder stops the
-- charge here; this side needs it too, to tell the orb when it has topped
-- out so it strains instead of growing.
local function ceilingFor(color: string): number
	local affordable = SpellRegistry.listAffordableSpells(
		color :: SpellRegistry.Color,
		session.energyReservoirs:get(color :: SpellRegistry.Color)
	)
	local top = affordable[#affordable]
	return if top then top.tier else 0
end

-- Ends the charge on every surface it touches: the local orb, and the
-- attributes other players are watching. `firedTier` > 0 means the spell
-- went out and gets the release flash; 0 is a cancel and collapses.
local function finishCharge(firedTier: number)
	local character = chargingCharacter
	if not character then return end
	chargingCharacter = nil

	if firedTier > 0 then
		ChargeOrbVfx.release(character, firedTier)
	else
		ChargeOrbVfx.stop(character)
	end
	chargeStateRemote:FireServer("end", nil, firedTier)
end

menu.chargeStarted:Connect(function(color: string)
	local character = player.Character
	if not character then
		log:warn("charge started but no character")
		return
	end
	chargingCharacter = character
	ChargeOrbVfx.start(character, color)
	chargeStateRemote:FireServer("start", color, 0)
end)

-- Tier crossings are the only thing that crosses the wire — at most one
-- per tier, never per-frame. Remote observers tween between them.
menu.chargeTierChanged:Connect(function(color: string, tier: number)
	if not chargingCharacter then return end
	chargeStateRemote:FireServer("tier", color, tier)
end)

-- Per-frame, and local only: the casting client animates its own orb off
-- the builder's hold clock, so its growth is continuous and costs no
-- bandwidth. This is the same prediction-vs-replication split the shield
-- bubble uses.
menu.chargeProgress:Connect(function(color: string, tier: number, alpha: number)
	local character = chargingCharacter
	if not character then return end
	local ceiling = ceilingFor(color)
	ChargeOrbVfx.setTier(character, tier, alpha, tier >= 1 and tier >= ceiling)
end)

menu.chargeCancelled:Connect(function(color: string)
	finishCharge(0)
	fizzleSound:Play()
	log:info(string.format("Charge cancelled (%s) — nothing drained", color))
end)

-- Forwarded, not handled: the controller resolves the target, casts and
-- relays. This side only draws the outcome.
menu.castRequested:Connect(function(color: string, tier: number)
	local result = requestCast:Invoke(color, tier)
	if result and result.ok then
		finishCharge(tier)
		menu:playFiredFlash(color)
		log:info(string.format("Cast: %s (t%d)", tostring(result.name), tier))
	else
		finishCharge(0)
		fizzleSound:Play()
		log:info(string.format("Cast fizzle: %s", tostring(result and result.reason or "?")))
	end
end)

-- A charge in flight when the caster dies has no rig left to sit on. The
-- builder's release will still arrive (the mouse button is still down),
-- but by then the orb has to be gone already.
player.CharacterRemoving:Connect(function(character: Model)
	if chargingCharacter == character then
		chargingCharacter = nil
	end
	ChargeOrbVfx.stop(character)
end)

log:info("Initialized")
