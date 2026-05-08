----------------------------------------------------------------------
-- MeleeSwingController (client-side)
----------------------------------------------------------------------
-- Drives the local swing state machine for a melee tool. Built directly
-- on WeaponStateMachine; deliberately does NOT inherit WeaponController
-- because that base class assumes firearm semantics (ammo, reload, aim).
--
-- Flow (hybrid authority — client detects, server validates):
--   Unequipped --equip--> Idle --activate--> Windup
--     Windup --timer--> Active
--       Active: Heartbeat-sample MeleeHitDetector at the blade's current
--       CFrame (Handle.CFrame, which tracks the swing animation via the
--       Tool grip weld). Accumulate hits into _claimedHits (deduped).
--     Active --timer--> Recovery
--       On Active exit: fire SwingRequest(weapon, clientTime, claimList)
--       The server validates each claim (cooldown, distance, alive, LOS,
--       payload sanity) and applies damage only for plausible hits.
--     Recovery --timer--> Idle
--
-- Cooldown is measured from Active entry to prevent spam. The client
-- enforces it for responsiveness; the server re-validates.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponStateMachine = require(ReplicatedStorage.Shared.Weapon.Scripts.WeaponStateMachine.WeaponStateMachine)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)
local MeleeHitDetector = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeHitDetector)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local playSoundFromSource = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.playSoundFromSource)

local log = Logger.new("MeleeSwingController")

local DEBUG_HITBOX_ATTRIBUTE = "MeleeHitboxDebug" -- workspace attribute; set true to visualize swept hitbox during Active
local DEBUG_HITBOX_LIFETIME = 1.0 -- seconds the debug Part stays visible (longer than Active so you can actually see it)

-- Dev-only: setting workspace:SetAttribute("DevTriggerSwing", true) from
-- anywhere (edit-time MCP, a test script, Studio Properties) fires a swing
-- on every equipped melee controller, then resets the attribute. Lets us
-- E2E-exercise the client→server claim pipeline without simulating a click.
local DEV_TRIGGER_ATTRIBUTE = "DevTriggerSwing"

local State = MeleeConstants.State
local Attr = {
	Windup = MeleeConstants.WINDUP_SECONDS_ATTRIBUTE,
	Active = MeleeConstants.ACTIVE_SECONDS_ATTRIBUTE,
	Recovery = MeleeConstants.RECOVERY_SECONDS_ATTRIBUTE,
	Cooldown = MeleeConstants.COOLDOWN_SECONDS_ATTRIBUTE,
}

local DEFAULT_WINDUP = 0.15
local DEFAULT_ACTIVE = 0.1
local DEFAULT_RECOVERY = 0.25
local DEFAULT_COOLDOWN = 0.5

local MeleeSwingController = {}
MeleeSwingController.__index = MeleeSwingController

local swingRequestRemote = ReplicatedStorage.Shared.Weapon.Remotes:WaitForChild(
	MeleeConstants.SWING_REQUEST_REMOTE
)

local function readAttr(weapon: Tool, attr: string, default: number): number
	local v = weapon:GetAttribute(attr)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return default
end

function MeleeSwingController.new(weapon: Tool)
	local self = setmetatable({
		weapon = weapon,
		equipped = false,
		activated = false, -- attack button held
		connections = {},
		phaseTask = nil, -- current task.delay handle; canceled on state change
		lastSwingStart = 0, -- workspace:GetServerTimeNow() when we last entered Active
		-- (server-synced so the server's stale-claim check sees a consistent
		-- clock; os.clock() diverges per VM in multi-client Studio tests)
		stateMachine = nil,
		swingTrack = nil, -- AnimationTrack loaded from weapon's SwingAnimation child
		claimedHits = {} :: { [Humanoid]: true }, -- dedupe set for the current swing's Active window
		activeSampleConnection = nil :: RBXScriptConnection?, -- Heartbeat driver during Active
	}, MeleeSwingController)

	self.stateMachine = WeaponStateMachine.new(State, {
		initialState = State.Unequipped,
		controller = self,
		onEnter = {
			[State.Idle] = function(c) c:onEnterIdle() end,
			[State.Windup] = function(c) c:onEnterWindup() end,
			[State.Active] = function(c) c:onEnterActive() end,
			[State.Recovery] = function(c) c:onEnterRecovery() end,
			[State.Unequipped] = function(c) c:onEnterUnequipped() end,
		},
	})

	self:_wireEvents()
	return self
end

-- ============================================
-- Event wiring
-- ============================================

-- Stops Roblox's auto-played "ToolNoneAnim" so the character keeps its
-- normal idle/walk animation while holding the sword. Without this, the
-- engine forces a generic tool-holding pose that overrides the arm.
function MeleeSwingController:_suppressDefaultToolAnim()
	local character = self.weapon.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Name == "ToolNoneAnim" then
			track:Stop(0)
		end
	end
end

function MeleeSwingController:_loadSwingTrack()
	local animInstance = self.weapon:FindFirstChild("SwingAnimation")
	if not animInstance or not animInstance:IsA("Animation") then
		log:warn("_loadSwingTrack: no SwingAnimation child on weapon")
		return
	end
	local character = self.weapon.Parent
	if not character or not character:IsA("Model") then
		log:warn("_loadSwingTrack: weapon not parented to a character Model (parent=" .. tostring(character) .. ")")
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:warn("_loadSwingTrack: no Humanoid on character " .. character.Name)
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 1)
	if not animator then
		log:warn("_loadSwingTrack: no Animator on humanoid")
		return
	end
	self.swingTrack = animator:LoadAnimation(animInstance)
	self.swingTrack.Priority = Enum.AnimationPriority.Action
	self.swingTrack.Looped = false
	log:info("Swing track loaded: " .. animInstance.AnimationId)
end

function MeleeSwingController:_unloadSwingTrack()
	if self.swingTrack then
		self.swingTrack:Stop(0)
		self.swingTrack:Destroy()
		self.swingTrack = nil
	end
end

function MeleeSwingController:_wireEvents()
	table.insert(self.connections, self.weapon.Equipped:Connect(function()
		log:info("Equipped")
		self.equipped = true
		self:_suppressDefaultToolAnim()
		-- ToolNoneAnim can respawn on character reset/animator refresh;
		-- swallow it whenever the animator starts a new one.
		local character = self.weapon.Parent
		local humanoid = character and character:IsA("Model") and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			table.insert(self.connections, animator.AnimationPlayed:Connect(function(track)
				if track.Name == "ToolNoneAnim" then
					track:Stop(0)
				end
			end))
		end
		self:_loadSwingTrack()
		self.stateMachine:transitionTo(State.Idle)
	end))

	table.insert(self.connections, self.weapon.Unequipped:Connect(function()
		self.equipped = false
		self.activated = false
		self:_cancelPhaseTask()
		self:_unloadSwingTrack()
		self.stateMachine:transitionTo(State.Unequipped)
	end))

	table.insert(self.connections, self.weapon.Activated:Connect(function()
		log:info("Activated")
		self.activated = true
		self:_tryStartSwing()
	end))

	table.insert(self.connections, self.weapon.Deactivated:Connect(function()
		self.activated = false
	end))

	-- Dev trigger: treat a rising-edge on workspace:GetAttribute(DEV_TRIGGER_ATTRIBUTE)
	-- as a synthetic click. Self-resets to false so the next write re-fires.
	table.insert(self.connections,
		workspace:GetAttributeChangedSignal(DEV_TRIGGER_ATTRIBUTE):Connect(function()
			local v = workspace:GetAttribute(DEV_TRIGGER_ATTRIBUTE)
			log:info(string.format("DevTriggerSwing changed: value=%s equipped=%s",
				tostring(v), tostring(self.equipped)))
			if v ~= true then
				return
			end
			if not self.equipped then
				return
			end
			self.activated = true
			self:_tryStartSwing()
			workspace:SetAttribute(DEV_TRIGGER_ATTRIBUTE, false)
		end))
end

-- ============================================
-- Swing lifecycle
-- ============================================

function MeleeSwingController:_tryStartSwing()
	if not self.equipped then
		log:info("tryStartSwing: blocked (not equipped)")
		return
	end
	if not self.stateMachine:isInState(State.Idle) then
		log:info("tryStartSwing: blocked (state=" .. self.stateMachine:getCurrentState() .. ")")
		return
	end
	local cooldown = readAttr(self.weapon, Attr.Cooldown, DEFAULT_COOLDOWN)
	local now = workspace:GetServerTimeNow()
	if now - self.lastSwingStart < cooldown then
		log:info(string.format("tryStartSwing: blocked (cooldown %.2fs remaining)",
			cooldown - (now - self.lastSwingStart)))
		return
	end
	log:info("tryStartSwing: starting swing -> Windup")
	self.stateMachine:transitionTo(State.Windup)
end

function MeleeSwingController:_cancelPhaseTask()
	if self.phaseTask then
		task.cancel(self.phaseTask)
		self.phaseTask = nil
	end
end

function MeleeSwingController:_schedulePhase(seconds: number, nextState: string)
	self:_cancelPhaseTask()
	self.phaseTask = task.delay(seconds, function()
		self.phaseTask = nil
		if self.equipped then
			self.stateMachine:transitionTo(nextState)
		end
	end)
end

-- ============================================
-- State handlers
-- ============================================

function MeleeSwingController:onEnterIdle()
	-- If the attack button is still held, chain another swing after cooldown
	if self.activated then
		task.defer(function()
			self:_tryStartSwing()
		end)
	end
end

-- Finds the spatial audio target on the character's weapon (Handle.AudioEmitter).
-- Sounds played through this are positioned at the weapon in 3D space.
function MeleeSwingController:_getAudioTarget(): Instance?
	local handle = self.weapon:FindFirstChild("Handle")
	return handle and handle:FindFirstChildOfClass("AudioEmitter")
end

-- Plays a one-shot sound by name from the Tool's Sounds folder through the
-- weapon's AudioEmitter. No-ops if either is missing (e.g. Sword has no
-- Shoot/Reload sounds, only a Swoosh on Windup).
function MeleeSwingController:_playSound(name: string)
	local sounds = self.weapon:FindFirstChild("Sounds")
	local player = sounds and sounds:FindFirstChild(name)
	local target = self:_getAudioTarget()
	if player and target then
		playSoundFromSource(player, target)
	end
end

function MeleeSwingController:onEnterWindup()
	self:_playSound("Swoosh")
	if self.swingTrack then
		self.swingTrack:Stop(0)
		self.swingTrack:Play(0.05)
	end
	local seconds = readAttr(self.weapon, Attr.Windup, DEFAULT_WINDUP)
	self:_schedulePhase(seconds, State.Active)
end

-- Draws the swept hitbox as a translucent red Part for DEBUG_HITBOX_LIFETIME
-- seconds. Gated by workspace:GetAttribute("MeleeHitboxDebug"); no-op in
-- normal play. Uses the same origin (Handle.CFrame) and geometry the
-- client hit detector uses, so what you see is exactly what gets
-- hit-tested against during the first Heartbeat of Active.
function MeleeSwingController:_drawHitboxDebug()
	if not workspace:GetAttribute(DEBUG_HITBOX_ATTRIBUTE) then
		return
	end
	local handle = self.weapon:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	local reach = readAttr(self.weapon, MeleeConstants.REACH_ATTRIBUTE, 6)
	local width = readAttr(self.weapon, MeleeConstants.HITBOX_WIDTH_ATTRIBUTE, 5)
	local height = readAttr(self.weapon, MeleeConstants.HITBOX_HEIGHT_ATTRIBUTE, 5)

	local box = Instance.new("Part")
	box.Name = "MeleeHitboxDebug"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Massless = true
	box.Material = Enum.Material.ForceField
	box.Color = Color3.fromRGB(255, 60, 60)
	box.Transparency = 0.5
	box.Size = Vector3.new(width, height, reach)
	-- Matches MeleeHitDetector.sweep: box center is reach/2 forward of origin
	box.CFrame = handle.CFrame * CFrame.new(0, 0, -reach * 0.5)
	box.Parent = workspace
	game:GetService("Debris"):AddItem(box, DEBUG_HITBOX_LIFETIME)
end

-- Runs one hit-detection sweep at the current blade CFrame. Accumulates
-- results into self.claimedHits (mutated by the detector's dedupe set).
function MeleeSwingController:_sampleActiveHitbox()
	local character = self.weapon.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local handle = self.weapon:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	-- Using Handle.CFrame as origin means hit detection tracks the swing
	-- animation (the Handle is welded to the right grip, which the arm
	-- animation rotates). This is what gives the feel of "blade passed
	-- through enemy → hit lands".
	MeleeHitDetector.sweep({
		originCFrame = handle.CFrame,
		reach = readAttr(self.weapon, MeleeConstants.REACH_ATTRIBUTE, 6),
		width = readAttr(self.weapon, MeleeConstants.HITBOX_WIDTH_ATTRIBUTE, 5),
		height = readAttr(self.weapon, MeleeConstants.HITBOX_HEIGHT_ATTRIBUTE, 5),
		attackerCharacter = character,
		hitMode = self.weapon:GetAttribute(MeleeConstants.HIT_MODE_ATTRIBUTE)
			or MeleeConstants.HitMode.Single,
		alreadyHit = self.claimedHits,
	})
end

function MeleeSwingController:_stopActiveSampling()
	if self.activeSampleConnection then
		self.activeSampleConnection:Disconnect()
		self.activeSampleConnection = nil
	end
end

function MeleeSwingController:onEnterActive()
	self.lastSwingStart = workspace:GetServerTimeNow()
	self.claimedHits = {}
	self:_drawHitboxDebug()
	-- Start per-frame hit sampling. The detector's dedupe set prevents
	-- the same humanoid from being claimed twice across Heartbeat ticks.
	self:_stopActiveSampling()
	self.activeSampleConnection = RunService.Heartbeat:Connect(function()
		self:_sampleActiveHitbox()
	end)
	local seconds = readAttr(self.weapon, Attr.Active, DEFAULT_ACTIVE)
	self:_schedulePhase(seconds, State.Recovery)
end

function MeleeSwingController:onEnterRecovery()
	-- End of damage window: stop sampling and ship the accumulated claim
	-- list to the server. Server will validate each claim independently.
	self:_stopActiveSampling()
	local claimList = {}
	for humanoid in self.claimedHits do
		table.insert(claimList, humanoid)
	end
	swingRequestRemote:FireServer(self.weapon, self.lastSwingStart, claimList)
	log:info(string.format("Claims sent: %d humanoid(s)", #claimList))

	local seconds = readAttr(self.weapon, Attr.Recovery, DEFAULT_RECOVERY)
	self:_schedulePhase(seconds, State.Idle)
end

function MeleeSwingController:onEnterUnequipped()
	self:_stopActiveSampling()
	self:_cancelPhaseTask()
end

-- ============================================
-- Public
-- ============================================

function MeleeSwingController:getCurrentState(): string
	return self.stateMachine:getCurrentState()
end

function MeleeSwingController:destroy()
	self:_stopActiveSampling()
	self:_cancelPhaseTask()
	self:_unloadSwingTrack()
	disconnectAndClear(self.connections)
end

return MeleeSwingController
