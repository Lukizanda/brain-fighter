----------------------------------------------------------------------
-- MeleeSwingService (server)
----------------------------------------------------------------------
-- Hybrid hit-detection server: client does the sweep (with blade-
-- accurate geometry) and sends a claim list of humanoids it believes
-- were hit. This service validates each claim:
--
--   • payload sanity  — is the list a table, not oversized, clientTime fresh
--   • cooldown        — attacker's rate-of-fire respected (authoritative)
--   • type check      — is each element actually a Humanoid instance
--   • alive check     — target's Health > 0
--   • self-hit check  — target ≠ attacker
--   • distance check  — target within reach * SERVER_SANITY_REACH_MULTIPLIER
--   • LOS raycast     — no wall between attacker and target
--
-- Validated claims get damage + hit-sound replication. Rejected claims
-- are logged with a specific reason so suspicious rejection patterns
-- are visible (exploiter fingerprinting).
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)

local log = Logger.new("MeleeSwingService")

local DEFAULT_DAMAGE = 20
local DEFAULT_REACH = 6
local DEFAULT_COOLDOWN = 0.5

-- Per-player cooldown tracking (os.clock() of last accepted swing's Active start)
local lastSwingByPlayer: { [Player]: number } = {}

local swingRequestRemote = ReplicatedStorage.Shared.Weapon.Remotes
	:WaitForChild(MeleeConstants.SWING_REQUEST_REMOTE)
local hitReplicationRemote = ReplicatedStorage.Shared.Weapon.Remotes
	:WaitForChild("MeleeHitReplication")

local function readNumberAttr(weapon: Tool, attr: string, default: number): number
	local v = weapon:GetAttribute(attr)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return default
end

-- Payload-level gate: shape + timing + weapon ownership
local function validatePayload(
	player: Player,
	weapon: any,
	clientTime: any,
	claimedHumanoids: any
): boolean
	if typeof(weapon) ~= "Instance" or not weapon:IsA("Tool") then
		log:warn(string.format("%s: rejected — weapon is not a Tool", player.Name))
		return false
	end
	local character = player.Character
	if not character or weapon.Parent ~= character then
		log:warn(string.format("%s: rejected — weapon not equipped by requesting player",
			player.Name))
		return false
	end
	if typeof(clientTime) ~= "number" then
		log:warn(string.format("%s: rejected — clientTime is not a number", player.Name))
		return false
	end
	-- clientTime is workspace:GetServerTimeNow() on the sender. Compare
	-- against the same clock here so client/server VMs don't disagree
	-- (os.clock() is per-VM and diverges 20+s in multi-client tests).
	local now = workspace:GetServerTimeNow()
	if now - clientTime > MeleeConstants.STALE_CLAIM_THRESHOLD then
		log:warn(string.format("%s: rejected — claim is stale (%.2fs old)",
			player.Name, now - clientTime))
		return false
	end
	if typeof(claimedHumanoids) ~= "table" then
		log:warn(string.format("%s: rejected — claimedHumanoids is not a table", player.Name))
		return false
	end
	if #claimedHumanoids > MeleeConstants.MAX_CLAIMS_PER_SWING then
		log:warn(string.format("%s: rejected — payload too large (%d claims > %d cap)",
			player.Name, #claimedHumanoids, MeleeConstants.MAX_CLAIMS_PER_SWING))
		return false
	end
	return true
end

-- Raycast HRP → target position, excluding the attacker's own character so
-- the cast doesn't hit the swinger's body. Returns true if nothing blocks.
local function hasLineOfSight(
	attackerCharacter: Model,
	attackerHRP: BasePart,
	targetRoot: BasePart
): boolean
	if not MeleeConstants.LOS_SANITY_ENABLED then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	local origin = attackerHRP.Position
	local direction = targetRoot.Position - origin
	local result = Workspace:Raycast(origin, direction, params)
	if not result then
		return true -- nothing hit; open path (target may also be clipped but we only care about obstruction)
	end
	-- Accept if the ray hit the target or a descendant of the target's model
	local targetModel = targetRoot:FindFirstAncestorOfClass("Model")
	return result.Instance == targetRoot
		or (targetModel ~= nil and result.Instance:IsDescendantOf(targetModel))
end

-- Validates a single claimed humanoid. Returns (ok, rootPart, reason?).
local function validateClaim(
	humanoid: any,
	attackerCharacter: Model,
	attackerHumanoid: Humanoid,
	attackerHRP: BasePart,
	sanityDist: number
): (boolean, BasePart?, string?)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return false, nil, "not-humanoid"
	end
	if humanoid == attackerHumanoid then
		return false, nil, "self-hit"
	end
	if humanoid.Health <= 0 then
		return false, nil, "already-dead"
	end
	local targetChar = humanoid.Parent
	if not targetChar or not targetChar:IsA("Model") then
		return false, nil, "orphan-humanoid"
	end
	local targetRoot = humanoid.RootPart or targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return false, nil, "no-root-part"
	end
	local dist = (targetRoot.Position - attackerHRP.Position).Magnitude
	if dist > sanityDist then
		return false, nil, string.format("out-of-sanity-range(%.1f>%.1f)", dist, sanityDist)
	end
	if not hasLineOfSight(attackerCharacter, attackerHRP, targetRoot) then
		return false, nil, "los-blocked"
	end
	return true, targetRoot, nil
end

Players.PlayerRemoving:Connect(function(player)
	lastSwingByPlayer[player] = nil
end)

swingRequestRemote.OnServerEvent:Connect(function(
	player: Player,
	weapon: any,
	clientTime: any,
	claimedHumanoids: any
)
	if not validatePayload(player, weapon, clientTime, claimedHumanoids) then
		return
	end

	local now = os.clock()
	local cooldown = readNumberAttr(weapon, MeleeConstants.COOLDOWN_SECONDS_ATTRIBUTE, DEFAULT_COOLDOWN)
	local last = lastSwingByPlayer[player] or 0
	if now - last + MeleeConstants.COOLDOWN_SKEW_TOLERANCE < cooldown then
		log:warn(string.format("%s: rejected swing — cooldown (%.2fs remaining)",
			player.Name, cooldown - (now - last)))
		return
	end
	lastSwingByPlayer[player] = now

	local character = player.Character
	local attackerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local attackerHRP = character and character:FindFirstChild("HumanoidRootPart")
	if not (attackerHumanoid and attackerHRP and attackerHRP:IsA("BasePart")) then
		return
	end

	if #claimedHumanoids == 0 then
		log:info(string.format("%s: swing with zero claims (miss reported by client)", player.Name))
		return
	end

	local damage = readNumberAttr(weapon, MeleeConstants.DAMAGE_ATTRIBUTE, DEFAULT_DAMAGE)
	local reach = readNumberAttr(weapon, MeleeConstants.REACH_ATTRIBUTE, DEFAULT_REACH)
	local sanityDist = reach * MeleeConstants.SERVER_SANITY_REACH_MULTIPLIER

	-- Iterate only the array part (ipairs). This makes MAX_CLAIMS_PER_SWING
	-- actually authoritative — a malicious client could otherwise smuggle
	-- extra claims through hash-keyed entries that bypass the `#t` cap.
	local accepted, rejected = 0, {}
	for _, humanoid in ipairs(claimedHumanoids) do
		local ok, targetRoot, reason = validateClaim(
			humanoid, character, attackerHumanoid, attackerHRP, sanityDist)
		if ok and targetRoot then
			applyDamage.process({
				sourcePlayer = player,
				targetHumanoid = humanoid,
				baseDamage = damage,
				damageType = DamageTypes.DamageType.Melee,
				hitZone = DamageTypes.HitZone.Torso,
				sourceWeapon = weapon,
				timestamp = clientTime,
			})
			hitReplicationRemote:FireAllClients(weapon, targetRoot)
			accepted += 1
		else
			table.insert(rejected, reason)
		end
	end

	if #rejected > 0 then
		log:warn(string.format("%s: %d/%d claims accepted, rejected: [%s]",
			player.Name, accepted, #claimedHumanoids, table.concat(rejected, ", ")))
	else
		log:info(string.format("%s: all %d claims accepted", player.Name, accepted))
	end
end)

log:info("Initialized")
