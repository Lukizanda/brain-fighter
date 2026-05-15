--!strict

----------------------------------------------------------------------
-- LetterBlaster controller
-- Tool.Activated → raycast → hit LetterBlock → consume + laser blast.
-- No reticle: player taps/clicks directly on the block they want.
----------------------------------------------------------------------

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockShoot          = require(ReplicatedStorage.Shared.BlockShoot)
local laserBeamEffect     = require(ReplicatedStorage.Shared.Weapon.Scripts.Effects.laserBeamEffect)
local LetterBlasterConfig = require(script.LetterBlasterConfig)
local Logger              = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LetterBlaster")

local consumeRemote = ReplicatedStorage.Shared.BlockShoot.Remotes.ConsumeBlock :: RemoteEvent

type IWordBuffer      = { append: (IWordBuffer, string, string) -> boolean }
type IMindFullManager = { isMindFull: (IMindFullManager) -> boolean }
type ISession         = { wordBuffer: IWordBuffer, mindFullManager: IMindFullManager }

export type Controller = {
	mount:   (self: Controller) -> (),
	destroy: (self: Controller) -> (),
}

type ControllerImpl = Controller & {
	_tool:        Tool,
	_session:     ISession,
	_connections: { RBXScriptConnection },
	_lastFired:   number,
}

local LetterBlaster = {}
LetterBlaster.__index = LetterBlaster

function LetterBlaster.new(tool: Tool, session: ISession): Controller
	local self: ControllerImpl = setmetatable({} :: any, LetterBlaster)
	self._tool        = tool
	self._session     = session
	self._connections = {}
	self._lastFired   = -math.huge
	return self
end

function LetterBlaster:_onActivated()
	local now = os.clock()
	if now - self._lastFired < LetterBlasterConfig.COOLDOWN then
		return
	end
	self._lastFired = now

	if self._session.mindFullManager:isMindFull() then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local character = Players.LocalPlayer.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if character then
		params.FilterDescendantsInstances = { character }
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * BlockShoot.MAX_RAYCAST_DISTANCE, params)

	local fireSound = self._tool:FindFirstChild(LetterBlasterConfig.FIRE_SOUND_NAME) :: Sound?
	if fireSound then fireSound:Play() end

	if not result then return end

	local block = BlockShoot.findLetterBlock(result.Instance)
	if not block then return end

	local letter, color = BlockShoot.readBlock(block)
	if not letter or not color then return end

	-- Laser blast from Muzzle attachment (crook) toward the block.
	local handle = self._tool:FindFirstChild("Handle") :: BasePart?
	if handle then
		local muzzle = handle:FindFirstChild("Muzzle") :: Attachment?
		local origin = if muzzle then muzzle.WorldPosition else handle.Position
		laserBeamEffect(origin, block:GetPivot().Position)
	end

	local appended = self._session.wordBuffer:append(letter, color)
	if not appended then return end

	consumeRemote:FireServer(block)
	log:info(string.format("consumed %s (%s)", letter, color))

	local hitSound = self._tool:FindFirstChild(LetterBlasterConfig.HIT_SOUND_NAME) :: Sound?
	if hitSound then hitSound:Play() end
end

function LetterBlaster:mount()
	local conn = self._tool.Activated:Connect(function()
		self:_onActivated()
	end)
	table.insert(self._connections, conn)
	log:info("mounted")
end

function LetterBlaster:destroy()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
	log:info("destroyed")
end

return LetterBlaster
