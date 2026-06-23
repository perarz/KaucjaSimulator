-- MenuController.client.luau
-- Główne menu gry: jeden przycisk MENU po lewej → kwadratowe menu prawie pełnoekranowe.
-- Pasek zakładek u góry (mocno zaokrąglony, akcent), animowany bubble indicator,
-- content area z animowanym slide między zakładkami.
--
-- Zakładki na razie zawierają placeholder content — istniejące panele
-- (skill tree, questy, ekwipunek, ustawienia) zostaną przeportowane w kolejnym kroku.
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")

local sfxGroup = SoundService:FindFirstChild("SfxGroup")
if not sfxGroup then
	sfxGroup = Instance.new("SoundGroup"); sfxGroup.Name = "SfxGroup"; sfxGroup.Parent = SoundService
end
local function playSfx(name: string)
	local sfxFolder = workspace:FindFirstChild("SFX")
	local tmpl = sfxFolder and sfxFolder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local s = tmpl:Clone(); s.SoundGroup = sfxGroup; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT_MAIN = Enum.Font.GothamBlack
local FONT_TAB  = Enum.Font.LuckiestGuy   -- ta sama co tytuł na loading screen (chunky cartoon)

-- Paleta (zgodna z resztą UI — green theme)
local C_BG           = Color3.fromRGB(18, 91, 73)
local C_PANEL        = Color3.fromRGB(24, 110, 90)
local C_HEADER       = Color3.fromRGB(0, 53, 39)
local C_TABBAR       = Color3.fromRGB(8, 60, 48)         -- ciemniejszy zielony pod tab bar
local C_BUBBLE       = Color3.fromRGB(170, 221, 102)     -- akcent dla bubble indicator
local C_BORDER       = Color3.fromRGB(5, 25, 20)
local C_WHITE        = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT      = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)

-- Wymiary
-- MENU_W=1480 mieści wider EQ (slotsW 760 + gap 24 + detail 480 = 1264 + paddings) + skill tree wide.
-- MENU_H=880 mieści 4 widoczne rzędy slotów (596) + tabbar + paddings + 28 toplabel + detal.
-- MobileScaleController zmniejsza na małych ekranach.
local MENU_W      = 1480
local MENU_H      = 880
local TABBAR_H    = 84
local TABBAR_PAD  = 12         -- padding bubble od krawędzi tab baru
local CONTENT_PAD = 24

-- ── Helpers ────────────────────────────────────────────────────────────────
local function mkCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function mkStroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color           = color
	s.Thickness       = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = parent
	return s
end

-- ── ScreenGui ──────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "MainMenu"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 30
gui.Parent         = playerGui

-- ── Przycisk MENU (środek dolnej krawędzi ekranu) — ImageButton z ikoną ─────
-- Po reorganizacji HUD: środek dół. SKLEP po lewo od MENU, hoverboard zostaje po lewej.
local HUD_BTN_BOTTOM_OFFSET = 20  -- piksele nad dolną krawędzią
local menuBtn = Instance.new("ImageButton")
menuBtn.Name                   = "MenuButton"
menuBtn.AnchorPoint            = Vector2.new(0.5, 1)
menuBtn.Position               = UDim2.new(0.5, 0, 1, -HUD_BTN_BOTTOM_OFFSET)
menuBtn.Size                   = UDim2.fromOffset(203, 135)
menuBtn.BackgroundTransparency = 1
menuBtn.BorderSizePixel        = 0
menuBtn.Image                  = "rbxassetid://99401921944526"
menuBtn.ScaleType              = Enum.ScaleType.Fit
menuBtn.AutoButtonColor        = false
menuBtn.Parent                 = gui

-- Hover: powiększenie + leciutki obrót
do
	local sc = Instance.new("UIScale")
	sc.Parent = menuBtn
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	menuBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.12 }):Play()
		TweenService:Create(menuBtn, ti, { Rotation = 6 }):Play()
	end)
	menuBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
		TweenService:Create(menuBtn, ti, { Rotation = 0 }):Play()
	end)
end

-- ── Overlay (przyciemnienie tła gdy menu otwarte) ──────────────────────────
local overlay = Instance.new("TextButton")
overlay.Name             = "Overlay"
overlay.Size             = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel  = 0
overlay.Text             = ""
overlay.AutoButtonColor  = false
overlay.Visible          = false
overlay.Parent           = gui

-- ── Główny panel ───────────────────────────────────────────────────────────
local panel = Instance.new("Frame")
panel.AnchorPoint        = Vector2.new(0.5, 0.5)
panel.Position           = UDim2.fromScale(0.5, 0.5)
panel.Size               = UDim2.fromOffset(MENU_W, MENU_H)
panel.BackgroundColor3   = C_BG
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel    = 0
panel.Visible            = false
panel.ClipsDescendants   = true
panel.Parent             = gui
mkCorner(panel, 12)
mkStroke(panel, C_BORDER, 5)

-- Close button (X) w prawym górnym rogu
-- X-close: czerwone wypełnione kółko z białym X. Wcześniej był sam czerwony tekst na
-- transparentnym tle — przy UIScale <1 (np. monitor 1280×1024 dostaje scale 0.865)
-- robił się na tyle drobny i niekontrastowy że gracze go nie widzieli i nie umieli
-- zamknąć menu (skarga z Discorda — "musze klikac samouczek zeby zamknac").
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint        = Vector2.new(1, 0)
closeBtn.Position           = UDim2.new(1, -16, 0, 14)
closeBtn.Size               = UDim2.fromOffset(52, 52)
closeBtn.BackgroundColor3   = Color3.fromRGB(200, 55, 55)
closeBtn.BorderSizePixel    = 0
closeBtn.Text               = "X"
closeBtn.Font               = FONT_MAIN
closeBtn.TextSize           = 32
closeBtn.TextColor3         = Color3.new(1, 1, 1)
closeBtn.AutoButtonColor    = false
closeBtn.ZIndex             = 10
closeBtn.Parent             = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = closeBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = closeBtn
	local sc = Instance.new("UIScale")
	sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundColor3 = Color3.fromRGB(235, 80, 80)
		TweenService:Create(sc, ti, { Scale = 1.12 }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
	end)
end

-- ── Money label w prawym górnym rogu (lewo od X-close) ────────────────────
-- Wallet HUD jest schowany gdy modalka otwarta (moveLockCount > 0), więc bez tego gracz
-- nie widzi swojego salda w menu. Czyta na bieżąco leaderstats.Zlotowki.
local MONEY_W = 240
local MONEY_GAP = 12  -- gap od X-close (52 wide + 16 right margin)
local moneyLbl = Instance.new("TextLabel")
moneyLbl.AnchorPoint            = Vector2.new(1, 0)
moneyLbl.Position               = UDim2.new(1, -(16 + 52 + MONEY_GAP), 0, 18)
moneyLbl.Size                   = UDim2.fromOffset(MONEY_W, 44)
moneyLbl.BackgroundColor3       = C_HEADER
moneyLbl.BorderSizePixel        = 0
moneyLbl.Text                   = "0 PLN"
moneyLbl.Font                   = FONT_MAIN
moneyLbl.TextSize               = 22
moneyLbl.TextColor3             = C_ACCENT_GREEN
moneyLbl.ZIndex                 = 9
moneyLbl.Parent                 = panel
mkCorner(moneyLbl, 8)
mkStroke(moneyLbl, C_BORDER, 3)

do
	local function formatMoney(n: number): string
		n = tonumber(n) or 0
		if math.abs(n - math.floor(n)) < 0.005 then
			return string.format("%d PLN", math.floor(n))
		end
		return string.format("%.2f PLN", n)
	end
	local function updateMoney(zl)
		if zl then moneyLbl.Text = formatMoney(zl.Value) end
	end
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 30)
		if not ls then return end
		local zl = ls:WaitForChild("Zlotowki", 30)
		if not zl then return end
		updateMoney(zl)
		zl:GetPropertyChangedSignal("Value"):Connect(function() updateMoney(zl) end)
	end)
end

-- ── Pasek zakładek (pill shape, no border, inny kolor) ────────────────────
-- Szerokość: -60 na X-close - MONEY_W - MONEY_GAP*2 (gap z każdej strony money label).
local TABBAR_RIGHT_RESERVE = 60 + MONEY_W + MONEY_GAP * 2
local tabBar = Instance.new("Frame")
tabBar.Position           = UDim2.fromOffset(CONTENT_PAD, CONTENT_PAD)
tabBar.Size               = UDim2.new(1, -CONTENT_PAD * 2 - TABBAR_RIGHT_RESERVE, 0, TABBAR_H)
tabBar.BackgroundColor3   = C_TABBAR
tabBar.BorderSizePixel    = 0
tabBar.Parent             = panel
mkCorner(tabBar, TABBAR_H / 2)  -- pill — radius = pół wysokości

-- Bubble indicator — pojedyncza ramka pod aktywną zakładką, animowana
local bubble = Instance.new("Frame")
bubble.BackgroundColor3 = C_BUBBLE
bubble.BorderSizePixel  = 0
bubble.ZIndex           = 2
bubble.Parent           = tabBar
mkCorner(bubble, (TABBAR_H - TABBAR_PAD * 2) / 2)

-- ── Zakładki ───────────────────────────────────────────────────────────────
type TabDef = { id: string, label: string, color: Color3 }

-- 4 zakładki. SKLEP jest osobnym GUI (ShopCatalogController) — przycisk w HUD obok MENU.
local TABS: { TabDef } = {
	{ id = "inventory", label = "EKWIPUNEK",    color = C_ACCENT_GREEN },
	{ id = "skills",    label = "UMIEJĘTNOŚCI", color = C_ACCENT_GREEN },
	{ id = "quests",    label = "QUESTY",       color = C_ACCENT_GREEN },
	{ id = "settings",  label = "USTAWIENIA",   color = C_ACCENT_GREEN },
}

local tabButtons: { TextButton } = {}
local activeTab = 1
local isMenuOpen = false

-- Obliczanie pozycji zakładki — równo rozłożone na pasku
local function tabRect(idx: number): (UDim2, UDim2)
	local tabAbsW = tabBar.AbsoluteSize.X
	if tabAbsW <= 0 then tabAbsW = MENU_W - CONTENT_PAD * 2 - TABBAR_RIGHT_RESERVE end  -- pre-layout fallback
	local cellW = (tabAbsW - TABBAR_PAD * 2) / #TABS
	local x     = TABBAR_PAD + (idx - 1) * cellW
	return UDim2.fromOffset(x, TABBAR_PAD),
		UDim2.fromOffset(cellW, TABBAR_H - TABBAR_PAD * 2)
end

-- Tworzymy przyciski (text-only, bubble pokazuje aktywność)
for i, def in ipairs(TABS) do
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor        = false
	btn.BorderSizePixel        = 0
	btn.Text                   = def.label
	btn.Font                   = FONT_TAB
	btn.TextSize               = 26
	btn.TextColor3             = C_DIMTEXT
	btn.ZIndex                 = 3
	btn.Parent                 = tabBar
	-- Pozycja ustawimy po pierwszym layoutcie (poniżej, w refreshLayout)
	tabButtons[i] = btn
end

-- Layout aktualizacja — wywoływane przy otwarciu menu i przy resize tab baru
local function refreshLayout()
	for i = 1, #TABS do
		local pos, size = tabRect(i)
		tabButtons[i].Position = pos
		tabButtons[i].Size     = size
	end
	-- Bubble pod aktywną
	local pos, size = tabRect(activeTab)
	bubble.Position = pos
	bubble.Size     = size
end

tabBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshLayout)

-- ── Content area + placeholder per zakładka ────────────────────────────────
local contentArea = Instance.new("Frame")
contentArea.Position           = UDim2.fromOffset(CONTENT_PAD, CONTENT_PAD + TABBAR_H + 18)
contentArea.Size               = UDim2.new(1, -CONTENT_PAD * 2, 1,
	-(CONTENT_PAD + TABBAR_H + 18) - CONTENT_PAD)
contentArea.BackgroundColor3   = C_PANEL
contentArea.BackgroundTransparency = 0.1
contentArea.BorderSizePixel    = 0
contentArea.ClipsDescendants   = true
contentArea.Parent             = panel
mkCorner(contentArea, 10)
mkStroke(contentArea, C_BORDER, 3)

local contentFrames: { Frame } = {}

local function buildPlaceholder(parent: Instance, def: TabDef): Frame
	local f = Instance.new("Frame")
	f.Size                   = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel        = 0
	f.Visible                = false
	f.Parent                 = parent

	-- Tytuł na środku
	local title = Instance.new("TextLabel")
	title.AnchorPoint            = Vector2.new(0.5, 0.5)
	title.Position               = UDim2.new(0.5, 0, 0.45, 0)
	title.Size                   = UDim2.fromOffset(800, 80)
	title.BackgroundTransparency = 1
	title.Text                   = def.label
	title.Font                   = FONT_MAIN
	title.TextSize               = 64
	title.TextColor3             = def.color
	title.TextXAlignment         = Enum.TextXAlignment.Center
	title.TextStrokeColor3       = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.7
	title.Parent                 = f

	-- Subtytuł
	local sub = Instance.new("TextLabel")
	sub.AnchorPoint            = Vector2.new(0.5, 0.5)
	sub.Position               = UDim2.new(0.5, 0, 0.58, 0)
	sub.Size                   = UDim2.fromOffset(800, 40)
	sub.BackgroundTransparency = 1
	sub.Text                   = "zawartość zakładki — wkrótce"
	sub.Font                   = FONT_MAIN
	sub.TextSize               = 20
	sub.TextColor3             = C_DIMTEXT
	sub.Parent                 = f

	return f
end

for i, def in ipairs(TABS) do
	contentFrames[i] = buildPlaceholder(contentArea, def)
end

-- ── Animacja przełączania ──────────────────────────────────────────────────
local TI_BUBBLE  = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CONTENT = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_DIST = 40  -- piksele przesunięcia in/out

local function setActiveTab(newIdx: number, animate: boolean)
	if newIdx < 1 or newIdx > #TABS then return end
	if newIdx == activeTab and animate then return end

	-- Bubble move
	local pos, size = tabRect(newIdx)
	if animate then
		TweenService:Create(bubble, TI_BUBBLE, { Position = pos, Size = size }):Play()
	else
		bubble.Position = pos
		bubble.Size     = size
	end

	-- Tab text colors
	for i, btn in ipairs(tabButtons) do
		if i == newIdx then
			btn.TextColor3 = Color3.new(0, 0, 0)  -- na zielonym bubblu czarny tekst
		else
			btn.TextColor3 = C_DIMTEXT
		end
	end

	-- Content slide
	local oldFrame = contentFrames[activeTab]
	local newFrame = contentFrames[newIdx]

	if animate and oldFrame ~= newFrame then
		-- Stary frame chowa się NATYCHMIAST — nie nakłada się na nowy podczas slide
		oldFrame.Visible  = false
		oldFrame.Position = UDim2.fromOffset(0, 0)

		-- Nowy slide-in z prawej
		newFrame.Position = UDim2.fromOffset(SLIDE_DIST, 0)
		newFrame.Visible  = true
		TweenService:Create(newFrame, TI_CONTENT, { Position = UDim2.fromOffset(0, 0) }):Play()
	else
		for _, f in ipairs(contentFrames) do f.Visible = false end
		newFrame.Visible  = true
		newFrame.Position = UDim2.fromOffset(0, 0)
	end

	activeTab = newIdx

	-- Per-zakładka hook po przełączeniu — np. animacja wejścia hexów w skill tree
	if newIdx == 2 and _G["__skillTreePlayEntry"] then
		-- task.defer żeby slide-in się zaczął, a entry animation odpaliła tuż po
		task.delay(0.05, _G["__skillTreePlayEntry"])
	end
end

for i, btn in ipairs(tabButtons) do
	local idx = i
	btn.MouseButton1Click:Connect(function() playSfx("Click"); setActiveTab(idx, true) end)
end

-- ── Open / Close ──────────────────────────────────────────────────────────
local TI_OPEN  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function setMenuOpen(open: boolean)
	if isMenuOpen == open then return end
	isMenuOpen = open

	-- Lock movement + sygnał dla wallet HUD żeby się schował (poprzez _G.__moveLockCount)
	if open then
		if _G["__lockMovement"] then _G["__lockMovement"]() end
	else
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
	end

	if open then
		panel.Visible   = true
		overlay.Visible = true
		panel.Size  = UDim2.fromOffset(MENU_W * 0.88, MENU_H * 0.88)
		overlay.BackgroundTransparency = 1
		TweenService:Create(panel, TI_OPEN, { Size = UDim2.fromOffset(MENU_W, MENU_H) }):Play()
		TweenService:Create(overlay, TI_OPEN, { BackgroundTransparency = 0.35 }):Play()
		task.defer(refreshLayout)  -- po pełnym layout cyklu Roblox zna AbsoluteSize
		-- Force render aktualnej zakładki bez animacji (initial)
		task.defer(function() setActiveTab(activeTab, false) end)
	else
		TweenService:Create(panel, TI_CLOSE, {
			Size = UDim2.fromOffset(MENU_W * 0.88, MENU_H * 0.88),
		}):Play()
		local tw = TweenService:Create(overlay, TI_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not isMenuOpen then
				panel.Visible   = false
				overlay.Visible = false
			end
		end)
		tw:Play()
	end
end

menuBtn.MouseButton1Click:Connect(function() playSfx("Click"); setMenuOpen(not isMenuOpen) end)
closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setMenuOpen(false) end)

-- Ikona MENU znika gdy inne UI otwarte (Bank/Sklep/itp). Wyłączam tylko zewnętrzny lock —
-- gdy mój panel jest otwarty, count zawiera mój własny lock — odejmuję go.
do
	local RunService = game:GetService("RunService")
	local lastVis = true
	RunService.RenderStepped:Connect(function()
		local count = tonumber(_G["__moveLockCount"]) or 0
		local externalLock = count - (isMenuOpen and 1 or 0)
		local shouldShow = externalLock <= 0
		if shouldShow ~= lastVis then
			menuBtn.Visible = shouldShow
			lastVis = shouldShow
		end
	end)
end
-- Klik w overlay (tło) NIE zamyka menu — zamykanie wyłącznie przyciskiem X lub ESC

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isMenuOpen then
		setMenuOpen(false)
	elseif input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.M then
		-- M = drugi toggle obok TAB; dodany po skardze gracza z 1280×1024 że nie umiał
		-- znaleźć X-close. ESC zamyka, TAB/M toggluje.
		setMenuOpen(not isMenuOpen)
	end
end)

-- Eksport (na wszelki wypadek — np. cutscena może chcieć zamknąć menu)
_G["__menuToggle"] = function() setMenuOpen(not isMenuOpen) end
_G["__menuClose"]  = function() setMenuOpen(false) end
_G["__menuOpen"]   = function() setMenuOpen(true) end
_G["__menuSetActiveTab"] = function(idx: number) setActiveTab(idx, true) end

-- Initial — pokaż zakładkę 1 bez animacji żeby pozycje wyliczyły się przed pierwszym otwarciem
task.defer(function()
	-- Force layout so tabRect ma poprawne AbsoluteSize
	panel.Visible = true
	panel.Size    = UDim2.fromOffset(MENU_W, MENU_H)
	task.wait()
	refreshLayout()
	setActiveTab(1, false)
	panel.Visible = false  -- ukryj z powrotem
end)

-- ── Handshake z kontrolerami: czekaj aż ustawią swój _G ready flag ────────
-- NIE poddajemy się po stałym oknie czasowym. Ciężkie kontrolery (CollectController
-- buduje 60 slotów EQ + kilka GUI synchronnie, PO blokującym workspace:WaitForChild("SFX"))
-- potrafią skończyć ładowanie po >10s na wolnym kliencie / cold-starcie w Studio.
-- Wcześniej twardy timeout 10s sprawiał, że port się poddawał NA ZAWSZE i zakładka
-- (najczęściej EKWIPUNEK — najcięższy kontroler przegrywa wyścig) zostawała na
-- placeholderze "wkrótce" do końca sesji. Teraz pollujemy dalej, z miękkim ostrzeżeniem
-- po 10s i twardym bezpiecznikiem po 60s (wtedy kontroler naprawdę padł przy ładowaniu).
local function waitForReady(readyKey: string, label: string): boolean
	local elapsed = 0
	local warned = false
	while not _G[readyKey] do
		task.wait(0.1)
		elapsed += 0.1
		if not warned and elapsed >= 10 then
			warned = true
			warn(string.format("[MenuController] %s wciąż nie gotowe po 10s — czekam dalej", label))
		end
		if elapsed >= 60 then
			warn(string.format("[MenuController] %s nie załadowane po 60s — poddaję się", label))
			return false
		end
	end
	return true
end

-- ── Port: Ekwipunek do zakładki 1 (EKWIPUNEK) ─────────────────────────────
-- CollectController eksportuje wrapper (count label + sloty + detail panel).
task.spawn(function()
	if not waitForReady("__inventoryReady", "EKWIPUNEK / CollectController") then return end
	local invWrap = _G["__inventoryWrap"] :: Frame?
	if not invWrap then
		warn("[MenuController] _G.__inventoryWrap not available — EKWIPUNEK zakładka pusta")
		return
	end

	-- Ukryj placeholder labels w zakładce 1
	for _, child in ipairs(contentFrames[1]:GetChildren()) do
		if child:IsA("TextLabel") then child.Visible = false end
	end

	invWrap.Parent      = contentFrames[1]
	invWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	invWrap.Position    = UDim2.fromScale(0.5, 0.5)
end)

-- ── Auto-fit helper: skaluje mały panel do rozmiaru contentFrame, aspect-ratio preserved.
-- Panele Quests/Settings mają fixed offsety (560×580 / 480×600), a contentArea ~1384×730 —
-- bez tego zajmują ~22% pola zakładki. UIScale powiększa wszystko proporcjonalnie.
local function fitPanelToContent(target: GuiObject, contentFrame: Frame, maxScale: number)
	local s = Instance.new("UIScale")
	s.Scale  = 1
	s.Parent = target
	local function recalc()
		local cs = contentFrame.AbsoluteSize
		if cs.X <= 0 or cs.Y <= 0 then return end
		-- AbsoluteSize uwzględnia UIScale, więc dzielimy żeby uzyskać rozmiar niesklejony.
		local ts = target.AbsoluteSize
		if ts.X <= 0 or ts.Y <= 0 then return end
		local ux = ts.X / s.Scale
		local uy = ts.Y / s.Scale
		local fit = math.min(cs.X / ux, cs.Y / uy) * 0.96  -- 4% margines na padding
		fit = math.clamp(fit, 0.6, maxScale)
		s.Scale = fit
	end
	contentFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
	task.defer(recalc)
	task.delay(0.1, recalc)   -- po pełnym layout cyklu
end

-- ── Port: Questy do zakładki 3 (QUESTY) ───────────────────────────────────
task.spawn(function()
	if not waitForReady("__questsReady", "QUESTY / QuestController") then return end
	local qPanel = _G["__questsPanel"] :: Frame?
	if not qPanel then
		warn("[MenuController] _G.__questsPanel not available — QUESTY zakładka pusta")
		return
	end

	-- Ukryj placeholder labels w zakładce 3
	for _, child in ipairs(contentFrames[3]:GetChildren()) do
		if child:IsA("TextLabel") then child.Visible = false end
	end

	qPanel.Parent      = contentFrames[3]
	qPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	qPanel.Position    = UDim2.fromScale(0.5, 0.5)
	fitPanelToContent(qPanel, contentFrames[3], 1.7)
end)

-- ── Port: Ustawienia do zakładki 4 (USTAWIENIA) ──────────────────────────
task.spawn(function()
	if not waitForReady("__settingsReady", "USTAWIENIA / SettingsController") then return end
	local setPanel = _G["__settingsPanel"] :: Frame?
	if not setPanel then
		warn("[MenuController] _G.__settingsPanel not available — USTAWIENIA zakładka pusta")
		return
	end

	for _, child in ipairs(contentFrames[4]:GetChildren()) do
		if child:IsA("TextLabel") then child.Visible = false end
	end

	setPanel.Parent      = contentFrames[4]
	setPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	setPanel.Position    = UDim2.fromScale(0.5, 0.5)
	fitPanelToContent(setPanel, contentFrames[4], 1.7)
end)

-- ── Port: Skill Tree do zakładki 2 (UMIEJĘTNOŚCI) ─────────────────────────
-- SkillTreeController eksportuje wrapper (canvas + detail panel obok siebie).
-- Reparentujemy go bezpośrednio do contentFrames[2] — bez własnej ramki/headera.
task.spawn(function()
	if not waitForReady("__skillTreeReady", "UMIEJĘTNOŚCI / SkillTreeController") then return end
	local stWrap = _G["__skillTreeWrap"] :: Frame?
	if not stWrap then
		warn("[MenuController] _G.__skillTreeWrap not available — UMIEJĘTNOŚCI zakładka pusta")
		return
	end

	-- Ukryj placeholder labels w zakładce 2
	for _, child in ipairs(contentFrames[2]:GetChildren()) do
		if child:IsA("TextLabel") then child.Visible = false end
	end

	stWrap.Parent      = contentFrames[2]
	stWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	stWrap.Position    = UDim2.fromScale(0.5, 0.5)
end)
