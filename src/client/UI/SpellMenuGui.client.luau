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
local NPCConstants      = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local PlayerSession     = require(script.Parent.Parent.PlayerSession)

local log = Logger.new("SpellMenuGui")

-- Max range for auto-targeting. Spells won't lock onto anything farther than this.
local AUTO_TARGET_RANGE_STUDS = 150

-- Returns the nearest living enemy Model (NPC or BossAdapter boss) within
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

	-- BossAdapter boss is named "Boss" in workspace but not tagged NPC
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

menu.gui.LayoutOrder = 2
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

	-- Green spells (heal) self-target; red/blue need the nearest enemy.
	local target: Model? = nil
	if color ~= "green" then
		target = findAutoTarget(character)
		if not target then
			log:info(string.format("Cast fizzle (%s) — no target in range", color))
			fizzleSound:Play()
			return
		end
	end

	local result = CastAction.tapReservoir(
		color :: CastAction.Color,
		session.energyReservoirs,
		character,
		target
	)
	if result.ok then
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
