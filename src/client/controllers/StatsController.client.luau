-- StatsController.client.luau
-- Przycisk STATS w HUD (środek dół, po PRAWO od MENU — symetrycznie do SKLEPU) + panel
-- statystyk. Layout 3-kolumnowy (wg szkicu): lewa = zebrane butelki per rzadkość,
-- środek = nick + skin gracza, prawa = PLN / kille PVP / najlepszy pet / użyte akcesoria.
-- Dane z serwera (StatsService) przez StatsRequest/StatsData — wszystko z DataStore.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

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

-- ── Paleta ─────────────────────────────────────────────────────────────────
local FONT      = Enum.Font.GothamBlack
local C_PANEL   = Color3.fromRGB(24, 110, 90)
local C_BG      = Color3.fromRGB(18, 91, 73)
local C_CARD    = Color3.fromRGB(14, 70, 56)
local C_HEADER  = Color3.fromRGB(0, 53, 39)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_WHITE   = Color3.fromRGB(255, 255, 255)
local C_DIM     = Color3.fromRGB(178, 200, 190)
local C_ACC     = Color3.fromRGB(170, 221, 102)
local C_GOLD    = Color3.fromRGB(239, 199, 95)
local C_GREEN   = Color3.fromRGB(120, 230, 130)
local X_RED     = Color3.fromRGB(220, 70, 70)

local RARITY_COLORS = {
	Zwykla     = Color3.fromRGB(180, 180, 180),
	Rzadka     = Color3.fromRGB(55, 138, 221),
	Epicka     = Color3.fromRGB(127, 119, 221),
	Legendarna = Color3.fromRGB(239, 159, 39),
	Mityczny   = Color3.fromRGB(150, 70, 200),
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
overlay.BackgroundTransparency = 0.45
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = gui

local PANEL_W, PANEL_H = 1120, 680
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
title.Text                   = "STATYSTYKI"
title.TextSize               = 26
title.Font                   = FONT
title.TextColor3             = C_ACC
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

-- Body
local body = Instance.new("Frame")
body.Size                   = UDim2.new(1, -28, 1, -76)
body.Position               = UDim2.fromOffset(14, 66)
body.BackgroundTransparency = 1
body.BorderSizePixel        = 0
body.ZIndex                 = 3
body.Parent                 = panel

local COL_GAP = 16
local COL1_W = 330
local COL3_W = 330
local COL2_W = PANEL_W - 28 - COL1_W - COL3_W - COL_GAP * 2

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

-- Karta statystyki: etykieta (góra, mała) + wartość (duża). Zwraca value-label.
local function makeStatCard(parent: Instance, label: string, h: number, accent: Color3?): TextLabel
	local card = Instance.new("Frame")
	card.Size              = UDim2.new(1, 0, 0, h)
	card.BackgroundColor3  = C_CARD
	card.BorderSizePixel   = 0
	card.ZIndex            = 4
	card.Parent            = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = card
	local s = Instance.new("UIStroke"); s.Color = accent or C_BORDER; s.Thickness = (accent and 3 or 2); s.Parent = card

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, -24, 0, 22)
	lbl.Position               = UDim2.fromOffset(14, 10)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = label
	lbl.TextSize               = 15
	lbl.Font                   = FONT
	lbl.TextColor3             = accent or C_DIM
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.TextTruncate           = Enum.TextTruncate.AtEnd
	lbl.ZIndex                 = 5
	lbl.Parent                 = card

	local val = Instance.new("TextLabel")
	val.Size                   = UDim2.new(1, -24, 1, -36)
	val.Position               = UDim2.fromOffset(14, 32)
	val.BackgroundTransparency = 1
	val.Text                   = "0"
	val.TextSize               = 30
	val.Font                   = FONT
	val.TextColor3             = C_WHITE
	val.TextXAlignment         = Enum.TextXAlignment.Left
	val.TextYAlignment         = Enum.TextYAlignment.Center
	val.TextWrapped            = true
	val.ZIndex                 = 5
	val.Parent                 = card
	return val
end

-- ── COL1: zebrane butelki ────────────────────────────────────────────────────
do
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = col1
end
local CARD_H1 = 88  -- 6 kart × 88 + 5×10 przerw = 578 < wys. body
local valTotal   = makeStatCard(col1, "ZEBRANE BUTELKI ŁĄCZNIE", CARD_H1, C_ACC)
local valZwykla  = makeStatCard(col1, "ZEBRANE ZWYKŁE",     CARD_H1, RARITY_COLORS.Zwykla)
local valRzadka  = makeStatCard(col1, "ZEBRANE RZADKIE",    CARD_H1, RARITY_COLORS.Rzadka)
local valEpicka  = makeStatCard(col1, "ZEBRANE EPICKIE",    CARD_H1, RARITY_COLORS.Epicka)
local valLegend  = makeStatCard(col1, "ZEBRANE LEGENDARNE", CARD_H1, RARITY_COLORS.Legendarna)
local valMit     = makeStatCard(col1, "ZEBRANE MITYCZNE",   CARD_H1, RARITY_COLORS.Mityczny)

-- ── COL2: nick + skin ────────────────────────────────────────────────────────
local nickCard = Instance.new("Frame")
nickCard.Size             = UDim2.new(1, 0, 0, 88)
nickCard.BackgroundColor3 = C_CARD
nickCard.BorderSizePixel  = 0
nickCard.ZIndex           = 4
nickCard.Parent           = col2
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = nickCard
	local s = Instance.new("UIStroke"); s.Color = C_GOLD; s.Thickness = 3; s.Parent = nickCard
end
local nickLbl = Instance.new("TextLabel")
nickLbl.Size                   = UDim2.new(1, -24, 1, 0)
nickLbl.Position               = UDim2.fromOffset(12, 0)
nickLbl.BackgroundTransparency = 1
nickLbl.Text                   = localPlayer.DisplayName
nickLbl.TextSize               = 34
nickLbl.Font                   = FONT
nickLbl.TextColor3             = C_WHITE
nickLbl.TextXAlignment         = Enum.TextXAlignment.Center
nickLbl.TextScaled             = false
nickLbl.TextTruncate           = Enum.TextTruncate.AtEnd
nickLbl.ZIndex                 = 5
nickLbl.Parent                 = nickCard

local skinCard = Instance.new("Frame")
skinCard.Size             = UDim2.new(1, 0, 1, -98)
skinCard.Position         = UDim2.fromOffset(0, 98)
skinCard.BackgroundColor3 = C_BG
skinCard.BorderSizePixel  = 0
skinCard.ZIndex           = 4
skinCard.Parent           = col2
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = skinCard
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = skinCard
end
local skinImg = Instance.new("ImageLabel")
skinImg.Size                   = UDim2.fromScale(0.92, 0.92)
skinImg.AnchorPoint            = Vector2.new(0.5, 0.5)
skinImg.Position               = UDim2.fromScale(0.5, 0.5)
skinImg.BackgroundTransparency = 1
skinImg.ScaleType              = Enum.ScaleType.Fit
skinImg.Image                  = string.format("rbxthumb://type=AvatarThumbnail&w=420&h=420&id=%d", localPlayer.UserId)
skinImg.ZIndex                 = 5
skinImg.Parent                 = skinCard

-- ── COL3: PLN / kille PVP / najlepszy pet / akcesoria ────────────────────────
do
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 12); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = col3
end
local valPln     = makeStatCard(col3, "ILOŚĆ PLN", 110, C_GREEN)
valPln.TextColor3 = C_GREEN
local valKills   = makeStatCard(col3, "KILLE W STREFIE PVP", 110, X_RED)
local valBestPet = makeStatCard(col3, "NAJLEPSZY PET", 150, C_GOLD)
valBestPet.TextSize = 24
valBestPet.TextColor3 = C_GOLD
local valAcc     = makeStatCard(col3, "UŻYTE AKCESORIA", 110, Color3.fromRGB(220, 120, 90))

-- ── Movement lock ──────────────────────────────────────────────────────────
local locked = false
local function lockMove() if not locked then locked = true; if _G["__lockMovement"] then _G["__lockMovement"]() end end end
local function unlockMove() if locked then locked = false; if _G["__unlockMovement"] then _G["__unlockMovement"]() end end end

-- ── Apply snapshot ─────────────────────────────────────────────────────────
local function applyStats(s)
	if type(s) ~= "table" then return end
	nickLbl.Text   = s.nick or localPlayer.DisplayName
	valTotal.Text  = fmtNum(s.totalBottles)
	local b = s.bottles or {}
	valZwykla.Text = fmtNum(b.Zwykla)
	valRzadka.Text = fmtNum(b.Rzadka)
	valEpicka.Text = fmtNum(b.Epicka)
	valLegend.Text = fmtNum(b.Legendarna)
	valMit.Text    = fmtNum(b.Mityczny)
	-- PLN: wspiera grosze (X PLN / X.XX PLN)
	local pln = tonumber(s.pln) or 0
	valPln.Text    = (pln == math.floor(pln)) and (fmtNum(pln) .. " PLN")
		or (string.format("%.2f PLN", pln))
	valKills.Text  = fmtNum(s.pvpKills)
	valBestPet.Text = tostring(s.bestPet or "Brak")
	valAcc.Text    = fmtNum(s.accessoriesUsed)
	if s.userId then
		skinImg.Image = string.format("rbxthumb://type=AvatarThumbnail&w=420&h=420&id=%d", s.userId)
	end
end

StatsData.OnClientEvent:Connect(applyStats)

-- ── Open / close ─────────────────────────────────────────────────────────────
local function openPanel()
	gui.Enabled = true
	lockMove()
	StatsRequest:FireServer()  -- pobierz świeże dane
end
local function closePanel()
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
