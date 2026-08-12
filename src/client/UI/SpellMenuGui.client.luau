--!strict
----------------------------------------------------------------------
-- SpellMenuGui
----------------------------------------------------------------------
-- Mounts the three-color spell panel at BottomRight and turns the
-- press-hold-release gesture on it into a cast.
--
-- The builder owns the gesture and picks the tier (see
-- wiki/systems/ChargeCast.md); this script owns everything that touches
-- the world: the local charge orb, the ChargeState relay that lets other
-- players see it, target resolution, and the cast itself.
--
-- Two things are deliberately done at *release* rather than at press:
--   • the enemy lock, because a 1.75 s T4 charge is long enough for the
--     world to move and a target picked at press time is stale by then;
--   • the mana drain, which is CastAction's, and happens exactly once for
--     exactly one tier. Nothing is reserved on the way in, so a cancelled
--     charge costs nothing and there is no refund path to get wrong.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager  = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local SpellMenuBuilder  = require(ReplicatedStorage.Shared.Hud.SpellMenuBuilder)
local CastAction        = require(ReplicatedStorage.Shared.CastAction)
local SpellRegistry     = require(ReplicatedStorage.Shared.SpellRegistry)
local NPCConstants      = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local VfxConfig         = require(ReplicatedStorage.Shared.Vfx.VfxConfig)
local ChargeOrbVfx      = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.ChargeOrbVfx)
local PlayerSession     = require(script.Parent.Parent.PlayerSession)

local spellCastRemote  = ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer :: RemoteEvent
local chargeStateRemote = ReplicatedStorage.Shared.SpellCast.Remotes.ChargeState :: RemoteEvent

local log = Logger.new("SpellMenuGui")

-- Max range for auto-targeting. Spells won't lock onto anything farther than this.
local AUTO_TARGET_RANGE_STUDS = 150

-- Returns the nearest living enemy Model (NPC or the Boss-system boss) within
-- AUTO_TARGET_RANGE_STUDS of the character. Returns nil if nothing is in range.
local function findAutoTarget(character: Model): Model?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return nil
	end
	local origin = (hrp :: BasePart).Position

	local nearest: Model? = nil
	local nearestDist = AUTO_TARGET_RANGE_STUDS

	local function consider(model: Instance)
		if not model:IsA("Model") or model == character then
			return
		end
		local h = model:FindFirstChildOfClass("Humanoid")
		if not h or h.Health <= 0 then
			return
		end
		local dist = (model:GetPivot().Position - origin).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = model :: Model
		end
	end

	for _, npc in CollectionService:GetTagged(NPCConstants.TAG_NPC) do
		consider(npc)
	end

	-- The Boss-system boss is named "Boss" in workspace but not tagged NPC
	local boss = workspace:FindFirstChild("Boss")
	if boss then
		consider(boss)
	end

	return nearest
end

-- Pitched well below the cast swoosh it shares an asset with, so a
-- refused cast is audibly a dud rather than a quieter success.
local FIZZLE_PLAYBACK_SPEED = 0.55

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId       = VfxConfig.SFX.fizzle
fizzleSound.Volume        = 1
fizzleSound.PlaybackSpeed = FIZZLE_PLAYBACK_SPEED
fizzleSound.Parent        = SoundService

local player = Players.LocalPlayer
local session = PlayerSession.get()
local menu = SpellMenuBuilder.build()

menu.gui.LayoutOrder = 1
HudLayoutManager:register("BottomRight", menu.gui)

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

menu.castRequested:Connect(function(color: string, tier: number)
	local character = player.Character
	if not character then
		log:warn("cast requested but no character")
		finishCharge(0)
		return
	end

	-- The builder already clamped the tier to what the reservoir can pay
	-- for, but ask the registry rather than trusting that: whether we need
	-- an enemy locked depends on the spell, not the colour — blue Shield is
	-- a self-buff, green Stone Wall is a placement.
	local lookupOk, specOrErr = pcall(SpellRegistry.getSpell, color :: SpellRegistry.Color, tier)
	if not lookupOk then
		log:warn(string.format("Cast fizzle (%s t%d) — %s", color, tier, tostring(specOrErr)))
		finishCharge(0)
		fizzleSound:Play()
		return
	end
	local spec = specOrErr :: SpellRegistry.Spec

	-- Resolved here, at release, not at press. See the header.
	local target: Model? = nil
	if SpellRegistry.needsEnemyTarget(spec) then
		target = findAutoTarget(character)
		if not target then
			log:info(string.format("Cast fizzle (%s) — no target in range", spec.name))
			finishCharge(0)
			fizzleSound:Play()
			return
		end
	end

	local result = CastAction.castSpecific(
		color :: CastAction.Color,
		tier,
		session.energyReservoirs,
		character,
		target
	)
	if result.ok then
		finishCharge(tier)
		menu:playFiredFlash(color)
		-- Relay every successful cast to the server. Offensive spells need
		-- it because client Health writes on server-owned rigs don't
		-- replicate; self-buffs need it because the shield pool is read by
		-- applyDamage server-side; Stone Wall needs it because a
		-- client-spawned Part can't block the server-owned boss.
		if result.cast then
			spellCastRemote:FireServer(result.cast.color, result.cast.tier, target)
		end
		log:info(string.format("Cast: %s (t%d) -> %s", result.cast and result.cast.name or "?",
			tier, target and target.Name or "self"))
	else
		finishCharge(0)
		fizzleSound:Play()
		log:info(string.format("Cast fizzle: %s", result.reason or "?"))
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

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.SpellMenu = menu

log:info("Initialized")
