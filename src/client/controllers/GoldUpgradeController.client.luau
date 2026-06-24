-- GoldUpgradeController.client.luau
-- UI ulepszania peta na ZŁOTEGO (rig "steve10die" w workspace.PUSTYNIA).
--
-- 3 kolumny (jak szkic):
--   • LEWA  — TWOJE PETY: siatka petów z EQ + zaznaczanie (✓), max 5, ta sama rzadkość.
--   • ŚRODEK — koło fortuny (łuk = % szansy), procent w środku, czarna kreska (wskaźnik),
--              LEWO/PRAWO (obrót łuku), ZAKRĘĆ, REROLL (po przegranej), 2x LUCK (Robux).
--   • PRAWA — obrazek gold peta + ODBIERZ (szary → zielony po wygranej).
--
-- Server (GoldPetService) jest autorytetem: zwraca {won, percent}. Klient ustawia łuk na
-- `percent` i animuje koło tak, by wskaźnik trafił w żółte (wygrana) lub poza (przegrana).
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local SoundService       = game:GetService("SoundService")
local RunService         = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Events             = ReplicatedStorage:WaitForChild("Events")
local OpenGoldUpgrade    = Events:WaitForChild("OpenGoldUpgrade")
local GoldUpgradeSpin    = Events:WaitForChild("GoldUpgradeSpin")
local GoldUpgradeResult  = Events:WaitForChild("GoldUpgradeResult")
local GoldUpgradeClaim   = Events:WaitForChild("GoldUpgradeClaim")
local GoldUpgradeBuy     = Events:WaitForChild("GoldUpgradeBuy")
local GoldUpgradeProduct = Events:WaitForChild("GoldUpgradeProduct")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── SFX ──────────────────────────────────────────────────────────────────────
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
local FONT       = Enum.Font.GothamBlack
local C_BG       = Color3.fromRGB(18, 91, 73)
local C_PANEL    = Color3.fromRGB(24, 110, 90)
local C_HEADER   = Color3.fromRGB(0, 53, 39)
local C_BORDER   = Color3.fromRGB(5, 25, 20)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIM      = Color3.fromRGB(180, 195, 188)
local C_ACC      = Color3.fromRGB(170, 221, 102)
local C_GOLD     = Color3.fromRGB(239, 199, 95)
local C_ARC      = Color3.fromRGB(245, 205, 45)
local C_DISC     = Color3.fromRGB(14, 46, 38)
local C_GRAY_BTN = Color3.fromRGB(90, 100, 96)
local X_RED      = Color3.fromRGB(220, 70, 70)

-- ── Config skróty ─────────────────────────────────────────────────────────
local gcfg = Config.Pets.GoldUpgrade

-- ── Stan ─────────────────────────────────────────────────────────────────
local cfgInit = {                 -- payload z OpenGoldUpgrade (z fallbackami)
	percentPerPet = gcfg.PercentPerPet or 20,
	maxSelect     = gcfg.MaxSelect or 5,
	images        = gcfg.Images or {},
	spinSeconds   = gcfg.SpinSeconds or 3.5,
	spinRotations = gcfg.SpinRotations or 5,
}
local petsState: { any } = {}
local selected: { string } = {}
local selectedSet: { [string]: boolean } = {}
local selectedRarity: string? = nil
local luckActive = false          -- kupione 2x luck na następny spin (preview ×2)
local phase = "select"            -- select | spinning | won | lost
local pendingGoldImage: string? = nil
local lastResultPercent = 0       -- % ostatniego spinu (do natychmiastowego ×2 po kupnie luck w fazie lost)

local function eligibleRarity(r: string): boolean
	return cfgInit.images[r] ~= nil
end

-- ── ScreenGui ─────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "GoldUpgrade"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 62
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = gui

local PANEL_W, PANEL_H = 1400, 780
local panel = Instance.new("Frame")
panel.Size             = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = C_PANEL
panel.BorderSizePixel  = 0
panel.ZIndex           = 2
panel.Parent           = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = panel
end

-- Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 56)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 12); fill.Position = UDim2.new(0, 0, 1, -12)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = header
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.ZIndex = 5; sep.Parent = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -56, 1, 0)
title.Position               = UDim2.fromOffset(24, 0)
title.BackgroundTransparency = 1
title.Text                   = "ULEPSZANIE PETA NA ZŁOTEGO"
title.TextSize               = 26
title.Font                   = FONT
title.TextColor3             = C_GOLD
title.TextXAlignment         = Enum.TextXAlignment.Center
title.ZIndex                 = 4
title.Parent                 = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size                   = UDim2.fromOffset(38, 38)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -14, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "X"
closeBtn.TextSize               = 26
closeBtn.Font                   = FONT
closeBtn.TextColor3             = X_RED
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 6
closeBtn.Parent                 = header

-- Body area below header
local body = Instance.new("Frame")
body.Size                   = UDim2.new(1, -24, 1, -72)
body.Position               = UDim2.fromOffset(12, 64)
body.BackgroundTransparency = 1
body.BorderSizePixel        = 0
body.ZIndex                 = 3
body.Parent                 = panel

-- Toast
local toastLbl = Instance.new("TextLabel")
toastLbl.AnchorPoint            = Vector2.new(0.5, 0)
toastLbl.Position               = UDim2.new(0.5, 0, 0, 10)
toastLbl.AutomaticSize          = Enum.AutomaticSize.X
toastLbl.Size                   = UDim2.fromOffset(0, 48)
toastLbl.BackgroundColor3       = Color3.new(0, 0, 0)
toastLbl.BackgroundTransparency = 0.3
toastLbl.BorderSizePixel        = 0
toastLbl.Text                   = ""
toastLbl.Font                   = Enum.Font.FredokaOne
toastLbl.TextSize               = 22
toastLbl.TextColor3             = X_RED
toastLbl.Visible                = false
toastLbl.ZIndex                 = 40
toastLbl.Parent                 = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = toastLbl
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = toastLbl
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 24); pad.PaddingRight = UDim.new(0, 24); pad.Parent = toastLbl
end
local toastJob: thread? = nil
local function showToast(msg: string, color: Color3?)
	if toastJob then task.cancel(toastJob); toastJob = nil end
	toastLbl.Text = msg
	toastLbl.TextColor3 = color or X_RED
	toastLbl.TextTransparency = 0
	toastLbl.BackgroundTransparency = 0.3
	toastLbl.Visible = true
	toastJob = task.spawn(function()
		task.wait(2.2)
		local ti = TweenInfo.new(0.3)
		TweenService:Create(toastLbl, ti, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.32)
		toastLbl.Visible = false
		toastJob = nil
	end)
end

-- ── Columns ───────────────────────────────────────────────────────────────
local COL_GAP = 16
local COL1_W = 420
local COL3_W = 360
local COL2_W = PANEL_W - 24 - COL1_W - COL3_W - COL_GAP * 2

local function makeColumn(x: number, w: number): Frame
	local f = Instance.new("Frame")
	f.Size                   = UDim2.new(0, w, 1, 0)
	f.Position               = UDim2.fromOffset(x, 0)
	f.BackgroundColor3       = C_BG
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel        = 0
	f.ZIndex                 = 3
	f.Parent                 = body
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = f
	return f
end

local col1 = makeColumn(0, COL1_W)
local col2 = makeColumn(COL1_W + COL_GAP, COL2_W)
local col3 = makeColumn(COL1_W + COL_GAP + COL2_W + COL_GAP, COL3_W)

-- ── COL1: TWOJE PETY ────────────────────────────────────────────────────────
local col1Title = Instance.new("TextLabel")
col1Title.Size                   = UDim2.new(1, -24, 0, 38)
col1Title.Position               = UDim2.fromOffset(12, 12)
col1Title.BackgroundTransparency = 1
col1Title.Text                   = "TWOJE PETY"
col1Title.TextSize               = 24
col1Title.Font                   = FONT
col1Title.TextColor3             = C_WHITE
col1Title.TextXAlignment         = Enum.TextXAlignment.Left
col1Title.ZIndex                 = 4
col1Title.Parent                 = col1

local petScroll = Instance.new("ScrollingFrame")
petScroll.Size                   = UDim2.new(1, -24, 1, -180)
petScroll.Position               = UDim2.fromOffset(12, 56)
petScroll.BackgroundTransparency = 1
petScroll.BorderSizePixel        = 0
petScroll.ScrollBarThickness     = 6
petScroll.ScrollingDirection     = Enum.ScrollingDirection.Y
petScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
petScroll.CanvasSize             = UDim2.new()
petScroll.ZIndex                 = 4
petScroll.Parent                 = col1
do
	local grid = Instance.new("UIGridLayout")
	grid.CellSize          = UDim2.fromOffset(112, 112)
	grid.CellPadding       = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder         = Enum.SortOrder.LayoutOrder
	grid.Parent            = petScroll
end

local descLbl = Instance.new("TextLabel")
descLbl.Size                   = UDim2.new(1, -24, 0, 112)
descLbl.AnchorPoint            = Vector2.new(0, 1)
descLbl.Position               = UDim2.new(0, 12, 1, -12)
descLbl.BackgroundTransparency = 1
descLbl.Text                   = "Posiadaj 5 petów takiej samej rzadkości aby mieć 100% szans na złotego peta. Przy mniejszej ilości szansa ta się zmniejsza (1 pet = 20%).\nZaznaczasz peta klikając na niego — pojawi się ✓."
descLbl.TextSize               = 15
descLbl.Font                   = FONT
descLbl.TextColor3             = C_DIM
descLbl.TextWrapped            = true
descLbl.TextXAlignment         = Enum.TextXAlignment.Left
descLbl.TextYAlignment         = Enum.TextYAlignment.Top
descLbl.ZIndex                 = 4
descLbl.Parent                 = col1

-- ── COL2: koło fortuny ─────────────────────────────────────────────────────
local WHEEL_D   = 320
local WHEEL_R   = WHEEL_D / 2
local SEG_N     = 120
local SEG_STEP  = 360 / SEG_N
local SEG_W     = math.ceil((2 * math.pi * WHEEL_R / SEG_N) * 1.35)

-- Holder centruje koło w górnej części kolumny
local wheelHolder = Instance.new("Frame")
wheelHolder.Size                   = UDim2.fromOffset(WHEEL_D + 20, WHEEL_D + 20)
wheelHolder.AnchorPoint            = Vector2.new(0.5, 0)
wheelHolder.Position               = UDim2.new(0.5, 0, 0, 24)
wheelHolder.BackgroundTransparency = 1
wheelHolder.ZIndex                 = 4
wheelHolder.Parent                 = col2

-- Statyczny ciemny dysk (nie rotuje)
local disc = Instance.new("Frame")
disc.Size                   = UDim2.fromOffset(WHEEL_D, WHEEL_D)
disc.AnchorPoint            = Vector2.new(0.5, 0.5)
disc.Position               = UDim2.fromScale(0.5, 0.5)
disc.BackgroundColor3       = C_DISC
disc.BorderSizePixel        = 0
disc.ZIndex                 = 4
disc.Parent                 = wheelHolder
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = disc
end

-- Łuk koła: cienki żółty pasek leżący DOKŁADNIE na obwodzie (czarnym okręgu).
-- Każda końcówka (tip) pozycjonowana TRYGONOMETRYCZNIE na promieniu = WHEEL_R, więc
-- arc jest idealnie współśrodkowy z kołem. arcRing (pełnowymiarowy, kotwica na środku)
-- rotuje TYLKO przyciskami LEWO/PRAWO — przesuwa łuk. Wskazówka kręci się osobno.
local RING_THICK = 16
local TIP_W      = 14
local CXY        = WHEEL_D / 2
local R_RIM      = WHEEL_R        -- środek paska na obwodzie → pokrywa czarny okrąg

local rimRing = Instance.new("Frame")
rimRing.Size                   = UDim2.fromOffset(WHEEL_D, WHEEL_D)
rimRing.AnchorPoint            = Vector2.new(0.5, 0.5)
rimRing.Position               = UDim2.fromScale(0.5, 0.5)
rimRing.BackgroundTransparency = 1
rimRing.ZIndex                 = 5
rimRing.Parent                 = wheelHolder
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = rimRing
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(8, 8, 8); s.Thickness = 6; s.Parent = rimRing
end

local arcRing = Instance.new("Frame")
arcRing.Size                   = UDim2.fromOffset(WHEEL_D, WHEEL_D)
arcRing.AnchorPoint            = Vector2.new(0.5, 0.5)
arcRing.Position               = UDim2.fromScale(0.5, 0.5)
arcRing.BackgroundTransparency = 1
arcRing.ZIndex                 = 9
arcRing.Parent                 = wheelHolder

local segs: { Frame } = {}  -- końcówki (tips)
for i = 0, SEG_N - 1 do
	local deg = i * SEG_STEP
	local ang = math.rad(deg)
	local tip = Instance.new("Frame")
	tip.AnchorPoint            = Vector2.new(0.5, 0.5)
	tip.Position               = UDim2.fromOffset(CXY + math.sin(ang) * R_RIM, CXY - math.cos(ang) * R_RIM)
	tip.Size                   = UDim2.fromOffset(TIP_W, RING_THICK)
	tip.Rotation               = deg
	tip.BackgroundColor3       = C_ARC
	tip.BackgroundTransparency = 1   -- domyślnie zgaszone
	tip.BorderSizePixel        = 0
	tip.ZIndex                 = 9
	tip.Parent                 = arcRing
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = tip
	segs[i + 1] = tip
end

-- WSKAZÓWKA — kontener pełnowymiarowy (kotwica na środku koła), więc Rotation obraca
-- ją czysto wokół centrum. Tył strzałki = środek koła. Grot na zewnętrznym końcu.
local needle = Instance.new("Frame")
needle.Size                   = UDim2.fromScale(1, 1)
needle.AnchorPoint            = Vector2.new(0.5, 0.5)
needle.Position               = UDim2.fromScale(0.5, 0.5)
needle.Rotation               = 0
needle.BackgroundTransparency = 1
needle.ZIndex                 = 10
needle.Parent                 = wheelHolder

local needleBar = Instance.new("Frame")
needleBar.Size             = UDim2.fromOffset(8, WHEEL_R - 8)
needleBar.AnchorPoint      = Vector2.new(0.5, 1)
needleBar.Position         = UDim2.fromScale(0.5, 0.5)  -- tył (dół) dokładnie w środku
needleBar.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
needleBar.BorderSizePixel  = 0
needleBar.ZIndex           = 10
needleBar.Parent           = needle
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = needleBar
	local head = Instance.new("Frame")
	head.Size = UDim2.fromOffset(18, 18); head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0); head.Rotation = 45
	head.BackgroundColor3 = Color3.fromRGB(8, 8, 8); head.BorderSizePixel = 0
	head.ZIndex = 10; head.Parent = needleBar
end
-- Środkowa kropka
local hub = Instance.new("Frame")
hub.Size             = UDim2.fromOffset(20, 20)
hub.AnchorPoint      = Vector2.new(0.5, 0.5)
hub.Position         = UDim2.fromScale(0.5, 0.5)
hub.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
hub.BorderSizePixel  = 0
hub.ZIndex           = 11
hub.Parent           = wheelHolder
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = hub
end

-- Procent w środku (chowany podczas kręcenia)
local percentLbl = Instance.new("TextLabel")
percentLbl.Size                   = UDim2.fromOffset(160, 70)
percentLbl.AnchorPoint            = Vector2.new(0.5, 0.5)
percentLbl.Position               = UDim2.fromScale(0.5, 0.5)
percentLbl.BackgroundTransparency = 1
percentLbl.Text                   = "0%"
percentLbl.TextSize               = 48
percentLbl.Font                   = FONT
percentLbl.TextColor3             = C_WHITE
percentLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
percentLbl.TextStrokeTransparency = 0.3
percentLbl.ZIndex                 = 12
percentLbl.Parent                 = wheelHolder

-- Etykieta 2x LUCK aktywne
local luckTag = Instance.new("TextLabel")
luckTag.Size                   = UDim2.fromOffset(200, 24)
luckTag.AnchorPoint            = Vector2.new(0.5, 0)
luckTag.Position               = UDim2.new(0.5, 0, 0.5, 40)
luckTag.BackgroundTransparency = 1
luckTag.Text                   = "✦ 2x LUCK AKTYWNE"
luckTag.TextSize               = 16
luckTag.Font                   = FONT
luckTag.TextColor3             = C_GOLD
luckTag.Visible                = false
luckTag.ZIndex                 = 12
luckTag.Parent                 = wheelHolder

-- setArc: zapala żółty łuk na obwodzie (od góry, zgodnie z ruchem wskazówek).
local function setArc(percent: number)
	local filled = math.floor((math.clamp(percent, 0, 100) / 100) * SEG_N + 0.5)
	for i = 1, SEG_N do
		segs[i].BackgroundTransparency = (i <= filled) and 0 or 1
	end
end

-- ── Buttony środka ─────────────────────────────────────────────────────────
local function makeBtn(parent: Instance, w: number, h: number, txt: string, color: Color3): (TextButton, TextLabel)
	local b = Instance.new("TextButton")
	b.Size                   = UDim2.fromOffset(w, h)
	b.BackgroundColor3       = color
	b.BorderSizePixel        = 0
	b.AutoButtonColor        = false
	b.Text                   = ""
	b.ZIndex                 = 5
	b.Parent                 = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = txt
	lbl.TextSize               = 20
	lbl.Font                   = FONT
	lbl.TextColor3             = Color3.new(0, 0, 0)
	lbl.ZIndex                 = 6
	lbl.Parent                 = b
	local sc = Instance.new("UIScale"); sc.Parent = b
	local ti = TweenInfo.new(0.1)
	b.MouseEnter:Connect(function() if b.Active then TweenService:Create(sc, ti, { Scale = 1.05 }):Play() end end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
	return b, lbl
end

-- Lewo / Prawo
local leftBtn  = makeBtn(col2, 130, 44, "← LEWO", C_BG)
leftBtn.Position = UDim2.new(0.5, -150, 0, WHEEL_D + 60)
do local l = leftBtn:FindFirstChildOfClass("TextLabel"); if l then l.TextColor3 = C_WHITE; l.TextSize = 18 end end

local rightBtn = makeBtn(col2, 130, 44, "PRAWO →", C_BG)
rightBtn.Position = UDim2.new(0.5, 20, 0, WHEEL_D + 60)
do local l = rightBtn:FindFirstChildOfClass("TextLabel"); if l then l.TextColor3 = C_WHITE; l.TextSize = 18 end end

-- ZAKRĘĆ
local spinBtn, spinLbl = makeBtn(col2, 280, 56, "ZAKRĘĆ!", C_ACC)
spinBtn.AnchorPoint = Vector2.new(0.5, 0)
spinBtn.Position    = UDim2.new(0.5, 0, 0, WHEEL_D + 116)
spinLbl.TextSize    = 26

-- Sam obrazek (bez ramki/napisu), tylko hover-scale. Wyśrodkowane w kolumnie, ułożone w pionie.
local PROD_H = 84
local LUCK_Y   = WHEEL_D + 174           -- 2x LUCK (na górze, szerszy)
local REROLL_Y = LUCK_Y + PROD_H + 10    -- REROLL pojawia się POD 2x LUCK
local function makeProductBtn(yOff: number, w: number): ImageButton
	local b = Instance.new("ImageButton")
	b.Size                   = UDim2.fromOffset(w, PROD_H)
	b.AnchorPoint            = Vector2.new(0.5, 0)
	b.Position               = UDim2.new(0.5, 0, 0, yOff)
	b.BackgroundTransparency = 1
	b.BorderSizePixel        = 0
	b.AutoButtonColor        = false
	b.ScaleType              = Enum.ScaleType.Fit
	b.ZIndex                 = 6
	b.Parent                 = col2
	local sc = Instance.new("UIScale"); sc.Parent = b
	local ti = TweenInfo.new(0.1)
	b.MouseEnter:Connect(function() if b.Active then TweenService:Create(sc, ti, { Scale = 1.06 }):Play() end end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
	return b
end

-- 2x LUCK (Robux) — przed spinem oraz po przegranej (per spin). Szerszy, na górze.
local luckBtn = makeProductBtn(LUCK_Y, 300)
luckBtn.Image = (gcfg.DoubleLuck and gcfg.DoubleLuck.Image) or ""

-- REROLL (Robux) — po przegranej, pod 2x LUCK
local rerollBtn = makeProductBtn(REROLL_Y, 240)
rerollBtn.Image   = (gcfg.Reroll and gcfg.Reroll.Image) or ""
rerollBtn.Visible = false

-- ── COL3: gold pet + ODBIERZ ────────────────────────────────────────────────
local goldFrame = Instance.new("Frame")
goldFrame.Size                   = UDim2.new(1, -48, 0, 380)
goldFrame.Position               = UDim2.fromOffset(24, 30)
goldFrame.BackgroundColor3       = C_DISC
goldFrame.BorderSizePixel        = 0
goldFrame.ZIndex                 = 4
goldFrame.Parent                 = col3
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = goldFrame
	local s = Instance.new("UIStroke"); s.Color = C_GOLD; s.Thickness = 3; s.Parent = goldFrame
end

local goldImg = Instance.new("ImageLabel")
goldImg.Size                   = UDim2.fromScale(0.86, 0.86)
goldImg.AnchorPoint            = Vector2.new(0.5, 0.5)
goldImg.Position               = UDim2.fromScale(0.5, 0.5)
goldImg.BackgroundTransparency = 1
goldImg.ScaleType              = Enum.ScaleType.Fit
goldImg.Image                  = ""
goldImg.Visible                = false
goldImg.ZIndex                 = 5
goldImg.Parent                 = goldFrame

local goldPlaceholder = Instance.new("TextLabel")
goldPlaceholder.Size                   = UDim2.new(1, -20, 0, 80)
goldPlaceholder.AnchorPoint            = Vector2.new(0.5, 0.5)
goldPlaceholder.Position               = UDim2.fromScale(0.5, 0.5)
goldPlaceholder.BackgroundTransparency = 1
goldPlaceholder.Text                   = "Wygraj aby\nzobaczyć złotego peta"
goldPlaceholder.TextSize               = 18
goldPlaceholder.Font                   = FONT
goldPlaceholder.TextColor3             = C_DIM
goldPlaceholder.TextWrapped            = true
goldPlaceholder.ZIndex                 = 5
goldPlaceholder.Parent                 = goldFrame

local claimBtn, claimLbl = makeBtn(col3, COL3_W - 48, 60, "ODBIERZ", C_GRAY_BTN)
claimBtn.AnchorPoint = Vector2.new(0.5, 1)
claimBtn.Position    = UDim2.new(0.5, 0, 1, -28)
claimLbl.TextColor3  = C_WHITE
claimLbl.TextSize    = 26
claimBtn.Active      = false

-- ── Movement lock ──────────────────────────────────────────────────────────
local locked = false
local function lockMove()
	if locked then return end
	locked = true
	if _G["__lockMovement"] then _G["__lockMovement"]() end
end
local function unlockMove()
	if not locked then return end
	locked = false
	if _G["__unlockMovement"] then _G["__unlockMovement"]() end
end

-- ── Selection / preview ─────────────────────────────────────────────────────
local function currentPreviewPercent(): number
	local mult = luckActive and 2 or 1
	return math.clamp(#selected * cfgInit.percentPerPet * mult, 0, 100)
end

local function refreshPreview()
	local p = currentPreviewPercent()
	percentLbl.Text = string.format("%d%%", p)
	setArc(p)
	luckTag.Visible = luckActive
end

local function setSpinEnabled(enabled: boolean)
	spinBtn.Active = enabled
	spinBtn.BackgroundColor3 = enabled and C_ACC or C_GRAY_BTN
	spinLbl.TextColor3 = enabled and Color3.new(0, 0, 0) or C_DIM
end

local function setClaimWon(won: boolean)
	claimBtn.Active = won
	claimBtn.BackgroundColor3 = won and C_ACC or C_GRAY_BTN
	claimLbl.TextColor3 = won and Color3.new(0, 0, 0) or C_WHITE
end

-- Buduje siatkę petów z petsState
local petTiles: { [string]: { frame: Frame, check: Frame } } = {}
local function rebuildPets()
	for _, c in ipairs(petScroll:GetChildren()) do
		if not c:IsA("UIGridLayout") then c:Destroy() end
	end
	petTiles = {}
	local order = 0
	for _, pet in ipairs(petsState) do
		order += 1
		local rcfg = (Config.Pets.Rarities and Config.Pets.Rarities[pet.rarity]) or {}
		local color = rcfg.color or C_WHITE
		local tile = Instance.new("TextButton")
		tile.BackgroundColor3 = Color3.new(color.R * 0.4, color.G * 0.4, color.B * 0.4)
		tile.BorderSizePixel  = 0
		tile.AutoButtonColor  = false
		tile.Text             = ""
		tile.LayoutOrder      = order
		tile.ZIndex           = 5
		tile.Parent           = petScroll
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = tile
		local s = Instance.new("UIStroke"); s.Color = color; s.Thickness = 3; s.Parent = tile

		-- obrazek peta (gold → osobna tekstura)
		local img = Instance.new("ImageLabel")
		img.Size                   = UDim2.fromScale(0.78, 0.78)
		img.AnchorPoint            = Vector2.new(0.5, 0.4)
		img.Position               = UDim2.fromScale(0.5, 0.4)
		img.BackgroundTransparency = 1
		img.ScaleType              = Enum.ScaleType.Fit
		local tex = rcfg.image
		if pet.gold then tex = cfgInit.images[pet.rarity] or tex end
		img.Image   = tex or ""
		img.Visible = tex ~= nil
		img.ZIndex  = 6
		img.Parent  = tile

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size                   = UDim2.new(1, 0, 0, 18)
		nameLbl.AnchorPoint            = Vector2.new(0.5, 1)
		nameLbl.Position               = UDim2.new(0.5, 0, 1, -3)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text                   = (pet.gold and "ZŁOTY " or "") .. pet.class
		nameLbl.TextSize               = 13
		nameLbl.Font                   = FONT
		nameLbl.TextColor3             = pet.gold and C_GOLD or C_WHITE
		nameLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
		nameLbl.TextStrokeTransparency = 0.4
		nameLbl.ZIndex                 = 6
		nameLbl.Parent                 = tile

		-- checkmark overlay (zielony ✓)
		local check = Instance.new("Frame")
		check.Size                   = UDim2.fromScale(1, 1)
		check.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
		check.BackgroundTransparency = 0.45
		check.BorderSizePixel        = 0
		check.Visible                = selectedSet[pet.id] == true
		check.ZIndex                 = 7
		check.Parent                 = tile
		do
			local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = check
			local circle = Instance.new("TextLabel")
			circle.Size = UDim2.fromOffset(48, 48)
			circle.AnchorPoint = Vector2.new(0.5, 0.5)
			circle.Position = UDim2.fromScale(0.5, 0.5)
			circle.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
			circle.Text = "✓"; circle.Font = FONT; circle.TextSize = 30
			circle.TextColor3 = C_WHITE; circle.ZIndex = 8; circle.Parent = check
			local ccc = Instance.new("UICorner"); ccc.CornerRadius = UDim.new(0.5, 0); ccc.Parent = circle
			local sss = Instance.new("UIStroke"); sss.Color = C_WHITE; sss.Thickness = 3; sss.Parent = circle
		end

		petTiles[pet.id] = { frame = tile, check = check }

		tile.MouseButton1Click:Connect(function()
			if phase ~= "select" then return end
			playSfx("Click")
			if selectedSet[pet.id] then
				-- odznacz
				selectedSet[pet.id] = nil
				for idx, id in ipairs(selected) do if id == pet.id then table.remove(selected, idx); break end end
				check.Visible = false
				if #selected == 0 then selectedRarity = nil end
			else
				if pet.gold then
					showToast("Nie można zaznaczać złotych petów")
					return
				end
				if not eligibleRarity(pet.rarity) then
					showToast("Tej rzadkości nie można ulepszać")
					return
				end
				if selectedRarity and pet.rarity ~= selectedRarity then
					showToast("Musisz zaznaczać pety o takiej samej rzadkości")
					return
				end
				if #selected >= cfgInit.maxSelect then
					showToast(string.format("Maksymalnie %d petów", cfgInit.maxSelect))
					return
				end
				selectedSet[pet.id] = true
				table.insert(selected, pet.id)
				selectedRarity = pet.rarity
				check.Visible = true
			end
			refreshPreview()
			setSpinEnabled(#selected > 0)
		end)
	end
end

-- ── Spin animation: KRĘCI SIĘ WSKAZÓWKA (łuk stoi), wskazówka wyznacza wynik ──
local spinTick: RBXScriptConnection? = nil
local function animateSpin(percent: number, won: boolean, onDone: () -> ())
	setArc(percent)
	local arcAngle = (math.clamp(percent, 0, 100) / 100) * 360
	local arcRot   = arcRing.Rotation % 360  -- początek łuku (od góry), ustawiony LEWO/PRAWO

	-- offset = pozycja w obrębie łuku (wygrana) lub poza nim (przegrana), licząc od arcRot.
	local offset
	if won then
		if arcAngle <= 0 then arcAngle = 1 end
		offset = arcAngle * (0.15 + math.random() * 0.7)  -- pewnie wewnątrz łuku
	else
		local emptySpan = 360 - arcAngle
		if emptySpan < 6 then
			offset = arcAngle * 0.5  -- łuk ~pełny → i tak praktycznie wygrana
		else
			local pad = emptySpan * 0.12
			offset = arcAngle + pad + math.random() * (emptySpan - 2 * pad)  -- w pustej części
		end
	end
	-- wskazówka ma się zatrzymać na kącie (arcRot + offset) od góry
	local targetMod = (arcRot + offset) % 360
	local cur  = needle.Rotation
	local base = cur + 360 * cfgInit.spinRotations
	local add  = (targetMod - (base % 360)) % 360
	local final = base + add

	-- Tick SFX per "ząbek" (12 na obrót) — zwalnia razem z wskazówką (Quint Out),
	-- jak roulette kosza/gabloty. NIE per-segment (120/obr to była kakofonia/za głośno).
	local NOTCH_DEG = 30
	local lastNotch = nil
	spinTick = RunService.RenderStepped:Connect(function()
		local n = math.floor((needle.Rotation % 360) / NOTCH_DEG)
		if n ~= lastNotch then
			lastNotch = n
			playSfx("RouletteTick")
		end
	end)

	local tw = TweenService:Create(needle,
		TweenInfo.new(cfgInit.spinSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Rotation = final })
	tw:Play()
	tw.Completed:Connect(function()
		if spinTick then spinTick:Disconnect(); spinTick = nil end
		onDone()
	end)
end

-- ── Phase setters ───────────────────────────────────────────────────────────
local function gotoSelect()
	phase = "select"
	percentLbl.Visible = true
	percentLbl.TextColor3 = C_WHITE
	rerollBtn.Visible = false
	luckBtn.Visible = true
	setSpinEnabled(#selected > 0)
	leftBtn.Active = true; rightBtn.Active = true
	refreshPreview()
end

-- ── Open / close ────────────────────────────────────────────────────────────
local function resetUiState()
	selected = {}; selectedSet = {}; selectedRarity = nil
	luckActive = false; pendingGoldImage = nil
	phase = "select"
	goldImg.Visible = false
	goldPlaceholder.Visible = true
	setClaimWon(false)
	rerollBtn.Visible = false
	luckBtn.Visible = true
	percentLbl.Visible = true
	percentLbl.TextColor3 = C_WHITE
	luckTag.Visible = false
	needle.Rotation = 0
	arcRing.Rotation = 0
end

local function openUI(payload)
	if type(payload) ~= "table" then return end
	cfgInit.percentPerPet = payload.percentPerPet or cfgInit.percentPerPet
	cfgInit.maxSelect     = payload.maxSelect or cfgInit.maxSelect
	cfgInit.images        = payload.images or cfgInit.images
	cfgInit.spinSeconds   = payload.spinSeconds or cfgInit.spinSeconds
	cfgInit.spinRotations = payload.spinRotations or cfgInit.spinRotations
	petsState = payload.pets or {}
	resetUiState()
	rebuildPets()
	refreshPreview()
	setSpinEnabled(false)
	gui.Enabled = true
	lockMove()
end

local function closeUI()
	-- Jeśli wygrany pet nie odebrany — auto-claim (player-friendly).
	if phase == "won" then
		GoldUpgradeClaim:FireServer()
	end
	if spinTick then spinTick:Disconnect(); spinTick = nil end
	gui.Enabled = false
	unlockMove()
end

-- ── Button wiring ───────────────────────────────────────────────────────────
local ROT_STEP = 36
-- LEWO/PRAWO obracają ŁUK (arcRing), nie wskazówkę.
-- LEWO/PRAWO działają w wyborze ORAZ po przegranej (przed rerollem) — tylko nie w trakcie kręcenia/wygranej.
leftBtn.MouseButton1Click:Connect(function()
	if phase ~= "select" and phase ~= "lost" then return end
	playSfx("Click")
	TweenService:Create(arcRing, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Rotation = arcRing.Rotation - ROT_STEP }):Play()
end)
rightBtn.MouseButton1Click:Connect(function()
	if phase ~= "select" and phase ~= "lost" then return end
	playSfx("Click")
	TweenService:Create(arcRing, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Rotation = arcRing.Rotation + ROT_STEP }):Play()
end)

local function beginSpin(isReroll: boolean)
	phase = "spinning"
	percentLbl.Visible = false
	luckTag.Visible = false
	setSpinEnabled(false)
	leftBtn.Active = false; rightBtn.Active = false
	rerollBtn.Visible = false
	luckBtn.Visible = false
	-- "muzyka otwierania" = ticki podczas kręcenia (jak roulette kosza/gabloty), Win na końcu
	if isReroll then
		GoldUpgradeSpin:FireServer({})
	else
		GoldUpgradeSpin:FireServer({ petIds = selected })
	end
end

spinBtn.MouseButton1Click:Connect(function()
	if not spinBtn.Active then return end
	if phase == "select" then
		if #selected == 0 then showToast("Zaznacz przynajmniej 1 peta"); return end
		playSfx("Click")
		beginSpin(false)
	end
end)

rerollBtn.MouseButton1Click:Connect(function()
	if phase ~= "lost" then return end
	playSfx("Click")
	GoldUpgradeBuy:FireServer("reroll")
end)

luckBtn.MouseButton1Click:Connect(function()
	-- 2x luck można kupić przed spinem ORAZ po przegranej (per spin, na reroll).
	if phase ~= "select" and phase ~= "lost" then return end
	if luckActive then showToast("2x LUCK już aktywne", C_GOLD); return end
	playSfx("Click")
	GoldUpgradeBuy:FireServer("luck")
end)

claimBtn.MouseButton1Click:Connect(function()
	if not claimBtn.Active or phase ~= "won" then return end
	playSfx("Click")
	GoldUpgradeClaim:FireServer()
end)

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); closeUI() end)
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and gui.Enabled then closeUI() end
end)

-- ── Eventy serwera ──────────────────────────────────────────────────────────
OpenGoldUpgrade.OnClientEvent:Connect(openUI)

GoldUpgradeResult.OnClientEvent:Connect(function(res)
	if type(res) ~= "table" then return end

	if res.claimed then
		-- pet odebrany → zamknij (phase=select żeby closeUI nie wysłał ponownego claim)
		if res.pets then petsState = res.pets end
		phase = "select"
		showToast("Złoty pet trafił do plecaka!", C_GOLD)
		closeUI()
		return
	end

	if not res.ok then
		-- odrzucenie spinu — wróć do wyboru
		local msg = (res.reason == "tooFar") and "Podejdź bliżej maszyny."
			or (res.reason == "mixedRarity") and "Musisz zaznaczać pety o takiej samej rzadkości"
			or (res.reason == "badRarity") and "Tej rzadkości nie można ulepszać."
			or (res.reason == "needReroll") and "Kup REROLL aby zakręcić ponownie."
			or (res.reason == "full") and "Brak miejsca w plecaku na peta."
			or "Coś poszło nie tak."
		showToast(msg)
		-- przywróć stan wyboru (chyba że trwa lost — zostaw reroll)
		if phase == "spinning" then
			if res.reason == "needReroll" then
				phase = "lost"
				rerollBtn.Visible = true
				luckBtn.Visible = (not luckActive)
				luckTag.Visible = luckActive
				leftBtn.Active = true; rightBtn.Active = true
				setSpinEnabled(false)
			else
				gotoSelect()
			end
		end
		return
	end

	-- Udany spin → aktualizuj pety (staked usunięte), animuj koło.
	-- UWAGA: NIE resetujemy luckActive — x2 luck zostaje aktywne przez całą próbę
	-- (też na reroll po przegranej), aż do wygranej/zamknięcia.
	if res.pets then petsState = res.pets; rebuildPets() end
	selected = {}; selectedSet = {}; selectedRarity = nil
	lastResultPercent = res.percent or 0  -- zapamiętaj % (do ×2 po kupnie luck w fazie lost)

	animateSpin(res.percent or 0, res.won == true, function()
		if res.won then
			phase = "won"
			pendingGoldImage = res.goldImage
			goldImg.Image = res.goldImage or ""
			goldImg.Visible = res.goldImage ~= nil
			goldPlaceholder.Visible = res.goldImage == nil
			rerollBtn.Visible = false
			luckBtn.Visible = false
			setClaimWon(true)
			percentLbl.Visible = true
			percentLbl.Text = "WYGRANA!"
			percentLbl.TextColor3 = C_GOLD
			playSfx("Win", { trimEnd = 0.6 })
			-- mały shimmer ramki gold
			local s = goldFrame:FindFirstChildOfClass("UIStroke")
			if s then
				task.spawn(function()
					for _ = 1, 6 do
						if not gui.Enabled then break end
						s.Thickness = 5; task.wait(0.12)
						if not gui.Enabled then break end
						s.Thickness = 3; task.wait(0.12)
					end
				end)
			end
		else
			phase = "lost"
			percentLbl.Visible = true
			percentLbl.Text = "PUDŁO"
			percentLbl.TextColor3 = X_RED
			rerollBtn.Visible = true
			luckBtn.Visible = (not luckActive)   -- jeśli 2x luck już aktywne, nie ma co kupować ponownie
			luckTag.Visible = luckActive          -- pokaż że x2 luck dalej działa
			leftBtn.Active = true; rightBtn.Active = true  -- LEWO/PRAWO znów klikalne
			setSpinEnabled(false)
			task.delay(0.05, function() percentLbl.TextColor3 = C_WHITE end)
		end
	end)
end)

GoldUpgradeProduct.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.kind == "luck" then
		luckActive = true
		luckTag.Visible = true
		luckBtn.Visible = false   -- już aktywne — nie kupuj drugi raz
		showToast("2x LUCK aktywne — szansa podwojona!", C_GOLD)
		if phase == "select" then
			refreshPreview()
		elseif phase == "lost" then
			-- Od razu po kupnie (nie czekając na reroll) pokaż podwojoną szansę na reroll.
			local np = math.clamp(lastResultPercent * 2, 0, 100)
			lastResultPercent = np
			setArc(np)
			percentLbl.Visible   = true
			percentLbl.Text      = string.format("%d%%", np)
			percentLbl.TextColor3 = C_GOLD
		end
	elseif payload.kind == "reroll" then
		if payload.hasStake then
			phase = "lost"
			showToast("REROLL gotowy — naciśnij ZAKRĘĆ!", C_GOLD)
			-- włącz ZAKRĘĆ do ponownego kręcenia tym samym wsadem
			spinBtn.Active = true
			spinBtn.BackgroundColor3 = C_ACC
			spinLbl.TextColor3 = Color3.new(0, 0, 0)
			rerollBtn.Visible = false
			luckTag.Visible = luckActive          -- x2 luck dalej działa na reroll
			luckBtn.Visible = (not luckActive)
			leftBtn.Active = true; rightBtn.Active = true  -- LEWO/PRAWO klikalne przed rerollem
			-- ZAKRĘĆ po rerollu = reroll spin (obsłużone w osobnym kliknięciu)
		else
			showToast("REROLL niedostępny tutaj.")
		end
	end
end)

-- ZAKRĘĆ w fazie lost (po kupnie reroll) = reroll spin
spinBtn.MouseButton1Click:Connect(function()
	if phase == "lost" and spinBtn.Active then
		playSfx("Click")
		beginSpin(true)
	end
end)

print("[GoldUpgradeController] gotowy")
