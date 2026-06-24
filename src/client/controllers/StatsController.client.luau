-- StatsController.client.luau
-- Przycisk STATS w HUD (środek dół, po PRAWO od MENU — symetrycznie do SKLEPU) + panel.
-- Premium look: gradient na panelu, jednolity subtelny stroke, duże zaokrąglenia (20/16),
-- duże liczby + małe etykiety z ikonkami, rzadkość = pasek koloru po lewej,
-- ViewportFrame z obracającym się modelem najlepszego peta w środku, hover + animacja open.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")
local RunService        = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Events       = ReplicatedStorage:WaitForChild("Events")
local StatsRequest = Events:WaitForChild("StatsRequest")
local StatsData    = Events:WaitForChild("StatsData")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local STATS_ICON_ID = "rbxassetid://93561657019134"

-- ── SFX ──────────────────────────────────────────────────────────────────────
local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl   = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

-- ── Paleta + fonty ───────────────────────────────────────────────────────────
local FONT_TITLE = Enum.Font.GothamBold
local FONT_VALUE = Enum.Font.GothamBold
local FONT_LABEL = Enum.Font.GothamMedium

local C_CARD    = Color3.fromRGB(17, 60, 48)
local C_HEADER  = Color3.fromRGB(10, 44, 34)
local C_STROKE  = Color3.fromRGB(70, 255, 140)   -- jednolity, subtelny stroke wszędzie
local C_WHITE   = Color3.fromRGB(240, 248, 244)
local C_DIM     = Color3.fromRGB(150, 185, 170)
local C_GOLD    = Color3.fromRGB(239, 199, 95)
local C_GREEN   = Color3.fromRGB(120, 235, 150)
local X_RED     = Color3.fromRGB(235, 95, 95)

local RARITY_COLORS = {
	Zwykla     = Color3.fromRGB(180, 180, 180),
	Rzadka     = Color3.fromRGB(70, 150, 235),
	Epicka     = Color3.fromRGB(150, 120, 235),
	Legendarna = Color3.fromRGB(245, 170, 55),
	Mityczny   = Color3.fromRGB(170, 80, 220),
}

local function fmtNum(n: number): string
	n = math.floor(tonumber(n) or 0)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

-- ── HUD button ───────────────────────────────────────────────────────────────
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "StatsHud"
hudGui.ResetOnSpawn   = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder   = 30
hudGui.Parent         = playerGui

local MENU_W = 203
local BTN_W, BTN_H = 203, 135
local HUD_GAP = 2
local STATS_X_OFFSET = (MENU_W / 2 + HUD_GAP + BTN_W / 2)  -- symetrycznie do SKLEPU (po prawo)

local statsBtn = Instance.new("ImageButton")
statsBtn.Name                   = "StatsButton"
statsBtn.AnchorPoint            = Vector2.new(0.5, 1)
statsBtn.Position               = UDim2.new(0.5, STATS_X_OFFSET, 1, -20)
statsBtn.Size                   = UDim2.fromOffset(BTN_W, BTN_H)
statsBtn.BackgroundTransparency = 1
statsBtn.BorderSizePixel        = 0
statsBtn.Image                  = STATS_ICON_ID
statsBtn.ScaleType              = Enum.ScaleType.Fit
statsBtn.AutoButtonColor        = false
statsBtn.Parent                 = hudGui
do
	local sc = Instance.new("UIScale"); sc.Parent = statsBtn
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
	statsBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.12 }):Play()
		TweenService:Create(statsBtn, ti, { Rotation = 6 }):Play()
	end)
	statsBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
		TweenService:Create(statsBtn, ti, { Rotation = 0 }):Play()
	end)
end

-- ── Panel ────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "StatsPanel"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 61
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = gui

local PANEL_W, PANEL_H = 1140, 690
local panel = Instance.new("Frame")
panel.Size             = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(16, 58, 46)
panel.BorderSizePixel  = 0
panel.ZIndex           = 2
panel.Parent           = gui
local panelScale = Instance.new("UIScale"); panelScale.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 22); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_STROKE; s.Thickness = 1.5; s.Transparency = 0.35; s.Parent = panel
	-- subtelny gradient (nie tęcza)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(18, 70, 55), Color3.fromRGB(12, 45, 35))
	g.Parent = panel
end

-- Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, -24, 0, 58)
header.Position         = UDim2.fromOffset(12, 12)
header.BackgroundColor3 = C_HEADER
header.BackgroundTransparency = 0.15
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = header
end

local titleIcon = Instance.new("TextLabel")
titleIcon.Size                   = UDim2.fromOffset(44, 58)
titleIcon.Position               = UDim2.fromOffset(16, 0)
titleIcon.BackgroundTransparency = 1
titleIcon.Text                   = "📊"
titleIcon.TextSize               = 30
titleIcon.Font                   = FONT_TITLE
titleIcon.ZIndex                 = 4
titleIcon.Parent                 = header

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(0, 300, 1, 0)
title.Position               = UDim2.fromOffset(64, 0)
title.BackgroundTransparency = 1
title.Text                   = "STATYSTYKI"
title.TextSize               = 24
title.Font                   = FONT_TITLE
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

local headerNick = Instance.new("TextLabel")
headerNick.Size                   = UDim2.new(0, 420, 1, 0)
headerNick.AnchorPoint            = Vector2.new(1, 0)
headerNick.Position               = UDim2.new(1, -64, 0, 0)
headerNick.BackgroundTransparency = 1
headerNick.Text                   = localPlayer.DisplayName
headerNick.TextSize               = 24
headerNick.Font                   = FONT_TITLE
headerNick.TextColor3             = C_GOLD
headerNick.TextXAlignment         = Enum.TextXAlignment.Right
headerNick.TextTruncate           = Enum.TextTruncate.AtEnd
headerNick.ZIndex                 = 4
headerNick.Parent                 = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size                   = UDim2.fromOffset(40, 40)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "✕"
closeBtn.TextSize               = 26
closeBtn.Font                   = FONT_TITLE
closeBtn.TextColor3             = X_RED
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 5
closeBtn.Parent                 = header

-- Body
local body = Instance.new("Frame")
body.Size                   = UDim2.new(1, -24, 1, -88)
body.Position               = UDim2.fromOffset(12, 78)
body.BackgroundTransparency = 1
body.BorderSizePixel        = 0
body.ZIndex                 = 3
body.Parent                 = panel

local COL_GAP = 16
local COL1_W = 300
local COL3_W = 300
local COL2_W = PANEL_W - 24 - COL1_W - COL3_W - COL_GAP * 2

local function makeColumn(x: number, w: number): Frame
	local f = Instance.new("Frame")
	f.Size                   = UDim2.new(0, w, 1, 0)
	f.Position               = UDim2.fromOffset(x, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel        = 0
	f.ZIndex                 = 3
	f.Parent                 = body
	return f
end

local col1 = makeColumn(0, COL1_W)
local col2 = makeColumn(COL1_W + COL_GAP, COL2_W)
local col3 = makeColumn(COL1_W + COL_GAP + COL2_W + COL_GAP, COL3_W)

-- Karta statystyki: ikonka + etykieta (mała) + duża wartość. Opcjonalny pasek rzadkości.
-- Zwraca value-label.
local function makeStatCard(parent: Instance, opts): TextLabel
	local card = Instance.new("Frame")
	card.Size              = UDim2.new(1, 0, 0, opts.h or 86)
	card.BackgroundColor3  = C_CARD
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel   = 0
	card.ZIndex            = 4
	card.Parent            = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = card
	local stroke = Instance.new("UIStroke"); stroke.Color = C_STROKE; stroke.Thickness = 1; stroke.Transparency = 0.55; stroke.Parent = card

	local padX = 18
	-- Pasek rzadkości po lewej (zamiast kolorowego stroke)
	if opts.barColor then
		local bar = Instance.new("Frame")
		bar.Size             = UDim2.new(0, 6, 1, -20)
		bar.Position         = UDim2.fromOffset(10, 10)
		bar.BackgroundColor3 = opts.barColor
		bar.BorderSizePixel  = 0
		bar.ZIndex           = 5
		bar.Parent           = card
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = bar
		padX = 28
	end

	-- Ikonka
	local icon = Instance.new("TextLabel")
	icon.Size                   = UDim2.fromOffset(34, 34)
	icon.Position               = UDim2.fromOffset(padX, 12)
	icon.BackgroundTransparency = 1
	icon.Text                   = opts.icon or ""
	icon.TextSize               = 24
	icon.Font                   = FONT_VALUE
	icon.ZIndex                 = 5
	icon.Parent                 = card

	-- Etykieta (mała)
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, -(padX + 44), 0, 18)
	lbl.Position               = UDim2.fromOffset(padX + 40, 12)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = opts.label
	lbl.TextSize               = 13
	lbl.Font                   = FONT_LABEL
	lbl.TextColor3             = C_DIM
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.TextTruncate           = Enum.TextTruncate.AtEnd
	lbl.ZIndex                 = 5
	lbl.Parent                 = card

	-- Wartość (duża)
	local val = Instance.new("TextLabel")
	val.Size                   = UDim2.new(1, -(padX + 16), 0, (opts.valueSize or 30) + 6)
	val.Position               = UDim2.fromOffset(padX, 36)
	val.BackgroundTransparency = 1
	val.Text                   = "0"
	val.TextSize               = opts.valueSize or 30
	val.Font                   = FONT_VALUE
	val.TextColor3             = opts.valueColor or C_WHITE
	val.TextXAlignment         = Enum.TextXAlignment.Left
	val.TextYAlignment         = Enum.TextYAlignment.Center
	val.TextTruncate           = Enum.TextTruncate.AtEnd
	val.ZIndex                 = 5
	val.Parent                 = card

	-- Hover (przezroczysty TextButton overlay — Frame nie ma MouseEnter)
	local sc = Instance.new("UIScale"); sc.Parent = card
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(1, 1); btn.BackgroundTransparency = 1; btn.Text = ""
	btn.AutoButtonColor = false; btn.ZIndex = 6; btn.Parent = card
	btn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.03 }):Play()
		TweenService:Create(stroke, ti, { Transparency = 0.1, Thickness = 2 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
		TweenService:Create(stroke, ti, { Transparency = 0.55, Thickness = 1 }):Play()
	end)

	return val
end

-- ── COL1: łącznie + zebrane per rzadkość ─────────────────────────────────────
do
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = col1
end
local valTotal  = makeStatCard(col1, { icon = "📦", label = "ZEBRANE BUTELKI ŁĄCZNIE", h = 96, valueSize = 38, valueColor = C_GREEN })
local valZwykla = makeStatCard(col1, { icon = "⚪", label = "ZWYKŁE",     h = 80, valueSize = 26, barColor = RARITY_COLORS.Zwykla })
local valRzadka = makeStatCard(col1, { icon = "🟦", label = "RZADKIE",    h = 80, valueSize = 26, barColor = RARITY_COLORS.Rzadka })
local valEpicka = makeStatCard(col1, { icon = "🟪", label = "EPICKIE",    h = 80, valueSize = 26, barColor = RARITY_COLORS.Epicka })
local valLegend = makeStatCard(col1, { icon = "🟨", label = "LEGENDARNE", h = 80, valueSize = 26, barColor = RARITY_COLORS.Legendarna })
local valMit    = makeStatCard(col1, { icon = "🟣", label = "MITYCZNE",   h = 80, valueSize = 26, barColor = RARITY_COLORS.Mityczny })

-- ── COL2: ViewportFrame z najlepszym petem (główny punkt) ───────────────────
local petCard = Instance.new("Frame")
petCard.Size              = UDim2.fromScale(1, 1)
petCard.BackgroundColor3  = Color3.fromRGB(12, 48, 38)
petCard.BackgroundTransparency = 0.05
petCard.BorderSizePixel   = 0
petCard.ZIndex            = 4
petCard.Parent            = col2
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 18); c.Parent = petCard
	local s = Instance.new("UIStroke"); s.Color = C_STROKE; s.Thickness = 1.5; s.Transparency = 0.4; s.Parent = petCard
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(16, 62, 48), Color3.fromRGB(10, 38, 30))
	g.Parent = petCard
end

local petHeading = Instance.new("TextLabel")
petHeading.Size                   = UDim2.new(1, -24, 0, 26)
petHeading.Position               = UDim2.fromOffset(12, 12)
petHeading.BackgroundTransparency = 1
petHeading.Text                   = "🐾  NAJLEPSZY PET"
petHeading.TextSize               = 14
petHeading.Font                   = FONT_LABEL
petHeading.TextColor3             = C_DIM
petHeading.TextXAlignment         = Enum.TextXAlignment.Center
petHeading.ZIndex                 = 5
petHeading.Parent                 = petCard

local viewport = Instance.new("ViewportFrame")
viewport.Size                   = UDim2.new(1, -32, 1, -100)
viewport.Position               = UDim2.fromOffset(16, 44)
viewport.BackgroundTransparency = 1
viewport.Ambient                = Color3.fromRGB(190, 200, 195)
viewport.LightColor             = Color3.fromRGB(255, 255, 255)
viewport.LightDirection         = Vector3.new(-0.4, -1, -0.3)
viewport.ZIndex                 = 5
viewport.Parent                 = petCard

local petNameLbl = Instance.new("TextLabel")
petNameLbl.Size                   = UDim2.new(1, -24, 0, 40)
petNameLbl.AnchorPoint            = Vector2.new(0.5, 1)
petNameLbl.Position               = UDim2.new(0.5, 0, 1, -12)
petNameLbl.BackgroundTransparency = 1
petNameLbl.Text                   = "Brak peta"
petNameLbl.TextSize               = 30
petNameLbl.Font                   = FONT_VALUE
petNameLbl.TextColor3             = C_GOLD
petNameLbl.TextXAlignment         = Enum.TextXAlignment.Center
petNameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
petNameLbl.ZIndex                 = 5
petNameLbl.Parent                 = petCard

-- ── COL3: PLN / PvP / akcesoria ──────────────────────────────────────────────
do
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 12); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = col3
end
local valPln  = makeStatCard(col3, { icon = "💰", label = "ILOŚĆ PLN", h = 150, valueSize = 42, valueColor = C_GREEN })
local valKill = makeStatCard(col3, { icon = "⚔️", label = "KILLE W STREFIE PVP", h = 120, valueSize = 38, valueColor = X_RED })
local valAcc  = makeStatCard(col3, { icon = "🎒", label = "UŻYTE AKCESORIA", h = 120, valueSize = 38, valueColor = Color3.fromRGB(235, 150, 95) })

-- ── Viewport: ładowanie + obrót modelu peta ─────────────────────────────────
local function petTemplate(rarity: string, gold: boolean): Instance?
	local segs = gold and (Config.Pets.GoldModelsFolderPath or { "Pets", "PetyGold" })
		or (Config.Pets.ModelsFolderPath or { "Pets", "PetyEnchanted" })
	local tryPaths = { segs, { "Pets", "PetyEnchanted" }, { "Pets", "PetyZwykle" } }
	if gold then tryPaths = { segs, { "Pets", "PetyGold" } } end
	local name = (Config.Pets.ModelNamePrefix or "Pet") .. rarity
	for _, path in ipairs(tryPaths) do
		local folder: Instance? = ReplicatedStorage
		for _, s in ipairs(path) do folder = folder and folder:FindFirstChild(s) end
		local m = folder and folder:FindFirstChild(name)
		if m then return m end
	end
	return nil
end

local vpModel: Model? = nil
local vpConn: RBXScriptConnection? = nil
local function clearViewport()
	if vpConn then vpConn:Disconnect(); vpConn = nil end
	if vpModel then vpModel:Destroy(); vpModel = nil end
end

local function loadPet(info)
	clearViewport()
	if not info then return end
	local tmpl = petTemplate(info.rarity, info.gold == true)
	if not tmpl then return end

	local clone
	if tmpl:IsA("Model") then
		clone = tmpl:Clone()
	elseif tmpl:IsA("BasePart") then
		clone = Instance.new("Model")
		local p = tmpl:Clone(); p.Parent = clone; clone.PrimaryPart = p
	else
		return
	end
	-- Anchor wszystko (viewport nie symuluje fizyki, ale dla pewności)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	local cam = viewport:FindFirstChildOfClass("Camera")
	if not cam then cam = Instance.new("Camera"); cam.Parent = viewport; viewport.CurrentCamera = cam end

	clone.Parent = viewport
	-- Wyśrodkuj bbox modelu w (0,0,0)
	local bbCF, size = clone:GetBoundingBox()
	clone:PivotTo(CFrame.new(-bbCF.Position) * clone:GetPivot())
	local recentered = clone:GetPivot()
	vpModel = clone

	local maxE = math.max(size.X, size.Y, size.Z)
	if maxE <= 0 then maxE = 4 end
	local dist = maxE * 1.9 + 2
	cam.FieldOfView = 45
	cam.CFrame = CFrame.new(Vector3.new(0, size.Y * 0.12, dist), Vector3.zero)

	local angle = 0
	vpConn = RunService.RenderStepped:Connect(function(dt)
		if not clone.Parent then return end
		angle += dt * 0.9
		clone:PivotTo(CFrame.Angles(0, angle, 0) * recentered)
	end)
end

-- ── Movement lock ──────────────────────────────────────────────────────────
local locked = false
local function lockMove() if not locked then locked = true; if _G["__lockMovement"] then _G["__lockMovement"]() end end end
local function unlockMove() if locked then locked = false; if _G["__unlockMovement"] then _G["__unlockMovement"]() end end end

-- ── Apply snapshot ─────────────────────────────────────────────────────────
local function applyStats(s)
	if type(s) ~= "table" then return end
	headerNick.Text = s.nick or localPlayer.DisplayName
	valTotal.Text   = fmtNum(s.totalBottles)
	local b = s.bottles or {}
	valZwykla.Text = fmtNum(b.Zwykla)
	valRzadka.Text = fmtNum(b.Rzadka)
	valEpicka.Text = fmtNum(b.Epicka)
	valLegend.Text = fmtNum(b.Legendarna)
	valMit.Text    = fmtNum(b.Mityczny)
	local pln = tonumber(s.pln) or 0
	valPln.Text    = (pln == math.floor(pln)) and (fmtNum(pln) .. " PLN") or string.format("%.2f PLN", pln)
	valKill.Text   = fmtNum(s.pvpKills)
	valAcc.Text    = fmtNum(s.accessoriesUsed)
	petNameLbl.Text = tostring(s.bestPet or "Brak")
	loadPet(s.bestPetInfo)
end

StatsData.OnClientEvent:Connect(applyStats)

-- ── Open / close ─────────────────────────────────────────────────────────────
local function openPanel()
	gui.Enabled = true
	lockMove()
	-- animacja otwierania (pop)
	panelScale.Scale = 0.7
	overlay.BackgroundTransparency = 1
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()
	StatsRequest:FireServer()
end
local function closePanel()
	clearViewport()
	gui.Enabled = false
	unlockMove()
end

statsBtn.MouseButton1Click:Connect(function() playSfx("Click"); openPanel() end)
closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); closePanel() end)
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and gui.Enabled then closePanel() end
end)

print("[StatsController] gotowy")
