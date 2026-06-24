-- DeckShopController.client.luau
-- 1) Gablota (ProximityPrompt) → OpenDeckShop → panel zakupu pojedynczej deski (nazwa, statystyki, cena, KUP)
-- 2) Przycisk hoverboard w HUD → menu TWOJE DESKI (4 okienka, statystyki, WYPOSAŻ)
-- Stan posiadania/equip synchronizowany przez DeckStatus.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Events        = ReplicatedStorage:WaitForChild("Events")
local OpenDeckShop  = Events:WaitForChild("OpenDeckShop")
local BuyDeck       = Events:WaitForChild("BuyDeck")
local BuyDeckResult = Events:WaitForChild("BuyDeckResult")
local EquipDeck     = Events:WaitForChild("EquipDeck")
local DeckStatus    = Events:WaitForChild("DeckStatus")

-- ── Paleta (green theme) ──────────────────────────────────────────────────────
local C_BG           = Color3.fromRGB(18, 91, 73)
local C_PANEL        = Color3.fromRGB(24, 110, 90)
local C_HEADER       = Color3.fromRGB(0, 53, 39)
local C_SLOT         = Color3.fromRGB(8, 60, 48)
local C_BORDER       = Color3.fromRGB(5, 25, 20)
local C_WHITE        = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT      = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)
local C_BLUE         = Color3.fromRGB(70, 120, 180)
local C_GOLD         = Color3.fromRGB(230, 190, 60)
local C_RED          = Color3.fromRGB(200, 70, 70)
local X_RED          = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER    = Color3.fromRGB(255, 110, 110)
local FONT_MAIN      = Enum.Font.GothamBlack
local TI             = TweenInfo.new(0.12, Enum.EasingStyle.Quad)

-- ── Stan ──────────────────────────────────────────────────────────────────────
local ownedDecks: { [string]: boolean } = {}
local equippedKey = ""

-- ── Helpers UI ──────────────────────────────────────────────────────────────
local function mkCorner(o: Instance, r: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o
end
local function mkStroke(o: Instance, col: Color3, th: number)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = o
	return s
end
local function hoverScale(btn: GuiObject, to: number)
	local sc = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Parent = btn
	btn.MouseEnter:Connect(function() TweenService:Create(sc, TI, { Scale = to }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(sc, TI, { Scale = 1 }):Play() end)
end
local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl = folder and folder:FindFirstChild(name)
	if not tmpl then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Volume = 1; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end
-- X-close — wspólny styl ze STATS (asset 124962493500922, ImageButton, hover UIScale 1.15)
local function makeXButton(parent: GuiObject, onClick: () -> ())
	local x = Instance.new("ImageButton")
	x.AnchorPoint            = Vector2.new(1, 0)
	x.Position               = UDim2.new(1, -12, 0, 10)
	x.Size                   = UDim2.fromOffset(46, 46)
	x.BackgroundTransparency = 1
	x.Image                  = "rbxassetid://124962493500922"
	x.ScaleType              = Enum.ScaleType.Fit
	x.AutoButtonColor        = false
	x.Parent                 = parent
	local sc = Instance.new("UIScale"); sc.Parent = x
	x.MouseEnter:Connect(function() TweenService:Create(sc, TI, { Scale = 1.15 }):Play() end)
	x.MouseLeave:Connect(function() TweenService:Create(sc, TI, { Scale = 1.0 }):Play() end)
	x.MouseButton1Click:Connect(function() playSfx("Click"); onClick() end)
	return x
end

local function deckByKey(key: string)
	for _, d in ipairs(Config.Decks) do if d.key == key then return d end end
	return nil
end
local function priceText(deck): string
	if deck.CostType == "Robux" or deck.CostType == "Gamepass" then
		return (deck.RobuxPrice or "?") .. " R$"
	end
	return (deck.Cost or 0) .. " PLN"
end
local function isPaidInRobux(deck): boolean
	return deck.CostType == "Robux" or deck.CostType == "Gamepass"
end

-- ════════════════════════════════════════════════════════════════════════════
-- 1) PANEL ZAKUPU (gablota)
-- ════════════════════════════════════════════════════════════════════════════
local buyGui = Instance.new("ScreenGui")
buyGui.Name = "DeckBuyGui"
buyGui.ResetOnSpawn = false
buyGui.IgnoreGuiInset = true
buyGui.DisplayOrder = 45
buyGui.Enabled = false
buyGui.Parent = playerGui

local buyOverlay = Instance.new("TextButton")
buyOverlay.Size = UDim2.fromScale(1, 1)
buyOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
buyOverlay.BackgroundTransparency = 0.30
buyOverlay.AutoButtonColor = false
buyOverlay.Text = ""
buyOverlay.Parent = buyGui

local buyPanel = Instance.new("Frame")
buyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
buyPanel.Position = UDim2.fromScale(0.5, 0.5)
buyPanel.Size = UDim2.fromOffset(460, 420)
buyPanel.BackgroundColor3 = C_BG
buyPanel.BackgroundTransparency = 0.05
buyPanel.BorderSizePixel = 0
buyPanel.Parent = buyGui
mkCorner(buyPanel, 8)
mkStroke(buyPanel, C_BORDER, 4)

local buyHeader = Instance.new("Frame")
buyHeader.Size = UDim2.new(1, 0, 0, 64)
buyHeader.BackgroundColor3 = C_HEADER
buyHeader.BorderSizePixel = 0
buyHeader.Parent = buyPanel
mkCorner(buyHeader, 8)
do
	local mask = Instance.new("Frame")
	mask.Size = UDim2.new(1, 0, 0, 10); mask.Position = UDim2.new(0, 0, 1, -10)
	mask.BackgroundColor3 = C_HEADER; mask.BorderSizePixel = 0; mask.Parent = buyHeader
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.Parent = buyHeader
end
local buyTitle = Instance.new("TextLabel")
buyTitle.BackgroundTransparency = 1
buyTitle.Position = UDim2.fromOffset(20, 0)
buyTitle.Size = UDim2.new(1, -70, 1, 0)
buyTitle.TextXAlignment = Enum.TextXAlignment.Left
buyTitle.Font = FONT_MAIN; buyTitle.TextSize = 26; buyTitle.TextColor3 = C_WHITE
buyTitle.Text = "SKLEP — DESKA"
buyTitle.Parent = buyHeader
local buyLocked = false
local function setBuyOpen(open: boolean)
	buyGui.Enabled = open
	if open and not buyLocked then
		buyLocked = true
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("DESKA_BUY") end
	elseif not open and buyLocked then
		buyLocked = false
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		if _G["__hudPanelClose"] then _G["__hudPanelClose"]("DESKA_BUY") end
	end
end
makeXButton(buyHeader, function() setBuyOpen(false) end)
buyOverlay.MouseButton1Click:Connect(function() end)  -- klik w tło nie zamyka

-- Swatch (obrazek deski)
local buySwatch = Instance.new("Frame")
buySwatch.AnchorPoint = Vector2.new(0.5, 0)
buySwatch.Position = UDim2.new(0.5, 0, 0, 84)
buySwatch.Size = UDim2.fromOffset(180, 110)
buySwatch.BackgroundColor3 = C_SLOT
buySwatch.BorderSizePixel = 0
buySwatch.Parent = buyPanel
mkCorner(buySwatch, 10)
local buySwatchStroke = mkStroke(buySwatch, C_BORDER, 3)
local buySwatchImg = Instance.new("ImageLabel")
buySwatchImg.BackgroundTransparency = 1
buySwatchImg.Size = UDim2.fromScale(0.92, 0.92)
buySwatchImg.AnchorPoint = Vector2.new(0.5, 0.5)
buySwatchImg.Position = UDim2.fromScale(0.5, 0.5)
buySwatchImg.ScaleType = Enum.ScaleType.Fit
buySwatchImg.ZIndex = 1
buySwatchImg.Parent = buySwatch
local buySwatchName = Instance.new("TextLabel")
buySwatchName.BackgroundTransparency = 1
buySwatchName.Size = UDim2.fromScale(1, 1)
buySwatchName.Font = FONT_MAIN; buySwatchName.TextSize = 24; buySwatchName.TextColor3 = C_WHITE
buySwatchName.TextStrokeTransparency = 0.4
buySwatchName.ZIndex = 2
buySwatchName.Text = ""
buySwatchName.Parent = buySwatch

local buySpeed = Instance.new("TextLabel")
buySpeed.BackgroundTransparency = 1
buySpeed.Position = UDim2.new(0, 0, 0, 210)
buySpeed.Size = UDim2.new(1, 0, 0, 30)
buySpeed.Font = FONT_MAIN; buySpeed.TextSize = 22; buySpeed.TextColor3 = C_ACCENT_GREEN
buySpeed.Text = ""
buySpeed.Parent = buyPanel

local buyPrice = Instance.new("TextLabel")
buyPrice.BackgroundTransparency = 1
buyPrice.Position = UDim2.new(0, 0, 0, 246)
buyPrice.Size = UDim2.new(1, 0, 0, 34)
buyPrice.Font = FONT_MAIN; buyPrice.TextSize = 28; buyPrice.TextColor3 = C_WHITE
buyPrice.Text = ""
buyPrice.Parent = buyPanel

local buyStatus = Instance.new("TextLabel")
buyStatus.BackgroundTransparency = 1
buyStatus.Position = UDim2.new(0, 0, 0, 284)
buyStatus.Size = UDim2.new(1, 0, 0, 24)
buyStatus.Font = FONT_MAIN; buyStatus.TextSize = 16; buyStatus.TextColor3 = C_DIMTEXT
buyStatus.Text = ""
buyStatus.Parent = buyPanel

local buyBtn = Instance.new("TextButton")
buyBtn.AnchorPoint = Vector2.new(0.5, 1)
buyBtn.Position = UDim2.new(0.5, 0, 1, -22)
buyBtn.Size = UDim2.fromOffset(260, 56)
buyBtn.BackgroundColor3 = C_ACCENT_GREEN
buyBtn.BorderSizePixel = 0
buyBtn.Font = FONT_MAIN; buyBtn.TextSize = 24; buyBtn.TextColor3 = C_HEADER
buyBtn.Text = "KUP"
buyBtn.AutoButtonColor = false
buyBtn.Parent = buyPanel
mkCorner(buyBtn, 8); mkStroke(buyBtn, C_BORDER, 4); hoverScale(buyBtn, 1.06)

local currentBuyKey = ""

local function refreshBuyPanel()
	local deck = deckByKey(currentBuyKey)
	if not deck then return end
	buyTitle.Text = "SKLEP — " .. string.upper(deck.name)
	buySwatchImg.Image = deck.image or ""
	buySwatchImg.Visible = deck.image ~= nil
	buySwatchStroke.Color = C_BORDER
	buySwatchName.Text = deck.name
	buySpeed.Text = "Prędkość: " .. deck.Speed
	buyPrice.Text = priceText(deck)

	if ownedDecks[deck.key] then
		buyStatus.Text = "Już posiadasz tę deskę"
		buyStatus.TextColor3 = C_ACCENT_GREEN
		buyBtn.Text = "POSIADANE ✓"
		buyBtn.BackgroundColor3 = C_SLOT
		buyBtn.TextColor3 = C_DIMTEXT
		buyBtn.Active = false
	else
		local robux = isPaidInRobux(deck)
		local label = (deck.CostType == "Gamepass") and "Gamepass" or "Płatność w Robux"
		buyStatus.Text = robux and label or "Naciśnij KUP aby kupić"
		buyStatus.TextColor3 = C_DIMTEXT
		buyBtn.Text = robux and ("KUP — " .. (deck.RobuxPrice or "?") .. " R$") or "KUP"
		buyBtn.BackgroundColor3 = robux and C_GOLD or C_ACCENT_GREEN
		buyBtn.TextColor3 = C_HEADER
		buyBtn.Active = true
	end
end

buyBtn.MouseButton1Click:Connect(function()
	local deck = deckByKey(currentBuyKey)
	if not deck or ownedDecks[deck.key] then return end
	playSfx("Click")
	BuyDeck:FireServer(deck.key)
	buyStatus.Text = "Przetwarzanie..."
	buyStatus.TextColor3 = C_DIMTEXT
end)

OpenDeckShop.OnClientEvent:Connect(function(deckKey: string)
	currentBuyKey = deckKey
	refreshBuyPanel()
	setBuyOpen(true)
end)

-- ════════════════════════════════════════════════════════════════════════════
-- 2) MENU TWOJE DESKI (przycisk hoverboard)
-- ════════════════════════════════════════════════════════════════════════════
local menuGui = Instance.new("ScreenGui")
menuGui.Name = "DeckMenuGui"
menuGui.ResetOnSpawn = false
menuGui.IgnoreGuiInset = true
menuGui.DisplayOrder = 20  -- pod głównym MENU (MenuController = 30), nad HUD
menuGui.Parent = playerGui

-- Btn hoverboard na DEDYKOWANYM ScreenGui DO=10 (pod wszystkimi panelami).
-- Wcześniej był na menuGui (DO=20) — co stawiało go nad innymi panelami i blokowało overlay.
local hudBtnGui = Instance.new("ScreenGui")
hudBtnGui.Name           = "DeckHudBtn"
hudBtnGui.ResetOnSpawn   = false
hudBtnGui.IgnoreGuiInset = true
hudBtnGui.DisplayOrder   = 10
hudBtnGui.Parent         = playerGui

-- Przycisk hoverboard (HUD, lewa strona pod przyciskiem MENU) — sam obrazek, bez tła/ramki
local hoverBtn = Instance.new("ImageButton")
hoverBtn.Name = "HoverboardButton"
hoverBtn.AnchorPoint = Vector2.new(0, 0.5)
hoverBtn.Position = UDim2.new(0, 16, 0.5, -95)  -- lewa strona, środek (nad teleportem)
hoverBtn.Size = UDim2.fromOffset(156, 156)
hoverBtn.BackgroundTransparency = 1
hoverBtn.BorderSizePixel = 0
hoverBtn.Image = Config.DeckMenuIconId
hoverBtn.ScaleType = Enum.ScaleType.Fit
hoverBtn.AutoButtonColor = false
hoverBtn.Parent = hudBtnGui
-- Hover: powiększenie + leciutki obrót (jak przycisk MENU)
do
	-- Hover przez Size (nie UIScale) — by responsywny __MobileUIScale działał na przycisku deski
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local baseSize = UDim2.fromOffset(156, 156)
	local hoverSize = UDim2.fromOffset(175, 175)
	hoverBtn.MouseEnter:Connect(function()
		TweenService:Create(hoverBtn, ti, { Size = hoverSize, Rotation = 6 }):Play()
	end)
	hoverBtn.MouseLeave:Connect(function()
		TweenService:Create(hoverBtn, ti, { Size = baseSize, Rotation = 0 }):Play()
	end)
end


local menuOverlay = Instance.new("TextButton")
menuOverlay.Size = UDim2.fromScale(1, 1)
menuOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
menuOverlay.BackgroundTransparency = 0.30
menuOverlay.AutoButtonColor = false
menuOverlay.Text = ""
menuOverlay.Visible = false
menuOverlay.Parent = menuGui

local menuPanel = Instance.new("Frame")
menuPanel.AnchorPoint = Vector2.new(0.5, 0.5)
menuPanel.Position = UDim2.fromScale(0.5, 0.5)
menuPanel.Size = UDim2.fromOffset(920, 560)
menuPanel.BackgroundColor3 = C_BG
menuPanel.BackgroundTransparency = 0.05
menuPanel.BorderSizePixel = 0
menuPanel.Visible = false
menuPanel.Parent = menuGui
mkCorner(menuPanel, 8); mkStroke(menuPanel, C_BORDER, 4)

-- (auto-hide hoverBtn przy `__moveLockCount > 0` usunięte — shared HUD lock teraz
-- robi dim+disable zamiast hide.)

local menuHeader = Instance.new("Frame")
menuHeader.Size = UDim2.new(1, 0, 0, 64)
menuHeader.BackgroundColor3 = C_HEADER
menuHeader.BorderSizePixel = 0
menuHeader.Parent = menuPanel
mkCorner(menuHeader, 8)
do
	local mask = Instance.new("Frame")
	mask.Size = UDim2.new(1, 0, 0, 10); mask.Position = UDim2.new(0, 0, 1, -10)
	mask.BackgroundColor3 = C_HEADER; mask.BorderSizePixel = 0; mask.Parent = menuHeader
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.Parent = menuHeader
end
local menuTitle = Instance.new("TextLabel")
menuTitle.BackgroundTransparency = 1
menuTitle.Position = UDim2.fromOffset(20, 0)
menuTitle.Size = UDim2.new(1, -70, 1, 0)
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
menuTitle.Font = FONT_MAIN; menuTitle.TextSize = 26; menuTitle.TextColor3 = C_WHITE
menuTitle.Text = "TWOJE DESKI"
menuTitle.Parent = menuHeader

-- Lewa siatka kart (2×2)
local cardsHolder = Instance.new("Frame")
cardsHolder.Position = UDim2.fromOffset(24, 84)
cardsHolder.Size = UDim2.fromOffset(440, 452)
cardsHolder.BackgroundTransparency = 1
cardsHolder.Parent = menuPanel
do
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(210, 218)
	grid.CellPadding = UDim2.fromOffset(20, 16)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cardsHolder
end

-- Prawy panel detali
local detail = Instance.new("Frame")
detail.AnchorPoint = Vector2.new(1, 0)
detail.Position = UDim2.new(1, -24, 0, 84)
detail.Size = UDim2.fromOffset(380, 452)
detail.BackgroundColor3 = C_PANEL
detail.BackgroundTransparency = 0.05
detail.BorderSizePixel = 0
detail.Parent = menuPanel
mkCorner(detail, 8); mkStroke(detail, C_BORDER, 4)

local detSwatch = Instance.new("Frame")
detSwatch.AnchorPoint = Vector2.new(0.5, 0)
detSwatch.Position = UDim2.new(0.5, 0, 0, 24)
detSwatch.Size = UDim2.fromOffset(200, 120)
detSwatch.BackgroundColor3 = C_SLOT
detSwatch.BorderSizePixel = 0
detSwatch.Parent = detail
mkCorner(detSwatch, 10)
local detSwatchStroke = mkStroke(detSwatch, C_BORDER, 3)
local detSwatchImg = Instance.new("ImageLabel")
detSwatchImg.BackgroundTransparency = 1
detSwatchImg.Size = UDim2.fromScale(0.92, 0.92)
detSwatchImg.AnchorPoint = Vector2.new(0.5, 0.5)
detSwatchImg.Position = UDim2.fromScale(0.5, 0.5)
detSwatchImg.ScaleType = Enum.ScaleType.Fit
detSwatchImg.Parent = detSwatch

local detName = Instance.new("TextLabel")
detName.BackgroundTransparency = 1
detName.Position = UDim2.new(0, 0, 0, 160)
detName.Size = UDim2.new(1, 0, 0, 34)
detName.Font = FONT_MAIN; detName.TextSize = 28; detName.TextColor3 = C_WHITE
detName.Text = ""
detName.Parent = detail

local detSpeed = Instance.new("TextLabel")
detSpeed.BackgroundTransparency = 1
detSpeed.Position = UDim2.new(0, 0, 0, 202)
detSpeed.Size = UDim2.new(1, 0, 0, 28)
detSpeed.Font = FONT_MAIN; detSpeed.TextSize = 22; detSpeed.TextColor3 = C_ACCENT_GREEN
detSpeed.Text = ""
detSpeed.Parent = detail

local detStatus = Instance.new("TextLabel")
detStatus.BackgroundTransparency = 1
detStatus.Position = UDim2.new(0, 0, 0, 238)
detStatus.Size = UDim2.new(1, 0, 0, 26)
detStatus.Font = FONT_MAIN; detStatus.TextSize = 18; detStatus.TextColor3 = C_DIMTEXT
detStatus.Text = ""
detStatus.Parent = detail

local equipBtn = Instance.new("TextButton")
equipBtn.AnchorPoint = Vector2.new(0.5, 1)
equipBtn.Position = UDim2.new(0.5, 0, 1, -22)
equipBtn.Size = UDim2.fromOffset(280, 58)
equipBtn.BackgroundColor3 = C_ACCENT_GREEN
equipBtn.BorderSizePixel = 0
equipBtn.Font = FONT_MAIN; equipBtn.TextSize = 24; equipBtn.TextColor3 = C_HEADER
equipBtn.Text = "WYPOSAŻ"
equipBtn.AutoButtonColor = false
equipBtn.Parent = detail
mkCorner(equipBtn, 8); mkStroke(equipBtn, C_BORDER, 4); hoverScale(equipBtn, 1.06)

local selectedKey = ""
local cardRefs: { [string]: any } = {}

local function refreshDetail()
	local deck = deckByKey(selectedKey)
	if not deck then
		detName.Text = "—"; detSpeed.Text = ""; detStatus.Text = "Wybierz deskę"
		equipBtn.Visible = false
		detSwatchImg.Image = ""; detSwatchStroke.Color = C_BORDER
		return
	end
	detSwatchImg.Image = deck.image or ""
	detSwatchImg.Visible = deck.image ~= nil
	detSwatchStroke.Color = C_BORDER
	detName.Text = deck.name
	detSpeed.Text = "Prędkość: " .. deck.Speed
	equipBtn.Visible = true

	if not ownedDecks[deck.key] then
		detStatus.Text = "Niezakupiona — kup przy gablocie " .. (deck.gablota or "?")
		detStatus.TextColor3 = C_DIMTEXT
		equipBtn.Text = "ZABLOKOWANE"
		equipBtn.BackgroundColor3 = C_SLOT
		equipBtn.TextColor3 = C_DIMTEXT
		equipBtn.Active = false
	elseif equippedKey == deck.key then
		detStatus.Text = "Aktualnie wyposażona"
		detStatus.TextColor3 = C_ACCENT_GREEN
		equipBtn.Text = "WYPOSAŻONA ✓"
		equipBtn.BackgroundColor3 = C_SLOT
		equipBtn.TextColor3 = C_ACCENT_GREEN
		equipBtn.Active = false
	else
		detStatus.Text = "Posiadasz tę deskę"
		detStatus.TextColor3 = C_ACCENT_GREEN
		equipBtn.Text = "WYPOSAŻ"
		equipBtn.BackgroundColor3 = C_ACCENT_GREEN
		equipBtn.TextColor3 = C_HEADER
		equipBtn.Active = true
	end
end

local function refreshCards()
	for _, deck in ipairs(Config.Decks) do
		local ref = cardRefs[deck.key]
		if ref then
			local isOwned = ownedDecks[deck.key]
			ref.badge.Text = (equippedKey == deck.key) and "WYPOSAŻONA"
				or (isOwned and "POSIADANA" or "ZABLOKOWANA")
			ref.badge.TextColor3 = (equippedKey == deck.key) and C_ACCENT_GREEN
				or (isOwned and C_WHITE or C_DIMTEXT)
			ref.lock.Visible = not isOwned
			ref.sel.Enabled = (selectedKey == deck.key)
		end
	end
end

local function makeCard(deck, order: number)
	local card = Instance.new("TextButton")
	card.Name = "Card_" .. deck.key
	card.LayoutOrder = order
	card.BackgroundColor3 = C_SLOT
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = cardsHolder
	mkCorner(card, 10); mkStroke(card, C_BORDER, 3); hoverScale(card, 1.04)

	-- selection outline (zielony stroke gdy zaznaczona)
	local sel = Instance.new("UIStroke")
	sel.Color = C_ACCENT_GREEN; sel.Thickness = 4
	sel.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sel.Enabled = false; sel.Parent = card

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0.5, 0)
	swatch.Position = UDim2.new(0.5, 0, 0, 16)
	swatch.Size = UDim2.fromOffset(170, 100)
	swatch.BackgroundColor3 = C_SLOT
	swatch.BorderSizePixel = 0
	swatch.Parent = card
	mkCorner(swatch, 8); mkStroke(swatch, C_BORDER, 2)

	local swatchImg = Instance.new("ImageLabel")
	swatchImg.BackgroundTransparency = 1
	swatchImg.Size = UDim2.fromScale(0.92, 0.92)
	swatchImg.AnchorPoint = Vector2.new(0.5, 0.5)
	swatchImg.Position = UDim2.fromScale(0.5, 0.5)
	swatchImg.ScaleType = Enum.ScaleType.Fit
	swatchImg.Image = deck.image or ""
	swatchImg.Visible = deck.image ~= nil
	swatchImg.ZIndex = 1
	swatchImg.Parent = swatch

	local lock = Instance.new("TextLabel")
	lock.BackgroundTransparency = 1
	lock.Size = UDim2.fromScale(1, 1)
	lock.Font = FONT_MAIN; lock.TextSize = 40; lock.TextColor3 = C_WHITE
	lock.ZIndex = 2
	lock.TextStrokeTransparency = 0.3
	lock.Text = "🔒"
	lock.Visible = false
	lock.Parent = swatch

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 0, 0, 126)
	name.Size = UDim2.new(1, 0, 0, 30)
	name.Font = FONT_MAIN; name.TextSize = 20; name.TextColor3 = C_WHITE
	name.Text = deck.name
	name.Parent = card

	local badge = Instance.new("TextLabel")
	badge.BackgroundTransparency = 1
	badge.Position = UDim2.new(0, 0, 0, 160)
	badge.Size = UDim2.new(1, 0, 0, 24)
	badge.Font = FONT_MAIN; badge.TextSize = 15; badge.TextColor3 = C_DIMTEXT
	badge.Text = "ZABLOKOWANA"
	badge.Parent = card

	card.MouseButton1Click:Connect(function()
		if selectedKey ~= deck.key then playSfx("Click") end
		selectedKey = deck.key
		refreshDetail()
		refreshCards()
	end)

	cardRefs[deck.key] = { card = card, badge = badge, lock = lock, sel = sel }
end

for i, deck in ipairs(Config.Decks) do
	makeCard(deck, i)
end

local deckMenuLocked = false
equipBtn.MouseButton1Click:Connect(function()
	local deck = deckByKey(selectedKey)
	if not deck or not ownedDecks[deck.key] or equippedKey == deck.key then return end
	EquipDeck:FireServer(deck.key)
	playSfx("Equip")
	menuOverlay.Visible = false
	menuPanel.Visible = false
	if deckMenuLocked then
		deckMenuLocked = false
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
	end
end)

-- Rejestracja w shared HUD-lock (MENU/SKLEP/STATS/DESKA/TELEPORT)
_G["__hudBtnRegistry"] = _G["__hudBtnRegistry"] or {}
_G["__hudBtnRegistry"]["DESKA"] = hoverBtn
if _G["__hudRegisterBtn"] then _G["__hudRegisterBtn"]("DESKA", hoverBtn) end

local function openMenu()
	-- domyślny wybór: wyposażona lub pierwsza posiadana lub pierwsza w configu
	if selectedKey == "" then
		selectedKey = (equippedKey ~= "" and equippedKey) or Config.Decks[1].key
		for _, d in ipairs(Config.Decks) do
			if ownedDecks[d.key] then selectedKey = (equippedKey ~= "" and equippedKey) or d.key; break end
		end
	end
	refreshDetail(); refreshCards()
	menuOverlay.Visible = true
	menuPanel.Visible = true
	if not deckMenuLocked then
		deckMenuLocked = true
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("DESKA_MENU") end
	end
end
local function closeMenu()
	menuOverlay.Visible = false
	menuPanel.Visible = false
	if deckMenuLocked then
		deckMenuLocked = false
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		if _G["__hudPanelClose"] then _G["__hudPanelClose"]("DESKA_MENU") end
	end
end

hoverBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	if menuPanel.Visible then closeMenu() else openMenu() end
end)
makeXButton(menuHeader, closeMenu)
menuOverlay.MouseButton1Click:Connect(closeMenu)

-- ── Sync stanu ─────────────────────────────────────────────────────────────
DeckStatus.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	ownedDecks = payload.owned or {}
	equippedKey = payload.equipped or ""
	if buyGui.Enabled then refreshBuyPanel() end
	if menuPanel.Visible then refreshDetail() end
	refreshCards()
end)

BuyDeckResult.OnClientEvent:Connect(function(res)
	if type(res) ~= "table" then return end
	if res.success then
		playSfx("Buy")
		if buyGui.Enabled then
			buyStatus.Text = "Kupiono! ✓"
			buyStatus.TextColor3 = C_ACCENT_GREEN
		end
	else
		if buyGui.Enabled then
			local msg = "Błąd zakupu"
			if res.reason == "broke" then msg = "Za mało złotówek!"
			elseif res.reason == "already" then msg = "Już posiadasz!"
			elseif res.reason == "noproduct" then msg = "Produkt Robux nie skonfigurowany"
			end
			buyStatus.Text = msg
			buyStatus.TextColor3 = C_RED
		end
	end
	refreshBuyPanel()
end)

print("[DeckShopController] Gotowy")
