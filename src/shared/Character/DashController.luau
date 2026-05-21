local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local CFG = GameConfig.DASH

export type DashController = {
	enable: (self: DashController) -> (),
	disable: (self: DashController) -> (),
	destroy: (self: DashController) -> (),
	trigger: (self: DashController) -> (),
}

type DashControllerImpl = DashController & {
	_character: Model,
	_humanoid: Humanoid,
	_hrp: BasePart,
	_animator: Animator,
	_dashTrack: AnimationTrack?,
	_rollTrack: AnimationTrack?,
	_inputConn: RBXScriptConnection?,
	_floorConn: RBXScriptConnection?,
	_canDash: boolean,
	_lastRollTime: number,
	_enabled: boolean,
}

local DashController = {}
DashController.__index = DashController

local log = Logger.new("DashController")

local DASH_ANIM_FOLDER = "DashAnimations"
local DASH_SOUNDS_FOLDER = "DashSounds"
local DASH_EFFECTS_FOLDER = "DashEffects"

function DashController.new(character: Model): DashController
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator

	local self: DashControllerImpl = setmetatable({
		_character    = character,
		_humanoid     = humanoid,
		_hrp          = hrp,
		_animator     = animator,
		_dashTrack    = nil,
		_rollTrack    = nil,
		_inputConn    = nil,
		_floorConn    = nil,
		_canDash      = true,
		_lastRollTime = -math.huge,
		_enabled      = false,
	}, DashController) :: any

	return self
end

-- Returns true when the character is standing on something
function DashController:_isGrounded(): boolean
	return (self._humanoid :: Humanoid).FloorMaterial ~= Enum.Material.Air
end

function DashController:_canRoll(): boolean
	return os.clock() - self._lastRollTime >= CFG.ROLL_DURATION + CFG.ROLL_COOLDOWN
end

-- Load animations lazily (character Animator must exist)
function DashController:_loadAnimations()
	local animFolder = ReplicatedStorage.Shared:FindFirstChild(DASH_ANIM_FOLDER)
	if not animFolder then
		log:warn("DashAnimations folder not found in ReplicatedStorage.Shared")
		return
	end

	local dashAnim = animFolder:FindFirstChild("Dash") :: Animation?
	local rollAnim = animFolder:FindFirstChild("Roll") :: Animation?

	if dashAnim then
		self._dashTrack = self._animator:LoadAnimation(dashAnim)
		self._dashTrack.Priority = Enum.AnimationPriority.Action
	end
	if rollAnim then
		self._rollTrack = self._animator:LoadAnimation(rollAnim)
		self._rollTrack.Priority = Enum.AnimationPriority.Action
	end
end

function DashController:_playTrack(track: AnimationTrack?)
	if not track then return end
	track:Play(CFG.ANIM_FADE_TIME)
end

function DashController:_playSound(name: string)
	local folder = ReplicatedStorage.Shared:FindFirstChild(DASH_SOUNDS_FOLDER)
	if not folder then return end
	local sound = folder:FindFirstChild(name) :: Sound?
	if not sound then return end
	local clone = sound:Clone()
	clone.Parent = self._hrp
	clone:Play()
	task.delay(clone.TimeLength + 0.1, function()
		if clone then clone:Destroy() end
	end)
end

function DashController:_playVFX()
	local folder = ReplicatedStorage.Shared:FindFirstChild(DASH_EFFECTS_FOLDER)
	if not folder then return end
	local template = folder:FindFirstChild("DashParticles") :: BasePart?
	if not template then return end

	local clone = template:Clone()
	clone.CFrame = self._hrp.CFrame
	clone.Parent = workspace

	-- Weld to HRP so it follows the character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self._hrp
	weld.Part1 = clone
	weld.Parent = clone

	task.delay(CFG.VFX_DURATION, function()
		if clone then clone:Destroy() end
	end)
end

-- Apply a velocity burst in the character's horizontal look direction.
-- Uses BodyVelocity with MaxForce.Y = 0 so gravity and floor contact are
-- unaffected — only XZ is driven. LinearVelocity.VectorVelocity constrains
-- all three axes and fights the Humanoid physics stepper on Y.
function DashController:_applyLinearVelocity(speed: number, duration: number, decelerate: boolean)
	local hrp = self._hrp

	local look = hrp.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end

	local bv = Instance.new("BodyVelocity")
	bv.Name = "DashBodyVelocity"
	bv.Velocity = forward * speed
	-- 1e6 is needed to overwhelm the default Humanoid's active deceleration braking.
	-- The Platformer Template's 1500×mass formula works for its custom controller
	-- but is orders of magnitude too weak against the default PlayerModule.
	-- Y=0 so gravity and floor contact are unaffected.
	bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
	bv.Parent = hrp

	if decelerate then
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		local tween = TweenService:Create(bv, tweenInfo, { Velocity = Vector3.new(0, 0, 0) })
		tween:Play()
		tween.Completed:Connect(function()
			if bv.Parent then bv:Destroy() end
		end)
	else
		task.delay(duration, function()
			if bv.Parent then bv:Destroy() end
		end)
	end
end

function DashController:_performDash()
	if not self._canDash then
		log:info("dash blocked — already used in this airtime")
		return
	end
	self._canDash = false
	log:info("dash start")

	self:_applyLinearVelocity(CFG.DASH_SPEED, CFG.DASH_DURATION, false)
	self:_playTrack(self._dashTrack)
	self:_playSound("Dash")
	self:_playVFX()
end

-- Shared entry point for keyboard input and mobile button.
-- Dispatches to roll (grounded) or dash (airborne) so both code paths
-- share the same cooldown gates inside _performDash / _performRoll.
function DashController:trigger()
	if not self._enabled then return end
	if self:_isGrounded() then
		self:_performRoll()
	else
		self:_performDash()
	end
end

function DashController:_performRoll()
	if not self:_canRoll() then
		log:info("roll blocked — cooldown active")
		return
	end
	self._lastRollTime = os.clock()
	log:info("roll start")

	self:_applyLinearVelocity(CFG.ROLL_SPEED, CFG.ROLL_DURATION, true)
	self:_playTrack(self._rollTrack)
	self:_playSound("Roll")
	self:_playVFX()
end

function DashController:enable()
	if self._enabled then return end
	self._enabled = true

	self:_loadAnimations()

	-- Reset canDash when character lands
	self._floorConn = (self._humanoid :: Humanoid):GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		if self._humanoid.FloorMaterial ~= Enum.Material.Air then
			if not self._canDash then
				log:info("landed — dash reset")
			end
			self._canDash = true
		end
	end)

	self._inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		if input.KeyCode ~= CFG.KEY then return end
		self:trigger()
	end)

	log:info("enabled")
end

function DashController:disable()
	if not self._enabled then return end
	self._enabled = false

	if self._inputConn then
		self._inputConn:Disconnect()
		self._inputConn = nil
	end
	if self._floorConn then
		self._floorConn:Disconnect()
		self._floorConn = nil
	end

	if self._dashTrack then
		self._dashTrack:Stop()
	end
	if self._rollTrack then
		self._rollTrack:Stop()
	end

	log:info("disabled")
end

function DashController:destroy()
	self:disable()

	if self._dashTrack then
		self._dashTrack:Destroy()
		self._dashTrack = nil
	end
	if self._rollTrack then
		self._rollTrack:Destroy()
		self._rollTrack = nil
	end

	log:info("destroyed")
end

return DashController
