--!strict

----------------------------------------------------------------------
-- sporeFixture
----------------------------------------------------------------------
-- Helpers for the spore-letter tests (Arena suite, spore_*). The pool, the
-- stand-in boss and the arena are hungerFixture's and bossEntranceFixture's;
-- this adds only what is spore-specific:
--
--   * a boss-type spec: a copy of the Brain (so it carries the real skills)
--     with the spore numbers set to the shipped values except the two times,
--     which are short so a test waits fractions of a second, not 7.5;
--   * `placePlayer`, which parks the harness player's root in the air at a
--     point (anchored, so a test arena with no floor does not drop them) and
--     `releasePlayer`, which undoes it;
--   * `landSpores`, which starts a lob on a BossSpores object and ticks it by
--     hand until the spores have landed.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)

local FLIGHT_SEC = 0.3
local FUSE_SEC = 0.6
local POLL_SEC = 0.05
local LAND_TIMEOUT_SEC = 3

local fixture = {}

fixture.FLIGHT_SEC = FLIGHT_SEC
fixture.FUSE_SEC = FUSE_SEC
fixture.POLL_SEC = POLL_SEC

-- Writes the spore numbers onto `spec`: the shipped ones (read from the
-- Brain's own config, so a retune keeps the tests honest) with short times.
-- `overrides` wins.
function fixture.apply(spec: any, overrides: { [string]: any }?)
	local shipped: any = BossConfig.BOSS_TYPES.Brain
	for _, key in {
		"sporeEveryNthAttack", "sporeCount", "sporeLandRadius", "sporeBurstDamage", "sporeBurstRadius",
		"sporePopDamageFraction", "sporeHoverHeight", "sporeLetterTable", "sporeColors",
	} do
		spec[key] = shipped[key]
	end
	spec.sporeFlightSec = FLIGHT_SEC
	spec.sporeFuseSec = FUSE_SEC
	if overrides then
		for key, value in overrides do
			spec[key] = value
		end
	end
end

-- A full boss-type spec: the Brain's, with the spore numbers applied.
function fixture.spec(overrides: { [string]: any }?): any
	local spec: any = table.clone(BossConfig.BOSS_TYPES.Brain)
	fixture.apply(spec, overrides)
	return spec
end

-- The player's root, anchored at `position`; false when there is no character.
function fixture.placePlayer(player: Player, position: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	-- An arrival protection window would swallow the damage under test.
	if character then
		character:SetAttribute(HealthConstants.PROTECTED_UNTIL_ATTRIBUTE, nil)
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(position)
	return true
end

function fixture.releasePlayer(player: Player?)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
end

-- Starts a lob at `target` and ticks `spores` by hand until it has landed.
-- Returns the seconds the flight took, or nil on timeout / refusal.
function fixture.landSpores(spores: any, target: Vector3): number?
	local landed = false
	local started = os.clock()
	if not spores:beginLob(target, function() landed = true end) then
		return nil
	end
	while not landed and os.clock() - started < LAND_TIMEOUT_SEC do
		task.wait(POLL_SEC)
		spores:tick()
	end
	return if landed then os.clock() - started else nil
end

return fixture
