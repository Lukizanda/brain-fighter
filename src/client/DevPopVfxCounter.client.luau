--!strict

----------------------------------------------------------------------
-- DevPopVfxCounter
----------------------------------------------------------------------
-- Counts the cosmetic instances each client actually builds for a block
-- pop, and logs one line per pop. Off unless GameConfig.DEV_COUNT_POP_VFX.
--
-- Exists for one question that cannot be answered by looking: **is the
-- popper's burst drawn twice?** The burst and the stream use deliberately
-- opposite broadcast rules —
--
--   burst   drawnLocallyBy = popper  → popper draws it locally, everyone
--                                      else draws it from the broadcast
--   stream  no exclusion             → *everyone* draws it from the
--                                      broadcast, popper included, because
--                                      attribution is a claim the
--                                      prediction layer may not assert
--
-- so the correct count on every client is exactly one of each. If the
-- exclusion ever breaks, the popper draws the burst locally *and* from
-- the broadcast — and two overlapping bursts read as "a bit brighter, a
-- bit louder", not as an obvious duplicate. That is a judgement call, and
-- this file exists so nobody has to make it.
--
-- Counting is by instance name at the world position, so it observes what
-- was *built* rather than what was requested — a call that silently drew
-- nothing is still counted as zero.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger     = require(ReplicatedStorage.Shared.Core.Logger)

if not GameConfig.DEV_COUNT_POP_VFX then
	return
end

local log = Logger.new("DevPopVfxCounter")

local LocalPlayer = Players.LocalPlayer

-- The two anchor Parts a pop builds. Both are created at the block's
-- position, which is what lets them be paired without either carrying an
-- id: SkillVisuals.spawnEffectAtPoint builds the first, CollectStream the
-- second, from the same Vector3.
local BURST_ANCHOR_NAME  = "SkillEffectAnchor"
local RIBBON_ANCHOR_NAME = "CollectStreamAnchor"

-- Two cosmetics belong to the same pop if they appear this close together.
-- A block is ~4 studs, and no two blocks are ever coincident, so this
-- cannot merge two different pops — but it comfortably tolerates the
-- burst anchoring to the pivot while the ribbon starts from the same
-- point read a frame earlier.
local GROUP_RADIUS_STUDS = 6

-- How long to wait before reporting a group. The burst is drawn on the
-- click frame and the ribbon arrives a round trip later, so this has to
-- outlast the worst round trip or a real pair would be reported as two
-- separate one-sided groups — which is exactly what a broken exclusion
-- looks like, so erring short would manufacture false alarms.
local SETTLE_SEC = 1.0

type Group = {
	position: Vector3,
	bursts: number,
	ribbons: number,
	flushing: boolean,
}

local groups: { Group } = {}

local function flush(group: Group)
	local index = table.find(groups, group)
	if index then
		table.remove(groups, index)
	end

	local expected = group.bursts == 1 and group.ribbons == 1
	local line = string.format(
		"%s | pop @ (%.0f, %.0f, %.0f): bursts=%d ribbons=%d",
		LocalPlayer.Name, group.position.X, group.position.Y, group.position.Z,
		group.bursts, group.ribbons
	)

	if expected then
		log:info(line .. "  OK")
	elseif group.ribbons == 0 then
		-- No stream means this was not a block pop at all — a spell impact
		-- also builds a SkillEffectAnchor. Reported rather than dropped, so
		-- a genuinely missing ribbon is never silently filtered away as
		-- "probably a spell".
		log:info(line .. "  (no stream — a spell impact, unless you were popping a block)")
	else
		log:warn(line .. string.format(
			"  UNEXPECTED — expected bursts=1 ribbons=1. %s",
			if group.bursts > 1
				then "More than one burst on one client is the drawnLocallyBy exclusion failing: the popper is drawing locally AND from the broadcast."
				else "Fewer bursts than streams means a burst was requested but nothing was built."
		))
	end
end

local function record(position: Vector3, isBurst: boolean)
	for _, group in groups do
		if (group.position - position).Magnitude <= GROUP_RADIUS_STUDS then
			if isBurst then
				group.bursts += 1
			else
				group.ribbons += 1
			end
			return
		end
	end

	local group: Group = {
		position = position,
		bursts   = if isBurst then 1 else 0,
		ribbons  = if isBurst then 0 else 1,
		flushing = true,
	}
	table.insert(groups, group)

	task.delay(SETTLE_SEC, function()
		flush(group)
	end)
end

workspace.DescendantAdded:Connect(function(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	if instance.Name == BURST_ANCHOR_NAME then
		record(instance.Position, true)
	elseif instance.Name == RIBBON_ANCHOR_NAME then
		record(instance.Position, false)
	end
end)

log:info(string.format(
	"counting block-pop cosmetics for %s — expect 'bursts=1 ribbons=1 OK' on every client, per pop",
	LocalPlayer.Name
))
