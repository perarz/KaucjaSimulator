-- CameraEffectsController.client.luau
-- 2 efekty kamery dla bardziej "smooth" feel:
--   1) Speed-based FOV — bazowane na FAKTYCZNEJ prędkości ruchu (XZ velocity HRP),
--      NIE na humanoid.WalkSpeed. Stojąc w miejscu FOV=BASE_FOV nawet gdy WalkSpeed=40
--      (deska/Sprinter pet). Tylko fizyczny ruch podbija FOV.
--   2) Camera smoothing — lerp cam.CFrame z poprzedniej klatki (follow + mouse).
--      ~50ms half-life — wygładza jitter bez "gumowego" lagu.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

-- ── FOV mapping (piecewise: idle → walk → sprint → deska) ──────────────────
-- 3 strefy żeby chodzenie czuło się jak idle, a sprint i deska wyraźnie się różniły.
-- Dlaczego: zwykła liniowa mapa od 16 (BaseSpeed) wybijała FOV już przy walkingu
-- gdy gracz miał czapkę/peta Sprinter (baseSpeed+2..+25), a deska (40-100) clampowała
-- się do tego samego maks co sprint.
local FOV_IDLE         = 65   -- ≤ WALK_PEAK (stanie + chodzenie z bonusami)
local FOV_SPRINT       = 78   -- przy SPRINT_PEAK (sprint pieszo)
local FOV_DESKA        = 95   -- przy DESKA_PEAK (deska / sprinter pet)
local WALK_PEAK        = 22   -- prędkość poniżej której FOV nie rośnie (idle + chodzenie)
local SPRINT_PEAK      = 36   -- typowa prędkość sprintu
local DESKA_PEAK       = 65   -- typowa prędkość deski
local FOV_LERP         = 0.12 -- jak szybko FOV dochodzi do targetu (per-frame)

local function fovForSpeed(s: number): number
	if s <= WALK_PEAK then
		return FOV_IDLE
	elseif s <= SPRINT_PEAK then
		local t = (s - WALK_PEAK) / (SPRINT_PEAK - WALK_PEAK)
		return FOV_IDLE + (FOV_SPRINT - FOV_IDLE) * t
	elseif s <= DESKA_PEAK then
		local t = (s - SPRINT_PEAK) / (DESKA_PEAK - SPRINT_PEAK)
		return FOV_SPRINT + (FOV_DESKA - FOV_SPRINT) * t
	else
		return FOV_DESKA
	end
end

-- ── Camera smoothing ────────────────────────────────────────────────────────
local CAM_LERP        = 0.40  -- 0=max smooth, 1=natychmiastowe. 0.40 ≈ 50ms half-life
local MAX_SNAP_DIST   = 30    -- gdy kamera teleportuje (>30 studs) — snap zamiast ślizgu

-- ── Stan ────────────────────────────────────────────────────────────────────
local currentCam: Camera = Workspace.CurrentCamera
local lastCamCF: CFrame? = nil

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	currentCam = Workspace.CurrentCamera
	lastCamCF = nil
end)

-- ── Per-frame loop ──────────────────────────────────────────────────────────
RunService:BindToRenderStep("CameraEffects", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = currentCam
	if not cam or not cam.Parent then return end

	-- 1) FOV bazowany na velocity HRP (XZ). Idle → FOV_IDLE.
	local char = localPlayer.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local targetFov = FOV_IDLE
	if hrp and hrp:IsA("BasePart") then
		local v = hrp.AssemblyLinearVelocity
		local horizSpeed = math.sqrt(v.X * v.X + v.Z * v.Z)
		targetFov = fovForSpeed(horizSpeed)
	end
	cam.FieldOfView = cam.FieldOfView + (targetFov - cam.FieldOfView) * FOV_LERP

	-- 2) Camera CFrame smoothing.
	if lastCamCF then
		local dist = (cam.CFrame.Position - lastCamCF.Position).Magnitude
		if dist <= MAX_SNAP_DIST then
			cam.CFrame = lastCamCF:Lerp(cam.CFrame, CAM_LERP)
		end
	end
	lastCamCF = cam.CFrame
end)
