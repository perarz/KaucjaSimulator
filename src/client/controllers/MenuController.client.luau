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

-- ── Przycisk MENU (po lewej, środek pionowo) — ImageButton z ikoną ──────────
local menuBtn = Instance.new("ImageButton")
menuBtn.Name                   = "MenuButton"
menuBtn.AnchorPoint            = Vector2.new(0, 0.5)
menuBtn.Position               = UDim2.new(0, -10, 0.35, 0)
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
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint        = Vector2.new(1, 0)
closeBtn.Position           = UDim2.new(1, -16, 0, 14)
closeBtn.Size               = UDim2.fromOffset(44, 44)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel    = 0
closeBtn.Text               = "X"
closeBtn.Font               = FONT_MAIN
closeBtn.TextSize           = 28
closeBtn.TextColor3         = Color3.fromRGB(220, 70, 70)
closeBtn.AutoButtonColor    = false
closeBtn.ZIndex             = 10
closeBtn.Parent             = panel
do
	local sc = Instance.new("UIScale")
	sc.Parent = closeBtn
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

-- ── Pasek zakładek (pill shape, no border, inny kolor) ────────────────────
local tabBar = Instance.new("Frame")
tabBar.Position           = UDim2.fromOffset(CONTENT_PAD, CONTENT_PAD)
tabBar.Size               = UDim2.new(1, -CONTENT_PAD * 2 - 60, 0, TABBAR_H)  -- -60 zostaw miejsce na X
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

local TABS: { TabDef } = {
	{ id = "inventory", label = "EKWIPUNEK",    color = C_ACCENT_GREEN },
	{ id = "skills",    label = "UMIEJĘTNOŚCI", color = C_ACCENT_GREEN },
	{ id = "quests",    label = "QUESTY",       color = C_ACCENT_GREEN },
	{ id = "shop",      label = "SKLEP",        color = C_ACCENT_GREEN },
	{ id = "settings",  label = "USTAWIENIA",   color = C_ACCENT_GREEN },
}

local tabButtons: { TextButton } = {}
local activeTab = 1
local isMenuOpen = false

-- Obliczanie pozycji zakładki — równo rozłożone na pasku
local function tabRect(idx: number): (UDim2, UDim2)
	local tabAbsW = tabBar.AbsoluteSize.X
	if tabAbsW <= 0 then tabAbsW = MENU_W - CONTENT_PAD * 2 - 60 end  -- pre-layout fallback
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
-- Klik w overlay (tło) NIE zamyka menu — zamykanie wyłącznie przyciskiem X lub ESC

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isMenuOpen then
		setMenuOpen(false)
	elseif input.KeyCode == Enum.KeyCode.Tab then
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

-- ── Port: Ekwipunek do zakładki 1 (EKWIPUNEK) ─────────────────────────────
-- CollectController eksportuje wrapper (count label + sloty + detail panel).
task.spawn(function()
	local elapsed = 0
	while not _G["__inventoryReady"] and elapsed < 10 do
		task.wait(0.1)
		elapsed += 0.1
	end
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

-- ── Port: Questy do zakładki 3 (QUESTY) ───────────────────────────────────
task.spawn(function()
	local elapsed = 0
	while not _G["__questsReady"] and elapsed < 10 do
		task.wait(0.1)
		elapsed += 0.1
	end
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
end)

-- ── Port: Ustawienia do zakładki 4 (USTAWIENIA) ──────────────────────────
task.spawn(function()
	local elapsed = 0
	while not _G["__settingsReady"] and elapsed < 10 do
		task.wait(0.1)
		elapsed += 0.1
	end
	local setPanel = _G["__settingsPanel"] :: Frame?
	if not setPanel then
		warn("[MenuController] _G.__settingsPanel not available — USTAWIENIA zakładka pusta")
		return
	end

	-- Ukryj placeholder labels w zakładce 5 (USTAWIENIA)
	for _, child in ipairs(contentFrames[5]:GetChildren()) do
		if child:IsA("TextLabel") then child.Visible = false end
	end

	setPanel.Parent      = contentFrames[5]
	setPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	setPanel.Position    = UDim2.fromScale(0.5, 0.5)
end)

-- ── Port: Sklep (BoostShop) do zakładki 4 (SKLEP) ─────────────────────────
task.spawn(function()
	local elapsed = 0
	while not _G["__boostShopReady"] and elapsed < 10 do
		task.wait(0.1); elapsed += 0.1
	end
	local shopWrap = _G["__boostShopWrap"] :: Frame?
	if not shopWrap then
		warn("[MenuController] _G.__boostShopWrap not available — SKLEP zakładka pusta")
		return
	end
	for _, child in ipairs(contentFrames[4]:GetChildren()) do
		if child:IsA("TextLabel") then child.Visible = false end
	end
	shopWrap.Parent      = contentFrames[4]
	shopWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	shopWrap.Position    = UDim2.fromScale(0.5, 0.5)
	print("[MenuController] SKLEP zakładka — wrap przeniesiony do contentFrames[4]")
end)

-- ── Port: Skill Tree do zakładki 2 (UMIEJĘTNOŚCI) ─────────────────────────
-- SkillTreeController eksportuje wrapper (canvas + detail panel obok siebie).
-- Reparentujemy go bezpośrednio do contentFrames[2] — bez własnej ramki/headera.
task.spawn(function()
	local timeout = 10
	local elapsed = 0
	while not _G["__skillTreeReady"] and elapsed < timeout do
		task.wait(0.1)
		elapsed += 0.1
	end
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
