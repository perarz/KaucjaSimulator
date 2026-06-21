-- StoryQuestController.client.luau
-- UI dla linii fabularnej:
--   1) StoryQuestInit (nowy quest) → wielki napis na środku przez 4s → przesuwa się do rogu (HUD)
--   2) StoryQuestUpdate (progress) → aktualizacja paska w rogu
--   3) StoryQuestComplete (ukończono) → WYKONANO + nagroda na środku przez 2s
-- Persistent corner HUD: zawsze widoczny póki jest aktywny quest.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")

local Events             = ReplicatedStorage:WaitForChild("Events")
local StoryQuestInit     = Events:WaitForChild("StoryQuestInit")
local StoryQuestUpdate   = Events:WaitForChild("StoryQuestUpdate")
local StoryQuestComplete = Events:WaitForChild("StoryQuestComplete")
local StoryQuestClaim    = Events:WaitForChild("StoryQuestClaim")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta (zgodna z resztą UI) ────────────────────────────────────────────
local C_BG           = Color3.fromRGB(18, 91, 73)
local C_HEADER       = Color3.fromRGB(0, 53, 39)
local C_BORDER       = Color3.fromRGB(5, 25, 20)
local C_WHITE        = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT      = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)
local C_GOLD         = Color3.fromRGB(239, 199, 95)
local FONT_MAIN      = Enum.Font.GothamBlack
local FONT_TITLE     = Enum.Font.LuckiestGuy

-- ── ScreenGui ──────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "StoryQuestGui"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 25  -- nad HUD, pod głównym menu
gui.Parent         = playerGui

local function mkCorner(parent, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = parent end
local function mkStroke(parent, color, th) local s = Instance.new("UIStroke"); s.Color = color or C_BORDER; s.Thickness = th or 4; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = parent end

-- ── CORNER HUD (persistent — prawy dolny róg) ──────────────────────────────
local cornerPanel = Instance.new("Frame")
cornerPanel.AnchorPoint = Vector2.new(1, 1)
cornerPanel.Position    = UDim2.new(1, -16, 1, -16)
cornerPanel.Size        = UDim2.fromOffset(460, 130)
cornerPanel.BackgroundColor3       = C_BG
cornerPanel.BackgroundTransparency = 0.05
cornerPanel.BorderSizePixel        = 0
cornerPanel.Visible                = false
cornerPanel.Parent                 = gui
mkCorner(cornerPanel, 8); mkStroke(cornerPanel, C_BORDER, 4)

local cornerHeader = Instance.new("TextLabel")
cornerHeader.Size                   = UDim2.new(1, -16, 0, 18)
cornerHeader.Position               = UDim2.fromOffset(8, 6)
cornerHeader.BackgroundTransparency = 1
cornerHeader.Font                   = FONT_MAIN
cornerHeader.TextSize               = 13
cornerHeader.TextColor3             = C_GOLD
cornerHeader.TextXAlignment         = Enum.TextXAlignment.Left
cornerHeader.Text                   = "FABUŁA — 1/6"
cornerHeader.Parent                 = cornerPanel

local cornerDesc = Instance.new("TextLabel")
cornerDesc.Size                   = UDim2.new(1, -16, 0, 50)
cornerDesc.Position               = UDim2.fromOffset(8, 24)
cornerDesc.BackgroundTransparency = 1
cornerDesc.Font                   = FONT_MAIN
cornerDesc.TextSize               = 15
cornerDesc.TextColor3             = C_WHITE
cornerDesc.TextXAlignment         = Enum.TextXAlignment.Left
cornerDesc.TextYAlignment         = Enum.TextYAlignment.Top
cornerDesc.TextWrapped            = true
cornerDesc.Text                   = ""
cornerDesc.Parent                 = cornerPanel

-- Nagroda — pod opisem, gold accent
local cornerReward = Instance.new("TextLabel")
cornerReward.Size                   = UDim2.new(1, -16, 0, 16)
cornerReward.Position               = UDim2.fromOffset(8, 78)
cornerReward.BackgroundTransparency = 1
cornerReward.Font                   = FONT_MAIN
cornerReward.TextSize               = 14
cornerReward.TextColor3             = C_GOLD
cornerReward.TextXAlignment         = Enum.TextXAlignment.Left
cornerReward.Text                   = "Nagroda: +0 zł"
cornerReward.Parent                 = cornerPanel

-- Pasek progresu
local progBg = Instance.new("Frame")
progBg.Size = UDim2.new(1, -16, 0, 12)
progBg.Position = UDim2.new(0, 8, 1, -20)
progBg.BackgroundColor3 = C_HEADER
progBg.BorderSizePixel = 0
progBg.Parent = cornerPanel
mkCorner(progBg, 4)

local progFill = Instance.new("Frame")
progFill.Size = UDim2.fromScale(0, 1)
progFill.BackgroundColor3 = C_ACCENT_GREEN
progFill.BorderSizePixel = 0
progFill.Parent = progBg
mkCorner(progFill, 4)

local progLbl = Instance.new("TextLabel")
progLbl.Size = UDim2.new(1, 0, 1, 0)
progLbl.BackgroundTransparency = 1
progLbl.Font = FONT_MAIN
progLbl.TextSize = 11
progLbl.TextColor3 = C_WHITE
progLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
progLbl.TextStrokeTransparency = 0.4
progLbl.Text = "0 / 0"
progLbl.Parent = progBg

-- Przycisk ODBIERZ (zastępuje progBg gdy quest gotowy do odbioru)
local claimBtn = Instance.new("TextButton")
claimBtn.Size = UDim2.new(1, -16, 0, 22)
claimBtn.Position = UDim2.new(0, 8, 1, -30)
claimBtn.BackgroundColor3 = C_ACCENT_GREEN
claimBtn.BorderSizePixel = 0
claimBtn.Text = "ODBIERZ"
claimBtn.Font = FONT_MAIN
claimBtn.TextSize = 16
claimBtn.TextColor3 = Color3.new(0, 0, 0)
claimBtn.AutoButtonColor = false
claimBtn.Visible = false
claimBtn.Parent = cornerPanel
mkCorner(claimBtn, 4)
do
	local sc = Instance.new("UIScale"); sc.Parent = claimBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	claimBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	claimBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end
claimBtn.MouseButton1Click:Connect(function()
	claimBtn.Visible = false
	StoryQuestClaim:FireServer()
end)

-- ── CENTER REVEAL (4s przy nowym, 2s przy completion) ──────────────────────
local centerOverlay = Instance.new("Frame")
centerOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
centerOverlay.Position    = UDim2.fromScale(0.5, 0.5)
centerOverlay.Size        = UDim2.fromOffset(680, 280)
centerOverlay.BackgroundColor3       = C_BG
centerOverlay.BackgroundTransparency = 0.1
centerOverlay.BorderSizePixel        = 0
centerOverlay.Visible                = false
centerOverlay.Parent                 = gui
mkCorner(centerOverlay, 12); mkStroke(centerOverlay, C_BORDER, 5)

local centerScale = Instance.new("UIScale"); centerScale.Scale = 0.8; centerScale.Parent = centerOverlay

local centerTitle = Instance.new("TextLabel")
centerTitle.AnchorPoint = Vector2.new(0.5, 0)
centerTitle.Position    = UDim2.new(0.5, 0, 0, 24)
centerTitle.Size        = UDim2.new(1, -32, 0, 60)
centerTitle.BackgroundTransparency = 1
centerTitle.Font = FONT_TITLE
centerTitle.TextSize = 52
centerTitle.TextColor3 = C_ACCENT_GREEN
centerTitle.TextXAlignment = Enum.TextXAlignment.Center
centerTitle.Text = "NOWY QUEST"
centerTitle.Parent = centerOverlay

local centerDesc = Instance.new("TextLabel")
centerDesc.AnchorPoint = Vector2.new(0.5, 0)
centerDesc.Position    = UDim2.new(0.5, 0, 0, 100)
centerDesc.Size        = UDim2.new(1, -48, 0, 80)
centerDesc.BackgroundTransparency = 1
centerDesc.Font = FONT_MAIN
centerDesc.TextSize = 28
centerDesc.TextColor3 = C_WHITE
centerDesc.TextXAlignment = Enum.TextXAlignment.Center
centerDesc.TextYAlignment = Enum.TextYAlignment.Center
centerDesc.TextWrapped = true
centerDesc.Text = ""
centerDesc.Parent = centerOverlay

local centerReward = Instance.new("TextLabel")
centerReward.AnchorPoint = Vector2.new(0.5, 1)
centerReward.Position    = UDim2.new(0.5, 0, 1, -24)
centerReward.Size        = UDim2.new(1, -32, 0, 40)
centerReward.BackgroundTransparency = 1
centerReward.Font = FONT_MAIN
centerReward.TextSize = 24
centerReward.TextColor3 = C_GOLD
centerReward.Text = "+0 zł"
centerReward.Parent = centerOverlay

-- ── State ──────────────────────────────────────────────────────────────────
local currentSnap = nil

local function refreshCorner(snap)
	if snap.done then
		cornerPanel.Visible = false
		return
	end
	cornerHeader.Text = string.format("FABUŁA %d/%d", snap.idx or 1, snap.total or 0)
	cornerDesc.Text   = snap.desc or ""
	cornerReward.Text = string.format("Nagroda: +%d zł", snap.reward or 0)
	local target = snap.target or 1
	local prog   = snap.progress or 0
	progFill.Size = UDim2.fromScale(math.clamp(prog / target, 0, 1), 1)
	progLbl.Text  = string.format("%d / %d", prog, target)
	-- Przełączanie: gotowy do odbioru → przycisk ODBIERZ zamiast paska
	if snap.readyToClaim then
		progBg.Visible = false
		claimBtn.Visible = true
	else
		progBg.Visible = true
		claimBtn.Visible = false
	end
	cornerPanel.Visible = true
end

-- Token-based reveal — pozwala anulować auto-hide gdy gracz kliknie wcześniej
local activeRevealToken: any = nil
local activeOnFinish: (() -> ())? = nil

local function hideCenterReveal()
	if not centerOverlay.Visible then return end
	-- Szybkie fade out
	local fadeTI = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(centerScale, fadeTI, { Scale = 0.85 }):Play()
	task.delay(0.16, function() centerOverlay.Visible = false end)
	local cb = activeOnFinish
	activeRevealToken = nil
	activeOnFinish    = nil
	if cb then cb() end  -- np. pokazanie corner HUD
end

local function showCenterReveal(title: string, desc: string, reward: number, duration: number, onFinish: (() -> ())?)
	centerTitle.Text  = title
	centerDesc.Text   = desc
	centerReward.Text = string.format("+%d zł", reward or 0)
	centerOverlay.Visible = true
	centerScale.Scale = 0.7

	TweenService:Create(centerScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.0 }):Play()

	local token = {}
	activeRevealToken = token
	activeOnFinish    = onFinish

	task.delay(duration, function()
		if activeRevealToken == token then hideCenterReveal() end
	end)
end

-- Click-catcher: przezroczysty TextButton na overlay, klik = od razu skip
local skipBtn = Instance.new("TextButton")
skipBtn.Size = UDim2.fromScale(1, 1)
skipBtn.BackgroundTransparency = 1
skipBtn.Text = ""
skipBtn.AutoButtonColor = false
skipBtn.ZIndex = 100
skipBtn.Parent = centerOverlay
skipBtn.MouseButton1Click:Connect(function()
	if activeRevealToken then hideCenterReveal() end
end)

-- ── StoryQuestInit (nowy quest lub sync na join) ───────────────────────────
StoryQuestInit.OnClientEvent:Connect(function(snap)
	currentSnap = snap
	if snap.done then
		cornerPanel.Visible = false
		return
	end
	-- Reveal na środku przez 4s, po jego zniknięciu (auto OR klik) → pokazujemy corner
	showCenterReveal("NOWY QUEST", snap.desc or "", snap.reward or 0, 4, function()
		if currentSnap == snap then refreshCorner(snap) end
	end)
end)

-- ── StoryQuestUpdate (progress) ────────────────────────────────────────────
StoryQuestUpdate.OnClientEvent:Connect(function(snap)
	currentSnap = snap
	if cornerPanel.Visible or centerOverlay.Visible == false then
		refreshCorner(snap)
	end
end)

-- ── StoryQuestComplete (WYKONANO) ──────────────────────────────────────────
StoryQuestComplete.OnClientEvent:Connect(function(payload)
	cornerPanel.Visible = false
	showCenterReveal("WYKONANO!", payload.desc or "", payload.reward or 0, 2)
end)

print("[StoryQuestController] Gotowy — czekam na StoryQuestInit")
