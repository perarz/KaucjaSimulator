-- BoostShopController.client.luau
-- Sklep Robux — wraper z 1 produktem (x2 KASA 10 min) portowany do zakładki SKLEP w menu.
-- Dodatkowo: maleńki pasek statusu z timerem w prawym górnym rogu gdy boost aktywny.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Config              = require(ReplicatedStorage:WaitForChild("Config"))
local Events              = ReplicatedStorage:WaitForChild("Events")
local BoostStatusUpdate   = Events:WaitForChild("BoostStatusUpdate")
local PromptBoostPurchase = Events:WaitForChild("PromptBoostPurchase")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

print("[BoostShopController] start")

local FONT       = Enum.Font.GothamBlack
local C_BG       = Color3.fromRGB(18, 91, 73)
local C_HEADER   = Color3.fromRGB(0, 53, 39)
local C_BORDER   = Color3.fromRGB(5, 25, 20)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT  = Color3.fromRGB(175, 175, 175)
local C_ROBUX    = Color3.fromRGB(255, 220, 100)
local C_ACTIVE   = Color3.fromRGB(170, 221, 102)

-- ── Hidden ScreenGui — bufor dla wrap'a zanim MenuController go nie przeniesie ──
local hidden = Instance.new("ScreenGui")
hidden.Name           = "BoostShopHidden"
hidden.ResetOnSpawn   = false
hidden.IgnoreGuiInset = true
hidden.Enabled        = false
hidden.Parent         = playerGui

-- Wrap — zawartość zakładki SKLEP. MenuController czeka na _G.__boostShopReady i reparentuje do contentFrames[4].
local wrap = Instance.new("Frame")
wrap.Name                  = "BoostShopWrap"
wrap.Size                  = UDim2.fromOffset(640, 480)
wrap.BackgroundTransparency = 1
wrap.BorderSizePixel       = 0
wrap.Parent                = hidden

-- Tytuł
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -32, 0, 40); title.Position = UDim2.fromOffset(16, 16)
title.BackgroundTransparency = 1; title.Text = "SKLEP ROBUX"
title.TextSize = 28; title.Font = FONT; title.TextColor3 = C_WHITE
title.TextXAlignment = Enum.TextXAlignment.Center
title.Parent = wrap

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -32, 0, 24); subtitle.Position = UDim2.fromOffset(16, 60)
subtitle.BackgroundTransparency = 1; subtitle.Text = "Boost dla całej rozgrywki — wspiera dewelopera"
subtitle.TextSize = 14; subtitle.Font = FONT; subtitle.TextColor3 = C_DIMTEXT
subtitle.TextXAlignment = Enum.TextXAlignment.Center
subtitle.Parent = wrap

-- Karta produktu
local card = Instance.new("Frame")
card.Size                  = UDim2.fromOffset(420, 320)
card.AnchorPoint           = Vector2.new(0.5, 0)
card.Position              = UDim2.new(0.5, 0, 0, 110)
card.BackgroundColor3      = C_BG
card.BackgroundTransparency = 0.05
card.BorderSizePixel       = 0
card.Parent                = wrap
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = card
	local s = Instance.new("UIStroke"); s.Color = C_ROBUX; s.Thickness = 3; s.Parent = card
end

-- Badge "ROBUX"
local badge = Instance.new("TextLabel")
badge.Size = UDim2.fromOffset(78, 28); badge.AnchorPoint = Vector2.new(1, 0)
badge.Position = UDim2.new(1, -16, 0, 16)
badge.BackgroundColor3 = C_ROBUX; badge.BorderSizePixel = 0
badge.Text = "ROBUX"; badge.TextSize = 14; badge.Font = FONT
badge.TextColor3 = Color3.fromRGB(40, 30, 0)
badge.Parent = card
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = badge
end

local cardTitle = Instance.new("TextLabel")
cardTitle.Size = UDim2.new(1, -32, 0, 36); cardTitle.Position = UDim2.fromOffset(16, 60)
cardTitle.BackgroundTransparency = 1; cardTitle.Text = "×2 KASA Z BUTELKOMATU"
cardTitle.TextSize = 22; cardTitle.Font = FONT; cardTitle.TextColor3 = C_ACTIVE
cardTitle.TextXAlignment = Enum.TextXAlignment.Center
cardTitle.Parent = card

local desc = Instance.new("TextLabel")
desc.Size = UDim2.new(1, -32, 0, 80); desc.Position = UDim2.fromOffset(16, 108)
desc.BackgroundTransparency = 1
desc.Text = "Podwaja zarobki ze sprzedaży butelek w butelkomacie.\nTrwa 10 minut. Stackuje się z mnożnikiem ze skill tree."
desc.TextSize = 14; desc.Font = FONT; desc.TextColor3 = C_WHITE
desc.TextWrapped = true; desc.TextXAlignment = Enum.TextXAlignment.Center
desc.Parent = card

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -32, 0, 28); status.Position = UDim2.fromOffset(16, 200)
status.BackgroundTransparency = 1; status.Text = ""
status.TextSize = 16; status.Font = FONT; status.TextColor3 = C_ACTIVE
status.TextXAlignment = Enum.TextXAlignment.Center
status.Parent = card

local buyBtn = Instance.new("TextButton")
buyBtn.Size                   = UDim2.new(1, -32, 0, 56)
buyBtn.AnchorPoint            = Vector2.new(0, 1)
buyBtn.Position               = UDim2.new(0, 16, 1, -16)
buyBtn.BackgroundColor3       = C_ROBUX
buyBtn.BorderSizePixel        = 0
buyBtn.Text                   = "KUP — 19 R$"
buyBtn.TextSize               = 20
buyBtn.Font                   = FONT
buyBtn.TextColor3             = Color3.fromRGB(40, 30, 0)
buyBtn.AutoButtonColor        = false
buyBtn.Parent                 = card
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = buyBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = buyBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	buyBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.03 }):Play() end)
	buyBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end
buyBtn.MouseButton1Click:Connect(function()
	PromptBoostPurchase:FireServer("DoubleEarn")
end)

-- ── Mały status HUD w prawym górnym rogu (widoczny tylko gdy boost active) ──
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "BoostStatusHUD"
hudGui.IgnoreGuiInset = true
hudGui.ResetOnSpawn   = false
hudGui.DisplayOrder   = 60
hudGui.Parent         = playerGui

local hudFrame = Instance.new("Frame")
hudFrame.AnchorPoint            = Vector2.new(1, 0)
hudFrame.Position               = UDim2.new(1, -16, 0, 110)
hudFrame.Size                   = UDim2.fromOffset(160, 44)
hudFrame.BackgroundColor3       = C_HEADER
hudFrame.BackgroundTransparency = 0.05
hudFrame.BorderSizePixel        = 0
hudFrame.Visible                = false
hudFrame.Parent                 = hudGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = hudFrame
	local s = Instance.new("UIStroke"); s.Color = C_ACTIVE; s.Thickness = 2; s.Parent = hudFrame
end

local hudLabel = Instance.new("TextLabel")
hudLabel.Size = UDim2.new(1, -8, 1, 0); hudLabel.Position = UDim2.fromOffset(4, 0)
hudLabel.BackgroundTransparency = 1; hudLabel.Text = ""
hudLabel.TextSize = 16; hudLabel.Font = FONT; hudLabel.TextColor3 = C_ACTIVE
hudLabel.TextXAlignment = Enum.TextXAlignment.Center
hudLabel.Parent = hudFrame

-- ── Sync z serwerem ───────────────────────────────────────────────────────────
local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local activeRemainingSec = 0
local function updateUI()
	if activeRemainingSec > 0 then
		buyBtn.Text     = "DOLICZ +10 MIN — 19 R$"
		status.Text     = "AKTYWNE — " .. formatTime(activeRemainingSec)
		hudLabel.Text   = "x2 KASA " .. formatTime(activeRemainingSec)
		hudFrame.Visible = true
	else
		buyBtn.Text     = "KUP — 19 R$"
		status.Text     = ""
		hudFrame.Visible = false
	end
end
updateUI()

BoostStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	activeRemainingSec = tonumber(data.doubleEarnRemainingSec) or 0
	updateUI()
end)

-- ── Eksport dla MenuController ────────────────────────────────────────────────
_G["__boostShopWrap"]  = wrap
_G["__boostShopReady"] = true
print("[BoostShopController] gotowy — wrap eksportowany do _G.__boostShopWrap")
