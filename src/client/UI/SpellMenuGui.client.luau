--!strict
----------------------------------------------------------------------
-- SpellMenuGui
----------------------------------------------------------------------
-- Mounts the three-color spell panel at BottomRight. On tap, calls
-- CastAction.tapReservoir with the local character as caster.
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
local PlayerSession     = require(script.Parent.Parent.PlayerSession)

local spellCastRemote = ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer :: RemoteEvent

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

local fizzleSound = Instance.new("Sound")
fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID
fizzleSound.Volume = 1
fizzleSound.Parent = SoundService

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

menu.castRequested:Connect(function(color: string)
	local character = player.Character
	if not character then
		log:warn("cast requested but no character")
		return
	end

	-- Resolve which spell the tap will fire *before* casting, because
	-- whether we need an enemy locked depends on the spell, not the
	-- colour — blue Shield is a self-buff, green Stone Wall is a
	-- placement. Asking the registry keeps that rule in one place.
	local spec = CastAction.resolveTapSpec(color :: CastAction.Color, session.energyReservoirs)
	if not spec then
		log:info(string.format("Cast fizzle (%s) — reservoir below T1", color))
		fizzleSound:Play()
		return
	end

	local target: Model? = nil
	if SpellRegistry.needsEnemyTarget(spec) then
		target = findAutoTarget(character)
		if not target then
			log:info(string.format("Cast fizzle (%s) — no target in range", spec.name))
			fizzleSound:Play()
			return
		end
	end

	local result = CastAction.castSpecific(
		color :: CastAction.Color,
		spec.tier,
		session.energyReservoirs,
		character,
		target
	)
	if result.ok then
		-- Relay every successful cast to the server. Offensive spells need
		-- it because client Health writes on server-owned rigs don't
		-- replicate; self-buffs need it because the shield pool is read by
		-- applyDamage server-side; Stone Wall needs it because a
		-- client-spawned Part can't block the server-owned boss.
		if result.cast then
			spellCastRemote:FireServer(result.cast.color, result.cast.tier, target)
		end
		log:info(string.format("Cast: %s -> %s", result.cast and result.cast.name or "?",
			target and target.Name or "self"))
	else
		fizzleSound:Play()
		log:info(string.format("Cast fizzle: %s", result.reason or "?"))
	end
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.SpellMenu = menu

log:info("Initialized")
