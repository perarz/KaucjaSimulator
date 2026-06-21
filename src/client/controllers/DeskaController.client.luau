-- DeskaController.client.luau

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer.PlayerGui

local Events          = ReplicatedStorage:WaitForChild("Events")
local DeskMount       = Events:WaitForChild("DeskMount")
local DeskDismount    = Events:WaitForChild("DeskDismount")
local DeskMountResult = Events:WaitForChild("DeskMountResult")

local SKATE_ANIM_ID = "rbxassetid://124308620927909"

local mounted          = false
local currentBoard     = nil :: Model?
local currentPrompt    = nil :: ProximityPrompt?
local skateTrack       = nil :: AnimationTrack?
local renderConnection = nil :: RBXScriptConnection?

-- ── Wsiadanie / wysiadanie ────────────────────────────────────────────────────
local function requestDismount()
	if not mounted then return end
	DeskDismount:FireServer()
end

DeskMountResult.OnClientEvent:Connect(function(success: boolean, board: Model?)
	if success and board then
		mounted      = true
		currentBoard = board
		_G["__deskaMounted"] = true  -- SprintController to czyta i blokuje sprint

		if currentPrompt then currentPrompt.Enabled = false end

		-- Wycisz dźwięki kroków natychmiast
		local charNow = localPlayer.Character
		local hrpNow  = charNow and charNow:FindFirstChild("HumanoidRootPart")
		if hrpNow then
			for _, s in hrpNow:GetDescendants() do
				if s:IsA("Sound") then s:Stop(); s.Volume = 0 end
			end
		end

		-- Animacja jazdy
		task.spawn(function()
			local char = localPlayer.Character
			if not char then return end
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end
			local animator = humanoid:FindFirstChildOfClass("Animator")
				or humanoid:WaitForChild("Animator", 5)
			if not animator then return end

			local anim = Instance.new("Animation")
			anim.AnimationId = SKATE_ANIM_ID
			local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
			if not ok or not track then return end
			skateTrack = track

			local animScript = char:FindFirstChild("Animate")
			if animScript then animScript.Enabled = false end

			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				for _, s in hrp:GetDescendants() do
					if s:IsA("Sound") then s:Stop(); s.Volume = 0 end
				end
			end

			for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0) end

			skateTrack.Priority = Enum.AnimationPriority.Action4
			skateTrack.Looped   = true
			skateTrack:Play()

			-- Gracz bokiem: AutoRotate=false + RenderStepped obraca HRP -90° od kamery
			humanoid.AutoRotate = false
			renderConnection = RunService.RenderStepped:Connect(function()
				if not mounted or not hrp or not hrp.Parent then
					if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
					return
				end
				local cam  = workspace.CurrentCamera
				local look = cam.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude < 0.01 then return end
				hrp.CFrame = CFrame.new(hrp.Position)
					* CFrame.lookAt(Vector3.zero, flat.Unit)
					* CFrame.Angles(0, math.rad(-90), 0)
			end)
		end)
	else
		mounted      = false
		currentBoard = nil
		_G["__deskaMounted"] = false  -- sprint znowu dostępny

		if currentPrompt then currentPrompt.Enabled = true end

		if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
		if skateTrack then skateTrack:Stop(); skateTrack = nil end

		local char = localPlayer.Character
		if char then
			local animScript = char:FindFirstChild("Animate")
			if animScript then animScript.Enabled = true end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum.AutoRotate = true end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				for _, s in hrp:GetDescendants() do
					if s:IsA("Sound") then s.Volume = 0.5 end
				end
			end
		end
	end
end)

-- Wspólny handler R / przycisk mobile
local function toggleDeska()
	if mounted then
		requestDismount()
	else
		DeskMount:FireServer(nil)
	end
end

-- R — wsiada / wysiada
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.R then
		toggleDeska()
	end
end)

-- API dla MobileControlsController (przycisk DESKA na ekranie)
_G["__deskaToggle"] = toggleDeska

-- Po respawnie ZAWSZE resetujemy stan klienta — weld zginął z postacią, więc nawet
-- jeśli server's DeskMountResult(false) dotrze z opóźnieniem, nie zostawimy stale
-- `mounted = true` które blokuje wsiadanie (DeskMount fire'uje Dismount zamiast Mount).
localPlayer.CharacterAdded:Connect(function()
	mounted      = false
	currentBoard = nil
	_G["__deskaMounted"] = false
	if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
	if skateTrack then skateTrack:Stop(); skateTrack = nil end
end)
