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

-- Play one of the staff's own Sounds.
--
-- They hang off the Handle, not the Tool. A Sound parented to a BasePart
-- is 3D-positional; one parented to the Tool is not, and would reach a
-- bystander at full volume from anywhere on the map. That distinction is
-- what makes the fire sound safe to replicate at all — see
-- BlockShootService.broadcastShot.
function LetterBlaster:_playSound(soundName: string)
	local handle = BlockShoot.resolveHandle(self._tool)
	if not handle then return end
	local sound = handle:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

function LetterBlaster:_onActivated()
	local now = os.clock()
	if now - self._lastFired < LetterBlasterConfig.COOLDOWN then
		log:infoThrottled("cooldown", 1, "on cooldown — skipping")
		return
	end
	self._lastFired = now

	if self._session.mindFullManager:isMindFull() then
		self:_playSound(LetterBlasterConfig.FIZZLE_SOUND_NAME)
		log:info("blocked: mind is full")
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		log:warn("no CurrentCamera")
		return
	end

	local character = Players.LocalPlayer.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if character then
		params.FilterDescendantsInstances = { character }
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * BlockShoot.MAX_RAYCAST_DISTANCE, params)

	self:_playSound(LetterBlasterConfig.FIRE_SOUND_NAME)

	if not result then
		log:info("raycast miss — nothing in crosshair within range")
		return
	end
	log:info(string.format("hit '%s' (%.1f studs)", result.Instance:GetFullName(), result.Distance))

	local block = BlockShoot.findLetterBlock(result.Instance)
	if not block then
		log:info(string.format("'%s' has no LetterBlock ancestor", result.Instance.Name))
		return
	end

	local letter, color = BlockShoot.readBlock(block)
	if not letter or not color then
		log:warn(string.format("block '%s' missing Letter/Color attrs", block.Name))
		return
	end

	-- Read before firing: the server destroys the block, and we want the
	-- beam endpoint from where it stood, not from a Model mid-teardown.
	local blockPos = block:GetPivot().Position

	local appended = self._session.wordBuffer:append(letter, color)
	if not appended then
		self:_playSound(LetterBlasterConfig.FIZZLE_SOUND_NAME)
		log:info(string.format("buffer rejected '%s' (%s)", letter, color))
		return
	end

	consumeRemote:FireServer(block)
	log:info(string.format("consumed %s (%s)", letter, color))

	-- Laser blast from the Muzzle attachment (crook) toward the block.
	--
	-- Drawn here rather than waiting for the server's copy to arrive: this
	-- is the prediction layer, cosmetic-only, and the shot should leave the
	-- staff on the frame the player clicked. BlockShootService redraws this
	-- same beam for every OTHER client once it has validated the consume,
	-- and excludes us so we never see it twice.
	--
	-- Deliberately below the buffer check, not above it as it was: a shot
	-- the buffer rejected used to draw a beam for the shooter that no other
	-- player could ever have a matching beam for, because the consume that
	-- triggers the broadcast never happened.
	local origin = BlockShoot.muzzlePosition(self._tool)
	if origin then
		laserBeamEffect(origin, blockPos)
	end

	-- Hit confirmation, and deliberately not broadcast. This is the same
	-- thing a hit marker is: feedback telling the shooter their shot landed.
	-- Other players get the fire sound, which is the event that happened in
	-- the world; whether it connected is the shooter's business.
	self:_playSound(LetterBlasterConfig.HIT_SOUND_NAME)
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
