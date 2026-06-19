-- IntroController.luau
-- Minimalna wersja TEST — lerpuje kamerę między Cam_Scene1 i Cam_Scene1_End,
-- letterbox czarne paski góra/dół, skip ESC lub przycisk POMIŃ.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local FONT       = Enum.Font.GothamBlack
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_BLACK    = Color3.new(0, 0, 0)

-- ── Tunable ──────────────────────────────────────────────────────────────

local NPC_NAME = "Marcelk1122"

-- Definicje scen (kolejność = kolejność odtwarzania).
-- Pola opcjonalne: animName, bottle, npcMarker
local SCENES = {
	{
		id          = "Scene1",
		text        = "ZBIERAJ BUTELKI",
		cameraStart = "Cam_Scene1",
		cameraEnd   = "Cam_Scene1_End",
		duration    = 3.5,
		-- animName usunięte — NPC w statycznej pozie sugerującej zbieranie
		bottle      = {
			delay  = 0,                          -- butelka od razu w ręce
			rarity = "Legendarna",
			offset = CFrame.new(0, -0.6, 0),
		},
		-- npcMarker = "NPC_Scene1",
	},
	{
		id          = "Scene2",
		text        = "ODDAWAJ I ZBIERAJ KASE",
		cameraStart = "Cam_Scene2",
		cameraEnd   = "Cam_Scene2_End",
		duration    = 3.5,
		-- animName = "Deposit",      -- gdy będzie gotowa
		-- bottle   = nil
		-- npcMarker = "NPC_Scene2",
	},
	{
		id          = "Scene3",
		text        = "ULEPSZAJ WYPOSAŻENIE",
		cameraStart = "Cam_Scene3",
		cameraEnd   = "Cam_Scene3_End",
		duration    = 3.5,
		-- animName = "Rummage",      -- gdy będzie gotowa
		-- bottle   = nil
		-- npcMarker = "NPC_Scene3",
	},
}
local BAR_H             = 100    -- wysokość czarnych pasów w pikselach
local LETTERBOX_TI_IN   = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local LETTERBOX_TI_OUT  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local TEXT_FADE_TI      = TweenInfo.new(0.40, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local function cameraTweenInfo(duration: number): TweenInfo
	return TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

-- ── ScreenGui ────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "Intro"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 100
gui.Enabled        = false
gui.Parent         = playerGui

-- Top bar
local topBar = Instance.new("Frame")
topBar.AnchorPoint           = Vector2.new(0, 0)
topBar.Size                  = UDim2.new(1, 0, 0, BAR_H)
topBar.Position              = UDim2.fromOffset(0, -BAR_H)  -- ukryty na starcie
topBar.BackgroundColor3      = C_BLACK
topBar.BackgroundTransparency = 0
topBar.BorderSizePixel       = 0
topBar.ZIndex                = 5
topBar.Parent                = gui

-- Bottom bar
local botBar = Instance.new("Frame")
botBar.AnchorPoint           = Vector2.new(0, 1)
botBar.Size                  = UDim2.new(1, 0, 0, BAR_H)
botBar.Position              = UDim2.new(0, 0, 1, BAR_H)   -- ukryty na starcie
botBar.BackgroundColor3      = C_BLACK
botBar.BackgroundTransparency = 0
botBar.BorderSizePixel       = 0
botBar.ZIndex                = 5
botBar.Parent                = gui

-- Tekst sceny (na dole, nad bot barem)
local textLbl = Instance.new("TextLabel")
textLbl.AnchorPoint            = Vector2.new(0.5, 1)
textLbl.Size                   = UDim2.fromOffset(700, 84)
textLbl.Position               = UDim2.new(0.5, 0, 1, -BAR_H - 14)
textLbl.BackgroundTransparency = 1
textLbl.Text                   = ""
textLbl.TextSize               = 52
textLbl.Font                   = FONT
textLbl.TextColor3             = C_WHITE
textLbl.TextStrokeColor3       = C_BLACK
textLbl.TextStrokeTransparency = 0.2
textLbl.TextTransparency       = 1
textLbl.ZIndex                 = 6
textLbl.Parent                 = gui

-- Skip button (prawy dolny róg, nad bot barem)
local skipBtn = Instance.new("TextButton")
skipBtn.AnchorPoint            = Vector2.new(1, 1)
skipBtn.Size                   = UDim2.fromOffset(180, 44)
skipBtn.Position               = UDim2.new(1, -20, 1, -BAR_H - 14)
skipBtn.BackgroundColor3       = Color3.fromRGB(18, 91, 73)
skipBtn.BackgroundTransparency = 0.2
skipBtn.BorderSizePixel        = 0
skipBtn.Text                   = "POMIŃ ›"
skipBtn.TextSize               = 18
skipBtn.Font                   = FONT
skipBtn.TextColor3             = C_WHITE
skipBtn.AutoButtonColor        = false
skipBtn.ZIndex                 = 6
skipBtn.Parent                 = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = skipBtn
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(15,15,15); s.Thickness = 2; s.Parent = skipBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = skipBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	skipBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.06 }):Play() end)
	skipBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- ── Stan ──────────────────────────────────────────────────────────────────

local active           = false
local origCameraType   = Enum.CameraType.Custom
local origCameraSubject: Instance? = nil
local cameraTween: Tween?          = nil

-- Spawnowana butelka w ręce NPC (do clean-upu)
local spawnedBottle: Instance? = nil
-- Aktualnie grany AnimationTrack na NPC
local npcAnimTrack: AnimationTrack? = nil
-- Tryb autoplay (pierwsze wejście) — wtedy stop() fire'uje IntroFinished do serwera
local autoPlayMode = false

-- Lista ScreenGui (innych niż intro) które wyłączyliśmy na czas cutsceny
local hiddenGuis: { [ScreenGui]: boolean } = {}

local function hideOtherGuis()
	hiddenGuis = {}
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child ~= gui and child.Enabled then
			hiddenGuis[child] = true
			child.Enabled = false
		end
	end
end

local function restoreOtherGuis()
	for sg in pairs(hiddenGuis) do
		if sg.Parent then sg.Enabled = true end
	end
	hiddenGuis = {}
end

-- ── Helpery ──────────────────────────────────────────────────────────────

local function findNPC(): Model?
	local stage = workspace:FindFirstChild("CutsceneStage")
	if stage then
		local n = stage:FindFirstChild(NPC_NAME, true)
		if n and n:IsA("Model") then return n :: Model end
	end
	local n = workspace:FindFirstChild(NPC_NAME, true)
	if n and n:IsA("Model") then return n :: Model end
	return nil
end

local function playNpcAnimation(animName: string)
	local npc = findNPC()
	if not npc then return end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[Intro] NPC nie ma Humanoid")
		return
	end

	local animFolder = ReplicatedStorage:FindFirstChild("IntroAnims")
	if not animFolder then
		warn("[Intro] Brak ReplicatedStorage.IntroAnims (czy IntroService się załadował?)")
		return
	end
	local anim = animFolder:FindFirstChild(animName)
	if not anim or not anim:IsA("Animation") then
		warn("[Intro] Brak Animation '" .. animName .. "' w IntroAnims")
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local track = animator:LoadAnimation(anim)
	track.Looped   = false
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	npcAnimTrack = track
end

local function stopNpcAnimation()
	if npcAnimTrack then
		npcAnimTrack:Stop()
		npcAnimTrack = nil
	end
end

local function spawnBottleInHand(rarity: string, offset: CFrame?)
	if spawnedBottle then spawnedBottle:Destroy(); spawnedBottle = nil end
	offset = offset or CFrame.new()

	local npc = findNPC()
	if not npc then
		warn("[Intro] NPC '" .. NPC_NAME .. "' nie znaleziony w workspace")
		return
	end
	local hand = npc:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		warn("[Intro] NPC nie ma RightHand (czy to R15?)")
		return
	end

	local modelsFolder = ReplicatedStorage:FindFirstChild("BottleModels")
	if not modelsFolder then
		warn("[Intro] Brak ReplicatedStorage.BottleModels")
		return
	end
	local template = modelsFolder:FindFirstChild(rarity)
	if not template or not template:IsA("Model") then
		warn("[Intro] Brak modelu butelki '" .. rarity .. "' w BottleModels")
		return
	end

	local bottle = template:Clone() :: Model
	bottle.Name = "IntroBottle"

	local primary = bottle.PrimaryPart
	if not primary then
		for _, d in ipairs(bottle:GetDescendants()) do
			if d:IsA("BasePart") then primary = d; break end
		end
	end
	if not primary then bottle:Destroy(); return end

	-- Konfiguracja części (anchored=false aby weld działał, no-collide, massless)
	for _, p in ipairs(bottle:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored   = false
			p.CanCollide = false
			p.Massless   = true
			p.CastShadow = false
		end
	end

	-- Pozycja na ręce + offset
	bottle:PivotTo(hand.CFrame * offset)

	-- Spawn (sklejenie) z ręką
	local weld = Instance.new("WeldConstraint")
	weld.Part0  = hand
	weld.Part1  = primary
	weld.Parent = primary

	-- VFX Legendarnej: złoty PointLight
	if rarity == "Legendarna" then
		local light = Instance.new("PointLight")
		light.Color      = Color3.fromRGB(255, 195, 70)
		light.Brightness = 1.2
		light.Range      = 8
		light.Parent     = primary
	end

	bottle.Parent  = npc
	spawnedBottle  = bottle
end

local function getMarker(name: string): BasePart?
	local stage = workspace:FindFirstChild("CutsceneStage")
	if stage then
		local found = stage:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then return found :: BasePart end
	end
	-- Fallback: bezpośrednio w workspace (jeśli jeszcze nie wrzuciłeś w CutsceneStage)
	local fallback = workspace:FindFirstChild(name, true)
	if fallback and fallback:IsA("BasePart") then return fallback :: BasePart end
	return nil
end

-- ── Start / stop ─────────────────────────────────────────────────────────

local function stop()
	if not active then return end
	active = false

	-- Jeśli to był autoplay (pierwsze wejście) — zapisz na serwerze że już widział
	if autoPlayMode then
		autoPlayMode = false
		local evts = ReplicatedStorage:FindFirstChild("Events")
		local introFinishedEv = evts and evts:FindFirstChild("IntroFinished")
		if introFinishedEv then introFinishedEv:FireServer() end
	end

	-- Anuluj tween kamery jeśli leci
	if cameraTween then
		cameraTween:Cancel()
		cameraTween = nil
	end

	-- Posprzątaj butelkę z ręki
	if spawnedBottle then
		spawnedBottle:Destroy()
		spawnedBottle = nil
	end

	-- Zatrzymaj animację NPC
	stopNpcAnimation()

	-- Przywróć kamerę
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = origCameraType
		if origCameraSubject then camera.CameraSubject = origCameraSubject end
	end

	-- Letterbox zjedź
	TweenService:Create(topBar, LETTERBOX_TI_OUT, { Position = UDim2.fromOffset(0, -BAR_H) }):Play()
	TweenService:Create(botBar, LETTERBOX_TI_OUT, { Position = UDim2.new(0, 0, 1, BAR_H) }):Play()

	-- Tekst i przycisk fade out
	TweenService:Create(textLbl, TEXT_FADE_TI, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(skipBtn, TEXT_FADE_TI, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()

	-- Przywróć HUD i inne panele
	restoreOtherGuis()

	-- Wyłącz GUI po fade
	task.delay(0.5, function()
		if not active then gui.Enabled = false end
	end)
end

-- Odtwarza pojedynczą scenę i blokuje do końca jej duration
local function playScene(scene: any, camera: Camera): boolean
	if not active then return false end

	local startMarker = getMarker(scene.cameraStart)
	local endMarker   = getMarker(scene.cameraEnd)
	if not startMarker or not endMarker then
		warn("[Intro] Brak markerów " .. scene.cameraStart .. " / " .. scene.cameraEnd)
		return false
	end

	-- Opcjonalny teleport NPC na pozycję dla tej sceny
	if scene.npcMarker then
		local npcMarker = getMarker(scene.npcMarker)
		if npcMarker then
			local npc = findNPC()
			if npc then npc:PivotTo(npcMarker.CFrame) end
		end
	end

	-- Kamera teleport na start sceny
	camera.CFrame = startMarker.CFrame

	-- Tekst sceny (fade out → swap → fade in)
	TweenService:Create(textLbl, TEXT_FADE_TI,
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.wait(0.20)
	if not active then return false end
	textLbl.Text = scene.text
	TweenService:Create(textLbl, TEXT_FADE_TI,
		{ TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()

	-- Animacja NPC (jeśli scena ma)
	if scene.animName then
		playNpcAnimation(scene.animName)
	end

	-- Spawn butelki w ręce (jeśli scena ma)
	if scene.bottle then
		local b = scene.bottle
		task.delay(b.delay, function()
			if active then spawnBottleInHand(b.rarity, b.offset) end
		end)
	end

	-- Tween kamery do końca sceny
	cameraTween = TweenService:Create(camera, cameraTweenInfo(scene.duration),
		{ CFrame = endMarker.CFrame })
	cameraTween:Play()
	-- Blokuje do końca tweena LUB do anulowania (skip)
	cameraTween.Completed:Wait()
	if not active then return false end

	-- Cleanup scene-specific
	if spawnedBottle then spawnedBottle:Destroy(); spawnedBottle = nil end
	stopNpcAnimation()
	return true
end

local function start()
	if active then return end

	-- Wstępna walidacja pierwszej sceny
	local s1 = SCENES[1]
	if not getMarker(s1.cameraStart) or not getMarker(s1.cameraEnd) then
		warn("[Intro] Brak markerów pierwszej sceny — " .. s1.cameraStart .. " / " .. s1.cameraEnd)
		return
	end

	active = true
	gui.Enabled = true
	hideOtherGuis()

	-- Reset UI
	topBar.Position = UDim2.fromOffset(0, -BAR_H)
	botBar.Position = UDim2.new(0, 0, 1, BAR_H)
	textLbl.Text                   = ""
	textLbl.TextTransparency       = 1
	textLbl.TextStrokeTransparency = 1
	skipBtn.BackgroundTransparency = 1
	skipBtn.TextTransparency       = 1

	-- Letterbox wjedź
	TweenService:Create(topBar, LETTERBOX_TI_IN, { Position = UDim2.fromOffset(0, 0) }):Play()
	TweenService:Create(botBar, LETTERBOX_TI_IN, { Position = UDim2.new(0, 0, 1, 0) }):Play()

	-- Skip button fade-in
	TweenService:Create(skipBtn, TEXT_FADE_TI,
		{ BackgroundTransparency = 0.2, TextTransparency = 0 }):Play()

	-- Przejmij kamerę
	local camera = workspace.CurrentCamera
	if not camera then warn("[Intro] CurrentCamera nil"); active = false; return end
	origCameraType    = camera.CameraType
	origCameraSubject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable

	-- Pętla scen
	task.spawn(function()
		for _, scene in ipairs(SCENES) do
			if not active then break end
			local ok = playScene(scene, camera)
			if not ok then break end
		end
		if active then stop() end
	end)
end

-- ── Bindy ────────────────────────────────────────────────────────────────

skipBtn.MouseButton1Click:Connect(stop)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if active and input.KeyCode == Enum.KeyCode.Escape then
		stop()
	end
end)

-- ── Autoplay (pierwsze wejście) ──────────────────────────────────────────

local Events         = ReplicatedStorage:WaitForChild("Events")
local PlayIntro      = Events:WaitForChild("PlayIntro")
local IntroFinished  = Events:WaitForChild("IntroFinished")

local pendingAutoplay = false

-- Próbuje odpalić autoplay gdy pending + loading skończony
local function tryAutoplay()
	if not pendingAutoplay then return end
	if not _G["__loadingDone"] then return end
	pendingAutoplay = false
	task.wait(0.4)  -- mała pauza po fade z loading
	if active then return end
	autoPlayMode = true
	start()
end

_G["__introTryAutoplay"] = tryAutoplay

PlayIntro.OnClientEvent:Connect(function()
	pendingAutoplay = true
	tryAutoplay()
end)

-- Eksport: TEST CUTSCENE (bez fire IntroFinished) + replay z settings
_G["__playIntroTest"] = start
