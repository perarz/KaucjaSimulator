-- PetGablotaController.client.luau
-- UI gabloty petów: pop-up wyboru (1 jajko / 3 jajka) + roulette spin.
-- Otwierane przez OpenPetGablota (ProximityPrompt w PetService).
-- Roulette wzorowane na KoszController + ulepszone polish (gradient per rzadkość, VFX).
--
-- 3-jajka pokazuje 3 spinnery obok siebie (jeden dźwięk dla wszystkich) — Krok 3.
-- Krok 2 (now): wsparcie 1-jajko + UI 3-jajek (3 osobne spiny ale uproszczone).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")
local RunService        = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local cfg    = Config.Pets

local Events                = ReplicatedStorage:WaitForChild("Events")
local OpenPetGablota        = Events:WaitForChild("OpenPetGablota")
local BuyEggOpen            = Events:WaitForChild("BuyEggOpen")
local PetRouletteResult     = Events:WaitForChild("PetRouletteResult")
local PromptPetGamepassBuy  = Events:WaitForChild("PromptPetGamepassBuy")
local PetStatusUpdate       = Events:WaitForChild("PetStatusUpdate")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── SFX ────────────────────────────────────────────────────────────────────
local function playSfx(name: string, opts: { trimEnd: number? }?)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl   = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	if opts and opts.trimEnd then
		task.delay(math.max(0, (s.TimeLength or 1) - opts.trimEnd), function()
			if s.Parent then s:Stop(); s:Destroy() end
		end)
	else
		s.Ended:Connect(function() s:Destroy() end)
	end
end

-- ── Paleta ─────────────────────────────────────────────────────────────────
local FONT        = Enum.Font.GothamBlack
local TOAST_FONT  = Enum.Font.FredokaOne   -- czytelny, bez neonu (popupy błędów / gamepass)
local TOAST_RED   = Color3.fromRGB(225, 70, 70)
local TOAST_YELLOW = Color3.fromRGB(240, 195, 70)
local C_BG        = Color3.fromRGB(18, 91, 73)
local C_PANEL     = Color3.fromRGB(24, 110, 90)
local C_HEADER    = Color3.fromRGB(0, 53, 39)
local C_BORDER    = Color3.fromRGB(5, 25, 20)
local C_WHITE     = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT   = Color3.fromRGB(175, 175, 175)
local C_ACC_GREEN = Color3.fromRGB(170, 221, 102)
local C_DANGER    = Color3.fromRGB(220, 70, 70)
local X_RED       = Color3.fromRGB(220, 70, 70)
local X_RED_HOV   = Color3.fromRGB(255, 110, 110)

-- ── Stan ───────────────────────────────────────────────────────────────────
local lastInit: { [string]: any } = {}  -- ostatni payload OpenPetGablota
local hasGamepass = false

-- Anty-spam otwierania: gdy trwa animacja ruletki blokujemy ponowne otwarcie.
-- `spinning` ignoruje nowe wyniki, a prompty E/T są wyłączane lokalnie więc
-- naciskanie ich nic nie robi. `roulLocked` trzyma blokadę ruchu idempotentnie
-- (1 lock ↔ 1 unlock) — inaczej spam dawał wiele locków i gracz nie mógł chodzić.
local spinning   = false
local roulLocked = false
local gablotaPrompts: { [ProximityPrompt]: boolean } = {}

local function setPromptsEnabled(enabled: boolean)
	for p in pairs(gablotaPrompts) do
		if p and p.Parent then p.Enabled = enabled end
	end
end

local function lockMove()
	if roulLocked then return end
	roulLocked = true
	if _G["__lockMovement"] then _G["__lockMovement"]() end
end

local function unlockMove()
	if not roulLocked then return end
	roulLocked = false
	if _G["__unlockMovement"] then _G["__unlockMovement"]() end
end

-- Sortowanie rzadkości po order
local function listRaritiesOrdered(): { string }
	local arr = {}
	for k in pairs(cfg.Rarities) do table.insert(arr, k) end
	table.sort(arr, function(a, b) return cfg.Rarities[a].order < cfg.Rarities[b].order end)
	return arr
end

-- ── ScreenGui scaffold ─────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "PetGablota"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 60
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

-- Toast notification (zamiast chStatus po usunięciu choice GUI)
local toastGui = Instance.new("ScreenGui")
toastGui.Name           = "PetToast"
toastGui.ResetOnSpawn   = false
toastGui.IgnoreGuiInset = true
toastGui.DisplayOrder   = 80
toastGui.Parent         = playerGui

local toastLbl = Instance.new("TextLabel")
toastLbl.AnchorPoint            = Vector2.new(0.5, 0)
toastLbl.Position               = UDim2.new(0.5, 0, 0, 240)
toastLbl.AutomaticSize          = Enum.AutomaticSize.X   -- szerokość dopasowana do tekstu
toastLbl.Size                   = UDim2.fromOffset(0, 56)
toastLbl.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
toastLbl.BackgroundTransparency = 0.35
toastLbl.BorderSizePixel        = 0
toastLbl.Text                   = ""
toastLbl.Font                   = TOAST_FONT
toastLbl.TextSize               = 24
toastLbl.TextColor3             = TOAST_RED
toastLbl.TextStrokeTransparency = 1     -- bez neonowego obrysu tekstu
toastLbl.Visible                = false
toastLbl.Parent                 = toastGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = toastLbl
	-- subtelny ciemny border zamiast jaskrawego (kolorowego) glow
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = toastLbl
	-- margines wewnętrzny — tekst nie dotyka krawędzi gdy box dopasowuje szerokość
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 28); pad.PaddingRight = UDim.new(0, 28)
	pad.Parent = toastLbl
end

local toastJob: thread? = nil
local function showToast(msg: string, color: Color3?)
	if toastJob then task.cancel(toastJob); toastJob = nil end
	toastLbl.Text         = msg
	toastLbl.TextColor3   = color or TOAST_RED   -- tylko czerwony lub żółty, bez neonu
	toastLbl.TextTransparency = 0
	toastLbl.BackgroundTransparency = 0.35
	local stroke = toastLbl:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0   -- ciemny border stały, NIE przebarwiamy na kolor tekstu
	end
	toastLbl.Visible      = true
	toastJob = task.spawn(function()
		task.wait(2.0)
		local fadeTi = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toastLbl, fadeTi, {
			TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1,
		}):Play()
		if stroke then TweenService:Create(stroke, fadeTi, { Transparency = 1 }):Play() end
		task.wait(0.4)
		toastLbl.Visible = false
		toastJob = nil
	end)
end

-- ── Choice panel (wybór 1 / 3 jajka) ───────────────────────────────────────
local CHOICE_W, CHOICE_H = 560, 360

local choicePanel = Instance.new("Frame")
choicePanel.Size                  = UDim2.fromOffset(CHOICE_W, CHOICE_H)
choicePanel.AnchorPoint           = Vector2.new(0.5, 0.5)
choicePanel.Position              = UDim2.new(0.5, 0, 0.55, 0)
choicePanel.BackgroundColor3      = C_PANEL
choicePanel.BackgroundTransparency = 0.05
choicePanel.BorderSizePixel       = 0
choicePanel.Visible               = false
choicePanel.ZIndex                = 2
choicePanel.Parent                = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = choicePanel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = choicePanel
end

-- Header
local chHeader = Instance.new("Frame")
chHeader.Size             = UDim2.new(1, 0, 0, 52)
chHeader.BackgroundColor3 = C_HEADER
chHeader.BorderSizePixel  = 0
chHeader.ZIndex           = 3
chHeader.Parent           = choicePanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = chHeader
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 10); fill.Position = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = chHeader
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.ZIndex = 5; sep.Parent = chHeader
end

local chTitle = Instance.new("TextLabel")
chTitle.Size                   = UDim2.new(1, -56, 1, 0)
chTitle.Position               = UDim2.fromOffset(22, 0)
chTitle.BackgroundTransparency = 1
chTitle.Text                   = "GABLOTA PETÓW"
chTitle.TextSize               = 22
chTitle.Font                   = FONT
chTitle.TextColor3             = C_WHITE
chTitle.TextXAlignment         = Enum.TextXAlignment.Left
chTitle.ZIndex                 = 4
chTitle.Parent                 = chHeader

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
closeBtn.ZIndex                 = 6
closeBtn.Parent                 = chHeader

-- Pomocnik na button — pełna karta opcji
local function makeOptionButton(parent: Instance, x: number, y: number, w: number, h: number,
		headerText: string, descText: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size                   = UDim2.fromOffset(w, h)
	b.Position               = UDim2.fromOffset(x, y)
	b.BackgroundColor3       = C_BG
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel        = 0
	b.AutoButtonColor        = false
	b.Text                   = ""
	b.ZIndex                 = 4
	b.Parent                 = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = 3; s.Parent = b

	local hdr = Instance.new("TextLabel")
	hdr.Size                   = UDim2.new(1, -20, 0, 36)
	hdr.Position               = UDim2.fromOffset(10, 14)
	hdr.BackgroundTransparency = 1
	hdr.Text                   = headerText
	hdr.TextSize               = 22
	hdr.Font                   = FONT
	hdr.TextColor3             = color
	hdr.TextXAlignment         = Enum.TextXAlignment.Center
	hdr.ZIndex                 = 5
	hdr.Parent                 = b

	local desc = Instance.new("TextLabel")
	desc.Size                   = UDim2.new(1, -20, 1, -60)
	desc.Position               = UDim2.fromOffset(10, 52)
	desc.BackgroundTransparency = 1
	desc.Text                   = descText
	desc.TextSize               = 14
	desc.Font                   = FONT
	desc.TextColor3             = C_DIMTEXT
	desc.TextWrapped            = true
	desc.TextXAlignment         = Enum.TextXAlignment.Center
	desc.TextYAlignment         = Enum.TextYAlignment.Top
	desc.ZIndex                 = 5
	desc.Parent                 = b

	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = b
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	b.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)

	return b
end

local OPT_W = 240
local OPT_H = 220
local OPT_GAP = 20
local OPT_Y = 96
local OPT_X1 = (CHOICE_W - OPT_W * 2 - OPT_GAP) / 2
local OPT_X2 = OPT_X1 + OPT_W + OPT_GAP

local opt1 = makeOptionButton(choicePanel, OPT_X1, OPT_Y, OPT_W, OPT_H,
	"OTWÓRZ 1 JAJKO",
	"Cena: 500 zł",
	C_ACC_GREEN)

local opt3 = makeOptionButton(choicePanel, OPT_X2, OPT_Y, OPT_W, OPT_H,
	"OTWÓRZ 3 JAJKA",
	"Cena: 1500 zł\n\n(wymaga Gamepass — 29 R$)",
	Color3.fromRGB(230, 190, 60))

-- Status u dołu
local chStatus = Instance.new("TextLabel")
chStatus.Size                   = UDim2.new(1, -32, 0, 24)
chStatus.AnchorPoint            = Vector2.new(0, 1)
chStatus.Position               = UDim2.new(0, 16, 1, -14)
chStatus.BackgroundTransparency = 1
chStatus.Text                   = ""
chStatus.TextSize               = 14
chStatus.Font                   = FONT
chStatus.TextColor3             = C_DIMTEXT
chStatus.TextXAlignment         = Enum.TextXAlignment.Center
chStatus.ZIndex                 = 4
chStatus.Parent                 = choicePanel

-- ── Roulette panel (VERTICAL pinball-style, jak KoszController) ─────────────
-- Każde okno: vertical strip z gradientem fade top/bottom, indicator (ramka)
-- na środku, jeden RouletteTick na item-overlap, jeden Win na koniec.
-- 1 jajko = 1 okno (szeroko). 3 jajka = 3 okna obok siebie.
local ROUL_W, ROUL_H  = 760, 480
local WINDOW_H        = 360
local ITEM_H          = 84    -- wysokość pojedynczego tile (vertical)
local SPIN_SECONDS    = 6.0   -- dłuższy roll dla dramaturgii
local STRIP_LEN       = 36
local WINNER_OFFSET   = 5     -- itemów PO winnerze (żeby strip nie wyglądał na kończący się)
local WINNER_IDX      = STRIP_LEN - 1 - WINNER_OFFSET

local roulPanel = Instance.new("Frame")
roulPanel.Size                   = UDim2.fromOffset(ROUL_W, ROUL_H)
roulPanel.AnchorPoint            = Vector2.new(0.5, 0.5)
roulPanel.Position               = UDim2.new(0.5, 0, 0.55, 0)
roulPanel.BackgroundTransparency = 1   -- bez tła i obramówki — czysta scena, jak Kosz
roulPanel.BorderSizePixel        = 0
roulPanel.Visible                = false
roulPanel.ZIndex                 = 2
roulPanel.Parent                 = gui

local roulHdr = Instance.new("TextLabel")
roulHdr.Size                   = UDim2.new(1, 0, 0, 36)
roulHdr.Position               = UDim2.fromOffset(0, 6)
roulHdr.BackgroundTransparency = 1
roulHdr.Text                   = "OTWIERANIE…"
roulHdr.TextSize               = 22
roulHdr.Font                   = FONT
roulHdr.TextColor3             = C_WHITE
roulHdr.TextStrokeColor3       = Color3.new(0, 0, 0)
roulHdr.TextStrokeTransparency = 0.4
roulHdr.TextXAlignment         = Enum.TextXAlignment.Center
roulHdr.ZIndex                 = 3
roulHdr.Parent                 = roulPanel

-- Container na N okien (dynamiczne, factory poniżej)
local windowsContainer = Instance.new("Frame")
windowsContainer.Size                   = UDim2.new(1, 0, 0, WINDOW_H)
windowsContainer.Position               = UDim2.fromOffset(0, 50)
windowsContainer.BackgroundTransparency = 1
windowsContainer.BorderSizePixel        = 0
windowsContainer.ZIndex                 = 3
windowsContainer.Parent                 = roulPanel

-- Result container (N labelów rzędem)
local resultContainer = Instance.new("Frame")
resultContainer.Size                   = UDim2.new(1, 0, 0, 50)
resultContainer.AnchorPoint            = Vector2.new(0.5, 1)
resultContainer.Position               = UDim2.new(0.5, 0, 1, -10)
resultContainer.BackgroundTransparency = 1
resultContainer.BorderSizePixel        = 0
resultContainer.ZIndex                 = 5
resultContainer.Parent                 = roulPanel

-- Click-anywhere overlay (skip auto-fadeout) — niewidoczny TextButton na całym ekranie,
-- aktywny tylko po zakończeniu spinów. Klik → natychmiast hideAll.
local skipOverlay = Instance.new("TextButton")
skipOverlay.Size                   = UDim2.fromScale(1, 1)
skipOverlay.BackgroundTransparency = 1
skipOverlay.BorderSizePixel        = 0
skipOverlay.Text                   = ""
skipOverlay.AutoButtonColor        = false
skipOverlay.Visible                = false
skipOverlay.ZIndex                 = 50  -- pod X (nie ma) ale nad result
skipOverlay.Parent                 = roulPanel

-- ── Pet tile factory (VERTICAL — wypełnia szerokość okna, wysokość ITEM_H) ─
local function makePetTile(rarity: string, class: string, parent: Instance, yOffset: number, windowW: number): Frame
	local rcfg = cfg.Rarities[rarity]
	local color = (rcfg and rcfg.color) or C_WHITE

	local f = Instance.new("Frame")
	f.Size               = UDim2.new(1, -16, 0, ITEM_H - 8)
	f.Position           = UDim2.fromOffset(8, yOffset + 4)
	f.BackgroundColor3   = Color3.new(color.R * 0.4, color.G * 0.4, color.B * 0.4)
	f.BorderSizePixel    = 0
	f.ZIndex             = 4
	f.Parent             = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = 3; s.Parent = f

	-- Lewa: emoji (klasa)
	local emoji = Instance.new("TextLabel")
	emoji.Size                   = UDim2.fromOffset(60, ITEM_H - 16)
	emoji.Position               = UDim2.fromOffset(8, 4)
	emoji.BackgroundTransparency = 1
	emoji.Text                   = (class == "Tank") and "🛡️" or "💨"
	emoji.TextSize               = 40
	emoji.Font                   = FONT
	emoji.TextColor3             = C_WHITE
	emoji.ZIndex                 = 5
	emoji.Parent                 = f

	-- Środek: nazwa rzadkości + klasa
	local mainLbl = Instance.new("TextLabel")
	mainLbl.Size                   = UDim2.new(1, -80, 0, 28)
	mainLbl.Position               = UDim2.fromOffset(72, 12)
	mainLbl.BackgroundTransparency = 1
	mainLbl.Text                   = (rcfg and rcfg.displayName) or rarity
	mainLbl.TextSize               = 20
	mainLbl.Font                   = FONT
	mainLbl.TextColor3             = color
	mainLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	mainLbl.TextStrokeTransparency = 0.4
	mainLbl.TextXAlignment         = Enum.TextXAlignment.Left
	mainLbl.ZIndex                 = 5
	mainLbl.Parent                 = f

	local subLbl = Instance.new("TextLabel")
	subLbl.Size                   = UDim2.new(1, -80, 0, 20)
	subLbl.Position               = UDim2.fromOffset(72, ITEM_H - 36)
	subLbl.BackgroundTransparency = 1
	subLbl.Text                   = class
	subLbl.TextSize               = 14
	subLbl.Font                   = FONT
	subLbl.TextColor3             = C_WHITE
	subLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	subLbl.TextStrokeTransparency = 0.4
	subLbl.TextXAlignment         = Enum.TextXAlignment.Left
	subLbl.ZIndex                 = 5
	subLbl.Parent                 = f

	return f
end

-- Generuje strip pionowo z STRIP_LEN tile'ów. Winner na pozycji WINNER_IDX.
local function buildStripContents(stripFrame: Frame, targetRarity: string, targetClass: string, windowW: number)
	for _, c in ipairs(stripFrame:GetChildren()) do c:Destroy() end
	local rarities = listRaritiesOrdered()
	for i = 0, STRIP_LEN - 1 do
		local r, c
		if i == WINNER_IDX then
			r, c = targetRarity, targetClass
		else
			r = rarities[math.random(1, #rarities)]
			c = (math.random() < 0.5) and "Sprinter" or "Tank"
		end
		makePetTile(r, c, stripFrame, i * ITEM_H, windowW)
	end
	stripFrame.Size = UDim2.new(1, 0, 0, STRIP_LEN * ITEM_H)
end

local function setOpen(panel: Instance, visible: boolean)
	gui.Enabled = visible
	if visible then
		if _G["__lockMovement"] then _G["__lockMovement"]() end
	else
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
	end
end

local function showChoice()
	roulPanel.Visible   = false
	choicePanel.Visible = true
	gui.Enabled         = true
	chStatus.Text       = ""
	-- 3-jajka — wizualnie wyróżnione gdy gracz ma gamepass + zmiana opisu
	-- Znajdujemy desc label opt3 (zbudowany w makeOptionButton — drugi child TextLabel)
	local desc3
	for _, c in ipairs(opt3:GetChildren()) do
		if c:IsA("TextLabel") and c.TextSize == 14 then desc3 = c; break end
	end
	if hasGamepass then
		opt3.BackgroundTransparency = 0.05
		if desc3 then desc3.Text = "Cena: 1500 zł\n\n✓ Gamepass aktywny" end
	else
		opt3.BackgroundTransparency = 0.4
		if desc3 then desc3.Text = "Cena: 1500 zł\n\n🔒 Kliknij — kupisz Gamepass (29 R$)" end
	end
	if _G["__lockMovement"] then _G["__lockMovement"]() end
end

-- Hide z fade animacją (jak questy). Slide w dół + fade out.
local FADE_OUT_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local fadingOut = false
local function fadeOutAndHide(panel: Frame, onDone: () -> ())
	if not panel.Visible then onDone(); return end
	fadingOut = true
	TweenService:Create(roulHdr, FADE_OUT_TI, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	for _, c in ipairs(windowsContainer:GetDescendants()) do
		if c:IsA("Frame") then
			TweenService:Create(c, FADE_OUT_TI, { BackgroundTransparency = 1 }):Play()
		elseif c:IsA("TextLabel") then
			TweenService:Create(c, FADE_OUT_TI, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		elseif c:IsA("UIStroke") then
			TweenService:Create(c, FADE_OUT_TI, { Transparency = 1 }):Play()
		end
	end
	for _, c in ipairs(resultContainer:GetDescendants()) do
		if c:IsA("TextLabel") then
			TweenService:Create(c, FADE_OUT_TI, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end
	TweenService:Create(panel, FADE_OUT_TI, { Position = UDim2.new(0.5, 0, 0.58, 0) }):Play()
	task.delay(0.36, function()
		panel.Visible = false
		panel.Position = UDim2.new(0.5, 0, 0.55, 0)
		fadingOut = false
		onDone()
	end)
end

local function hideAll()
	if fadingOut then return end  -- nie spamuj
	skipOverlay.Visible = false
	if roulPanel.Visible then
		-- WAŻNE: spinning i prompty zostają zablokowane DOPÓKI fade-out się nie skończy.
		-- Wcześniej `spinning = false` + `setPromptsEnabled(true)` leciały od razu,
		-- gracz w 0.35s okienku fade'u mógł kliknąć E → nowa ruletka rusza, stare tween'y
		-- fade-out psują panel (znika), a SFX nowego spinu gra. Ten guard zamyka to okno.
		fadeOutAndHide(roulPanel, function()
			spinning = false
			setPromptsEnabled(true)
			if not choicePanel.Visible then gui.Enabled = false end
			unlockMove()
		end)
	else
		spinning = false
		setPromptsEnabled(true)
		if choicePanel.Visible then choicePanel.Visible = false end
		gui.Enabled = false
		unlockMove()
	end
end

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); hideAll() end)

UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and gui.Enabled then hideAll() end
end)

-- Skip click = natychmiastowe zamknięcie (po zakończeniu spinów)
skipOverlay.MouseButton1Click:Connect(function()
	playSfx("Click")
	hideAll()
end)

-- ── Vertical window factory ────────────────────────────────────────────────
-- Każde okno = clip + gradient fade top/bottom + strip vertical + indicator ramka.
-- Bez tła i obramówki na panelu — czyste, jak Kosz.

local function makeWindow(parent: Instance, x: number, w: number): (Frame, Frame)
	-- Outer (no bg, just clip for gradient fade)
	local window = Instance.new("Frame")
	window.Size                   = UDim2.fromOffset(w, WINDOW_H)
	window.Position               = UDim2.fromOffset(x, 0)
	window.BackgroundTransparency = 1
	window.BorderSizePixel        = 0
	window.ClipsDescendants       = true
	window.ZIndex                 = 3
	window.Parent                 = parent

	-- Gradient fade top/bottom (jak Kosz) — daje wrażenie głębi
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1.00),
		NumberSequenceKeypoint.new(0.22, 0.00),
		NumberSequenceKeypoint.new(0.78, 0.00),
		NumberSequenceKeypoint.new(1.00, 1.00),
	})
	grad.Parent = window

	-- Strip vertical (przesuwana w pionie)
	local strip = Instance.new("Frame")
	strip.Size                   = UDim2.new(1, 0, 0, 0)
	strip.Position               = UDim2.fromOffset(0, 0)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel        = 0
	strip.ZIndex                 = 4
	strip.Parent                 = window

	-- Indicator (biała ramka na środku okna — JEDYNA widoczna ramka).
	-- Szerokość = w (offset, bo każde okno może mieć inną), centered nad oknem.
	-- Parented do `parent` (windowsContainer) — nie do window, bo gradient by go zfadeował.
	local indicator = Instance.new("Frame")
	indicator.AnchorPoint            = Vector2.new(0.5, 0.5)
	indicator.Size                   = UDim2.fromOffset(w - 4, ITEM_H + 4)
	indicator.Position               = UDim2.fromOffset(x + w / 2, WINDOW_H / 2)
	indicator.BackgroundTransparency = 1
	indicator.BorderSizePixel        = 0
	indicator.ZIndex                 = 10
	indicator.Parent                 = parent
	do
		local s = Instance.new("UIStroke")
		s.Color = C_WHITE; s.Thickness = 4; s.Transparency = 0.05
		s.Parent = indicator
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = indicator
	end

	return window, strip
end

-- Spin pojedynczego okna — strip slide w pionie, Quint Out
local function spinWindow(window: Frame, strip: Frame, targetRarity: string, targetClass: string,
		onDone: () -> ())
	local windowW = window.AbsoluteSize.X
	if windowW < 10 then windowW = window.Size.X.Offset end  -- fallback gdy AbsoluteSize jeszcze niegotowy
	buildStripContents(strip, targetRarity, targetClass, windowW)

	-- Start: strip na pozycji 0 (pierwszy item na górze)
	strip.Position = UDim2.fromOffset(0, 0)
	-- Cel: winner wycentrowany w oknie
	local winnerY = WINNER_IDX * ITEM_H + 4
	local targetY = -(winnerY) + (WINDOW_H / 2) - ((ITEM_H - 8) / 2)

	local tw = TweenService:Create(strip,
		TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, targetY) })
	tw:Play()
	tw.Completed:Connect(onDone)
end

-- Polish: screen shake (RenderStepped CFrame nudge na CurrentCamera) dla HUGE
local function screenShake(durationSec: number, intensity: number)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local startT = tick()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = tick() - startT
		if t >= durationSec then
			if conn then conn:Disconnect() end
			return
		end
		local decay = 1 - (t / durationSec)
		local off = Vector3.new(
			(math.random() - 0.5) * intensity * decay,
			(math.random() - 0.5) * intensity * decay,
			0)
		cam.CFrame = cam.CFrame * CFrame.new(off)
	end)
end

-- Wynik label dla pojedynczego peta (pod jego trackiem)
local function makeResultLabel(parent: Instance, x: number, w: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromOffset(w, 70)
	lbl.Position               = UDim2.fromOffset(x, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = ""
	lbl.TextSize               = 22
	lbl.Font                   = FONT
	lbl.TextColor3             = C_WHITE
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.TextXAlignment         = Enum.TextXAlignment.Center
	lbl.TextWrapped            = true
	lbl.ZIndex                 = 6
	lbl.Parent                 = parent
	return lbl
end

-- ── Result handlers ────────────────────────────────────────────────────────
local function showRoulette(pets: { any })
	-- BUGFIX: trzeba włączyć ScreenGui — wcześniej robił to showChoice, ale po usunięciu
	-- choice GUI ruletka leciała bez gui.Enabled=true → niewidoczna (słychać tylko SFX).
	gui.Enabled         = true
	spinning            = true
	setPromptsEnabled(false)  -- wyłącz E/T — naciskanie podczas animacji nic nie robi
	lockMove()

	choicePanel.Visible = false
	roulPanel.Visible   = true
	roulPanel.Position  = UDim2.new(0.5, 0, 0.55, 0)
	-- Reset transparency (po poprzednim fade-out)
	roulHdr.TextTransparency       = 0
	roulHdr.TextStrokeTransparency = 0.4
	roulHdr.Text                   = (#pets == 1) and "OTWIERANIE…" or string.format("OTWIERANIE %d JAJEK…", #pets)
	skipOverlay.Visible            = false  -- click-to-skip aktywowane po zakończeniu

	-- Sprzątanie po poprzednim spinie
	for _, c in ipairs(windowsContainer:GetChildren()) do c:Destroy() end
	for _, c in ipairs(resultContainer:GetChildren()) do c:Destroy() end

	local n = #pets
	-- containerW = ROUL_W (windowsContainer ma Size = (1, 0, ...) → fullwidth)
	local containerW = ROUL_W
	local windowGap  = 14
	local windowW    = math.floor((containerW - windowGap * (n - 1)) / n)

	local windows = {}
	local strips  = {}
	for i = 1, n do
		local x = (i - 1) * (windowW + windowGap)
		local w, s = makeWindow(windowsContainer, x, windowW)
		windows[i] = w; strips[i] = s
		makeResultLabel(resultContainer, x, windowW)
	end

	-- Jeden ticker (RenderStepped tick co przejście itemu przez wskaźnik) na PIERWSZYM oknie.
	-- Win SFX po ostatnim ukończonym spinie. Bez tła i obramówki na panelu.
	local tickConn: RBXScriptConnection? = nil
	if strips[1] then
		local lastIdx = -1
		tickConn = RunService.RenderStepped:Connect(function()
			local strip = strips[1]
			if not strip or not strip.Parent then return end
			local stripY = strip.Position.Y.Offset
			local idx = math.floor((WINDOW_H / 2 - (ITEM_H - 8) / 2 - stripY) / ITEM_H + 0.5)
			if idx ~= lastIdx then
				lastIdx = idx
				playSfx("RouletteTick")
			end
		end)
	end

	local completedCount = 0
	local highestRarityOrder = 0
	for i, pet in ipairs(pets) do
		spinWindow(windows[i], strips[i], pet.rarity, pet.class, function()
			completedCount += 1
			-- Pokaż wynik pod tym oknem
			local lbl = resultContainer:GetChildren()[i]
			if lbl and lbl:IsA("TextLabel") then
				local rcfg = cfg.Rarities[pet.rarity]
				local color = (rcfg and rcfg.color) or C_WHITE
				lbl.Text       = string.format("%s %s", (rcfg and rcfg.displayName) or pet.rarity, pet.class)
				lbl.TextColor3 = color
				-- Polish: animowany shimmer gradient dla Legendary/Huge
				if pet.rarity == "Legendary" or pet.rarity == "Huge" then
					local grad = Instance.new("UIGradient")
					grad.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0,   color),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1,   color),
					})
					grad.Rotation = 45
					grad.Parent = lbl
					task.spawn(function()
						while lbl.Parent do
							grad.Rotation = (grad.Rotation + 2) % 360
							task.wait(0.03)
						end
					end)
				end
			end

			local rcfg = cfg.Rarities[pet.rarity]
			highestRarityOrder = math.max(highestRarityOrder, (rcfg and rcfg.order) or 0)

			-- Po ukończeniu OSTATNIEGO — Win SFX + screen shake + auto-fadeout po 2s (lub klik)
			if completedCount == n then
				if tickConn then tickConn:Disconnect() end
				playSfx("Win", { trimEnd = 0.6 })
				local hugeOrder = (cfg.Rarities.Huge and cfg.Rarities.Huge.order) or 5
				if highestRarityOrder >= hugeOrder then
					screenShake(0.6, 1.5)
				end
				-- Aktywuj click-to-skip
				skipOverlay.Visible = true
				-- Auto-fadeout po 2s
				task.delay(2.0, function()
					-- Jeśli gracz nie kliknął sam (panel nadal widoczny) — fadeout
					if roulPanel.Visible and skipOverlay.Visible then
						hideAll()
					end
				end)
			end
		end)
	end
end

-- ── Eventy ────────────────────────────────────────────────────────────────
-- OpenPetGablota — legacy event (choice GUI), już nie używane.
-- Server teraz triggeruje OpenEgg bezpośrednio z 2 promptów (E/T) na gablocie.
-- Listener zostaje jako no-op żeby nie crashował starego payloadu.
OpenPetGablota.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		hasGamepass = payload.hasGamepass == true
	end
end)

PetRouletteResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	-- Trwa już animacja — ignoruj kolejny wynik (anty-spam, defense in depth).
	if spinning and result.success then return end
	if not result.success then
		local msg = (result.reason == "broke") and "Za mało złotówek."
			or (result.reason == "full") and "Brak miejsca w plecaku."
			or "Coś poszło nie tak."
		showToast(msg, TOAST_RED)
		return
	end
	showRoulette(result.pets or {})
end)

PromptPetGamepassBuy.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	MarketplaceService:PromptGamePassPurchase(localPlayer, payload.gamepassId or cfg.TripleEggGamepassId)
	showToast("Wymaga Gamepass (29 R$) — kup w pop-upie aby otwierać 3 jajka.", TOAST_YELLOW)
end)

PetStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	hasGamepass = data.hasGamepass == true
end)

print("[PetGablotaController] gotowy")

-- ── Custom ProximityPrompt UI ─────────────────────────────────────────────
-- Server ustawia Style=Custom + attribute PetGablotaPrompt na 2 promptach gabloty.
-- Tu budujemy ładny billboard UI na PromptShown i sprzątamy na PromptHidden.
local ProximityPromptService = game:GetService("ProximityPromptService")

local function buildPromptUi(prompt: ProximityPrompt)
	local kind = prompt:GetAttribute("PetGablotaPrompt")  -- "single" / "triple"
	if not kind then return end

	local accent = (kind == "triple") and Color3.fromRGB(230, 190, 60) or C_ACC_GREEN
	local emoji  = (kind == "triple") and "🥚🥚🥚" or "🥚"
	local keyTxt = (prompt.KeyboardKeyCode == Enum.KeyCode.T) and "T" or "E"

	local bb = Instance.new("BillboardGui")
	bb.Name              = "PetPromptUI"
	bb.AlwaysOnTop       = true
	bb.LightInfluence    = 0
	bb.Size              = UDim2.fromOffset(280, 88)
	bb.StudsOffset       = Vector3.new(0, prompt.UIOffset.Y / 30, 0)  -- przeskaluj UIOffset Y na studs
	bb.Adornee           = prompt.Parent
	bb.Parent            = playerGui

	local panel = Instance.new("Frame")
	panel.Size                  = UDim2.fromScale(1, 1)
	panel.BackgroundColor3      = Color3.fromRGB(10, 30, 24)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel       = 0
	panel.Parent                = bb
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = panel
		local s = Instance.new("UIStroke"); s.Color = accent; s.Thickness = 3; s.Parent = panel
	end

	-- Lewa: klawisz w pudełku
	local keyBox = Instance.new("Frame")
	keyBox.Size                  = UDim2.fromOffset(54, 54)
	keyBox.Position              = UDim2.fromOffset(12, 17)
	keyBox.BackgroundColor3      = accent
	keyBox.BorderSizePixel       = 0
	keyBox.Parent                = panel
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = keyBox
		local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = 2; s.Parent = keyBox
	end

	local keyLbl = Instance.new("TextLabel")
	keyLbl.Size                   = UDim2.fromScale(1, 1)
	keyLbl.BackgroundTransparency = 1
	keyLbl.Text                   = keyTxt
	keyLbl.Font                   = FONT
	keyLbl.TextSize               = 30
	keyLbl.TextColor3             = Color3.new(0, 0, 0)
	keyLbl.Parent                 = keyBox

	-- Prawa: emoji + action text + cost
	local actionLbl = Instance.new("TextLabel")
	actionLbl.Size                   = UDim2.new(1, -84, 0, 24)
	actionLbl.Position               = UDim2.fromOffset(78, 12)
	actionLbl.BackgroundTransparency = 1
	actionLbl.Text                   = string.format("%s  %s", emoji, prompt.ActionText)
	actionLbl.Font                   = FONT
	actionLbl.TextSize               = 17
	actionLbl.TextColor3             = C_WHITE
	actionLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	actionLbl.TextStrokeTransparency = 0.4
	actionLbl.TextXAlignment         = Enum.TextXAlignment.Left
	actionLbl.Parent                 = panel

	local costLbl = Instance.new("TextLabel")
	costLbl.Size                   = UDim2.new(1, -84, 0, 24)
	costLbl.Position               = UDim2.fromOffset(78, 40)
	costLbl.BackgroundTransparency = 1
	costLbl.Text                   = prompt.ObjectText
	costLbl.Font                   = FONT
	costLbl.TextSize               = 15
	costLbl.TextColor3             = accent
	costLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	costLbl.TextStrokeTransparency = 0.4
	costLbl.TextXAlignment         = Enum.TextXAlignment.Left
	costLbl.Parent                 = panel

	-- Pop-in animacja
	panel.Size = UDim2.fromScale(0.6, 0.6)
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1) }):Play()

	return bb
end

local promptUis: { [ProximityPrompt]: BillboardGui } = {}

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if not prompt:GetAttribute("PetGablotaPrompt") then return end
	gablotaPrompts[prompt] = true
	-- Jeśli akurat trwa animacja — pokaż prompt wyłączony (E/T nieaktywne).
	if spinning then prompt.Enabled = false end
	if promptUis[prompt] then return end
	local ui = buildPromptUi(prompt)
	if ui then promptUis[prompt] = ui end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	local ui = promptUis[prompt]
	if ui then
		ui:Destroy()
		promptUis[prompt] = nil
	end
end)
