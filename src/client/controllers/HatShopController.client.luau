-- HatShopController.client.luau
-- UI sklepu czapek (standalone, jak BankController). Otwierany przez ProximityPrompt na Kasjerze.
-- 1 karta produktu z kosztem (zł + butelki) i bonusami.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

local Config        = require(ReplicatedStorage:WaitForChild("Config"))
local Events        = ReplicatedStorage:WaitForChild("Events")
local OpenHatShop   = Events:WaitForChild("OpenHatShop")
local BuyHat        = Events:WaitForChild("BuyHat")
local BuyHatResult  = Events:WaitForChild("BuyHatResult")
local UpdateHUD     = Events:WaitForChild("UpdateHUD")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta ────────────────────────────────────────────────────────────────────
local FONT          = Enum.Font.GothamBlack
local C_BG          = Color3.fromRGB(18, 91, 73)
local C_PANEL       = Color3.fromRGB(24, 110, 90)
local C_HEADER      = Color3.fromRGB(0, 53, 39)
local C_BORDER      = Color3.fromRGB(5, 25, 20)
local C_WHITE       = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT     = Color3.fromRGB(175, 175, 175)
local C_ACC_GREEN   = Color3.fromRGB(170, 221, 102)
local C_ACC_BLUE    = Color3.fromRGB(88, 166, 255)
local C_DANGER      = Color3.fromRGB(220, 70, 70)
local X_RED         = Color3.fromRGB(220, 70, 70)
local X_RED_HOV     = Color3.fromRGB(255, 110, 110)
local RARITY_COLORS = Config.BottleColors

-- ── Stan ──────────────────────────────────────────────────────────────────────
local pData = { Zlotowki = 0, HatOwned = false, BackpackContents = { Zwykla=0, Rzadka=0, Epicka=0, Legendarna=0, Mityczny=0 } }

local function readLeaderstats()
	local ls = localPlayer:FindFirstChild("leaderstats")
	if ls then
		local zl = ls:FindFirstChild("Zlotowki")
		if zl then pData.Zlotowki = zl.Value end
	end
end
readLeaderstats()

-- ── UI ────────────────────────────────────────────────────────────────────────
local PANEL_W  = 540
local PANEL_H  = 540

local gui = Instance.new("ScreenGui")
gui.Name           = "HatShop"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 55
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = gui

local panel = Instance.new("Frame")
panel.Size                  = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint           = Vector2.new(0.5, 0.5)
panel.Position              = UDim2.new(0.5, 0, 0.55, 0)
panel.BackgroundColor3      = C_PANEL
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel       = 0
panel.ZIndex                = 2
panel.Parent                = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = panel
end

-- Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 10); fill.Position = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = header
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.ZIndex = 5; sep.Parent = header
end
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -56, 1, 0); title.Position = UDim2.fromOffset(22, 0)
title.BackgroundTransparency = 1; title.Text = "SKLEP — CZAPKI"
title.TextSize = 18; title.Font = FONT; title.TextColor3 = C_WHITE
title.TextXAlignment = Enum.TextXAlignment.Left; title.ZIndex = 4; title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(36, 36); closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -12, 0.5, 0); closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel = 0; closeBtn.Text = "X"; closeBtn.TextSize = 24
closeBtn.Font = FONT; closeBtn.TextColor3 = X_RED; closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 6; closeBtn.Parent = header
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play(); closeBtn.TextColor3 = X_RED_HOV
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1 }):Play(); closeBtn.TextColor3 = X_RED
	end)
end

-- ── Karta produktu ──────────────────────────────────────────────────────────
local PAD = 20
local card = Instance.new("Frame")
card.Size                  = UDim2.new(1, -PAD * 2, 1, -50 - PAD * 2)
card.Position              = UDim2.fromOffset(PAD, 50 + PAD)
card.BackgroundColor3      = C_BG
card.BackgroundTransparency = 0.05
card.BorderSizePixel       = 0
card.ZIndex                = 3
card.Parent                = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = card
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = card
end

-- Nazwa
local itemName = Instance.new("TextLabel")
itemName.Size = UDim2.new(1, -32, 0, 36); itemName.Position = UDim2.fromOffset(16, 16)
itemName.BackgroundTransparency = 1; itemName.Text = "Magiczna Czapka"
itemName.TextSize = 26; itemName.Font = FONT; itemName.TextColor3 = C_ACC_GREEN
itemName.TextXAlignment = Enum.TextXAlignment.Center; itemName.ZIndex = 4; itemName.Parent = card

-- Bonusy
local bonuses = Instance.new("TextLabel")
bonuses.Size = UDim2.new(1, -32, 0, 80); bonuses.Position = UDim2.fromOffset(16, 56)
bonuses.BackgroundTransparency = 1
bonuses.Text = string.format(
	"+%d HP    +%d STAMINY    +%d SPEED",
	Config.HatShop.HpBonus, Config.HatShop.StaminaBonus, Config.HatShop.SpeedBonus)
bonuses.TextSize = 16; bonuses.Font = FONT; bonuses.TextColor3 = C_WHITE
bonuses.TextWrapped = true
bonuses.TextXAlignment = Enum.TextXAlignment.Center; bonuses.ZIndex = 4; bonuses.Parent = card

-- Separator
do
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -32, 0, 2); sep.Position = UDim2.fromOffset(16, 150)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.ZIndex = 4; sep.Parent = card
end

-- Koszt: header + lista
local costHdr = Instance.new("TextLabel")
costHdr.Size = UDim2.new(1, -32, 0, 24); costHdr.Position = UDim2.fromOffset(16, 162)
costHdr.BackgroundTransparency = 1; costHdr.Text = "KOSZT"
costHdr.TextSize = 14; costHdr.Font = FONT; costHdr.TextColor3 = C_DIMTEXT
costHdr.TextXAlignment = Enum.TextXAlignment.Left; costHdr.ZIndex = 4; costHdr.Parent = card

-- Row helper
local function makeCostRow(yOffset: number, label: string, color: Color3): TextLabel
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, -32, 0, 28); row.Position = UDim2.fromOffset(16, yOffset)
	row.BackgroundTransparency = 1; row.Text = label
	row.TextSize = 18; row.Font = FONT; row.TextColor3 = color
	row.TextXAlignment = Enum.TextXAlignment.Left; row.ZIndex = 4; row.Parent = card
	return row
end

local zlRow = makeCostRow(192, "", C_WHITE)
local legRow = makeCostRow(224, "", RARITY_COLORS.Legendarna)
local mytRow = makeCostRow(256, "", RARITY_COLORS.Mityczny)

-- Status pod kosztami
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -32, 0, 28); status.Position = UDim2.fromOffset(16, 300)
status.BackgroundTransparency = 1; status.Text = ""
status.TextSize = 16; status.Font = FONT; status.TextColor3 = C_DIMTEXT
status.TextXAlignment = Enum.TextXAlignment.Center; status.ZIndex = 4; status.Parent = card

-- Buy button
local buyBtn = Instance.new("TextButton")
buyBtn.Size                   = UDim2.new(1, -32, 0, 58)
buyBtn.AnchorPoint            = Vector2.new(0, 1)
buyBtn.Position               = UDim2.new(0, 16, 1, -16)
buyBtn.BackgroundColor3       = C_ACC_GREEN
buyBtn.BorderSizePixel        = 0
buyBtn.Text                   = "KUP"
buyBtn.TextSize               = 22
buyBtn.Font                   = FONT
buyBtn.TextColor3             = Color3.fromRGB(0, 0, 0)
buyBtn.AutoButtonColor        = false
buyBtn.ZIndex                 = 4
buyBtn.Parent                 = card
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 0; s.Parent = buyBtn  -- bez ciemnej obramowki — czyściej, lepsza czytelność czarnego tekstu na zielonym
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = buyBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	buyBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.03 }):Play() end)
	buyBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- ── Refresh karty ────────────────────────────────────────────────────────────
local function fmtHave(have: number, need: number): string
	return string.format(" (%d / %d)", math.min(have, need), need)
end

local function refresh()
	local shop = Config.HatShop
	local zl = pData.Zlotowki or 0
	local legHave = (pData.BackpackContents and pData.BackpackContents.Legendarna) or 0
	local mytHave = (pData.BackpackContents and pData.BackpackContents.Mityczny) or 0
	local legNeed = shop.CostBottles.Legendarna or 0
	local mytNeed = shop.CostBottles.Mityczny or 0

	zlRow.Text  = string.format("%d PLN", shop.CostZl) .. fmtHave(math.floor(zl), shop.CostZl)
	zlRow.TextColor3 = (zl >= shop.CostZl) and C_ACC_GREEN or C_DANGER

	legRow.Text = string.format("%d × Legendarna", legNeed) .. fmtHave(legHave, legNeed)
	legRow.TextColor3 = (legHave >= legNeed) and C_ACC_GREEN or C_DANGER

	mytRow.Text = string.format("%d × Mityczna", mytNeed) .. fmtHave(mytHave, mytNeed)
	mytRow.TextColor3 = (mytHave >= mytNeed) and C_ACC_GREEN or C_DANGER

	if pData.HatOwned then
		status.Text = ""
		buyBtn.Text = "POSIADANE ✓"
		buyBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
		buyBtn.Active = false
	elseif zl >= shop.CostZl and legHave >= legNeed and mytHave >= mytNeed then
		status.Text = "Wszystko gotowe — kliknij KUP!"
		status.TextColor3 = C_ACC_GREEN
		buyBtn.Text = "KUP"
		buyBtn.BackgroundColor3 = C_ACC_GREEN
		buyBtn.Active = true
	else
		status.Text = "Brakuje surowców."
		status.TextColor3 = C_DANGER
		buyBtn.Text = "KUP"
		buyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		buyBtn.Active = true  -- pozwalamy klik — server odrzuci i pokaże powód
	end
end

-- ── Open / close ─────────────────────────────────────────────────────────────
local POS_SHOW = UDim2.new(0.5, 0, 0.5, 0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local TW_OPEN  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TW_CLOSE = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local isOpen   = false

local function setOpen(open: boolean)
	isOpen = open
	if open then
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		readLeaderstats()
		refresh()
		gui.Enabled = true
		panel.Position = POS_HIDE
		overlay.BackgroundTransparency = 1
		TweenService:Create(panel, TW_OPEN, { Position = POS_SHOW }):Play()
		TweenService:Create(overlay, TW_OPEN, { BackgroundTransparency = 0.35 }):Play()
	else
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		TweenService:Create(panel, TW_CLOSE, { Position = POS_HIDE }):Play()
		local tw = TweenService:Create(overlay, TW_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function() if not isOpen then gui.Enabled = false end end)
		tw:Play()
	end
end

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)

buyBtn.MouseButton1Click:Connect(function()
	if not buyBtn.Active then return end
	if pData.HatOwned then return end
	BuyHat:FireServer()
end)

-- ── Eventy ───────────────────────────────────────────────────────────────────
OpenHatShop.OnClientEvent:Connect(function() setOpen(true) end)

BuyHatResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	if result.success then
		pData.HatOwned = true
		refresh()
		-- Ustawiamy status PO refresh — inaczej branch `if pData.HatOwned` w refresh
		-- nadpisuje "Kupiono!" na "" i gracz nigdy nie widzi potwierdzenia.
		status.Text = "Kupiono! Czapka założona."
		status.TextColor3 = C_ACC_GREEN
	else
		local msg = "Nie udało się kupić."
		if result.reason == "broke"   then msg = "Za mało złotówek."
		elseif result.reason == "bottles" then msg = string.format("Za mało butelek %s (potrzeba %d).", result.rarity or "?", result.need or 0)
		elseif result.reason == "already" then msg = "Już posiadasz czapkę."
		end
		status.Text = msg
		status.TextColor3 = C_DANGER
	end
end)

-- Sync z UpdateHUD (zmiana backpackContents po zakupie / sprzedaży / koszu / butelkomacie / drop)
UpdateHUD.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.backpackContents then
		pData.BackpackContents = data.backpackContents
		if isOpen then refresh() end
	end
end)

-- BUG FIX: zbieranie butelki (klik prompt) NIE wysyła UpdateHUD — tylko CollectBottleResult.
-- Magnes sweep też leci przez ten sam result (TryCollectBottle → CollectBottleResult).
-- Bez tego listenera sklep nie aktualizuje pData.BackpackContents w trakcie zbierania,
-- przez co status "Brakuje surowców" pozostaje mimo że gracz właśnie zebrał potrzebną butelkę.
local CollectBottleResult = Events:WaitForChild("CollectBottleResult")
CollectBottleResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or not result.success then return end
	local r = result.rarity
	if type(r) ~= "string" then return end
	pData.BackpackContents[r] = (pData.BackpackContents[r] or 0) + 1
	if isOpen then refresh() end
end)

-- Sync salda
local function watchLeaderstats()
	local ls = localPlayer:FindFirstChild("leaderstats") or localPlayer:WaitForChild("leaderstats", 5)
	if not ls then return end
	local zl = ls:FindFirstChild("Zlotowki") or ls:WaitForChild("Zlotowki", 5)
	if not zl then return end
	zl.Changed:Connect(function(v)
		pData.Zlotowki = v
		if isOpen then refresh() end
	end)
end
task.spawn(watchLeaderstats)

-- HatStatusUpdate ustawia HatOwned po reconnect
local HatStatusUpdate = Events:WaitForChild("HatStatusUpdate")
HatStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) == "table" then
		pData.HatOwned = data.owned == true
		if isOpen then refresh() end
	end
end)
