-- ShopCatalogController.client.luau
-- Sklep Robux — osobny przycisk w HUD (po lewo od MENU) + katalog GUI z kwadratowymi kartami.
-- Karty placeholder (kolor + tekst); user dorzuci ikonki ID później.
-- Stany: POSIADASZ (deck VIP / gamepass triple), AKTYWNE z timerem (boost x2).
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local SoundService       = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Config              = require(ReplicatedStorage:WaitForChild("Config"))
local Events              = ReplicatedStorage:WaitForChild("Events")
local BoostStatusUpdate   = Events:WaitForChild("BoostStatusUpdate")
local PromptBoostPurchase = Events:WaitForChild("PromptBoostPurchase")
local DeckStatus          = Events:WaitForChild("DeckStatus")
local PetStatusUpdate     = Events:WaitForChild("PetStatusUpdate")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local sfxGroup = SoundService:FindFirstChild("SfxGroup")
if not sfxGroup then
	sfxGroup = Instance.new("SoundGroup"); sfxGroup.Name = "SfxGroup"; sfxGroup.Parent = SoundService
end
local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl   = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local s = tmpl:Clone(); s.SoundGroup = sfxGroup; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

-- ── Paleta ──────────────────────────────────────────────────────────────────
local FONT       = Enum.Font.GothamBlack
local FONT_TITLE = Enum.Font.LuckiestGuy
local C_BG          = Color3.fromRGB(18, 91, 73)
local C_PANEL       = Color3.fromRGB(24, 110, 90)
local C_HEADER      = Color3.fromRGB(0, 53, 39)
local C_BORDER      = Color3.fromRGB(5, 25, 20)
local C_WHITE       = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT     = Color3.fromRGB(175, 175, 175)
local C_ROBUX       = Color3.fromRGB(255, 220, 100)
local C_ACTIVE      = Color3.fromRGB(170, 221, 102)
local C_OWNED       = Color3.fromRGB(110, 110, 110)
local C_VIP         = Color3.fromRGB(230, 190, 60)
local C_BOOST       = Color3.fromRGB(255, 130, 70)
local C_EGG         = Color3.fromRGB(170, 110, 230)

local SHOP_ICON_ID  = "rbxassetid://116179222814716"

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function mkCorner(parent: Instance, r: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = parent
	return c
end
local function mkStroke(parent: Instance, color: Color3, t: number)
	local s = Instance.new("UIStroke")
	s.Color = color; s.Thickness = t; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- ── ScreenGui ───────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "ShopCatalog"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 31  -- ten sam co MenuController + 1, żeby otwarty katalog był nad menu
gui.Parent         = playerGui

-- ── Przycisk SKLEP w HUD ────────────────────────────────────────────────────
-- Pozycja: środek dół, po lewo od MENU. MENU jest centered (203x135) na (0.5, 0, 1, -20).
-- Offset = -(MENU_W/2 + GAP + SHOP_W/2). MENU_W=203, SHOP_W=135, GAP=14 → -184.
local MENU_W   = 203
-- Ikona sklepu ma natywne wymiary 1536×1024 (3:2). Dopasowane do MENU (też 3:2 → 203×135),
-- żeby grafika nie była ścinana ScaleType.Fit + żeby wizualnie pasowały obok siebie w HUD.
local SHOP_W   = 203
local SHOP_H   = 135
local HUD_GAP  = 14
local HUD_OFFSET_BOTTOM = 20
local SHOP_X_OFFSET = -(MENU_W / 2 + HUD_GAP + SHOP_W / 2)

local shopBtn = Instance.new("ImageButton")
shopBtn.Name                   = "ShopButton"
shopBtn.AnchorPoint            = Vector2.new(0.5, 1)
shopBtn.Position               = UDim2.new(0.5, SHOP_X_OFFSET, 1, -HUD_OFFSET_BOTTOM)
shopBtn.Size                   = UDim2.fromOffset(SHOP_W, SHOP_H)
shopBtn.BackgroundTransparency = 1
shopBtn.BorderSizePixel        = 0
shopBtn.Image                  = SHOP_ICON_ID
shopBtn.ScaleType              = Enum.ScaleType.Fit
shopBtn.AutoButtonColor        = false
shopBtn.Parent                 = gui
do
	local sc = Instance.new("UIScale"); sc.Parent = shopBtn
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
	shopBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.12 }):Play()
		TweenService:Create(shopBtn, ti, { Rotation = -6 }):Play()
	end)
	shopBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
		TweenService:Create(shopBtn, ti, { Rotation = 0 }):Play()
	end)
end

-- ── Overlay przyciemnienia ──────────────────────────────────────────────────
local overlay = Instance.new("TextButton")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.Visible                = false
overlay.Parent                 = gui

-- ── Główny panel katalogu ───────────────────────────────────────────────────
-- Panel dopasowany do węższych kart 1050×200 (obrazek skalowany 720×180 + text 300×180).
-- Niższe karty → więcej widoczne naraz w pionowej liście.
local PANEL_W = 1140
local PANEL_H = 720
local HEADER_H = 88

local panel = Instance.new("Frame")
panel.AnchorPoint            = Vector2.new(0.5, 0.5)
panel.Position               = UDim2.fromScale(0.5, 0.5)
panel.Size                   = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3       = C_BG
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel        = 0
panel.Visible                = false
panel.ClipsDescendants       = true
panel.Parent                 = gui
mkCorner(panel, 12)
mkStroke(panel, C_BORDER, 5)

-- Header
local header = Instance.new("Frame")
header.Size                   = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3       = C_HEADER
header.BorderSizePixel        = 0
header.Parent                 = panel
mkCorner(header, 12)
-- Maska na dolną krawędź headera (UICorner dla całego prostokąta, ale dół ma być prostokątny)
local headerMask = Instance.new("Frame")
headerMask.Size                   = UDim2.new(1, 0, 0, 14)
headerMask.Position               = UDim2.new(0, 0, 1, -14)
headerMask.BackgroundColor3       = C_HEADER
headerMask.BorderSizePixel        = 0
headerMask.Parent                 = header
local headerSep = Instance.new("Frame")
headerSep.Size                    = UDim2.new(1, 0, 0, 2)
headerSep.Position                = UDim2.new(0, 0, 1, -2)
headerSep.BackgroundColor3        = C_BORDER
headerSep.BorderSizePixel         = 0
headerSep.Parent                  = header

local headerTitle = Instance.new("TextLabel")
headerTitle.AnchorPoint            = Vector2.new(0.5, 0.5)
headerTitle.Position               = UDim2.new(0.5, 0, 0.5, 0)
headerTitle.Size                   = UDim2.fromOffset(500, HEADER_H - 20)
headerTitle.BackgroundTransparency = 1
headerTitle.Text                   = "SKLEP"
headerTitle.Font                   = FONT_TITLE
headerTitle.TextSize               = 44
headerTitle.TextColor3             = C_WHITE
headerTitle.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
headerTitle.TextStrokeTransparency = 0.5
headerTitle.Parent                 = header

-- X-close
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint        = Vector2.new(1, 0.5)
closeBtn.Position           = UDim2.new(1, -16, 0.5, 0)
closeBtn.Size               = UDim2.fromOffset(50, 50)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel    = 0
closeBtn.Text               = "X"
closeBtn.Font               = FONT
closeBtn.TextSize           = 32
closeBtn.TextColor3         = Color3.fromRGB(220, 70, 70)
closeBtn.AutoButtonColor    = false
closeBtn.Parent             = header
do
	local sc = Instance.new("UIScale"); sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	closeBtn.MouseEnter:Connect(function()
		closeBtn.TextColor3 = Color3.fromRGB(255, 110, 110)
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.TextColor3 = Color3.fromRGB(220, 70, 70)
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
	end)
end

-- Scroll obszar — większy gap pod headerem żeby pierwszy rząd kart nie wycierał się o headerSep
local SCROLL_TOP_GAP = 32
local scroll = Instance.new("ScrollingFrame")
scroll.Position                   = UDim2.fromOffset(24, HEADER_H + SCROLL_TOP_GAP)
scroll.Size                       = UDim2.new(1, -48, 1, -(HEADER_H + SCROLL_TOP_GAP + 24))
scroll.BackgroundTransparency     = 1
scroll.BorderSizePixel            = 0
scroll.ScrollBarThickness         = 8
scroll.ScrollBarImageColor3       = Color3.fromRGB(8, 50, 35)
scroll.CanvasSize                 = UDim2.fromOffset(0, 0)
scroll.AutomaticCanvasSize        = Enum.AutomaticSize.Y
scroll.ClipsDescendants           = true
scroll.Parent                     = panel

-- Padding wewnątrz scroll'a — żeby UIStroke kart nie ucierał się o krawędź viewportu
local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop    = UDim.new(0, 12)
scrollPad.PaddingBottom = UDim.new(0, 12)
scrollPad.PaddingLeft   = UDim.new(0, 4)
scrollPad.PaddingRight  = UDim.new(0, 4)
scrollPad.Parent        = scroll

-- Pionowa lista kart — każda 1340×270 (obrazek 1000×250 + text-panel po prawej).
local list = Instance.new("UIListLayout")
list.FillDirection         = Enum.FillDirection.Vertical
list.Padding               = UDim.new(0, 18)
list.HorizontalAlignment   = Enum.HorizontalAlignment.Center
list.SortOrder             = Enum.SortOrder.LayoutOrder
list.Parent                = scroll

-- ── Karta produktu ──────────────────────────────────────────────────────────
type CardHandles = {
	frame:      Frame,
	buyBtn:     TextButton,
	statusLbl:  TextLabel,
	titleLbl:   TextLabel,
	priceLbl:   TextLabel,
	stroke:     UIStroke,
	accentColor: Color3,
}

-- Karta sklepu: poziomy banner — obrazek 720×180 (4:1 aspect, skalowany z natywnego 1000×250)
-- + text-panel 300×180 po prawej. Karta niższa niż wcześniej (200 vs 270) → 3 karty mieszczą
-- się bez scroll'a (660px łącznie z gapami), zostaje zapas na 4. kartę gdy dodasz.
local CARD_W   = 1050
local CARD_H   = 200
local IMAGE_W  = 720
local IMAGE_H  = 180
local CARD_PAD = 10
local IMG_GAP  = 20
local TEXT_W   = CARD_W - IMAGE_W - IMG_GAP - CARD_PAD * 2  -- = 280

local function makeCard(opts: { title: string, desc: string, price: string, accent: Color3, order: number, imageId: string? }): CardHandles
	local f = Instance.new("Frame")
	f.Size                   = UDim2.fromOffset(CARD_W, CARD_H)
	f.BackgroundColor3       = C_PANEL
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel        = 0
	f.LayoutOrder            = opts.order
	f.Parent                 = scroll
	mkCorner(f, 12)
	local stroke = mkStroke(f, opts.accent, 4)

	-- Obrazek 1000×250 po lewej — ImageLabel z accent-kolorem jako fallback gdy Image="".
	-- User wstawi rbxassetid:// po nazwie karty w wywołaniu makeCard.
	local imageLbl = Instance.new("ImageLabel")
	imageLbl.Size                   = UDim2.fromOffset(IMAGE_W, IMAGE_H)
	imageLbl.Position               = UDim2.fromOffset(CARD_PAD, CARD_PAD)
	imageLbl.BackgroundColor3       = opts.accent
	imageLbl.BackgroundTransparency = 0.2  -- gdy brak Image, widać kolor accent jako tło
	imageLbl.BorderSizePixel        = 0
	imageLbl.Image                  = opts.imageId or ""
	imageLbl.ScaleType              = Enum.ScaleType.Fit
	imageLbl.Parent                 = f
	mkCorner(imageLbl, 10)
	mkStroke(imageLbl, C_BORDER, 2)

	-- Text-panel po prawej (320×250)
	local txt = Instance.new("Frame")
	txt.Size                   = UDim2.fromOffset(TEXT_W, IMAGE_H)
	txt.Position               = UDim2.fromOffset(CARD_PAD + IMAGE_W + IMG_GAP, CARD_PAD)
	txt.BackgroundTransparency = 1
	txt.BorderSizePixel        = 0
	txt.Parent                 = f

	-- Tytuł (góra)
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Position               = UDim2.fromOffset(0, 2)
	titleLbl.Size                   = UDim2.new(1, 0, 0, 32)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text                   = opts.title
	titleLbl.Font                   = FONT_TITLE
	titleLbl.TextSize               = 24
	titleLbl.TextColor3             = C_WHITE
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
	titleLbl.Parent                 = txt

	-- Opis
	local descLbl = Instance.new("TextLabel")
	descLbl.Position               = UDim2.fromOffset(0, 36)
	descLbl.Size                   = UDim2.new(1, 0, 0, 48)
	descLbl.BackgroundTransparency = 1
	descLbl.Text                   = opts.desc
	descLbl.Font                   = FONT
	descLbl.TextSize               = 14
	descLbl.TextColor3             = C_DIMTEXT
	descLbl.TextWrapped            = true
	descLbl.TextXAlignment         = Enum.TextXAlignment.Left
	descLbl.TextYAlignment         = Enum.TextYAlignment.Top
	descLbl.Parent                 = txt

	-- Status (POSIADASZ / AKTYWNE)
	local statusLbl = Instance.new("TextLabel")
	statusLbl.AnchorPoint            = Vector2.new(0, 1)
	statusLbl.Position               = UDim2.new(0, 0, 1, -56)
	statusLbl.Size                   = UDim2.new(1, 0, 0, 20)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text                   = ""
	statusLbl.Font                   = FONT
	statusLbl.TextSize               = 14
	statusLbl.TextColor3             = C_ACTIVE
	statusLbl.TextXAlignment         = Enum.TextXAlignment.Left
	statusLbl.Parent                 = txt

	-- Przycisk KUP (dół text-panelu)
	local buyBtn = Instance.new("TextButton")
	buyBtn.AnchorPoint            = Vector2.new(0, 1)
	buyBtn.Position               = UDim2.new(0, 0, 1, -2)
	buyBtn.Size                   = UDim2.new(1, 0, 0, 48)
	buyBtn.BackgroundColor3       = C_ROBUX
	buyBtn.BorderSizePixel        = 0
	buyBtn.Text                   = opts.price
	buyBtn.Font                   = FONT
	buyBtn.TextSize               = 20
	buyBtn.TextColor3             = Color3.fromRGB(0, 0, 0)
	buyBtn.AutoButtonColor        = false
	buyBtn.Parent                 = txt
	mkCorner(buyBtn, 8)

	-- Hover scale
	do
		local sc = Instance.new("UIScale"); sc.Parent = buyBtn
		local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
		buyBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
		buyBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
	end

	return {
		frame       = f,
		buyBtn      = buyBtn,
		statusLbl   = statusLbl,
		titleLbl    = titleLbl,
		priceLbl    = buyBtn,
		stroke      = stroke,
		accentColor = opts.accent,
	}
end

-- ── 3 karty ─────────────────────────────────────────────────────────────────
local vipDeck = nil
for _, d in ipairs(Config.Decks) do
	if d.key == "VIP" then vipDeck = d; break end
end
local boostCfg = Config.BoostShop.DoubleEarn

-- ImageId 1000×250 banner'ów — wpisz "rbxassetid://..." gdy mas (zostaw "" → kolorowy placeholder accent).
local IMG_VIP   = "rbxassetid://123843002430702"
local IMG_BOOST = "rbxassetid://116247651082673"
local IMG_EGG   = "rbxassetid://77784925604472"

local cardVip = makeCard({
	title   = "VIP DESKA",
	desc    = "Najszybsza deska w grze (Speed 100). Permanentne odblokowanie przez Gamepass.",
	price   = vipDeck and (string.format("%d R$", vipDeck.RobuxPrice or 30)) or "30 R$",
	accent  = C_VIP,
	order   = 1,
	imageId = IMG_VIP,
})
local cardBoost = makeCard({
	title   = "x2 KASA",
	desc    = "Podwaja zarobki z butelkomatu na 10 minut. Stackuje się z mnożnikiem.",
	price   = string.format("%d R$", boostCfg.PriceRobux or 19),
	accent  = C_BOOST,
	order   = 2,
	imageId = IMG_BOOST,
})
local eggPriceText = string.format("%d R$",
	(Config.Pets and Config.Pets.TripleEggPriceRobux) or 39)
local cardEgg = makeCard({
	title   = "TRIPLE EGG",
	desc    = "Odblokowuje opcję otwierania 3 jajek naraz w gablocie petów.",
	price   = eggPriceText,
	accent  = C_EGG,
	order   = 3,
	imageId = IMG_EGG,
})

-- ── Paczki złotówek (Developer Products — konsumowalne, zawsze kupowalne) ─────
local C_MONEY = Color3.fromRGB(110, 205, 120)
local moneyPacks = Config.BoostShop.MoneyPacks or {}
local moneyCards: { { card: CardHandles, pack: any } } = {}
for i, pack in ipairs(moneyPacks) do
	local card = makeCard({
		title   = pack.Name,
		desc    = string.format("Dolicza %s PLN do Twojego salda. Natychmiast po zakupie.",
			tostring(pack.Amount)),
		price   = string.format("%d R$", pack.PriceRobux or 0),
		accent  = C_MONEY,
		order   = 3 + i,
		imageId = pack.image,
	})
	card.buyBtn.MouseButton1Click:Connect(function()
		playSfx("Click")
		PromptBoostPurchase:FireServer(pack.key)
	end)
	table.insert(moneyCards, { card = card, pack = pack })
end

-- ── Stany kart ──────────────────────────────────────────────────────────────
local ownedVipDeck   = false
local boostRemaining = 0
local hasTripleEgg   = false

local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function setCardOwned(card: CardHandles, ownedText: string)
	card.statusLbl.Text       = ownedText
	card.statusLbl.TextColor3 = C_ACTIVE
	card.buyBtn.Text          = "POSIADASZ"
	card.buyBtn.BackgroundColor3 = C_OWNED
	card.buyBtn.TextColor3    = C_WHITE
	card.buyBtn.Active        = false
	card.buyBtn.AutoButtonColor = false
end

local function setCardBuyable(card: CardHandles, priceText: string)
	card.statusLbl.Text       = ""
	card.buyBtn.Text          = priceText
	card.buyBtn.BackgroundColor3 = C_ROBUX
	card.buyBtn.TextColor3    = Color3.fromRGB(0, 0, 0)
	card.buyBtn.Active        = true
	card.stroke.Color         = card.accentColor  -- przywróć oryginalny akcent (gdy wrócił z AKTYWNE)
end

local function setCardActive(card: CardHandles, timeLeft: number, refillPriceText: string)
	-- Wyraźny visual: zielony stroke (zamiast pomarańczowego accent'u) + zielony status nad buttonem.
	-- Button szary "DOLICZ +X R$" — można doliczyć cumulative ale nie jest krzykliwy żółty.
	card.statusLbl.Text       = "AKTYWNE — " .. formatTime(timeLeft)
	card.statusLbl.TextColor3 = C_ACTIVE
	card.stroke.Color         = C_ACTIVE
	card.buyBtn.Text          = "DOLICZ +10 MIN — " .. refillPriceText
	card.buyBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
	card.buyBtn.TextColor3    = C_WHITE
	card.buyBtn.Active        = true
end

local function refreshVip()
	if ownedVipDeck then
		setCardOwned(cardVip, "DESKA ODBLOKOWANA")
	else
		setCardBuyable(cardVip, vipDeck and string.format("%d R$", vipDeck.RobuxPrice or 30) or "30 R$")
	end
end
local function refreshBoost()
	if boostRemaining > 0 then
		setCardActive(cardBoost, boostRemaining, string.format("%d R$", boostCfg.PriceRobux or 19))
	else
		setCardBuyable(cardBoost, string.format("%d R$", boostCfg.PriceRobux or 19))
	end
end
local function refreshEgg()
	if hasTripleEgg then
		setCardOwned(cardEgg, "ODBLOKOWANE")
	else
		setCardBuyable(cardEgg, eggPriceText)
	end
end

refreshVip(); refreshBoost(); refreshEgg()

-- ── Akcje kup ───────────────────────────────────────────────────────────────
cardVip.buyBtn.MouseButton1Click:Connect(function()
	if ownedVipDeck then playSfx("Click"); return end
	playSfx("Click")
	if vipDeck and vipDeck.GamepassId then
		MarketplaceService:PromptGamePassPurchase(localPlayer, vipDeck.GamepassId)
	else
		warn("[ShopCatalog] VIP deck: brak GamepassId w Config")
	end
end)

cardBoost.buyBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	PromptBoostPurchase:FireServer("DoubleEarn")
end)

cardEgg.buyBtn.MouseButton1Click:Connect(function()
	if hasTripleEgg then playSfx("Click"); return end
	playSfx("Click")
	if Config.Pets and Config.Pets.TripleEggGamepassId then
		MarketplaceService:PromptGamePassPurchase(localPlayer, Config.Pets.TripleEggGamepassId)
	else
		warn("[ShopCatalog] Triple egg: brak TripleEggGamepassId w Config")
	end
end)

-- ── Listenery stanu ─────────────────────────────────────────────────────────
local refreshHud  -- forward-declare (definicja niżej, ale BoostStatusUpdate może odpalić zaraz po :Connect)
DeckStatus.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local owned = payload.owned or {}
	ownedVipDeck = owned.VIP == true
	refreshVip()
end)
BoostStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	boostRemaining = tonumber(data.doubleEarnRemainingSec) or 0
	-- Diagnostyka: jeśli x2 KASA nie aktywuje się po zakupie, sprawdź Output czy ta linia się drukuje.
	-- Brak printu = server nie wysyła update'u (ProcessReceipt nie odpalany — np. test w Studio Solo).
	print(string.format("[ShopCatalog] BoostStatusUpdate: remaining=%d", boostRemaining))
	refreshBoost()
	refreshHud()
end)
PetStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	hasTripleEgg = data.hasGamepass == true
	refreshEgg()
end)

-- Listener na PromptGamePassPurchaseFinished — odśwież status po udanym zakupie
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, gpId, purchased)
	if p ~= localPlayer or not purchased then return end
	if vipDeck and gpId == vipDeck.GamepassId then
		ownedVipDeck = true; refreshVip()
	elseif Config.Pets and gpId == Config.Pets.TripleEggGamepassId then
		hasTripleEgg = true; refreshEgg()
	end
end)

-- ── Floating HUD timer dla aktywnego boost (zachowany z BoostShopController) ──
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "ShopBoostStatusHUD"
hudGui.IgnoreGuiInset = true
hudGui.ResetOnSpawn   = false
hudGui.DisplayOrder   = 60
hudGui.Parent         = playerGui

local hudFrame = Instance.new("Frame")
hudFrame.AnchorPoint            = Vector2.new(1, 0)
hudFrame.Position               = UDim2.new(1, -16, 0, 110)
hudFrame.Size                   = UDim2.fromOffset(170, 44)
hudFrame.BackgroundColor3       = C_HEADER
hudFrame.BackgroundTransparency = 0.05
hudFrame.BorderSizePixel        = 0
hudFrame.Visible                = false
hudFrame.Parent                 = hudGui
mkCorner(hudFrame, 8); mkStroke(hudFrame, C_ACTIVE, 2)

local hudLabel = Instance.new("TextLabel")
hudLabel.Size                   = UDim2.new(1, -8, 1, 0)
hudLabel.Position               = UDim2.fromOffset(4, 0)
hudLabel.BackgroundTransparency = 1
hudLabel.Text                   = ""
hudLabel.Font                   = FONT
hudLabel.TextSize               = 16
hudLabel.TextColor3             = C_ACTIVE
hudLabel.TextXAlignment         = Enum.TextXAlignment.Center
hudLabel.Parent                 = hudFrame

function refreshHud()
	if boostRemaining > 0 then
		hudLabel.Text    = "x2 KASA " .. formatTime(boostRemaining)
		hudFrame.Visible = true
	else
		hudFrame.Visible = false
	end
end

-- Co sekundę: refresh kart + HUD (serwer pushuje co sekundę, ale jeśli timing zawodzi,
-- lokalny tick decyduje).
task.spawn(function()
	while true do
		task.wait(1)
		if boostRemaining > 0 then boostRemaining = math.max(0, boostRemaining - 1) end
		refreshBoost()
		refreshHud()
	end
end)
refreshHud()

-- ── Open / Close ────────────────────────────────────────────────────────────
local isOpen = false
local TI_OPEN  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function setOpen(open: boolean)
	if isOpen == open then return end
	isOpen = open
	if open then
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		panel.Visible   = true
		overlay.Visible = true
		panel.Size      = UDim2.fromOffset(PANEL_W * 0.88, PANEL_H * 0.88)
		overlay.BackgroundTransparency = 1
		TweenService:Create(panel, TI_OPEN, { Size = UDim2.fromOffset(PANEL_W, PANEL_H) }):Play()
		TweenService:Create(overlay, TI_OPEN, { BackgroundTransparency = 0.35 }):Play()
	else
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		TweenService:Create(panel, TI_CLOSE, {
			Size = UDim2.fromOffset(PANEL_W * 0.88, PANEL_H * 0.88),
		}):Play()
		local tw = TweenService:Create(overlay, TI_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not isOpen then panel.Visible = false; overlay.Visible = false end
		end)
		tw:Play()
	end
end

shopBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(not isOpen) end)
closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)
overlay.MouseButton1Click:Connect(function() end)  -- klik w tło nie zamyka (jak menu)

-- Ikona SKLEP znika gdy gracz otworzy MENU / Bank / inne UI (każdy lock bumpuje __moveLockCount).
-- Pokazujemy też ją z powrotem po zamknięciu UI. Wykluczamy własny lock (gdy mój katalog otwarty,
-- ikona i tak jest pod overlay'em — nie ukrywamy żeby zamknięcie X działało).
local shopBtnLastVisible = true
local RunService = game:GetService("RunService")
RunService.RenderStepped:Connect(function()
	local count = tonumber(_G["__moveLockCount"]) or 0
	-- Gdy mój katalog otwarty, count zawiera +1 z mojego lock'a — odejmuję
	local externalLock = count - (isOpen and 1 or 0)
	local shouldShow = externalLock <= 0
	if shouldShow ~= shopBtnLastVisible then
		shopBtn.Visible = shouldShow
		shopBtnLastVisible = shouldShow
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)

print(string.format("[ShopCatalogController] gotowy — %d kart (VIP / x2 KASA / Triple Egg + %d paczki PLN)",
	3 + #moneyCards, #moneyCards))
