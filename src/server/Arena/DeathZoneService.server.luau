----------------------------------------------------------------------
-- DeathZoneService
----------------------------------------------------------------------
-- Watches every BasePart tagged "DeathZone" and instantly kills any
-- humanoid that touches it. Used as the "below the floating arena"
-- kill volume for the sky-level greybox: any fall off a platform or
-- ledge ends up in the volume, character takes a one-shot.
--
-- Place tagged parts wherever you want lethal volumes. Convention:
--   - Anchored = true
--   - CanCollide = false (so falling players pass through, not bounce)
--   - CanTouch = true (default; required for Touched events)
--   - Transparency = 1 (invisible)
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)

local log = Logger.new("DeathZoneService")

local TAG = "DeathZone"

local function onTouched(zone: BasePart, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	-- Through applyDamage rather than a Health write or TakeDamage, so the
	-- one damage path (PlayerEliminated, kill feed, respawn bookkeeping)
	-- sees the fall. No source: the world did it.
	applyDamage.process({
		sourcePlayer   = nil,
		targetHumanoid = humanoid,
		baseDamage     = HealthConstants.INSTANT_KILL_DAMAGE,
		damageType     = DamageTypes.DamageType.Environmental,
		timestamp      = os.clock(),
		cause          = DamageTypes.Cause.DeathZone,
	})
	log:info(string.format("%s fell into %s", character.Name, zone:GetFullName()))
end

local function watchZone(zone: Instance)
	if not zone:IsA("BasePart") then
		return
	end
	zone.Touched:Connect(function(hit)
		onTouched(zone, hit)
	end)
end

for _, zone in CollectionService:GetTagged(TAG) do
	watchZone(zone)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(watchZone)

log:info("Initialized")
