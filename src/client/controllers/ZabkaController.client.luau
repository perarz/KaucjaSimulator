-- ZabkaController.client.luau
-- UI sklepu "Żabka" — split layout:
--   • lewa: ScrollingFrame z tile'ami asortymentu (na razie: Magnes)
--   • prawa: detale wybranego itemu + KUP
-- Otwierane przez ProximityPrompt z ZabkaService.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl   = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Events = ReplicatedStorage:WaitForChild("Events")
local OpenZabka            = Events:WaitForChild("OpenZabka")
local BuyZabkaMagnet       = Events:WaitForChild("BuyZabkaMagnet")
local BuyZabkaMagnetResult = Events:WaitForChild("BuyZabkaMagnetResult")
local UpdateHUD            = Events:WaitForChild("UpdateHUD")
local CollectBottleResult  = Events:WaitForChild("CollectBottleResult")
local MagnetStatusUpdate   = Events:WaitForChild("MagnetStatusUpdate")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta ────────────────────────────────────────────────────────────────
local FONT        = Enum.Font.GothamBlack
local C_BG        = Color3.fromRGB(18, 91, 73)
local C_PANEL     = Color3.fromRGB(24, 110, 90)
local C_HEADER    = Color3.fromRGB(0, 53, 39)
local C_TILE      = Color3.fromRGB(14, 75, 60)
local C_TILE_HOV  = Color3.fromRGB(20, 95, 76)
local C_TILE_SEL  = Color3.fromRGB(30, 120, 100)
local C_BORDER    = Color3.fromRGB(5, 25, 20)
local C_WHITE     = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT   = Color3.fromRGB(175, 175, 175)
local C_ACC_GREEN = Color3.fromRGB(170, 221, 102)
local C_DANGER    = Color3.fromRGB(220, 70, 70)
local X_RED       = Color3.fromRGB(220, 70, 70)
local X_RED_HOV   = Color3.fromRGB(255, 110, 110)
local C_MAGNET    = (Config.Magnet and Config.Magnet.Color) or Color3.fromRGB(220, 90, 90)

-- ── Asortyment ─────────────────────────────────────────────────────────────
-- Każdy item w formacie: { id, name, color, price, icon, getDesc(), buy() }
local MAGNET_DURATION = (Config.Magnet and Config.Magnet.DurationSec) or 120
local MAGNET_RADMUL   = (Config.Magnet and Config.Magnet.RadiusMultiplier) or 1.5
local MAGNET_COST     = (Config.Zabka and Config.Zabka.MagnetCost) or 1000

local items = {
	{
		id    = "magnet",
		name  = "Magnes",
		color = C_MAGNET,
		price = MAGNET_COST,
		icon  = "🧲",
		desc  = string.format(
			"Aktywuj, by przez %d sekund automatycznie zbierać wszystkie butelki w zwiększonym promieniu (×%.1f). Każdy magnes zajmuje 1 slot w plecaku.",
			MAGNET_DURATION, MAGNET_RADMUL),
		buy   = function() BuyZabkaMagnet:FireServer() end,
	},
}

-- ── Stan ───────────────────────────────────────────────────────────────────
local pData = {
	Zlotowki         = 0,
	BackpackContents = { Zwykla=0, Rzadka=0, Epicka=0, Legendarna=0, Mityczny=0 },
	BackpackCapacity = Config.BackpackUpgrades[1].Capacity,
	HasSyrup         = false,
}
local selectedId: string = items[1].id

local function getMagnetCount(): number
	local m = _G["__magnetState"]
	return (m and tonumber(m.count)) or 0
end

local function getCarried(): number
	local n = 0
	for _, c in pairs(pData.BackpackContents) do n += c end
	if pData.HasSyrup then n += 1 end
	n += getMagnetCount()
	return n
end

local function readLeaderstats()
	local ls = localPlayer:FindFirstChild("leaderstats")
	if ls then
		local zl = ls:FindFirstChild("Zlotowki")
		if zl then pData.Zlotowki = zl.Value end
	end
end
readLeaderstats()

-- ── Wymiary ────────────────────────────────────────────────────────────────
local PANEL_W    = 760
local PANEL_H    = 520
local HEADER_H   = 52
local PAD        = 18
local GAP        = 14
local LIST_W     = 280
local TILE_H     = 84
local TILE_GAP   = 10

-- ── ScreenGui ──────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "ZabkaShop"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 55
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

local panel = Instance.new("Frame")
panel.Size                  = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint           = Vector2.new(0.5, 0.5)
panel.Position              = UDim2.new(0.5, 0, 0.55, 0)
panel.BackgroundColor3      = C_PANEL
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel       = 0
panel.ZIndex                = 2
panel.Parent                = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = panel
end

-- ── Header ─────────────────────────────────────────────────────────────────
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 10); fill.Position = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = header
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER; sep.BorderSizePixel = 0; sep.ZIndex = 5; sep.Parent = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -56, 1, 0)
title.Position               = UDim2.fromOffset(22, 0)
title.BackgroundTransparency = 1
title.Text                   = "ŻABKA"
title.TextSize               = 22
title.Font                   = FONT
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

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
closeBtn.Parent                 = header
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play(); closeBtn.TextColor3 = X_RED_HOV
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1 }):Play(); closeBtn.TextColor3 = X_RED
	end)
end

-- ── LEWA: ScrollingFrame z asortymentem ────────────────────────────────────
local listFrame = Instance.new("ScrollingFrame")
listFrame.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD)
listFrame.Size                   = UDim2.new(0, LIST_W, 1, -HEADER_H - PAD * 2)
listFrame.BackgroundColor3       = C_BG
listFrame.BackgroundTransparency = 0.1
listFrame.BorderSizePixel        = 0
listFrame.ScrollBarThickness     = 6
listFrame.ScrollBarImageColor3   = C_BORDER
listFrame.CanvasSize             = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize    = Enum.AutomaticSize.Y
listFrame.ZIndex                 = 3
listFrame.Parent                 = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = listFrame
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = listFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft   = UDim.new(0, 10)
	pad.PaddingRight  = UDim.new(0, 10)
	pad.Parent        = listFrame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection       = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder           = Enum.SortOrder.LayoutOrder
	layout.Padding             = UDim.new(0, TILE_GAP)
	layout.Parent              = listFrame
end

-- ── PRAWA: detail panel ────────────────────────────────────────────────────
local detail = Instance.new("Frame")
detail.Position              = UDim2.fromOffset(PAD + LIST_W + GAP, HEADER_H + PAD)
detail.Size                  = UDim2.new(1, -PAD * 2 - LIST_W - GAP, 1, -HEADER_H - PAD * 2)
detail.BackgroundColor3      = C_BG
detail.BackgroundTransparency = 0.05
detail.BorderSizePixel       = 0
detail.ZIndex                = 3
detail.Parent                = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = detail
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = detail
end

-- Detail: ikona + nazwa
local detIcon = Instance.new("TextLabel")
detIcon.Size                   = UDim2.fromOffset(80, 80)
detIcon.Position               = UDim2.fromOffset(20, 20)
detIcon.BackgroundTransparency = 1
detIcon.Text                   = ""
detIcon.Font                   = FONT
detIcon.TextSize               = 56
detIcon.TextColor3             = C_WHITE
detIcon.TextXAlignment         = Enum.TextXAlignment.Center
detIcon.ZIndex                 = 4
detIcon.Parent                 = detail

local detName = Instance.new("TextLabel")
detName.Size                   = UDim2.new(1, -120, 0, 36)
detName.Position               = UDim2.fromOffset(108, 28)
detName.BackgroundTransparency = 1
detName.Text                   = ""
detName.Font                   = FONT
detName.TextSize               = 28
detName.TextColor3             = C_WHITE
detName.TextXAlignment         = Enum.TextXAlignment.Left
detName.ZIndex                 = 4
detName.Parent                 = detail

local detPrice = Instance.new("TextLabel")
detPrice.Size                   = UDim2.new(1, -120, 0, 24)
detPrice.Position               = UDim2.fromOffset(108, 64)
detPrice.BackgroundTransparency = 1
detPrice.Text                   = ""
detPrice.Font                   = FONT
detPrice.TextSize               = 18
detPrice.TextColor3             = C_ACC_GREEN
detPrice.TextXAlignment         = Enum.TextXAlignment.Left
detPrice.ZIndex                 = 4
detPrice.Parent                 = detail

-- Separator
do
	local sep = Instance.new("Frame")
	sep.Size               = UDim2.new(1, -32, 0, 2)
	sep.Position           = UDim2.fromOffset(16, 116)
	sep.BackgroundColor3   = C_BORDER
	sep.BorderSizePixel    = 0
	sep.ZIndex             = 4
	sep.Parent             = detail
end

-- Opis (długi)
local detDesc = Instance.new("TextLabel")
detDesc.Size                   = UDim2.new(1, -32, 0, 130)
detDesc.Position               = UDim2.fromOffset(16, 128)
detDesc.BackgroundTransparency = 1
detDesc.Text                   = ""
detDesc.Font                   = FONT
detDesc.TextSize               = 15
detDesc.TextColor3             = C_DIMTEXT
detDesc.TextWrapped            = true
detDesc.TextXAlignment         = Enum.TextXAlignment.Left
detDesc.TextYAlignment         = Enum.TextYAlignment.Top
detDesc.ZIndex                 = 4
detDesc.Parent                 = detail

-- Info: saldo + miejsce w plecaku
local detInfo = Instance.new("TextLabel")
detInfo.Size                   = UDim2.new(1, -32, 0, 22)
detInfo.AnchorPoint            = Vector2.new(0, 1)
detInfo.Position               = UDim2.new(0, 16, 1, -110)
detInfo.BackgroundTransparency = 1
detInfo.Text                   = ""
detInfo.Font                   = FONT
detInfo.TextSize               = 14
detInfo.TextColor3             = C_DIMTEXT
detInfo.TextXAlignment         = Enum.TextXAlignment.Left
detInfo.ZIndex                 = 4
detInfo.Parent                 = detail

-- Status (komunikat)
local detStatus = Instance.new("TextLabel")
detStatus.Size                   = UDim2.new(1, -32, 0, 22)
detStatus.AnchorPoint            = Vector2.new(0, 1)
detStatus.Position               = UDim2.new(0, 16, 1, -84)
detStatus.BackgroundTransparency = 1
detStatus.Text                   = ""
detStatus.Font                   = FONT
detStatus.TextSize               = 14
detStatus.TextColor3             = C_DIMTEXT
detStatus.TextXAlignment         = Enum.TextXAlignment.Left
detStatus.ZIndex                 = 4
detStatus.Parent                 = detail

-- KUP button (na dole detail)
local buyBtn = Instance.new("TextButton")
buyBtn.Size                   = UDim2.new(1, -32, 0, 56)
buyBtn.AnchorPoint            = Vector2.new(0, 1)
buyBtn.Position               = UDim2.new(0, 16, 1, -16)
buyBtn.BackgroundColor3       = C_ACC_GREEN
buyBtn.BorderSizePixel        = 0
buyBtn.Text                   = "KUP"
buyBtn.TextSize               = 22
buyBtn.Font                   = FONT
buyBtn.TextColor3             = Color3.fromRGB(0, 0, 0)
buyBtn.AutoButtonColor        = false
buyBtn.ZIndex                 = 4
buyBtn.Parent                 = detail
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = buyBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	buyBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.03 }):Play() end)
	buyBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- ── Tile factory ──────────────────────────────────────────────────────────
local tileRefs: { [string]: { frame: Frame, stroke: UIStroke } } = {}

local function getItem(id: string)
	for _, it in ipairs(items) do
		if it.id == id then return it end
	end
	return nil
end

local function setSelected(id: string)
	selectedId = id
	for tid, ref in pairs(tileRefs) do
		if tid == id then
			ref.frame.BackgroundColor3 = C_TILE_SEL
			ref.stroke.Color = C_ACC_GREEN
			ref.stroke.Thickness = 3
		else
			ref.frame.BackgroundColor3 = C_TILE
			ref.stroke.Color = C_BORDER
			ref.stroke.Thickness = 2
		end
	end
	-- forward declare; refresh defined below
	if _G["__zabkaRefresh"] then _G["__zabkaRefresh"]() end
end

local function makeTile(it, order: number)
	local frame = Instance.new("TextButton")
	frame.Size                   = UDim2.new(1, 0, 0, TILE_H)
	frame.BackgroundColor3       = C_TILE
	frame.BorderSizePixel        = 0
	frame.AutoButtonColor        = false
	frame.Text                   = ""
	frame.LayoutOrder            = order
	frame.ZIndex                 = 4
	frame.Parent                 = listFrame
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = frame

	local iconLbl = Instance.new("TextLabel")
	iconLbl.Size                   = UDim2.fromOffset(56, TILE_H)
	iconLbl.Position               = UDim2.fromOffset(8, 0)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Text                   = it.icon or "?"
	iconLbl.Font                   = FONT
	iconLbl.TextSize               = 36
	iconLbl.TextColor3             = it.color
	iconLbl.ZIndex                 = 5
	iconLbl.Parent                 = frame

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size                   = UDim2.new(1, -76, 0, 26)
	nameLbl.Position               = UDim2.fromOffset(70, 14)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text                   = it.name
	nameLbl.Font                   = FONT
	nameLbl.TextSize               = 18
	nameLbl.TextColor3             = C_WHITE
	nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
	nameLbl.ZIndex                 = 5
	nameLbl.Parent                 = frame

	local priceLbl = Instance.new("TextLabel")
	priceLbl.Size                   = UDim2.new(1, -76, 0, 22)
	priceLbl.Position               = UDim2.fromOffset(70, 42)
	priceLbl.BackgroundTransparency = 1
	priceLbl.Text                   = tostring(it.price) .. " ZŁ"
	priceLbl.Font                   = FONT
	priceLbl.TextSize               = 15
	priceLbl.TextColor3             = C_ACC_GREEN
	priceLbl.TextXAlignment         = Enum.TextXAlignment.Left
	priceLbl.ZIndex                 = 5
	priceLbl.Parent                 = frame

	tileRefs[it.id] = { frame = frame, stroke = s }

	frame.MouseEnter:Connect(function()
		if selectedId ~= it.id then frame.BackgroundColor3 = C_TILE_HOV end
	end)
	frame.MouseLeave:Connect(function()
		if selectedId ~= it.id then frame.BackgroundColor3 = C_TILE end
	end)
	frame.MouseButton1Click:Connect(function()
		playSfx("Click")
		setSelected(it.id)
	end)

	return frame
end

for i, it in ipairs(items) do makeTile(it, i) end

-- ── Refresh detail panel ──────────────────────────────────────────────────
local function refresh()
	local it = getItem(selectedId)
	if not it then return end

	detIcon.Text     = it.icon or ""
	detIcon.TextColor3 = it.color
	detName.Text     = it.name
	detName.TextColor3 = it.color
	detPrice.Text    = string.format("Cena: %d ZŁ", it.price)
	detDesc.Text     = it.desc or ""

	local zl       = pData.Zlotowki or 0
	local carried  = getCarried()
	local capacity = pData.BackpackCapacity
	local canAfford = zl >= it.price
	local hasSpace  = carried < capacity

	detInfo.Text = string.format(
		"Twoje saldo: %d ZŁ    •    Plecak: %d/%d",
		math.floor(zl), carried, capacity)

	if not canAfford then
		detStatus.Text = "Za mało złotówek."
		detStatus.TextColor3 = C_DANGER
		buyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		buyBtn.Active = true  -- pozwalamy klik, server odrzuci
	elseif not hasSpace then
		detStatus.Text = "Plecak pełny — opróżnij w butelkomacie."
		detStatus.TextColor3 = C_DANGER
		buyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		buyBtn.Active = true
	else
		detStatus.Text = "Wszystko gotowe — kliknij KUP!"
		detStatus.TextColor3 = C_ACC_GREEN
		buyBtn.BackgroundColor3 = C_ACC_GREEN
		buyBtn.Active = true
	end
	buyBtn.Text = "KUP"
end
_G["__zabkaRefresh"] = refresh

setSelected(items[1].id)

-- ── Open / close ──────────────────────────────────────────────────────────
local POS_SHOW = UDim2.new(0.5, 0, 0.5, 0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local TW_OPEN  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TW_CLOSE = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local isOpen   = false

local function setOpen(open: boolean)
	isOpen = open
	if open then
		readLeaderstats()
		detStatus.Text = ""
		refresh()
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		gui.Enabled = true
		panel.Position = POS_HIDE
		overlay.BackgroundTransparency = 1
		TweenService:Create(panel, TW_OPEN, { Position = POS_SHOW }):Play()
		TweenService:Create(overlay, TW_OPEN, { BackgroundTransparency = 0.35 }):Play()
	else
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		TweenService:Create(panel, TW_CLOSE, { Position = POS_HIDE }):Play()
		local tw = TweenService:Create(overlay, TW_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function() if not isOpen then gui.Enabled = false end end)
		tw:Play()
	end
end

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)

UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)

buyBtn.MouseButton1Click:Connect(function()
	if not buyBtn.Active then return end
	local it = getItem(selectedId)
	if not it then return end
	playSfx("Click")
	if it.buy then it.buy() end
end)

-- ── Eventy ────────────────────────────────────────────────────────────────
OpenZabka.OnClientEvent:Connect(function()
	print("[ZabkaController] OpenZabka odebrane — otwieram sklep")
	setOpen(true)
end)
print("[ZabkaController] gotowy, listener OpenZabka podpięty")

BuyZabkaMagnetResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	if result.success then
		playSfx("Buy")
		refresh()
		detStatus.Text = "Kupiono! Znajdziesz przedmiot w ekwipunku."
		detStatus.TextColor3 = C_ACC_GREEN
	else
		local msg = "Nie udało się kupić."
		if result.reason == "broke" then msg = "Za mało złotówek."
		elseif result.reason == "full" then msg = "Plecak pełny — opróżnij w butelkomacie."
		end
		detStatus.Text = msg
		detStatus.TextColor3 = C_DANGER
	end
end)

-- Sync z UpdateHUD (zmiana backpackContents/pojemność)
UpdateHUD.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.backpackContents then pData.BackpackContents = data.backpackContents end
	if data.backpackCapacity then pData.BackpackCapacity = data.backpackCapacity end
	if data.hasSyrup ~= nil    then pData.HasSyrup        = data.hasSyrup end
	if isOpen then refresh() end
end)

-- Zbieranie butelki nie wysyła UpdateHUD — łapiemy CollectBottleResult
CollectBottleResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or not result.success then return end
	local r = result.rarity
	if type(r) ~= "string" then return end
	pData.BackpackContents[r] = (pData.BackpackContents[r] or 0) + 1
	if isOpen then refresh() end
end)

-- Magnes się zmienia (count) — przelicz capacity
MagnetStatusUpdate.OnClientEvent:Connect(function()
	if isOpen then refresh() end
end)

-- Saldo
local function watchLeaderstats()
	local ls = localPlayer:FindFirstChild("leaderstats") or localPlayer:WaitForChild("leaderstats", 5)
	if not ls then return end
	local zl = ls:FindFirstChild("Zlotowki") or ls:WaitForChild("Zlotowki", 5)
	if not zl then return end
	zl.Changed:Connect(function(v)
		pData.Zlotowki = v
		if isOpen then refresh() end
	end)
end
task.spawn(watchLeaderstats)
