-- TeleportController.client.luau
-- Przycisk teleportacji w HUD (pod przyciskiem deski) → GUI z listą lokalizacji.
-- Klik lokalizacji → TeleportTo:FireServer(key); serwer przenosi do partu o tej nazwie.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Events          = ReplicatedStorage:WaitForChild("Events")
local TeleportTo      = Events:WaitForChild("TeleportTo")
local ZoneOwnedUpdate = Events:WaitForChild("ZoneOwnedUpdate")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- Strefy posiadane przez gracza (sync z ZoneEntryService) — do gatingu teleportu (Pustynia).
local ownedZones: { [string]: boolean } = {}
ZoneOwnedUpdate.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then return end
	ownedZones = {}
	for k, v in pairs(snapshot) do
		if v then ownedZones[k] = true end
	end
end)

local cfg       = Config.Teleport or {}
local LOCATIONS = cfg.Locations or {}
local ICON_ID   = cfg.IconId or "rbxassetid://70773777562362"

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
local FONT      = Enum.Font.GothamBold
local C_PANEL   = Color3.fromRGB(24, 110, 90)
local C_HEADER  = Color3.fromRGB(0, 53, 39)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_BTN     = Color3.fromRGB(18, 91, 73)
local C_WHITE   = Color3.fromRGB(245, 250, 247)
local C_ACC     = Color3.fromRGB(170, 221, 102)
local X_RED     = Color3.fromRGB(225, 80, 80)

-- ── HUD button (pod deską) ───────────────────────────────────────────────────
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "TeleportHud"
hudGui.ResetOnSpawn   = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder   = 10  -- pod wszystkimi panelami; shared HUD lock dim'uje btn pod overlay'em
hudGui.Parent         = playerGui

local tpBtn = Instance.new("ImageButton")
tpBtn.Name                   = "TeleportButton"
tpBtn.AnchorPoint            = Vector2.new(0, 0.5)
tpBtn.Position               = UDim2.new(0, 16, 0.5, 0)  -- lewa strona; stos: deska / teleport / wymiana
tpBtn.Size                   = UDim2.fromOffset(156, 156)
tpBtn.BackgroundTransparency = 1
tpBtn.BorderSizePixel        = 0
tpBtn.Image                  = ICON_ID
tpBtn.ScaleType              = Enum.ScaleType.Fit
tpBtn.AutoButtonColor        = false
tpBtn.Parent                 = hudGui
do
	-- Hover przez Size (nie UIScale) — by responsywny __MobileUIScale działał na przycisku
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
	local baseSize = UDim2.fromOffset(156, 156)
	local hoverSize = UDim2.fromOffset(175, 175)
	tpBtn.MouseEnter:Connect(function()
		TweenService:Create(tpBtn, ti, { Size = hoverSize, Rotation = -6 }):Play()
	end)
	tpBtn.MouseLeave:Connect(function()
		TweenService:Create(tpBtn, ti, { Size = baseSize, Rotation = 0 }):Play()
	end)
end

-- ── Panel z lokalizacjami ─────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "TeleportPanel"
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

local BTN_H, BTN_GAP = 54, 10
local HEADER_H = 56
local PANEL_W = 380
local PANEL_H = HEADER_H + 16 + (#LOCATIONS * BTN_H) + ((#LOCATIONS - 1) * BTN_GAP) + 16

local panel = Instance.new("Frame")
panel.Size             = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = C_PANEL
panel.BorderSizePixel  = 0
panel.ZIndex           = 2
panel.Parent           = gui
-- brak własnego UIScale na panelu (MobileScaleController dokłada responsywny; dwa się gryzą)
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = panel
end

local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 12); fill.Position = UDim2.new(0, 0, 1, -12)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -56, 1, 0)
title.Position               = UDim2.fromOffset(20, 0)
title.BackgroundTransparency = 1
title.Text                   = "TELEPORTACJA"
title.TextSize               = 24
title.Font                   = FONT
title.TextColor3             = C_ACC
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

-- X-close — wspólny styl ze STATS
local closeBtn = Instance.new("ImageButton")
closeBtn.Size                   = UDim2.fromOffset(46, 46)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Image                  = "rbxassetid://124962493500922"
closeBtn.ScaleType              = Enum.ScaleType.Fit
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 4
closeBtn.Parent                 = header
do
	local sc = Instance.new("UIScale"); sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	closeBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.15 }):Play() end)
	closeBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
end

-- Lista przycisków
local list = Instance.new("Frame")
list.Size                   = UDim2.new(1, -32, 1, -(HEADER_H + 24))
list.Position               = UDim2.fromOffset(16, HEADER_H + 12)
list.BackgroundTransparency = 1
list.BorderSizePixel        = 0
list.ZIndex                 = 3
list.Parent                 = panel
do
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, BTN_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
end

-- Toast (komunikat o zablokowanej lokalizacji, np. brak kupionej Pustyni).
-- Plain text, bez neonowego obrysu; wyświetlany wysoko (tuż pod headerem panelu).
local toast = Instance.new("TextLabel")
toast.AnchorPoint            = Vector2.new(0.5, 0)
toast.Position               = UDim2.new(0.5, 0, 0, HEADER_H + 8)
toast.Size                   = UDim2.new(1, -24, 0, 44)
toast.BackgroundTransparency = 1
toast.BorderSizePixel        = 0
toast.Text                   = ""
toast.TextWrapped            = true
toast.TextSize               = 17
toast.Font                   = FONT
toast.TextColor3             = X_RED
toast.Visible                = false
toast.ZIndex                 = 8
toast.Parent                 = panel
local toastToken = 0
local function showToast(msg: string)
	toast.Text = msg
	toast.Visible = true
	toastToken += 1
	local my = toastToken
	task.delay(2.5, function() if toastToken == my then toast.Visible = false end end)
end

-- ── Movement lock ──────────────────────────────────────────────────────────
local locked = false
local function lockMove() if not locked then locked = true; if _G["__lockMovement"] then _G["__lockMovement"]() end end end
local function unlockMove() if locked then locked = false; if _G["__unlockMovement"] then _G["__unlockMovement"]() end end end

-- Rejestracja w shared HUD-lock (MENU/SKLEP/STATS/DESKA/TELEPORT)
_G["__hudBtnRegistry"] = _G["__hudBtnRegistry"] or {}
_G["__hudBtnRegistry"]["TELEPORT"] = tpBtn
if _G["__hudRegisterBtn"] then _G["__hudRegisterBtn"]("TELEPORT", tpBtn) end

local resetHover  -- forward declaration (definicja po zbudowaniu przycisków)

local function closePanel()
	gui.Enabled = false
	unlockMove()
	if _G["__hudPanelClose"] then _G["__hudPanelClose"]("TELEPORT") end
end

local function openPanel()
	gui.Enabled = true
	lockMove()
	if resetHover then resetHover() end  -- świeży stan przycisków (bez przyklejonego hovera)
	toast.Visible = false
	if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("TELEPORT") end
	panel.Size = UDim2.fromOffset(PANEL_W * 0.85, PANEL_H * 0.85)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(PANEL_W, PANEL_H) }):Play()
end

-- Buduj przyciski lokalizacji. Trzymamy referencje (btn/stroke/scale) żeby zresetować
-- stan hover przy każdym otwarciu — inaczej klik+zamknięcie zostawia podświetlenie na zielono
-- (MouseLeave nie odpala bo panel znika spod kursora).
local btnEntries: { { stroke: UIStroke, scale: UIScale } } = {}

for i, loc in ipairs(LOCATIONS) do
	local b = Instance.new("TextButton")
	b.Size                   = UDim2.new(1, 0, 0, BTN_H)
	b.BackgroundColor3       = C_BTN
	b.BorderSizePixel        = 0
	b.AutoButtonColor        = false
	b.Text                   = loc.label or loc.key
	b.TextSize               = 22
	b.Font                   = FONT
	b.TextColor3             = C_WHITE
	b.LayoutOrder            = i
	b.ZIndex                 = 4
	b.Parent                 = list
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = b
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = b
	local sc = Instance.new("UIScale"); sc.Parent = b
	table.insert(btnEntries, { stroke = s, scale = sc })
	local ti = TweenInfo.new(0.1)
	b.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.03 }):Play()
		TweenService:Create(s, ti, { Color = C_ACC }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
		TweenService:Create(s, ti, { Color = C_BORDER }):Play()
	end)
	b.MouseButton1Click:Connect(function()
		playSfx("Click")
		-- Gating strefowy — np. Pustynia wymaga kupionej strefy.
		if loc.requiresZone and not ownedZones[loc.requiresZone] then
			showToast(loc.lockedMsg or ("Musisz najpierw odblokować: " .. (loc.label or loc.key)))
			return
		end
		TeleportTo:FireServer(loc.key)
		closePanel()
	end)
end

-- Reset stanu hover wszystkich przycisków do bazowego (wywoływane przy otwarciu panelu).
function resetHover()
	for _, e in ipairs(btnEntries) do
		e.scale.Scale  = 1.0
		e.stroke.Color = C_BORDER
	end
end

-- ── Wiring ───────────────────────────────────────────────────────────────────
tpBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	if gui.Enabled then closePanel() else openPanel() end
end)
closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); closePanel() end)
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and gui.Enabled then closePanel() end
end)

print("[TeleportController] gotowy —", #LOCATIONS, "lokalizacji")
