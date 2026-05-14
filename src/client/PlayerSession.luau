--!strict

----------------------------------------------------------------------
-- PlayerSession
----------------------------------------------------------------------
-- Lazy-creates and caches the local player's per-session state
-- instances (WordBuffer, MindFullManager, EnergyReservoirs). Every
-- client system that needs player state requires this module rather
-- than constructing its own copies.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)
local MindFullManager = require(ReplicatedStorage.Shared.MindFullManager)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

export type Session = {
	wordBuffer: WordBuffer.WordBuffer,
	mindFullManager: MindFullManager.MindFullManager,
	energyReservoirs: EnergyReservoirs.EnergyReservoirs,
}

local session: Session? = nil

local PlayerSession = {}

function PlayerSession.get(): Session
	if session then
		return session
	end

	local buffer = WordBuffer.new()
	local mindFull = MindFullManager.new(buffer)
	local reservoirs = EnergyReservoirs.new()

	session = {
		wordBuffer = buffer,
		mindFullManager = mindFull,
		energyReservoirs = reservoirs,
	}

	return session
end

function PlayerSession.destroy()
	if not session then
		return
	end
	session.mindFullManager:destroy()
	session.wordBuffer:destroy()
	session.energyReservoirs:destroy()
	session = nil
end

return PlayerSession
