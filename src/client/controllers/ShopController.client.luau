-- ShopController.luau
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local SFX_FOLDER = workspace:WaitForChild("SFX")
local function getOrCreateSfxGroup(): SoundGroup
	local existing = SoundService:FindFirstChild("SfxGroup")
	if existing and existing:IsA("SoundGroup") then return existing :: SoundGroup end
	local g = Instance.new("SoundGroup")
	g.Name = "SfxGroup"; g.Volume = 1; g.Parent = SoundService
	return g
end
local SFX_GROUP = getOrCreateSfxGroup()
local function playSfx(name: string)
	local template = SFX_FOLDER:FindFirstChild(name)
	if not template or not template:IsA("Sound") then return end
	local s = template:Clone()
	s.SoundGroup = SFX_GROUP
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

local Config         = require(ReplicatedStorage:WaitForChild("Config"))
local Util           = require(ReplicatedStorage:WaitForChild("Util"))
local Events         = ReplicatedStorage:WaitForChild("Events")
local OpenShop       = Events:WaitForChild("OpenShop")
local BuyBackpack    = Events:WaitForChild("BuyBackpack")
local BackpackResult = Events:WaitForChild("BackpackResult")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta (zgodna z HUD / Inventory / SkillTree) ─────────────────────────

local C_BG       = Color3.fromRGB(18, 91, 73)
local C_PANEL    = Color3.fromRGB(24, 110, 90)
local C_HEADER   = Color3.fromRGB(0, 53, 39)
local C_CARD     = Color3.fromRGB(14, 75, 60)
local C_BORDER   = Color3.fromRGB(5, 25, 20)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT  = Color3.fromRGB(175, 175, 175)
local C_ACC_OK   = Color3.fromRGB(170, 221, 102)
local C_ACC_BAD  = Color3.fromRGB(220, 80, 80)
local C_ACC_BLUE = Color3.fromRGB(88, 166, 255)
local FONT       = Enum.Font.GothamBlack

-- ── Stan lokalny ──────────────────────────────────────────────────────────

local pData = { BackpackLevel = 1, Zlotowki = 0 }
local isOpen = false

-- ── ScreenGui ─────────────────────────────────────────────────────────────

local PANEL_W  = 680
local HEADER_H = 52
local CARD_H   = 88
local CARD_GAP = 12
local PADDING  = 24
local CARDS_H  = 4 * CARD_H + 3 * CARD_GAP
local PANEL_H  = HEADER_H + PADDING + CARDS_H + PADDING

local shopGui = Instance.new("ScreenGui")
shopGui.Name           = "Shop"
shopGui.ResetOnSpawn   = false
shopGui.IgnoreGuiInset = true
shopGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
shopGui.DisplayOrder   = 30   -- nad HUD btnami (DO=10); overlay panelu przykrywa ikonki HUD
shopGui.Enabled        = false
shopGui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = shopGui

local panel = Instance.new("Frame")
panel.Size                  = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint           = Vector2.new(0.5, 0.5)
panel.Position              = UDim2.new(0.5, 0, 0.55, 0)
panel.BackgroundColor3      = C_PANEL
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel       = 0
panel.ClipsDescendants      = true
panel.ZIndex                = 2
panel.Parent                = shopGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = panel
	local s = Instance.new("UIStroke")
	s.Color = C_BORDER; s.Thickness = 4; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = panel
end

-- ── Header z UICorner + bottom-fill + separator (wzór z CLAUDE.md) ────────

local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.Position         = UDim2.fromOffset(0, 0)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(1, 0, 0, 10)
	fill.Position         = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3 = C_HEADER
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 3
	fill.Parent           = header
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, 0, 0, 2)
	sep.Position         = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER
	sep.BorderSizePixel  = 0
	sep.ZIndex           = 5
	sep.Parent           = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -70, 1, 0)
title.Position               = UDim2.fromOffset(22, 0)
title.BackgroundTransparency = 1
title.Text                   = "SKLEP — PLECAKI"
title.TextSize               = 16
title.Font                   = FONT
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

local X_RED       = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER = Color3.fromRGB(255, 110, 110)

local closeBtn = Instance.new("TextButton")
closeBtn.Size                   = UDim2.fromOffset(36, 36)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "X"
closeBtn.TextSize               = 24
closeBtn.Font                   = FONT
closeBtn.TextColor3             = X_RED
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 5
closeBtn.Parent                 = header
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
		closeBtn.TextColor3 = X_RED_HOVER
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		closeBtn.TextColor3 = X_RED
	end)
end

-- ── Kontener kart ─────────────────────────────────────────────────────────

-- ScrollingFrame — karty plecaków układane UIListLayout, scroll Y gdy L5+ nie mieści się.
local cardsContainer = Instance.new("ScrollingFrame")
cardsContainer.Size                   = UDim2.new(1, -PADDING * 2, 0, CARDS_H)
cardsContainer.Position               = UDim2.fromOffset(PADDING, HEADER_H + PADDING)
cardsContainer.BackgroundTransparency = 1
cardsContainer.BorderSizePixel        = 0
cardsContainer.CanvasSize             = UDim2.fromOffset(0, 0)  -- AutomaticCanvasSize liczy sam
cardsContainer.AutomaticCanvasSize    = Enum.AutomaticSize.Y
cardsContainer.ScrollBarThickness     = 6
cardsContainer.ScrollBarImageColor3   = Color3.fromRGB(80, 120, 100)
cardsContainer.ScrollingDirection     = Enum.ScrollingDirection.Y
cardsContainer.ZIndex                 = 3
cardsContainer.Parent                 = panel
do
	local list = Instance.new("UIListLayout")
	list.Padding              = UDim.new(0, CARD_GAP)
	list.SortOrder            = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment  = Enum.HorizontalAlignment.Center
	list.Parent               = cardsContainer
end

-- ── Karta plecaka ─────────────────────────────────────────────────────────

type CardHandle = {
	level:        number,
	frame:        Frame,
	nameLbl:      TextLabel,
	capLbl:       TextLabel,
	statusLbl:    TextLabel,
	buyBtn:       TextButton,
	buyStroke:    UIStroke,
}

local cards: { CardHandle } = {}

local function buildCard(level: number, upgrade: any): CardHandle
	local frame = Instance.new("Frame")
	frame.Size                   = UDim2.new(1, -12, 0, CARD_H)  -- -12 na ScrollBar
	frame.BackgroundColor3       = C_CARD
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel        = 0
	frame.LayoutOrder            = level
	frame.ZIndex                 = 3
	frame.Parent                 = cardsContainer
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
		local s = Instance.new("UIStroke")
		s.Color = C_BORDER; s.Thickness = 3; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = frame
	end

	-- Numer poziomu (badge po lewej)
	local badge = Instance.new("TextLabel")
	badge.Size                   = UDim2.fromOffset(56, 56)
	badge.AnchorPoint            = Vector2.new(0, 0.5)
	badge.Position               = UDim2.new(0, 14, 0.5, 0)
	badge.BackgroundColor3       = C_HEADER
	badge.BorderSizePixel        = 0
	badge.Text                   = "LV " .. level
	badge.TextSize               = 16
	badge.Font                   = FONT
	badge.TextColor3             = C_WHITE
	badge.ZIndex                 = 4
	badge.Parent                 = frame
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = badge
		local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = badge
	end

	-- Nazwa
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size                   = UDim2.new(0, 280, 0, 24)
	nameLbl.Position               = UDim2.fromOffset(84, 14)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text                   = upgrade.Name
	nameLbl.TextSize               = 18
	nameLbl.Font                   = FONT
	nameLbl.TextColor3             = C_WHITE
	nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
	nameLbl.ZIndex                 = 4
	nameLbl.Parent                 = frame

	-- Pojemność — total + split per kategoria (butelki / pety / akcesoria).
	-- Liczone tym samym Util.getCategoryCaps co serwer i EQ → wartości spójne.
	local caps = Util.getCategoryCaps(upgrade.Capacity, Config.BackpackCategorySplit)
	local capLbl = Instance.new("TextLabel")
	capLbl.Size                   = UDim2.new(0, 380, 0, 38)
	capLbl.Position               = UDim2.fromOffset(84, 40)
	capLbl.BackgroundTransparency = 1
	capLbl.Text                   = string.format(
		"Pojemność: %d miejsc\n%d butelek · %d petów · %d akcesoriów",
		upgrade.Capacity, caps.bottles, caps.pets, caps.accessories
	)
	capLbl.TextSize               = 13
	capLbl.Font                   = FONT
	capLbl.TextColor3             = C_DIMTEXT
	capLbl.TextXAlignment         = Enum.TextXAlignment.Left
	capLbl.TextYAlignment         = Enum.TextYAlignment.Top
	capLbl.ZIndex                 = 4
	capLbl.Parent                 = frame

	-- Status (mała etykieta nad przyciskiem)
	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size                   = UDim2.new(0, 180, 0, 16)
	statusLbl.AnchorPoint            = Vector2.new(1, 0)
	statusLbl.Position               = UDim2.new(1, -14, 0, 12)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text                   = ""
	statusLbl.TextSize               = 12
	statusLbl.Font                   = FONT
	statusLbl.TextColor3             = C_DIMTEXT
	statusLbl.TextXAlignment         = Enum.TextXAlignment.Right
	statusLbl.ZIndex                 = 4
	statusLbl.Parent                 = frame

	-- Przycisk KUP
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size                 = UDim2.fromOffset(200, 44)
	buyBtn.AnchorPoint          = Vector2.new(1, 1)
	buyBtn.Position             = UDim2.new(1, -14, 1, -14)
	buyBtn.BackgroundColor3     = C_BG
	buyBtn.BorderSizePixel      = 0
	buyBtn.Text                 = "KUP"
	buyBtn.TextSize             = 15
	buyBtn.Font                 = FONT
	buyBtn.TextColor3           = C_WHITE
	buyBtn.AutoButtonColor      = false
	buyBtn.ZIndex               = 4
	buyBtn.Parent               = frame

	local buyStroke
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn
		buyStroke = Instance.new("UIStroke")
		buyStroke.Color = C_BORDER; buyStroke.Thickness = 3
		buyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		buyStroke.Parent = buyBtn

		local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = buyBtn
		local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		buyBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
		buyBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
	end

	buyBtn.MouseButton1Click:Connect(function()
		playSfx("Click")
		BuyBackpack:FireServer(level)
	end)

	return {
		level     = level,
		frame     = frame,
		nameLbl   = nameLbl,
		capLbl    = capLbl,
		statusLbl = statusLbl,
		buyBtn    = buyBtn,
		buyStroke = buyStroke,
	}
end

for i, upgrade in ipairs(Config.BackpackUpgrades) do
	cards[i] = buildCard(i, upgrade)
end

-- ── Render stanu ──────────────────────────────────────────────────────────

local function renderCards()
	for _, card in ipairs(cards) do
		local upgrade = Config.BackpackUpgrades[card.level]
		local current = pData.BackpackLevel

		if card.level <= current then
			-- KUPIONE
			card.statusLbl.Text       = "KUPIONE"
			card.statusLbl.TextColor3 = C_ACC_OK
			card.buyBtn.Text          = "POSIADANE ✓"
			card.buyBtn.TextColor3    = C_ACC_OK
			card.buyBtn.BackgroundColor3 = C_BG
			card.buyStroke.Color      = C_BORDER
			card.buyBtn.Active        = false
		elseif card.level == current + 1 then
			-- DOSTĘPNE — sprawdź czy stać
			local afford = upgrade.Cost <= pData.Zlotowki
			if afford then
				card.statusLbl.Text       = "DOSTĘPNE"
				card.statusLbl.TextColor3 = C_ACC_BLUE
				card.buyBtn.Text          = "KUP — " .. upgrade.Cost .. " ZŁ"
				card.buyBtn.TextColor3    = Color3.new(0, 0, 0)
				card.buyBtn.BackgroundColor3 = C_ACC_OK
				card.buyStroke.Color      = C_ACC_OK
				card.buyBtn.Active        = true
			else
				card.statusLbl.Text       = "ZA MAŁO ZŁ"
				card.statusLbl.TextColor3 = C_ACC_BAD
				card.buyBtn.Text          = upgrade.Cost .. " ZŁ"
				card.buyBtn.TextColor3    = C_DIMTEXT
				card.buyBtn.BackgroundColor3 = C_BG
				card.buyStroke.Color      = C_BORDER
				card.buyBtn.Active        = false
			end
		else
			-- ZABLOKOWANE (poziom > current + 1)
			card.statusLbl.Text       = "WYMAGA LV " .. (card.level - 1)
			card.statusLbl.TextColor3 = C_DIMTEXT
			card.buyBtn.Text          = "ZABLOKOWANE"
			card.buyBtn.TextColor3    = C_DIMTEXT
			card.buyBtn.BackgroundColor3 = C_BG
			card.buyStroke.Color      = C_BORDER
			card.buyBtn.Active        = false
		end
	end
end

-- ── Toggle ────────────────────────────────────────────────────────────────

local POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local TI_OPEN  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local shopMoveLocked = false
local function setOpen(open: boolean)
	isOpen = open
	if open and not shopMoveLocked then
		shopMoveLocked = true
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("BACKPACK_SHOP") end
	elseif not open and shopMoveLocked then
		shopMoveLocked = false
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		if _G["__hudPanelClose"] then _G["__hudPanelClose"]("BACKPACK_SHOP") end
	end
	if open then
		shopGui.Enabled              = true
		panel.Position               = POS_HIDE
		overlay.BackgroundTransparency = 1
		renderCards()
		TweenService:Create(panel,   TI_OPEN, { Position = POS_SHOW }):Play()
		TweenService:Create(overlay, TI_OPEN, { BackgroundTransparency = 0.30 }):Play()
	else
		TweenService:Create(panel, TI_CLOSE, { Position = POS_HIDE }):Play()
		local tw = TweenService:Create(overlay, TI_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not isOpen then shopGui.Enabled = false end
		end)
		tw:Play()
	end
end

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, proc)
	if proc then return end
	if isOpen and input.KeyCode == Enum.KeyCode.Escape then setOpen(false) end
end)

-- ── Remote listeners ──────────────────────────────────────────────────────

OpenShop.OnClientEvent:Connect(function()
	setOpen(true)
end)

BackpackResult.OnClientEvent:Connect(function(result)
	if result.success then
		playSfx("Buy")
		pData.BackpackLevel = result.newLevel
		renderCards()
	end
	-- Cichy fail (re-render i tak się dzieje przez Zlotowki.Changed)
end)

-- Saldo z leaderstats (auto-replikacja)
task.spawn(function()
	local ls = localPlayer:WaitForChild("leaderstats", 15)
	if not ls then return end
	local zl = ls:WaitForChild("Zlotowki", 10)
	if not zl then return end
	pData.Zlotowki = zl.Value
	zl.Changed:Connect(function(v)
		pData.Zlotowki = v
		if isOpen then renderCards() end
	end)
end)

-- Initial BackpackLevel z UpdateHUD (pełny snapshot przy starcie)
local UpdateHUD = Events:WaitForChild("UpdateHUD")
UpdateHUD.OnClientEvent:Connect(function(data)
	-- backpackCapacity → wnioskujemy poziom
	if data.backpackCapacity then
		for i, u in ipairs(Config.BackpackUpgrades) do
			if u.Capacity == data.backpackCapacity then
				pData.BackpackLevel = i
				break
			end
		end
		if isOpen then renderCards() end
	end
end)
