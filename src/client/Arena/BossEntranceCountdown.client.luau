--!strict

----------------------------------------------------------------------
-- BossEntranceCountdown
----------------------------------------------------------------------
-- Draws the "boss incoming" countdown over the BossPoint while the boss
-- entrance is running. The server (BossService) tags the BossPoint with
-- `BossConstants.ENTRANCE_TAG` and publishes the instant the boss appears as
-- `BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE` in `workspace:GetServerTimeNow()`
-- time, which is the one clock the server and every client agree on
-- (os.clock is per-VM). This script owns only what a player sees: a
-- billboard counting down to that instant. The tag coming off ends it.
--
-- Greybox quality: a header and a whole-second number, one BillboardGui per
-- tagged part. A late joiner's first sight of a running entrance is just a
-- tagged part with an attribute already on it, which draws the same way.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BossEntranceCountdown")

local ROOT_GUI_NAME = "BossEntranceCountdown"
-- Label font sizing: the header is the smaller line above the number.
local HEADER_HEIGHT_SCALE = 0.35
local NUMBER_HEIGHT_SCALE = 0.65
-- Shown when the attribute has not arrived yet (tag and attribute replicate
-- independently) or has already passed.
local NO_TIME_TEXT = "..."

type Tell = {
	billboard: BillboardGui,
	number: TextLabel,
}

local tells: { [BasePart]: Tell } = {}
local tagConns: { RBXScriptConnection } = {}
local refreshThread: thread? = nil

local function secondsLeft(part: BasePart): number?
	local appearAt = part:GetAttribute(BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE)
	if typeof(appearAt) ~= "number" then
		return nil
	end
	return math.max(0, (appearAt :: number) - workspace:GetServerTimeNow())
end

local function draw(part: BasePart, tell: Tell)
	local left = secondsLeft(part)
	tell.number.Text = if left then tostring(math.ceil(left)) else NO_TIME_TEXT
end

local function makeLabel(parent: Instance, text: string, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, height)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = BossConstants.ENTRANCE_LABEL_TEXT_COLOR
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = parent
	return label
end

local function attach(instance: Instance)
	if not instance:IsA("BasePart") or tells[instance] then
		return
	end
	local part: BasePart = instance
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = ROOT_GUI_NAME
	billboard.Adornee = part
	billboard.Size = BossConstants.ENTRANCE_LABEL_SIZE
	billboard.StudsOffset = Vector3.new(0, BossConstants.ENTRANCE_LABEL_HEIGHT_STUDS, 0)
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	makeLabel(billboard, BossConstants.ENTRANCE_LABEL_HEADER, 0, HEADER_HEIGHT_SCALE)
	local number = makeLabel(billboard, NO_TIME_TEXT, HEADER_HEIGHT_SCALE, NUMBER_HEIGHT_SCALE)
	billboard.Parent = playerGui

	local tell: Tell = { billboard = billboard, number = number }
	tells[part] = tell
	draw(part, tell)
end

local function detach(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local tell = tells[instance]
	if tell then
		tells[instance] = nil
		tell.billboard:Destroy()
	end
end

table.insert(tagConns, CollectionService:GetInstanceAddedSignal(BossConstants.ENTRANCE_TAG):Connect(attach))
table.insert(tagConns, CollectionService:GetInstanceRemovedSignal(BossConstants.ENTRANCE_TAG):Connect(detach))
for _, part in CollectionService:GetTagged(BossConstants.ENTRANCE_TAG) do
	attach(part)
end

refreshThread = task.spawn(function()
	while true do
		for part, tell in tells do
			draw(part, tell)
		end
		task.wait(BossConstants.ENTRANCE_LABEL_REFRESH_SEC)
	end
end)

-- Rojo replaces this script on every sync; drop what it made.
script.Destroying:Connect(function()
	for _, conn in tagConns do
		conn:Disconnect()
	end
	table.clear(tagConns)
	if refreshThread then
		pcall(task.cancel, refreshThread)
		refreshThread = nil
	end
	for part in tells do
		detach(part)
	end
end)

log:info("ready")
