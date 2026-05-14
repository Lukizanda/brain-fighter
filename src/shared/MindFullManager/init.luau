--!strict

--[[
	MindFullManager — transition watcher over a WordBuffer.

	The diegetic rule from `wiki/design/gameplay-loop.md` "Buffer & input":
	when the 12-slot buffer is full, shooting is blocked (the wizard's mind
	is at capacity). This module observes `WordBuffer.changed` and emits
	rising-edge / falling-edge signals so downstream consumers (BlockShoot
	gating, the MindFullIndicator HUD piece) only react on transitions, not
	on every buffer mutation.

	Pure observer — never mutates the buffer, never touches Roblox instances
	beyond its internal BindableEvents.

	Usage:
		local MindFullManager = require(ReplicatedStorage.Shared.MindFullManager)
		local mgr = MindFullManager.new(buffer)

		mgr.mindFull:Connect(function()
			-- buffer just transitioned full → grey out crosshair, etc.
		end)
		mgr.mindFreed:Connect(function()
			-- buffer just transitioned out of full → re-enable shoot input.
		end)

		mgr:isMindFull() -- current edge state (cheap; reads the live buffer)
		mgr:destroy()    -- disconnects from buffer.changed, destroys signals

	Signal semantics: both `.mindFull` and `.mindFreed` are
	`BindableEvent.Event` signals, so they fire in Roblox's Deferred mode —
	handlers run on the next resumption cycle, not synchronously after the
	mutating `buffer:append` / `buffer:remove` / `buffer:clear` call.
	Re-read `:isMindFull()` inside the handler if you need the current
	state; do not assume the signal arrived "because of" any specific
	preceding mutation.

	See also: wiki/systems/MindFullManager.md, wiki/systems/WordBuffer.md
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)

local MindFullManager = {}
MindFullManager.__index = MindFullManager

export type MindFullManager = typeof(setmetatable(
	{} :: {
		_buffer: WordBuffer.WordBuffer,
		_wasFull: boolean,
		_mindFullEvent: BindableEvent,
		_mindFreedEvent: BindableEvent,
		_changedConn: RBXScriptConnection?,
		_log: Logger.Logger,
		_destroyed: boolean,
		mindFull: RBXScriptSignal,
		mindFreed: RBXScriptSignal,
	},
	MindFullManager
))

function MindFullManager.new(buffer: WordBuffer.WordBuffer): MindFullManager
	local mindFullEvent = Instance.new("BindableEvent")
	mindFullEvent.Name = "MindFullManagerMindFull"

	local mindFreedEvent = Instance.new("BindableEvent")
	mindFreedEvent.Name = "MindFullManagerMindFreed"

	local self = setmetatable({
		_buffer = buffer,
		-- Seed from the buffer's current state so a manager constructed
		-- over an already-full buffer doesn't fire mindFull as a phantom
		-- transition on the first :append rejection.
		_wasFull = buffer:isFull(),
		_mindFullEvent = mindFullEvent,
		_mindFreedEvent = mindFreedEvent,
		_changedConn = nil,
		_log = Logger.new("MindFullManager"),
		_destroyed = false,
		mindFull = mindFullEvent.Event,
		mindFreed = mindFreedEvent.Event,
	}, MindFullManager)

	self._changedConn = buffer.changed:Connect(function()
		self:_onBufferChanged()
	end)

	return (self :: any) :: MindFullManager
end

function MindFullManager:isMindFull(): boolean
	return self._buffer:isFull()
end

function MindFullManager:_onBufferChanged()
	if self._destroyed then
		return
	end

	local nowFull = self._buffer:isFull()
	if nowFull == self._wasFull then
		return
	end

	self._wasFull = nowFull
	if nowFull then
		self._log:info("Mind full")
		self._mindFullEvent:Fire()
	else
		self._log:info("Mind freed")
		self._mindFreedEvent:Fire()
	end
end

function MindFullManager:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	if self._changedConn then
		self._changedConn:Disconnect()
		self._changedConn = nil
	end

	self._mindFullEvent:Destroy()
	self._mindFreedEvent:Destroy()
	self._mindFullEvent = nil :: any
	self._mindFreedEvent = nil :: any
	self.mindFull = nil :: any
	self.mindFreed = nil :: any
end

return MindFullManager
