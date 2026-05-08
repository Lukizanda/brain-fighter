local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local lerp = require(ReplicatedStorage.Utility.lerp)

local camera = Workspace.CurrentCamera

local recoil = Vector2.new()
local zoom = 0
-- Track the zoom we applied last frame so we can subtract it before adding
-- this frame's. Without this, FOV drifts upward each shot (old bug: the
-- previous implementation did `FOV += zoom` every frame with no reversal,
-- so during each recoil decay the FOV would permanently inflate by ~3°
-- before returning, and the camera felt like it was slowly zooming out).
local lastAppliedZoom = 0

local function onRenderStepped(deltaTime: number)
	camera.CFrame *= CFrame.Angles(recoil.Y * deltaTime, recoil.X * deltaTime, 0)
	-- Undo last frame's bump, apply this frame's — net effect is that FOV
	-- stays layered on top of whatever CameraController has written as the
	-- base, without accumulating across frames.
	camera.FieldOfView = camera.FieldOfView - lastAppliedZoom + zoom
	lastAppliedZoom = zoom
	recoil = recoil:Lerp(Vector2.zero, math.min(deltaTime * Constants.RECOIL_STOP_SPEED, 1))
	zoom = lerp(zoom, 0, math.min(deltaTime * Constants.RECOIL_ZOOM_RETURN_SPEED, 1))
end

local CameraRecoiler = {}

function CameraRecoiler.recoil(recoilAmount: Vector2)
	zoom = 1
	recoil += recoilAmount
end

-- apply recoil after aim assist
RunService:BindToRenderStep(Constants.RECOIL_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, onRenderStepped)

return CameraRecoiler
