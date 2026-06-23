-- SkillTreeController.luau
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

local Config          = require(ReplicatedStorage:WaitForChild("Config"))
local Events          = ReplicatedStorage:WaitForChild("Events")
local BuySkillUpgrade = Events:WaitForChild("BuySkillUpgrade")
local SkillTreeUpdate = Events:WaitForChild("SkillTreeUpdate")
local UpdateHUD       = Events:WaitForChild("UpdateHUD")
local SkillTreeInit   = Events:WaitForChild("SkillTreeInit")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta (zgodna z HUD/Inventory) ───────────────────────────────────────

local C_BG       = Color3.fromRGB(18, 91, 73)
local C_PANEL    = Color3.fromRGB(24, 110, 90)
local C_HEADER   = Color3.fromRGB(0, 53, 39)
local C_CANVAS   = Color3.fromRGB(10, 10, 10)   -- czarne tło pod drzewko (ciemne)
local C_BORDER   = Color3.fromRGB(5, 25, 20)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT  = Color3.fromRGB(175, 175, 175)
local FONT       = Enum.Font.GothamBlack

-- Akcenty gałęzi — głębsze, bardziej matowe (mniej jaskrawe)
local C_BASE_ACC  = Color3.fromRGB(170, 221, 102)
local C_SPEED_ACC = Color3.fromRGB(70, 120, 180)
local C_MULT_ACC  = Color3.fromRGB(195, 145, 55)

-- ── Helpers kolorów ───────────────────────────────────────────────────────

local function lighten(c: Color3, mix: number): Color3
	return Color3.new(c.R + (1 - c.R) * mix, c.G + (1 - c.G) * mix, c.B + (1 - c.B) * mix)
end
local function darken(c: Color3, mix: number): Color3
	return Color3.new(c.R * (1 - mix), c.G * (1 - mix), c.B * (1 - mix))
end
local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- Stany węzła — kolory tła hexa
local C_HEX_DARK  = Color3.fromRGB(28, 28, 28)   -- fill dla available / locked
local C_HEX_LOCK  = Color3.fromRGB(70, 70, 70)   -- stroke dla locked

-- Ikony (CLAUDE.md)
local ICON_BASE  = "rbxassetid://97427046520791"
local ICON_SPEED = "rbxassetid://134318061601774"
local ICON_MULT  = "rbxassetid://82455275969069"
local ICON_LOCK  = "rbxassetid://136661234578099"

-- ── Hexagon: konfigurowalna funkcja ───────────────────────────────────────
-- Flat-top hex z pasków 1px (SACRED — nie zmieniać logiki rysowania)
-- Domyślne wartości można nadpisać per-wywołanie przez `opts`

local DEFAULT_HEX = {
	hexW    = 130,                          -- szerokość bounding box
	nStrip  = 320,                          -- liczba pasków (gęstość krawędzi — wyższe = gładsze)
	border  = 8,                            -- grubość borderu (px szerzej po każdej stronie)
	fill    = Color3.fromRGB(8, 60, 48),
	stroke  = Color3.fromRGB(80, 80, 80),
	zIndex  = 3,
}

--[[
	makeHex(parent, cx, cy, opts?) → { wrap, setColors, flash }

	parent: Frame nadrzędny
	cx, cy: środek hexa w pikselach (offset wewnątrz parenta)
	opts: opcjonalna tabela z polami hexW/nStrip/border/fill/stroke/zIndex
]]
local function makeHex(parent: Instance, cx: number, cy: number, opts: { [string]: any }?)
	opts = opts or {}
	local hexW   = (opts :: any).hexW   or DEFAULT_HEX.hexW
	local nStrip = (opts :: any).nStrip or DEFAULT_HEX.nStrip
	local border = (opts :: any).border or DEFAULT_HEX.border
	local fill   = (opts :: any).fill   or DEFAULT_HEX.fill
	local stroke = (opts :: any).stroke or DEFAULT_HEX.stroke
	local zi     = (opts :: any).zIndex or DEFAULT_HEX.zIndex

	local hexH   = hexW * 0.866
	local outerW = hexW + border * 2
	local outerH = hexH + border * 2
	local wrapW  = outerW + 2
	local wrapH  = outerH

	local wrap = Instance.new("Frame")
	wrap.Size                  = UDim2.fromOffset(wrapW, wrapH)
	wrap.AnchorPoint           = Vector2.new(0.5, 0.5)
	wrap.Position              = UDim2.fromOffset(cx, cy)
	wrap.BackgroundTransparency = 1
	wrap.BorderSizePixel       = 0
	wrap.ZIndex                = zi
	wrap.Parent                = parent

	-- UIScale dla hover (centrowane bo anchor 0.5,0.5)
	local hexScale = Instance.new("UIScale")
	hexScale.Scale = 1
	hexScale.Parent = wrap

	local borders, fills = {}, {}

	-- BORDER: większy hex pokrywający cały wrap (od y=0 do y=outerH)
	local bStripH = outerH / nStrip
	for i = 0, nStrip - 1 do
		local yFrac    = (i + 0.5) / nStrip
		local halfFrac = math.abs(yFrac - 0.5)
		local bW       = outerW * (1 - halfFrac)

		local bs = Instance.new("Frame")
		bs.Size                = UDim2.fromOffset(bW, math.ceil(bStripH) + 1)
		bs.Position            = UDim2.new(0.5, -bW/2, 0, i * bStripH)
		bs.BackgroundColor3    = stroke
		bs.BorderSizePixel     = 0
		bs.ZIndex              = zi + 1
		bs.Parent              = wrap
		borders[i + 1]         = bs
	end

	-- FILL: mniejszy hex w środku, offsetowany o `border` w dół
	local fStripH = hexH / nStrip
	for i = 0, nStrip - 1 do
		local yFrac    = (i + 0.5) / nStrip
		local halfFrac = math.abs(yFrac - 0.5)
		local fW       = hexW * (1 - halfFrac)

		local fs = Instance.new("Frame")
		fs.Size                = UDim2.fromOffset(fW, math.ceil(fStripH) + 1)
		fs.Position            = UDim2.new(0.5, -fW/2, 0, border + i * fStripH)
		fs.BackgroundColor3    = fill
		fs.BorderSizePixel     = 0
		fs.ZIndex              = zi + 2
		fs.Parent              = wrap
		fills[i + 1]           = fs
	end

	-- Flash overlay strips (VFX zakupu — biały błysk w kształcie hexa)
	-- Mirroruje strukturę fill stripów: każdy pasek = fragment hexa, ZIndex nad fill+border
	local flashStrips = {}
	for i = 0, nStrip - 1 do
		local yFrac    = (i + 0.5) / nStrip
		local halfFrac = math.abs(yFrac - 0.5)
		local fW       = hexW * (1 - halfFrac)

		local fl = Instance.new("Frame")
		fl.Size                   = UDim2.fromOffset(fW, math.ceil(fStripH) + 1)
		fl.Position               = UDim2.new(0.5, -fW/2, 0, border + i * fStripH)
		fl.BackgroundColor3       = C_WHITE
		fl.BackgroundTransparency = 1
		fl.BorderSizePixel        = 0
		fl.ZIndex                 = zi + 8
		fl.Parent                 = wrap
		flashStrips[i + 1]        = fl
	end

	-- Click button (transparentny overlay nad hexem)
	local btn = Instance.new("TextButton")
	btn.AnchorPoint            = Vector2.new(0.5, 0.5)
	btn.Position               = UDim2.fromScale(0.5, 0.5)
	btn.Size                   = UDim2.fromOffset(hexW, hexH)
	btn.BackgroundTransparency = 1
	btn.Text                   = ""
	btn.AutoButtonColor        = false
	btn.ZIndex                 = zi + 20
	btn.Parent                 = wrap

	-- Hover-animacja UIScale (jak w ekwipunku)
	local hoverTI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(hexScale, hoverTI, { Scale = 1.06 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(hexScale, hoverTI, { Scale = 1.00 }):Play()
	end)

	local onClick = (opts :: any).onClick
	if onClick then
		btn.MouseButton1Click:Connect(onClick)
	end

	local function setColors(newFill: Color3, newStroke: Color3)
		for _, f in ipairs(fills)   do f.BackgroundColor3 = newFill   end
		for _, b in ipairs(borders) do b.BackgroundColor3 = newStroke end
	end

	local function setStroke(newStroke: Color3)
		for _, b in ipairs(borders) do b.BackgroundColor3 = newStroke end
	end

	return {
		wrap        = wrap,
		setColors   = setColors,
		setStroke   = setStroke,
		flashStrips = flashStrips,
		button      = btn,
		scale       = hexScale,
	}
end

-- ── Stan ──────────────────────────────────────────────────────────────────

local pData = {
	BaseLevel       = 0,
	SpeedLevel      = 0,
	MultiplierLevel = 0,
	LuckLevel       = 0,
	StaminaLevel    = 0,
	Zlotowki        = 0,
}

local isOpen = false

-- ── Logika zakupu / stanu węzła ───────────────────────────────────────────

local function tryBuy(branch: string, level: number): boolean
	if branch == "Base" then
		if pData.BaseLevel >= 1 then return false end
		if Config.BaseUpgrade.Cost > pData.Zlotowki then return false end
		BuySkillUpgrade:FireServer("Base", 1)
		return true
	end
	if pData.BaseLevel < 1 then return false end

	-- Luck: single-level, wymaga MultiplierLevel >= 2
	if branch == "Luck" then
		if pData.LuckLevel >= 1 then return false end
		if pData.MultiplierLevel < 2 then return false end
		if Config.LuckUpgrade.Cost > pData.Zlotowki then return false end
		BuySkillUpgrade:FireServer("Luck", 1)
		return true
	end

	-- Stamina: single-level, wymaga SpeedLevel >= 2
	if branch == "Stamina" then
		if (pData.StaminaLevel or 0) >= 1 then return false end
		if pData.SpeedLevel < 2 then return false end
		if Config.StaminaUpgrade.Cost > pData.Zlotowki then return false end
		BuySkillUpgrade:FireServer("Stamina", 1)
		return true
	end

	local cur, upgrades
	if branch == "Speed" then
		cur, upgrades = pData.SpeedLevel, Config.SpeedUpgrades
	else
		cur, upgrades = pData.MultiplierLevel, Config.MultiplierUpgrades
	end
	if level ~= cur + 1 then return false end
	if level > #upgrades then return false end
	if upgrades[level].Cost > pData.Zlotowki then return false end
	BuySkillUpgrade:FireServer(branch, level)
	return true
end

local function nodeState(branch: string, level: number): string
	if branch == "Luck" then
		if pData.LuckLevel >= 1 then return "purchased" end
		if pData.BaseLevel < 1 then return "locked" end
		if pData.MultiplierLevel < 2 then return "locked" end
		return "available"
	end

	if branch == "Stamina" then
		if (pData.StaminaLevel or 0) >= 1 then return "purchased" end
		if pData.BaseLevel < 1 then return "locked" end
		if pData.SpeedLevel < 2 then return "locked" end
		return "available"
	end

	local cur
	if branch == "Base"       then cur = pData.BaseLevel
	elseif branch == "Speed"  then cur = pData.SpeedLevel
	else                           cur = pData.MultiplierLevel
	end
	if level <= cur then return "purchased" end
	if branch ~= "Base" and pData.BaseLevel < 1 then return "locked" end
	if level == cur + 1 then return "available" end
	return "locked"
end

_G["__skillTreeState"] = {
	data      = pData,
	tryBuy    = tryBuy,
	nodeState = nodeState,
	makeHex   = makeHex,
}

-- ── UI ────────────────────────────────────────────────────────────────────

local HEADER_H   = 52
local CANVAS_PAD = 24
local CANVAS_W   = 920
local CANVAS_H   = 560
local DET_W      = 320
local DET_GAP    = 18
local SKILL_GAP  = 24  -- gap między canvas a detail panel w wrapperze
local ST_W_COMPACT = CANVAS_PAD + CANVAS_W + CANVAS_PAD                   -- 968
local ST_W_WIDE    = ST_W_COMPACT + DET_W + CANVAS_PAD                    -- detail + prawy padding
local ST_W         = ST_W_WIDE  -- używane do pozycji detail panelu
-- Panel mieszka w zakładce MenuController — header zostaje ukryty, więc
-- ST_H NIE zawiera HEADER_H (Menu zapewnia własny pasek zakładek)
local ST_H       = CANVAS_PAD + CANVAS_H + CANVAS_PAD                     -- 608

local stGui = Instance.new("ScreenGui")
stGui.Name           = "SkillTree"
stGui.ResetOnSpawn   = false
stGui.IgnoreGuiInset = true
stGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
stGui.Enabled        = false
stGui.Parent         = playerGui

-- Overlay (przyciemnienie tła)
local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false   -- KRYTYCZNE: bez tego jaśnieje na trzymanym LPM
overlay.ZIndex                 = 1
overlay.Parent                 = stGui

-- Zewnętrzny panel (szara ramka, styl Inventory)
local panel = Instance.new("Frame")
panel.Size                   = UDim2.fromOffset(ST_W_COMPACT, ST_H)
panel.AnchorPoint            = Vector2.new(0.5, 0.5)
panel.Position               = UDim2.new(0.5, 0, 0.55, 0)
panel.BackgroundColor3       = C_PANEL
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel        = 0
panel.ClipsDescendants       = true
panel.ZIndex                 = 2
panel.Parent                 = stGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent       = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color           = C_BORDER
panelStroke.Thickness       = 4
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent          = panel

-- Header: UICorner zaokrągla rogi; dolne maskujemy prostokątnym fillem
-- + separator C_BORDER jako wizualny rozdział od reszty panelu
local header = Instance.new("Frame")
header.Size                   = UDim2.new(1, 0, 0, HEADER_H)
header.Position               = UDim2.fromOffset(0, 0)
header.BackgroundColor3       = C_HEADER
header.BorderSizePixel        = 0
header.ZIndex                 = 3
header.Parent                 = panel

do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = header

	-- Maskuje zaokrąglone dolne rogi
	local fill = Instance.new("Frame")
	fill.Size                  = UDim2.new(1, 0, 0, 10)
	fill.Position              = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3      = C_HEADER
	fill.BorderSizePixel       = 0
	fill.ZIndex                = 3
	fill.Parent                = header

	-- Cienka linia C_BORDER na samym dole
	local sep = Instance.new("Frame")
	sep.Size                   = UDim2.new(1, 0, 0, 2)
	sep.Position               = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3       = C_BORDER
	sep.BorderSizePixel        = 0
	sep.ZIndex                 = 5
	sep.Parent                 = header
end

-- Header niewidoczny — MenuController dostarcza własny pasek zakładek
header.Visible = false

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -70, 1, 0)
title.Position               = UDim2.fromOffset(22, 0)
title.BackgroundTransparency = 1
title.Text                   = "UMIEJĘTNOŚCI"
title.TextSize               = 16
title.Font                   = FONT
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

-- Close X (czerwony, bez ramki, hover-animacja jak w Inventory)
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
	local xScale = Instance.new("UIScale"); xScale.Scale = 1; xScale.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(xScale, ti, { Scale = 1.18 }):Play()
		closeBtn.TextColor3 = X_RED_HOVER
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(xScale, ti, { Scale = 1.00 }):Play()
		closeBtn.TextColor3 = X_RED
	end)
end

-- Wrapper który MenuController bierze do swojej zakładki UMIEJĘTNOŚCI.
-- Zawiera canvas + detPanel obok siebie, bez własnej ramki/headera.
local skillTreeWrap = Instance.new("Frame")
skillTreeWrap.Size                   = UDim2.fromOffset(CANVAS_W + SKILL_GAP + DET_W, CANVAS_H)
skillTreeWrap.BackgroundTransparency = 1
skillTreeWrap.BorderSizePixel        = 0
skillTreeWrap.AnchorPoint            = Vector2.new(0.5, 0.5)
skillTreeWrap.Position               = UDim2.fromScale(0.5, 0.5)
skillTreeWrap.Parent                 = panel  -- domyślnie w hidden stGui, MenuController przeniesie

-- Wewnętrzna ramka — czarne tło pod drzewko (ramka w ramce)
local canvas = Instance.new("Frame")
canvas.Size                   = UDim2.fromOffset(CANVAS_W, CANVAS_H)
-- Pozycja (0, 0) — siedzi w skillTreeWrap obok detPanel'a
canvas.Position               = UDim2.fromOffset(0, 0)
canvas.BackgroundColor3       = C_CANVAS
canvas.BackgroundTransparency = 0
canvas.BorderSizePixel        = 0
canvas.ClipsDescendants       = true
canvas.ZIndex                 = 3
canvas.Parent                 = skillTreeWrap

local canvasCorner = Instance.new("UICorner")
canvasCorner.CornerRadius = UDim.new(0, 8)
canvasCorner.Parent       = canvas

local canvasStroke = Instance.new("UIStroke")
canvasStroke.Color           = C_BORDER
canvasStroke.Thickness       = 3
canvasStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
canvasStroke.Parent          = canvas

-- ── Detail panel (po prawej) ──────────────────────────────────────────────
-- Wysuwa się po kliknięciu w hex; zaokrąglona ramka w stylu Inventory.

-- Detail panel zaczyna się dokładnie na prawej krawędzi compact panelu —
-- gdy panel zwinięty, klipuje się 1:1 i nic nie widać
-- Detail panel zawsze po prawej obok canvasa — nie ma już slide/clip animacji
-- bo w MenuController content area zawsze mamy miejsce na obie kolumny.
local DET_X_SHOWN  = CANVAS_W + SKILL_GAP

local detPanel = Instance.new("Frame")
detPanel.Size                  = UDim2.fromOffset(DET_W, CANVAS_H)
detPanel.Position              = UDim2.fromOffset(DET_X_SHOWN, 0)
detPanel.BackgroundColor3      = C_BG
detPanel.BackgroundTransparency = 0.05
detPanel.BorderSizePixel       = 0
detPanel.ZIndex                = 4
detPanel.Parent                = skillTreeWrap

do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = detPanel
	local s = Instance.new("UIStroke")
	s.Color = C_BORDER; s.Thickness = 4; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = detPanel
end

-- Close X (prawy górny róg detail panelu — czerwony, bez ramki)
local detCloseBtn = Instance.new("TextButton")
detCloseBtn.Size                   = UDim2.fromOffset(30, 30)
detCloseBtn.AnchorPoint            = Vector2.new(1, 0)
detCloseBtn.Position               = UDim2.new(1, -12, 0, 12)
detCloseBtn.BackgroundTransparency = 1
detCloseBtn.BorderSizePixel        = 0
detCloseBtn.Text                   = "X"
detCloseBtn.TextSize               = 22
detCloseBtn.Font                   = FONT
detCloseBtn.TextColor3             = X_RED
detCloseBtn.AutoButtonColor        = false
detCloseBtn.ZIndex                 = 6
detCloseBtn.Parent                 = detPanel
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = detCloseBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	detCloseBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
		detCloseBtn.TextColor3 = X_RED_HOVER
	end)
	detCloseBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		detCloseBtn.TextColor3 = X_RED
	end)
end

-- Tytuł
local detTitle = Instance.new("TextLabel")
detTitle.Size                   = UDim2.new(1, -56, 0, 32)
detTitle.Position               = UDim2.fromOffset(16, 18)
detTitle.BackgroundTransparency = 1
detTitle.Text                   = ""
detTitle.TextSize               = 22
detTitle.Font                   = FONT
detTitle.TextColor3             = C_WHITE
detTitle.TextXAlignment         = Enum.TextXAlignment.Left
detTitle.ZIndex                 = 5
detTitle.Parent                 = detPanel

-- Podtytuł (kategoria/poziom)
local detSubtitle = Instance.new("TextLabel")
detSubtitle.Size                   = UDim2.new(1, -32, 0, 20)
detSubtitle.Position               = UDim2.fromOffset(16, 52)
detSubtitle.BackgroundTransparency = 1
detSubtitle.Text                   = ""
detSubtitle.TextSize               = 13
detSubtitle.Font                   = FONT
detSubtitle.TextColor3             = C_DIMTEXT
detSubtitle.TextXAlignment         = Enum.TextXAlignment.Left
detSubtitle.ZIndex                 = 5
detSubtitle.Parent                 = detPanel

-- Status badge (KUPIONE / DOSTĘPNE / ZABLOKOWANE)
local detBadge = Instance.new("TextLabel")
detBadge.Size                   = UDim2.fromOffset(DET_W - 32, 32)
detBadge.Position               = UDim2.fromOffset(16, 84)
detBadge.BackgroundColor3       = C_HEADER
detBadge.BackgroundTransparency = 0
detBadge.BorderSizePixel        = 0
detBadge.Text                   = ""
detBadge.TextSize               = 14
detBadge.Font                   = FONT
detBadge.TextColor3             = C_WHITE
detBadge.ZIndex                 = 5
detBadge.Parent                 = detPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = detBadge
	local s = Instance.new("UIStroke")
	s.Color = C_BORDER; s.Thickness = 2; s.Parent = detBadge
end

-- Separator
local detSep = Instance.new("Frame")
detSep.Size             = UDim2.new(1, -32, 0, 1)
detSep.Position         = UDim2.fromOffset(16, 132)
detSep.BackgroundColor3 = C_BORDER
detSep.BorderSizePixel  = 0
detSep.ZIndex           = 5
detSep.Parent           = detPanel

-- Opis efektu
local detEffect = Instance.new("TextLabel")
detEffect.Size                   = UDim2.new(1, -32, 0, 120)
detEffect.Position               = UDim2.fromOffset(16, 146)
detEffect.BackgroundTransparency = 1
detEffect.Text                   = ""
detEffect.TextSize               = 14
detEffect.Font                   = FONT
detEffect.TextColor3             = C_WHITE
detEffect.TextWrapped            = true
detEffect.TextXAlignment         = Enum.TextXAlignment.Left
detEffect.TextYAlignment         = Enum.TextYAlignment.Top
detEffect.ZIndex                 = 5
detEffect.Parent                 = detPanel

-- Koszt
local detCostLbl = Instance.new("TextLabel")
detCostLbl.Size                   = UDim2.new(1, -32, 0, 24)
detCostLbl.Position               = UDim2.new(0, 16, 1, -110)
detCostLbl.BackgroundTransparency = 1
detCostLbl.Text                   = ""
detCostLbl.TextSize               = 15
detCostLbl.Font                   = FONT
detCostLbl.TextColor3             = C_DIMTEXT
detCostLbl.TextXAlignment         = Enum.TextXAlignment.Left
detCostLbl.ZIndex                 = 5
detCostLbl.Parent                 = detPanel

-- Przycisk KUP
local buyBtn = Instance.new("TextButton")
buyBtn.Size                 = UDim2.new(1, -32, 0, 56)
buyBtn.Position             = UDim2.new(0, 16, 1, -72)
buyBtn.BackgroundColor3     = C_BG
buyBtn.BackgroundTransparency = 0.05
buyBtn.BorderSizePixel      = 0
buyBtn.Text                 = "KUP"
buyBtn.TextSize             = 18
buyBtn.Font                 = FONT
buyBtn.TextColor3           = C_WHITE
buyBtn.AutoButtonColor      = false
buyBtn.ZIndex               = 5
buyBtn.Parent               = detPanel

local buyStroke
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn
	buyStroke = Instance.new("UIStroke")
	buyStroke.Color = C_BORDER; buyStroke.Thickness = 3
	buyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buyStroke.Parent = buyBtn

	-- Hover anim
	local bScale = Instance.new("UIScale"); bScale.Scale = 1; bScale.Parent = buyBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	buyBtn.MouseEnter:Connect(function() TweenService:Create(bScale, ti, { Scale = 1.04 }):Play() end)
	buyBtn.MouseLeave:Connect(function() TweenService:Create(bScale, ti, { Scale = 1.00 }):Play() end)
end

-- Placeholder pokazywany w detail panel gdy żaden węzeł nie jest wybrany
local detPlaceholder = Instance.new("TextLabel")
detPlaceholder.AnchorPoint            = Vector2.new(0.5, 0.5)
detPlaceholder.Position               = UDim2.fromScale(0.5, 0.5)
detPlaceholder.Size                   = UDim2.new(1, -32, 0, 120)
detPlaceholder.BackgroundTransparency = 1
detPlaceholder.Text                   = "Kliknij węzeł umiejętności\naby zobaczyć szczegóły"
detPlaceholder.Font                   = FONT
detPlaceholder.TextSize               = 16
detPlaceholder.TextColor3             = C_DIMTEXT
detPlaceholder.TextXAlignment         = Enum.TextXAlignment.Center
detPlaceholder.TextYAlignment         = Enum.TextYAlignment.Center
detPlaceholder.TextWrapped            = true
detPlaceholder.ZIndex                 = 5
detPlaceholder.Parent                 = detPanel

-- Stan i animacja detail panelu
local detailVisible    = false
local detailBranch     = nil :: string?
local detailLevel      = nil :: number?
local DET_TI_OPEN  = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DET_TI_CLOSE = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function applyDetailStatus()
	if not detailBranch or not detailLevel then return end
	local st = nodeState(detailBranch, detailLevel)
	local cost
	if detailBranch == "Base" then
		cost = Config.BaseUpgrade.Cost
	elseif detailBranch == "Speed" then
		cost = Config.SpeedUpgrades[detailLevel].Cost
	elseif detailBranch == "Multiplier" then
		cost = Config.MultiplierUpgrades[detailLevel].Cost
	elseif detailBranch == "Stamina" then
		cost = Config.StaminaUpgrade.Cost
	else  -- Luck
		cost = Config.LuckUpgrade.Cost
	end

	if st == "purchased" then
		detBadge.Text = "KUPIONE"
		detBadge.TextColor3 = Color3.fromRGB(100, 220, 130)
		detCostLbl.Text = "—"
		buyBtn.Text = "KUPIONE ✓"
		buyBtn.TextColor3 = Color3.fromRGB(100, 220, 130)
		buyStroke.Color = C_BORDER
	elseif st == "available" then
		local afford = cost <= pData.Zlotowki
		detBadge.Text = "DOSTĘPNE"
		detBadge.TextColor3 = Color3.fromRGB(88, 166, 255)
		detCostLbl.Text = "Koszt: " .. cost .. " ZŁ"
		if afford then
			buyBtn.Text = "KUP — " .. cost .. " ZŁ"
			buyBtn.TextColor3 = C_WHITE
			buyStroke.Color = Color3.fromRGB(88, 166, 255)
		else
			buyBtn.Text = "ZA MAŁO ZŁ (" .. cost .. ")"
			buyBtn.TextColor3 = C_DIMTEXT
			buyStroke.Color = C_BORDER
		end
	else
		detBadge.Text = "ZABLOKOWANE"
		detBadge.TextColor3 = Color3.fromRGB(220, 80, 80)
		detCostLbl.Text = if detailBranch == "Luck" and pData.MultiplierLevel < 2
			then "Wymaga Mnożnika poziom 2"
			elseif detailBranch == "Stamina" and pData.SpeedLevel < 2
			then "Wymaga Prędkości poziom 2"
			elseif detailBranch ~= "Base" and pData.BaseLevel < 1
			then "Kup Fundament najpierw"
			else "Wymaga poprzedniego poziomu"
		buyBtn.Text = "ZABLOKOWANE"
		buyBtn.TextColor3 = C_DIMTEXT
		buyStroke.Color = C_BORDER
	end
end

local function clearDetailContent()
	detTitle.Text     = ""
	detSubtitle.Text  = ""
	detBadge.Text     = ""
	detEffect.Text    = ""
	detCostLbl.Text   = ""
	buyBtn.Text       = ""
	buyBtn.Visible    = false
	detBadge.Visible  = false
	detSep.Visible    = false
	detCloseBtn.Visible    = false   -- X niepotrzebny gdy nic nie wybrane
	detPlaceholder.Visible = true
end

local function hideDetail()
	if not detailVisible then return end
	detailVisible = false
	detailBranch = nil
	detailLevel  = nil
	clearDetailContent()
end

local function showDetail(branch: string, level: number)
	-- Klik w ten sam hex podczas wyświetlania → schowaj
	if detailVisible and detailBranch == branch and detailLevel == level then
		hideDetail()
		return
	end

	detailBranch = branch
	detailLevel  = level

	if branch == "Base" then
		detTitle.Text    = string.upper(Config.BaseUpgrade.Name)
		detSubtitle.Text = "Węzeł bazowy"
		detEffect.Text   = "Odblokowuje gałęzie Prędkości i Mnożnika, dostęp do BANKU (skarbiec na butelki) oraz SPRINT na Shift z paskiem staminy na dole ekranu."
	elseif branch == "Speed" then
		local up = Config.SpeedUpgrades[level]
		detTitle.Text    = string.upper(up.Name)
		detSubtitle.Text = "Prędkość — Poziom " .. level
		detEffect.Text   = "Zwiększa prędkość poruszania do " .. up.Speed .. ". Szybciej zbierasz butelki i docierasz do butelkomatu."
	elseif branch == "Multiplier" then
		local up = Config.MultiplierUpgrades[level]
		detTitle.Text    = string.upper(up.Name)
		detSubtitle.Text = "Mnożnik zarobków — Poziom " .. level
		detEffect.Text   = "Mnożnik zarobków: ×" .. up.Multiplier .. ". Więcej złotówek za każdą oddaną butelkę."
	elseif branch == "Luck" then
		local up = Config.LuckUpgrade
		detTitle.Text    = string.upper(up.Name)
		detSubtitle.Text = "Szczęście — odnoga Mnożnika"
		detEffect.Text   = "Podwaja szanse na lepsze rzadkości w koszach (Rzadka × " .. up.LuckMultiplier
			.. ", Epicka × " .. up.LuckMultiplier .. ", Legendarna × " .. up.LuckMultiplier .. ")."
	elseif branch == "Stamina" then
		local up = Config.StaminaUpgrade
		detTitle.Text    = string.upper(up.Name)
		detSubtitle.Text = "Wytrzymałość — odnoga Prędkości"
		detEffect.Text   = "+" .. (up.StaminaBonus or 50)
			.. " do maksymalnej staminy (dłuższy sprint). Sumuje się z bonusem czapki."
	end

	-- Pokaż content, ukryj placeholder (detail panel jest zawsze widoczny w menu)
	detPlaceholder.Visible = false
	detBadge.Visible       = true
	detSep.Visible         = true
	buyBtn.Visible         = true
	detCloseBtn.Visible    = true

	applyDetailStatus()
	detailVisible = true
end

buyBtn.MouseButton1Click:Connect(function()
	if not detailBranch or not detailLevel then return end
	playSfx("Click")
	tryBuy(detailBranch, detailLevel)
end)

detCloseBtn.MouseButton1Click:Connect(function() playSfx("Click"); hideDetail() end)


-- treeWorld: kontener przesuwany (pan) + skalowany (zoom).
-- Wszystkie węzły drzewka idą tutaj, NIE bezpośrednio do canvasa.
local treeWorld = Instance.new("Frame")
treeWorld.Size                  = UDim2.fromScale(1, 1)
treeWorld.AnchorPoint           = Vector2.new(0.5, 0.5)
treeWorld.Position              = UDim2.new(0.5, 0, 0.5, 0)
treeWorld.BackgroundTransparency = 1
treeWorld.BorderSizePixel       = 0
treeWorld.ZIndex                = 3
treeWorld.Parent                = canvas

local DEFAULT_ZOOM = 0.85

local worldScale = Instance.new("UIScale")
worldScale.Scale = DEFAULT_ZOOM
worldScale.Parent = treeWorld

-- ── Pan & Zoom ────────────────────────────────────────────────────────────

local MIN_SCALE = 0.50
local MAX_SCALE = 2.00
local ZOOM_STEP = 0.10

local panActive       = false
local panStartMouse   = Vector2.zero
local panStartOffset  = Vector2.zero
local mouseOverCanvas = false

local function clampPan(offX: number, offY: number): (number, number)
	-- Limity: pozwól przesunąć do połowy rozmiaru canvasa w każdym kierunku
	local sz = canvas.AbsoluteSize
	local lim = math.max(120, sz.X * 0.6)
	local limY = math.max(120, sz.Y * 0.6)
	return math.clamp(offX, -lim, lim), math.clamp(offY, -limY, limY)
end

canvas.MouseEnter:Connect(function() mouseOverCanvas = true end)
canvas.MouseLeave:Connect(function() mouseOverCanvas = false end)

canvas.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		panActive      = true
		panStartMouse  = Vector2.new(input.Position.X, input.Position.Y)
		panStartOffset = Vector2.new(treeWorld.Position.X.Offset, treeWorld.Position.Y.Offset)
		-- Scale jest scale na (0.5, 0.5), offset trzymamy w X.Offset/Y.Offset
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and panActive then
		local cur   = Vector2.new(input.Position.X, input.Position.Y)
		local delta = cur - panStartMouse
		local nx, ny = clampPan(panStartOffset.X + delta.X, panStartOffset.Y + delta.Y)
		treeWorld.Position = UDim2.new(0.5, nx, 0.5, ny)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and mouseOverCanvas then
		local dir = input.Position.Z  -- +1 scroll up, -1 scroll down
		local newScale = math.clamp(worldScale.Scale + dir * ZOOM_STEP, MIN_SCALE, MAX_SCALE)
		worldScale.Scale = newScale
		-- Po zmianie zoom-u jeszcze raz wymuś clamp pozycji
		local nx, ny = clampPan(treeWorld.Position.X.Offset, treeWorld.Position.Y.Offset)
		treeWorld.Position = UDim2.new(0.5, nx, 0.5, ny)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and panActive then
		panActive = false
	end
end)

-- Eksport treeWorld dla budowy drzewa
_G["__skillTreeState"].treeWorld = treeWorld

-- ── DEMO: jeden hexagon po środku treeWorld ────────────────────────────────

-- ── Drzewko ───────────────────────────────────────────────────────────────

local HEX_W      = 110
local HEX_ICON   = 42
local BASE_CX    = CANVAS_W / 2          -- 460
local BASE_CY    = 490
local BRANCH_DX  = 70                    -- offset gałęzi w bok od osi
local V_STEP     = 120                   -- odstęp pionowy między poziomami (~25px przerwy)
local L1_CY      = BASE_CY - V_STEP      -- 388
local SPEED_CX   = BASE_CX - BRANCH_DX
local MULT_CX    = BASE_CX + BRANCH_DX
local LUCK_CX    = MULT_CX + 130            -- odnoga w prawo od Mult column
local STAMINA_CX = SPEED_CX - 130           -- odnoga w lewo od Speed column

-- Accent kolor dla Luck (fioletowy)
local C_LUCK_ACC    = Color3.fromRGB(150, 90, 200)
-- Accent dla Stamina (cyjan/turkus — odróżnia od Speed niebieskiego)
local C_STAMINA_ACC = Color3.fromRGB(80, 200, 200)

type NodeDef = {
	branch: string,
	level:  number,
	cx:     number,
	cy:     number,
	accent: Color3,
	icon:   string,
}

local NODES_ORDER: { string } = {
	"Base_1",
	"Speed_1", "Speed_2", "Speed_3", "Speed_4",
	"Mult_1",  "Mult_2",  "Mult_3",  "Mult_4",
	"Luck_1",
	"Stamina_1",
}

local NODES: { [string]: NodeDef } = {
	Base_1  = { branch = "Base",       level = 1, cx = BASE_CX,  cy = BASE_CY, accent = C_BASE_ACC,  icon = ICON_BASE  },

	Speed_1 = { branch = "Speed",      level = 1, cx = SPEED_CX, cy = L1_CY,             accent = C_SPEED_ACC, icon = ICON_SPEED },
	Speed_2 = { branch = "Speed",      level = 2, cx = SPEED_CX, cy = L1_CY - V_STEP,    accent = C_SPEED_ACC, icon = ICON_SPEED },
	Speed_3 = { branch = "Speed",      level = 3, cx = SPEED_CX, cy = L1_CY - V_STEP*2,  accent = C_SPEED_ACC, icon = ICON_SPEED },
	Speed_4 = { branch = "Speed",      level = 4, cx = SPEED_CX, cy = L1_CY - V_STEP*3,  accent = C_SPEED_ACC, icon = ICON_SPEED },

	Mult_1  = { branch = "Multiplier", level = 1, cx = MULT_CX,  cy = L1_CY,             accent = C_MULT_ACC,  icon = ICON_MULT  },
	Mult_2  = { branch = "Multiplier", level = 2, cx = MULT_CX,  cy = L1_CY - V_STEP,    accent = C_MULT_ACC,  icon = ICON_MULT  },
	Mult_3  = { branch = "Multiplier", level = 3, cx = MULT_CX,  cy = L1_CY - V_STEP*2,  accent = C_MULT_ACC,  icon = ICON_MULT  },
	Mult_4  = { branch = "Multiplier", level = 4, cx = MULT_CX,  cy = L1_CY - V_STEP*3,  accent = C_MULT_ACC,  icon = ICON_MULT  },

	-- Odnoga "Szczęście" od Mult_2 w prawo (fioletowy, ★ icon)
	Luck_1  = { branch = "Luck",       level = 1, cx = LUCK_CX,  cy = L1_CY - V_STEP,    accent = C_LUCK_ACC,  icon = ICON_BASE  },

	-- Odnoga "Wytrzymałość" od Speed_2 w lewo (cyjan, +50 max stamina)
	Stamina_1 = { branch = "Stamina",  level = 1, cx = STAMINA_CX, cy = L1_CY - V_STEP,  accent = C_STAMINA_ACC, icon = ICON_SPEED },
}

type NodeHandle = {
	def:        NodeDef,
	setColors:  (Color3, Color3) -> (),
	setStroke:  (Color3) -> (),
	icon:       ImageLabel,
	scale:      UIScale,
	entryScale: UIScale,
	flashStrips: { Frame },
	state:      string,
}

local nodeHandles: { [string]: NodeHandle } = {}

-- Linie łączące węzły. "from" = węzeł bliżej Bazy.
type LineDef = { from: string, to: string, frame: Frame }
local lineDefs: { LineDef } = {}

local function drawLine(fromKey: string, toKey: string)
	local nf = NODES[fromKey]; local nt = NODES[toKey]
	if not nf or not nt then return end
	local dx, dy = nt.cx - nf.cx, nt.cy - nf.cy
	local len    = math.sqrt(dx*dx + dy*dy)
	local angle  = math.deg(math.atan2(dy, dx))
	-- Skróć linię żeby nie wchodziła w hexy
	local trim = HEX_W * 0.42
	local effLen = math.max(1, len - trim * 2)

	local line = Instance.new("Frame")
	line.AnchorPoint       = Vector2.new(0.5, 0.5)
	line.Position          = UDim2.fromOffset((nf.cx + nt.cx) / 2, (nf.cy + nt.cy) / 2)
	line.Size              = UDim2.fromOffset(effLen, 5)
	line.Rotation          = angle
	line.BackgroundColor3  = C_HEX_LOCK
	line.BorderSizePixel   = 0
	line.ZIndex            = 2
	line.Parent            = treeWorld
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = line

	table.insert(lineDefs, { from = fromKey, to = toKey, frame = line })
end

-- Najpierw linie (pod hexami)
drawLine("Base_1",  "Speed_1")
drawLine("Base_1",  "Mult_1")
for lv = 1, 3 do
	drawLine("Speed_" .. lv, "Speed_" .. (lv + 1))
	drawLine("Mult_"  .. lv, "Mult_"  .. (lv + 1))
end
-- Odnoga: Luck rozgałęzia się z Mult_2 w prawo
drawLine("Mult_2", "Luck_1")
drawLine("Speed_2", "Stamina_1")

-- Tworzymy hexy
for _, key in ipairs(NODES_ORDER) do
	local n = NODES[key]
	local h = makeHex(treeWorld, n.cx, n.cy, {
		hexW    = HEX_W,
		nStrip  = 320,
		border  = 7,
		fill    = C_HEX_DARK,
		stroke  = C_HEX_LOCK,
		zIndex  = 3,
		onClick = function() playSfx("Click"); showDetail(n.branch, n.level) end,
	})

	-- Ikona na hexie (zindex między fillem a clickButtonem)
	local icon = Instance.new("ImageLabel")
	icon.Size                   = UDim2.fromOffset(HEX_ICON, HEX_ICON)
	icon.AnchorPoint            = Vector2.new(0.5, 0.5)
	icon.Position               = UDim2.fromScale(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image                  = n.icon
	icon.ImageColor3            = C_WHITE
	icon.ZIndex                 = 13
	icon.Parent                 = h.wrap

	-- Osobny UIScale do animacji wejścia (mnoży się z hexScale do hover)
	local entryScale = Instance.new("UIScale")
	entryScale.Scale = 1
	entryScale.Parent = h.wrap

	nodeHandles[key] = {
		def         = n,
		setColors   = h.setColors,
		setStroke   = h.setStroke,
		icon        = icon,
		scale       = h.scale,
		entryScale  = entryScale,
		flashStrips = h.flashStrips,
		state       = "locked",
	}
end

-- ── Render stanu drzewka ──────────────────────────────────────────────────

local function renderNodes()
	for _, key in ipairs(NODES_ORDER) do
		local h = nodeHandles[key]
		local n = h.def
		local st = nodeState(n.branch, n.level)
		h.state = st

		if st == "purchased" then
			-- Full kolor: fill = stroke = accent
			h.setColors(n.accent, n.accent)
			h.icon.Image       = n.icon
			h.icon.ImageColor3 = Color3.fromRGB(8, 30, 24)
		elseif st == "available" then
			-- Środek jaśniejszy niż obramówka (stroke pulsuje w Heartbeat poniżej)
			local fillC = lighten(n.accent, 0.40)
			h.setColors(fillC, n.accent)
			h.icon.Image       = n.icon
			h.icon.ImageColor3 = darken(n.accent, 0.55)
		else
			-- Locked: szary
			h.setColors(C_HEX_DARK, C_HEX_LOCK)
			h.icon.Image       = ICON_LOCK
			h.icon.ImageColor3 = Color3.fromRGB(120, 120, 120)
		end
	end

	-- Linie: kolor akcentu jeśli węzeł `from` kupiony, inaczej szare
	for _, ld in ipairs(lineDefs) do
		local nf = NODES[ld.from]
		local fromState = nodeState(nf.branch, nf.level)
		if fromState == "purchased" then
			-- Akcent gałęzi `to`
			local nt = NODES[ld.to]
			ld.frame.BackgroundColor3 = nt.accent
		else
			ld.frame.BackgroundColor3 = C_HEX_LOCK
		end
	end
end

renderNodes()

-- ── Animacja wejścia (pop-in hexów + fade linii) ──────────────────────────

-- Kolejność staggera (rząd → klucze)
local ENTRY_ROWS: { { number | { string } } } = {
	{ 0, { "Base_1" } },
	{ 1, { "Speed_1", "Mult_1" } },
	{ 2, { "Speed_2", "Mult_2", "Luck_1" } },  -- Luck wjeżdża razem z Mult_2
	{ 3, { "Speed_3", "Mult_3" } },
	{ 4, { "Speed_4", "Mult_4" } },
}

local ENTRY_DELAY    = 0.12
local ENTRY_STAGGER  = 0.07
local ENTRY_DUR_HEX  = 0.34
local ENTRY_DUR_LINE = 0.22

local function playEntryAnim()
	-- Reset stanu początkowego
	for _, h in pairs(nodeHandles) do
		h.entryScale.Scale = 0
	end
	for _, ld in ipairs(lineDefs) do
		ld.frame.BackgroundTransparency = 1
	end

	-- Stagger po rzędach
	for _, row in ipairs(ENTRY_ROWS) do
		local rowIdx = row[1] :: number
		local keys   = row[2] :: { string }
		local d      = ENTRY_DELAY + rowIdx * ENTRY_STAGGER
		task.delay(d, function()
			-- isOpen check usunięty — MenuController kontroluje widoczność,
			-- entry animation musi zawsze odpalić tweens przywracające hexy i linie
			local hexTI  = TweenInfo.new(ENTRY_DUR_HEX,  Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local lineTI = TweenInfo.new(ENTRY_DUR_LINE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			for _, k in ipairs(keys) do
				local h = nodeHandles[k]
				if h then
					TweenService:Create(h.entryScale, hexTI, { Scale = 1 }):Play()
				end
				for _, ld in ipairs(lineDefs) do
					if ld.to == k then
						TweenService:Create(ld.frame, lineTI, { BackgroundTransparency = 0 }):Play()
					end
				end
			end
		end)
	end
end

-- ── Puls "available" hexów (stroke pulsuje od ciemnego do jasnego) ────────

local RunService = game:GetService("RunService")
local pulseAccum = 0
RunService.Heartbeat:Connect(function(dt)
	pulseAccum += dt
	if pulseAccum < 1/30 then return end  -- throttle ~30 Hz, oszczędzamy CPU
	pulseAccum = 0
	if not isOpen then return end

	local p = (math.sin(tick() * 4.0) + 1) * 0.5  -- 0..1
	for _, key in ipairs(NODES_ORDER) do
		local h = nodeHandles[key]
		if h.state == "available" then
			local strokeDim    = darken(h.def.accent, 0.45)
			local strokeBright = lighten(h.def.accent, 0.25)
			h.setStroke(lerpColor(strokeDim, strokeBright, p))
		end
	end
end)

-- ── Toggle ────────────────────────────────────────────────────────────────

local POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local TI_OPEN  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function setOpen(open: boolean)
	isOpen = open
	if open then
		stGui.Enabled                = true
		panel.Position               = POS_HIDE
		overlay.BackgroundTransparency = 1
		-- Reset kamery (zoom + pan) do defaultów
		worldScale.Scale   = DEFAULT_ZOOM
		treeWorld.Position = UDim2.new(0.5, 0, 0.5, 0)
		TweenService:Create(panel,   TI_OPEN, { Position = POS_SHOW }):Play()
		TweenService:Create(overlay, TI_OPEN, { BackgroundTransparency = 0.30 }):Play()
		playEntryAnim()
	else
		hideDetail()
		panel.Size = UDim2.fromOffset(ST_W_COMPACT, ST_H)
		detailBranch = nil; detailLevel = nil
		TweenService:Create(panel, TI_CLOSE, { Position = POS_HIDE }):Play()
		local tw = TweenService:Create(overlay, TI_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not isOpen then stGui.Enabled = false end
		end)
		tw:Play()
	end
end

-- Toggle nie otwiera już samodzielnego panelu — kieruje do MenuController na zakładkę 2 (UMIEJĘTNOŚCI)
_G["__skillTreeToggle"] = function()
	if _G["__menuSetActiveTab"] then
		_G["__menuOpen"]()
		_G["__menuSetActiveTab"](2)
	else
		setOpen(not isOpen)  -- fallback gdyby MenuController nie był załadowany
	end
end

-- Eksport wrappera (canvas + detPanel obok siebie) — MenuController przeniesie
-- go do swojej zakładki UMIEJĘTNOŚCI. Bez własnej ramki/headera.
_G["__skillTreeWrap"] = skillTreeWrap
-- Entry animation hexów — Menu woła to przy każdym wejściu na zakładkę UMIEJĘTNOŚCI
_G["__skillTreePlayEntry"] = function()
	-- Reset kamery do defaultów + zagraj animację wejścia hexów
	worldScale.Scale   = DEFAULT_ZOOM
	treeWorld.Position = UDim2.new(0.5, 0, 0.5, 0)
	playEntryAnim()
end
_G["__skillTreeReady"] = true

-- Initial state — placeholder widoczny, content schowany
clearDetailContent()

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, proc)
	if proc then return end
	if input.KeyCode == Enum.KeyCode.U then
		if _G["__skillTreeToggle"] then _G["__skillTreeToggle"]() end
	end
end)

-- ── Remote listeners ──────────────────────────────────────────────────────

SkillTreeUpdate.OnClientEvent:Connect(function(result)
	if not result.success then return end
	if result.upgradeType == "Base"       then pData.BaseLevel       = result.newLevel end
	if result.upgradeType == "Speed"      then pData.SpeedLevel      = result.newLevel end
	if result.upgradeType == "Multiplier" then pData.MultiplierLevel = result.newLevel end
	if result.upgradeType == "Luck"       then pData.LuckLevel       = result.newLevel end
	if result.upgradeType == "Stamina"    then pData.StaminaLevel    = result.newLevel end

	playSfx("Buy")
	playSfx("LevelUp")

	-- VFX zakupu — flash kupionego węzła
	local key = if result.upgradeType == "Base"  then "Base_1"
		elseif result.upgradeType == "Speed"     then "Speed_" .. result.newLevel
		elseif result.upgradeType == "Multiplier" then "Mult_" .. result.newLevel
		else                                          "Luck_" .. result.newLevel
	local h = nodeHandles[key]
	if h then
		local ti = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, strip in ipairs(h.flashStrips) do
			strip.BackgroundTransparency = 0.1
			TweenService:Create(strip, ti, { BackgroundTransparency = 1 }):Play()
		end
	end

	renderNodes()
	if detailVisible then applyDetailStatus() end
end)

UpdateHUD.OnClientEvent:Connect(function(_data) end)

task.spawn(function()
	local ls = localPlayer:WaitForChild("leaderstats", 15)
	if not ls then return end
	local zl = ls:WaitForChild("Zlotowki", 10)
	if not zl then return end
	pData.Zlotowki = zl.Value
	zl.Changed:Connect(function(v)
		pData.Zlotowki = v
		if detailVisible then applyDetailStatus() end
	end)
end)

SkillTreeInit.OnClientEvent:Connect(function(data)
	pData.BaseLevel       = data.baseLevel       or 0
	pData.SpeedLevel      = data.speedLevel      or 0
	pData.MultiplierLevel = data.multiplierLevel or 0
	pData.LuckLevel       = data.luckLevel       or 0
	pData.StaminaLevel    = data.staminaLevel    or 0
	renderNodes()
end)
