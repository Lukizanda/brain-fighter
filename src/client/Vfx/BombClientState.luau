--!strict

----------------------------------------------------------------------
-- BombClientState
----------------------------------------------------------------------
-- What this client believes about a bomb beyond what the server published:
-- the tiles the player tapped that the server has not confirmed yet (the
-- prediction), and the tiles that were just refused (for the shake).
-- BombTapController writes it; BombVisuals reads it every frame. Both are
-- client-local, so nothing here is ever replicated, and the word buffer is
-- never touched (a bomb has nothing to do with it).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local BombRules = require(ReplicatedStorage.Shared.Boss.BombRules)

local BombClientState = {}

-- Tiles predicted accepted and not yet in the server's list, in tap order.
local predicted: { [Model]: { number } } = setmetatable({}, { __mode = "k" }) :: any
-- os.clock() of the last refusal of a tile.
local refusedAt: { [Model]: { [number]: number } } = setmetatable({}, { __mode = "k" }) :: any

-- Seekers hidden locally ahead of the server (harmless removals).
local hiddenSeekers: { [Model]: { [number]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

-- The tiles the server has accepted, in tap order.
function BombClientState.serverAccepted(bomb: Model): { number }
	local text = bomb:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE)
	return BombRules.decodeIndices(if type(text) == "string" then text else "")
end

-- The server's accepted tiles, then the predicted ones it has not caught up
-- with. This is the list to draw and to predict the next tap from.
function BombClientState.effectiveAccepted(bomb: Model): { number }
	local accepted = BombClientState.serverAccepted(bomb)
	local mine = predicted[bomb]
	if mine ~= nil then
		for _, tile in mine do
			if table.find(accepted, tile) == nil then
				table.insert(accepted, tile)
			end
		end
	end
	return accepted
end

function BombClientState.addPrediction(bomb: Model, tile: number)
	local mine = predicted[bomb]
	if mine == nil then
		mine = {}
		predicted[bomb] = mine
	end
	if table.find(mine :: { number }, tile) == nil then
		table.insert(mine :: { number }, tile)
	end
end

-- Drop a prediction. True when it was still unconfirmed (so it is a rollback),
-- false when the server had already accepted the tile or it was never there.
function BombClientState.removePrediction(bomb: Model, tile: number): boolean
	local mine = predicted[bomb]
	if mine == nil then
		return false
	end
	local index = table.find(mine, tile)
	if index == nil then
		return false
	end
	table.remove(mine, index)
	return table.find(BombClientState.serverAccepted(bomb), tile) == nil
end

function BombClientState.isPredicted(bomb: Model, tile: number): boolean
	local mine = predicted[bomb]
	return mine ~= nil and table.find(mine, tile) ~= nil
end

function BombClientState.markRefused(bomb: Model, tile: number)
	local perBomb = refusedAt[bomb]
	if perBomb == nil then
		perBomb = {}
		refusedAt[bomb] = perBomb
	end
	(perBomb :: { [number]: number })[tile] = os.clock()
end

-- Seconds since the tile was last refused, nil if never.
function BombClientState.secondsSinceRefused(bomb: Model, tile: number): number?
	local perBomb = refusedAt[bomb]
	local at = if perBomb then perBomb[tile] else nil
	return if at then os.clock() - at else nil
end

-- Seekers the player popped as a harmless removal (the salvo is broken) that
-- the server has not confirmed yet: drawn hidden at once.
function BombClientState.setHidden(bomb: Model, tile: number, hidden: boolean)
	local perBomb = hiddenSeekers[bomb]
	if perBomb == nil then
		perBomb = {}
		hiddenSeekers[bomb] = perBomb
	end
	(perBomb :: { [number]: boolean })[tile] = if hidden then true else nil
end

function BombClientState.isHidden(bomb: Model, tile: number): boolean
	local perBomb = hiddenSeekers[bomb]
	return perBomb ~= nil and perBomb[tile] == true
end

function BombClientState.forget(bomb: Model)
	predicted[bomb] = nil
	refusedAt[bomb] = nil
	hiddenSeekers[bomb] = nil
end

return BombClientState
