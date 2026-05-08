local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local ReticleConfig = require(ReplicatedStorage.Shared.Hud.ReticleConfig)
local AimAssistController = require(script.Parent.AimAssistController)
local AimAssistEnum = require(script.Parent.AimAssistController.AimAssistEnum)
local WeaponTouchInputController = require(script.Parent.WeaponTouchInputController)
local CameraRecoiler = require(script.Parent.CameraRecoiler)
local WeaponAnimationController = require(script.Parent.WeaponAnimationController)
local WeaponGuiController = require(script.Parent.WeaponGuiController)

local WeaponController = require(script.Parent.WeaponController)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)

local drawRayResults = require(script.Parent.Utility.drawRayResults)
local getRayDirections = require(script.Parent.Utility.getRayDirections)
local castRays = require(script.Parent.Utility.castRays)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local remotes = ReplicatedStorage.Shared.Weapon.Remotes
local effects = ReplicatedStorage.Shared.Weapon.Scripts.Effects
local shootRemote = remotes.Shoot
local reloadRemote = remotes.Reload

local random = Random.new()

-- Default camera mode family if a weapon Tool doesn't set the
-- `cameraModeFamily` attribute. The full mode set is derived as
-- `<family>`, `<family>Aiming`, `<family>Sprinting` so the camera
-- config layer (CameraManager) only needs the family registered.
local DEFAULT_CAMERA_MODE_FAMILY = "Handgun"
local CAMERA_MODE_FAMILY_ATTRIBUTE = "cameraModeFamily"

local function deriveCameraModes(family: string): { idle: string, aiming: string, sprinting: string }
	return {
		idle = family,
		aiming = family .. "Aiming",
		sprinting = family .. "Sprinting",
	}
end

-- Inherit: FirearmController -> WeaponController
local FirearmController = setmetatable({}, WeaponController)
FirearmController.__index = FirearmController

function FirearmController.new(
	weapon: Tool,
	config: {
		cameraController: any?,
		viewModelController: any?,
		cameraModes: { idle: string, aiming: string, sprinting: string }?,
		ikChainRoot: string?,
	}
)
	-- 1) construct base (but do NOT auto-initialize yet)
	local self = WeaponController.new(weapon, {
		states = WeaponController.WeaponState,
		initialState = WeaponController.WeaponState.Unequipped,
		autoInitialize = false,
	})

	-- 2) switch metatable to subclass
	setmetatable(self, FirearmController)

	-- 3) Firearm-specific members
	-- Camera mode resolution: explicit config wins, then Tool attribute,
	-- then DEFAULT_CAMERA_MODE_FAMILY. Templates set the attribute in
	-- their init.meta.json (e.g. cameraModeFamily="Handgun" or "Rifle").
	if config.cameraModes then
		self.cameraModes = config.cameraModes
	else
		local family = weapon:GetAttribute(CAMERA_MODE_FAMILY_ATTRIBUTE)
		if type(family) ~= "string" or family == "" then
			family = DEFAULT_CAMERA_MODE_FAMILY
		end
		self.cameraModes = deriveCameraModes(family)
	end
	self.aimAssistController = AimAssistController.new()
	self.guiController = WeaponGuiController.new(weapon)
	self.touchInputController = WeaponTouchInputController.new(weapon)
	self.weaponAnimationController = WeaponAnimationController.new(weapon, {
		ikChainRoot = config.ikChainRoot,
	})

	-- Camera controller (optional - if provided, weapon will control camera)
	self.cameraController = config.cameraController
	self.viewModelController = config.viewModelController

	local haptics = weapon:FindFirstChild("Haptics")
	self.shootHaptic = haptics and haptics:FindFirstChild("ShootHaptic") or nil

	-- Cached aim assist attrs
	self.range = 0
	self.fov = 0
	self.friction = 0
	self.tracking = 0
	self.centering = 0

	-- 4) now run initialize
	self:initialize()

	return self
end

-- ============================================
-- STATE MACHINE CALLBACKS (override)
-- ============================================

function FirearmController:onEnterIdle()
	local WS = WeaponController.WeaponState

	if self.cameraController then
		self.cameraController:setMode(self.cameraModes.idle)
	end

	if self.activated and self:canShoot() then
		self:transitionTo(WS.Firing)
	elseif self:shouldReload() then
		self:transitionTo(WS.Reloading)
	end
end

function FirearmController:onEnterFiring()
	self.shooting = true
	self:startShootingLoop()
	if self.cameraController then
		self.cameraController:setMode(self.cameraModes.aiming)
	end
end

function FirearmController:onEnterReloading()
	self:startReload()
end

function FirearmController:onEnterSprinting()
	if self.cameraController then
		self.cameraController:setMode(self.cameraModes.sprinting)
	end
end

function FirearmController:onExitSprinting()
	-- Camera will be reset by the next state transition
end

function FirearmController:onEnterAiming()
	if self.cameraController then
		self.cameraController:setMode(self.cameraModes.aiming)
	end
end

function FirearmController:onExitAiming()
	-- Camera will be reset by the next state transition
end

function FirearmController:onEnterAimingFiring()
	-- Already in aiming mode, just start firing
end

function FirearmController:onExitAimingFiring()
	WeaponController.onExitAimingFiring(self)
	self.weaponAnimationController:stopShootAnimation()
	-- Camera stays in aiming mode
end

function FirearmController:onEnterAimingReloading()
	-- Already in aiming mode, just reload
end

function FirearmController:onExitAimingReloading()
	-- Camera stays in aiming mode
end

function FirearmController:onEnterUnequipped()
	if self.aimAssistController then
		self.aimAssistController:setDebug(false)
		self.aimAssistController:disable()
	end
	if self.guiController then
		self.guiController:disable()
	end
	if self.touchInputController then
		self.touchInputController:disable()
	end
	if self.weaponAnimationController then
		self.weaponAnimationController:disable()
	end
end

function FirearmController:onExitFiring()
	WeaponController.onExitFiring(self)
	self.weaponAnimationController:stopShootAnimation()
	if self.cameraController then
		self.cameraController:setMode(self.cameraModes.idle)
	end
end

function FirearmController:onExitReloading()
	WeaponController.onExitReloading(self)
	self.guiController:setReloading(false)
	-- Restore passive IK aim tracking after reload
	if self.weaponAnimationController.ikControl then
		self.weaponAnimationController.ikControl.Weight = Constants.IK_PASSIVE_WEIGHT
	end
end

-- ============================================
-- FIREARM ACTIONS
-- ============================================

function FirearmController:recoil()
	local recoilMin = self.weapon:GetAttribute(Constants.RECOIL_MIN_ATTRIBUTE)
	local recoilMax = self.weapon:GetAttribute(Constants.RECOIL_MAX_ATTRIBUTE)

	local xDif = recoilMax.X - recoilMin.X
	local yDif = recoilMax.Y - recoilMin.Y
	local x = recoilMin.X + random:NextNumber() * xDif
	local y = recoilMin.Y + random:NextNumber() * yDif

	CameraRecoiler.recoil(Vector2.new(math.rad(-x), math.rad(y)))
end

function FirearmController:shoot()
	local spread = self.weapon:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = self.weapon:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = self.weapon:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = self.weapon:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)

	self.weaponAnimationController:playShootAnimation()
	self:recoil()

	self.ammo -= 1
	self.guiController:setAmmo(self.ammo)

	-- Bump crosshair spread on each shot (decays automatically via Heartbeat in ReticleBuilder).
	self._spreadNormalized = math.clamp((self._spreadNormalized or 0) + ReticleConfig.SPREAD_PER_SHOT, 0, 1)
	self.guiController:setSpread(self._spreadNormalized)

	local now = Workspace:GetServerTimeNow()
	local origin = camera.CFrame

	local rayDirections = getRayDirections(origin, raysPerShot, math.rad(spread), now)
	for i, dir in rayDirections do
		rayDirections[i] = dir * range
	end

	local rayResults = castRays(player, origin.Position, rayDirections, rayRadius)

	local tagged = {}
	local didTag = false
	for index, rayResult in rayResults do
		if rayResult.taggedHumanoid then
			tagged[tostring(index)] = rayResult.taggedHumanoid
			didTag = true
		end
	end

	if didTag then
		self.guiController:showHitmarker()
	end

	shootRemote:FireServer(now, self.weapon, origin, tagged)

	local effectName = self.weapon and self.weapon:GetAttribute("ShotEffect")
	local effectModule = effects:FindFirstChild(effectName or "laserBeamEffect") or effects.laserBeamEffect
	local shotEffect = require(effectModule)
	local muzzleAttachment = self.weapon:FindFirstChild("MuzzleAttachment", true)
	local drawOrigin = muzzleAttachment and muzzleAttachment.WorldPosition or origin.Position
	for i, rayResult in rayResults do
		if not rayResult.instance then
			rayResult.position = drawOrigin + rayDirections[i].Unit * range
		end
	end
	drawRayResults(drawOrigin, rayResults, shotEffect)

	if self.shootHaptic then
		self.shootHaptic:Play()
	end
end

function FirearmController:startShootingLoop()
	local WS = WeaponController.WeaponState
	local fireMode = self.weapon:GetAttribute(Constants.FIRE_MODE_ATTRIBUTE)
	local rateOfFire = self.weapon:GetAttribute(Constants.RATE_OF_FIRE_ATTRIBUTE)

	if fireMode == Constants.FIRE_MODE.SEMI then
		self:shoot()
		task.delay(Constants.SECONDS_PER_MINUTE / rateOfFire, function()
			if self:isInState(WS.Firing) then
				if not self:canShoot() or not self.activated then
					self:transitionTo(WS.Idle)
				end
			end
		end)
	elseif fireMode == Constants.FIRE_MODE.AUTO then
		self.shootTask = task.spawn(function()
			while self:isInState(WS.Firing) and self:canShoot() and self.activated do
				self:shoot()
				task.wait(Constants.SECONDS_PER_MINUTE / rateOfFire)
			end

			if self:isInState(WS.Firing) then
				if self:shouldReload() then
					self:transitionTo(WS.Reloading)
				else
					self:transitionTo(WS.Idle)
				end
			end
		end)
	end
end

function FirearmController:startReload()
	local WS = WeaponController.WeaponState
	local reloadTime = self.weapon:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)

	self.reloading = true
	self.guiController:setReloading(true)
	reloadRemote:FireServer(self.weapon)

	self.weaponAnimationController:playReloadAnimation(reloadTime)

	self.reloadTask = task.delay(reloadTime, function()
		-- Mirror the server's Ammo.performReload math so we don't refill past
		-- what reserve actually has. Without this, the client jumps to a full
		-- magazine while the server (which silently rejects the reload when
		-- reserve == 0) stays at 0, and every subsequent shot fails validateShot
		-- — the player sees tracers but no damage applies.
		local reserve = self.weapon:GetAttribute(Constants.RESERVE_AMMO_ATTRIBUTE) or 0
		local needed = self.magazineSize - self.ammo
		local transfer = math.min(needed, reserve)
		self.ammo += transfer
		self.reloading = false
		self.reloadTask = nil

		self.guiController:setAmmo(self.ammo)
		self.guiController:setReloading(false)

		if self:isInState(WS.Reloading) then
			if self.activated and self:canShoot() then
				self:transitionTo(WS.Firing)
			else
				self:transitionTo(WS.Idle)
			end
		end
	end)
end

-- ============================================
-- EQUIP/UNEQUIP
-- ============================================

function FirearmController:equip()
	if self.equipped then
		return
	end

	WeaponController.equip(self)

	-- Aim assist setup
	self.range = self.weapon:GetAttribute(Constants.AIM_ASSIST_RANGE_ATTRIBUTE)
	self.fov = self.weapon:GetAttribute(Constants.AIM_ASSIST_FOV_ATTRIBUTE)
	self.friction = self.weapon:GetAttribute(Constants.AIM_ASSIST_FRICTION_STRENGTH_ATTRIBUTE)
	self.tracking = self.weapon:GetAttribute(Constants.AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE)
	self.centering = self.weapon:GetAttribute(Constants.AIM_ASSIST_CENTERING_STRENGTH_ATTRIBUTE)

	self.aimAssistController:setSubject(Workspace.CurrentCamera)
	self.aimAssistController:setRange(self.range)
	self.aimAssistController:setFieldOfView(self.fov)
	self.aimAssistController:addTargetTag(Constants.AIM_ASSIST_TARGET_TAG)
	self.aimAssistController:addPlayerTargets(true, true)
	self.aimAssistController:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, self.friction)
	self.aimAssistController:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, self.tracking)
	self.aimAssistController:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, self.centering)
	self.aimAssistController:setEasingFunc(
		AimAssistEnum.AimAssistEasingAttribute.Distance,
		function(distance: number): number
			return (distance < Constants.AIM_ASSIST_MIN_RANGE) and 0 or 1
		end
	)
	self.aimAssistController:setDebug(false)
	self.aimAssistController:enable()

	-- GUI
	self.guiController:setAmmo(self.ammo)
	self.guiController:setReloading(self.reloading)
	self.guiController:enable()

	-- Touch + anim
	self.touchInputController:enable()
	self.weaponAnimationController:enable()
end

function FirearmController:unequip()
	if not self.equipped then
		return
	end

	WeaponController.unequip(self)
end

-- ============================================
-- INITIALIZE
-- ============================================

function FirearmController:initialize()
	WeaponController.initialize(self)

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(inputObject: InputObject, processed: boolean)
			if processed then
				return
			end
			if
				inputObject.KeyCode == Constants.KEYBOARD_RELOAD_KEY_CODE
				or inputObject.KeyCode == Constants.GAMEPAD_RELOAD_KEY_CODE
			then
				self:reload()
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if
				inputObject.UserInputType == Enum.UserInputType.Gamepad1
				and (inputObject.KeyCode == Enum.KeyCode.Thumbstick1 or inputObject.KeyCode == Enum.KeyCode.Thumbstick2)
			then
				self.aimAssistController:updateGamepadEligibility(inputObject.KeyCode, inputObject.Position)
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.TouchPan:Connect(function()
			self.aimAssistController:updateTouchEligibility()
		end)
	)

	self.touchInputController:setReloadCallback(function()
		self:reload()
	end)
end

function FirearmController:disable()
	WeaponController.disable(self)

	if self.aimAssistController then
		self.aimAssistController:disable()
	end
	if self.touchInputController then
		self.touchInputController:disable()
	end
	if self.weaponAnimationController then
		self.weaponAnimationController:disable()
	end
	if self.guiController then
		self.guiController:disable()
	end
end

function FirearmController:destroy()
	self:disable()
	disconnectAndClear(self.connections)

	if self.aimAssistController then
		self.aimAssistController:destroy()
	end
	if self.touchInputController then
		self.touchInputController:destroy()
	end
	if self.weaponAnimationController then
		self.weaponAnimationController:destroy()
	end
	if self.guiController then
		self.guiController:destroy()
	end
end

return FirearmController
