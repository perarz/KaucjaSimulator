-- PvPEntryGuiController.client.luau
-- Wrzuć do: StarterPlayer.StarterPlayerScripts (Rojo mapuje automatycznie)
-- GUI opłaty 300 PLN za wstęp do strefy PvP. Otwierane przez OpenPvPEntry (ProximityPrompt na KasjerPVP).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer.PlayerGui

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local COST   = Config.PvPEntry.Cost

-- ── Paleta (green theme) ──────────────────────────────────────────────────────
local C_BG           = Color3.fromRGB(18, 91, 73)
local C_HEADER       = Color3.fromRGB(0, 53, 39)
local C_BORDER       = Color3.fromRGB(5, 25, 20)
local C_WHITE        = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT      = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)
local C_ACC_RED      = Color3.fromRGB(200, 70, 70)
local X_RED          = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER    = Color3.fromRGB(255, 110, 110)
local FONT_MAIN      = Enum.Font.GothamBlack
local PAD            = 18

-- ── SFX ──────────────────────────────────────────────────────────────────────
local function playSfx(name: string)
	local sfxFolder = workspace:FindFirstChild("SFX")
	if not sfxFolder then return end
	local template = sfxFolder:FindFirstChild(name)
	if not template then return end
	local sfxGroup = SoundService:FindFirstChild("SfxGroup")
	if not sfxGroup then
		sfxGroup = Instance.new("SoundGroup")
		sfxGroup.Name   = "SfxGroup"
		sfxGroup.Volume = 1
		sfxGroup.Parent = SoundService
	end
	local s = template:Clone()
	s.SoundGroup = sfxGroup
	s.Parent     = SoundService
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

-- ── Remote events ─────────────────────────────────────────────────────────────
local Events         = ReplicatedStorage:WaitForChild("Events")
local OpenPvPEntry   = Events:WaitForChild("OpenPvPEntry")
local ClosePvPEntry  = Events:WaitForChild("ClosePvPEntry")
local BuyPvPEntry    = Events:WaitForChild("BuyPvPEntry")
local PvPEntryResult = Events:WaitForChild("PvPEntryResult")

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function formatAmount(n: number): string
	local rounded = math.floor(n * 100 + 0.5) / 100
	if math.abs(rounded - math.floor(rounded)) < 0.005 then
		return tostring(math.floor(rounded))
	end
	return string.format("%.2f", rounded)
end

local function getBalance(): number
	local ls = localPlayer:FindFirstChild("leaderstats")
	local zl = ls and ls:FindFirstChild("Zlotowki")
	return zl and zl.Value or 0
end

-- ── Budowa GUI ────────────────────────────────────────────────────────────────
local PANEL_W, PANEL_H, HEADER_H = 480, 368, 56

local gui = Instance.new("ScreenGui")
gui.Name = "PvPEntryGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.Enabled = false
gui.Parent = playerGui

local overlay = Instance.new("TextButton")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.ZIndex = 1
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = C_BG
panel.BackgroundTransparency = 0.05
panel.ZIndex = 2
panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = panel
end

-- Brak własnego UIScale na panelu — responsywny UIScale dokłada MobileScaleController
-- (dwa UIScale na jednym obiekcie się gryzą). Pop otwierania/zamykania przez Size.

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_HEADER
header.ZIndex = 3
header.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = header
	local mask = Instance.new("Frame")
	mask.Size = UDim2.new(1, 0, 0, 10); mask.Position = UDim2.new(0, 0, 1, -10)
	mask.BackgroundColor3 = C_HEADER; mask.BorderSizePixel = 0; mask.ZIndex = 3; mask.Parent = header
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.ZIndex = 4; sep.Parent = header
end

local headerLbl = Instance.new("TextLabel")
headerLbl.Size = UDim2.new(1, -HEADER_H - PAD, 1, 0)
headerLbl.Position = UDim2.fromOffset(PAD, 0)
headerLbl.BackgroundTransparency = 1
headerLbl.Text = "STREFA PVP — WSTĘP"
headerLbl.Font = FONT_MAIN
headerLbl.TextSize = 22
headerLbl.TextColor3 = C_WHITE
headerLbl.TextXAlignment = Enum.TextXAlignment.Left
headerLbl.ZIndex = 4
headerLbl.Parent = header

local xBtn = Instance.new("TextButton")
xBtn.Size = UDim2.fromOffset(HEADER_H, HEADER_H)
xBtn.Position = UDim2.new(1, -HEADER_H, 0, 0)
xBtn.BackgroundTransparency = 1
xBtn.Text = "X"
xBtn.Font = FONT_MAIN
xBtn.TextSize = 22
xBtn.TextColor3 = X_RED
xBtn.AutoButtonColor = false
xBtn.ZIndex = 5
xBtn.Parent = header
local xScale = Instance.new("UIScale"); xScale.Parent = xBtn
xBtn.MouseEnter:Connect(function()
	TweenService:Create(xScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.18 }):Play()
	xBtn.TextColor3 = X_RED_HOVER
end)
xBtn.MouseLeave:Connect(function()
	TweenService:Create(xScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.0 }):Play()
	xBtn.TextColor3 = X_RED
end)

-- Treść
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -PAD * 2, 1, -HEADER_H - PAD * 2)
content.Position = UDim2.new(0, PAD, 0, HEADER_H + PAD)
content.BackgroundTransparency = 1
content.ZIndex = 3
content.Parent = panel

-- Ikona (miecze)
local iconFrame = Instance.new("Frame")
iconFrame.Size = UDim2.fromOffset(72, 72)
iconFrame.AnchorPoint = Vector2.new(0.5, 0)
iconFrame.Position = UDim2.new(0.5, 0, 0, 0)
iconFrame.BackgroundColor3 = C_HEADER
iconFrame.ZIndex = 3
iconFrame.Parent = content
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = iconFrame
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = iconFrame
end
local iconLbl = Instance.new("TextLabel")
iconLbl.Size = UDim2.fromScale(1, 1)
iconLbl.BackgroundTransparency = 1
iconLbl.Text = "⚔"
iconLbl.Font = FONT_MAIN
iconLbl.TextSize = 44
iconLbl.TextColor3 = C_ACCENT_GREEN
iconLbl.ZIndex = 4
iconLbl.Parent = iconFrame

local descLbl = Instance.new("TextLabel")
descLbl.Size = UDim2.new(1, 0, 0, 32)
descLbl.Position = UDim2.fromOffset(0, 80)
descLbl.BackgroundTransparency = 1
descLbl.Text = "Opłata za wejście do strefy walki (każdorazowo)"
descLbl.Font = FONT_MAIN
descLbl.TextSize = 16
descLbl.TextColor3 = C_DIMTEXT
descLbl.TextXAlignment = Enum.TextXAlignment.Center
descLbl.ZIndex = 3
descLbl.Parent = content

local priceLbl = Instance.new("TextLabel")
priceLbl.Size = UDim2.new(1, 0, 0, 52)
priceLbl.Position = UDim2.fromOffset(0, 116)
priceLbl.BackgroundTransparency = 1
priceLbl.Text = COST .. " PLN"
priceLbl.Font = FONT_MAIN
priceLbl.TextSize = 44
priceLbl.TextColor3 = C_ACCENT_GREEN
priceLbl.TextXAlignment = Enum.TextXAlignment.Center
priceLbl.ZIndex = 3
priceLbl.Parent = content

local balanceLbl = Instance.new("TextLabel")
balanceLbl.Size = UDim2.new(1, 0, 0, 24)
balanceLbl.Position = UDim2.fromOffset(0, 170)
balanceLbl.BackgroundTransparency = 1
balanceLbl.Text = ""
balanceLbl.Font = FONT_MAIN
balanceLbl.TextSize = 16
balanceLbl.TextColor3 = C_DIMTEXT
balanceLbl.TextXAlignment = Enum.TextXAlignment.Center
balanceLbl.ZIndex = 3
balanceLbl.Parent = content

local msgLbl = Instance.new("TextLabel")
msgLbl.Size = UDim2.new(1, 0, 0, 24)
msgLbl.Position = UDim2.fromOffset(0, 196)
msgLbl.BackgroundTransparency = 1
msgLbl.Text = ""
msgLbl.Font = FONT_MAIN
msgLbl.TextSize = 15
msgLbl.TextColor3 = C_ACCENT_GREEN
msgLbl.TextXAlignment = Enum.TextXAlignment.Center
msgLbl.ZIndex = 3
msgLbl.Parent = content

-- Przyciski
local CONTENT_W = PANEL_W - PAD * 2
local BTN_GAP = 14
local BTN_W = (CONTENT_W - BTN_GAP) / 2
local BTN_H = 46
local BTN_Y = 232

local function makeBtn(name, text, bgColor, txtColor, posX)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromOffset(BTN_W, BTN_H)
	btn.Position = UDim2.fromOffset(posX, BTN_Y)
	btn.BackgroundColor3 = bgColor
	btn.Text = text
	btn.Font = FONT_MAIN
	btn.TextSize = 18
	btn.TextColor3 = txtColor
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = content
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = btn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 0; s.Parent = btn  -- bez ciemnej obramowki — czytelność tekstu
	local sc = Instance.new("UIScale"); sc.Parent = btn
	btn.MouseEnter:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.06 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.0 }):Play()
	end)
	return btn
end

local buyBtn   = makeBtn("BuyBtn", "ZAPŁAĆ " .. COST .. " PLN", C_ACCENT_GREEN, Color3.fromRGB(0, 0, 0), 0)
local closeBtn = makeBtn("CloseBtn", "ZAMKNIJ", C_BG, C_WHITE, BTN_W + BTN_GAP)

-- ── Otwieranie / zamykanie ────────────────────────────────────────────────────
local waiting = false

local function setBuyReady()
	waiting = false
	buyBtn.Active = true
	buyBtn.Text = "ZAPŁAĆ " .. COST .. " PLN"
	buyBtn.BackgroundColor3 = C_ACCENT_GREEN
end

local function openGui()
	setBuyReady()
	msgLbl.Text = ""
	balanceLbl.Text = "Twoje saldo: " .. formatAmount(getBalance()) .. " PLN"
	gui.Enabled = true
	panel.Size = UDim2.fromOffset(PANEL_W * 0.85, PANEL_H * 0.85)
	TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(PANEL_W, PANEL_H) }):Play()
end

local function closeGui()
	local t = TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.fromOffset(PANEL_W * 0.85, PANEL_H * 0.85) })
	t:Play()
	t.Completed:Connect(function()
		gui.Enabled = false
		panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	end)
end

xBtn.Activated:Connect(closeGui)
closeBtn.Activated:Connect(closeGui)

-- ── Zakup ─────────────────────────────────────────────────────────────────────
buyBtn.Activated:Connect(function()
	if waiting then return end
	waiting = true
	buyBtn.Active = false
	buyBtn.Text = "ŁADOWANIE..."
	buyBtn.BackgroundColor3 = Color3.fromRGB(100, 160, 60)
	BuyPvPEntry:FireServer()
	task.delay(6, function()
		if not waiting then return end
		setBuyReady()
		msgLbl.TextColor3 = C_ACC_RED
		msgLbl.Text = "Brak odpowiedzi serwera. Sprawdź Output (F9)."
	end)
end)

PvPEntryResult.OnClientEvent:Connect(function(result)
	waiting = false
	if result.success then
		playSfx("Money")
		msgLbl.TextColor3 = C_ACCENT_GREEN
		msgLbl.Text = "Wstęp opłacony! Brama się otwiera."
		buyBtn.Text = "OPŁACONO ✓"
		buyBtn.Active = false
		buyBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 45)
		task.delay(1.6, closeGui)
	elseif result.reason == "broke" then
		playSfx("error")
		msgLbl.TextColor3 = C_ACC_RED
		msgLbl.Text = "Za mało złotówek! Potrzebujesz " .. COST .. " PLN."
		setBuyReady()
	else
		msgLbl.TextColor3 = C_ACC_RED
		msgLbl.Text = "Błąd. Spróbuj ponownie."
		setBuyReady()
	end
end)

-- ── Trigger z serwera (ProximityPrompt na KasjerPVP) ─────────────────────────
OpenPvPEntry.OnClientEvent:Connect(openGui)
ClosePvPEntry.OnClientEvent:Connect(function()
	if gui.Enabled then closeGui() end
end)

print("[PvPEntryGuiController] Gotowy — czekam na OpenPvPEntry")
