-- TeleportController.client.luau
-- Przycisk teleportacji w HUD (pod przyciskiem deski) → GUI z listą lokalizacji.
-- Klik lokalizacji → TeleportTo:FireServer(key); serwer przenosi do partu o tej nazwie.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Events     = ReplicatedStorage:WaitForChild("Events")
local TeleportTo = Events:WaitForChild("TeleportTo")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

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
hudGui.DisplayOrder   = 25
hudGui.Parent         = playerGui

local tpBtn = Instance.new("ImageButton")
tpBtn.Name                   = "TeleportButton"
tpBtn.AnchorPoint            = Vector2.new(0, 0.5)
tpBtn.Position               = UDim2.new(0, 16, 0.35, 309)  -- pod hoverboard (deska) button
tpBtn.Size                   = UDim2.fromOffset(135, 135)
tpBtn.BackgroundTransparency = 1
tpBtn.BorderSizePixel        = 0
tpBtn.Image                  = ICON_ID
tpBtn.ScaleType              = Enum.ScaleType.Fit
tpBtn.AutoButtonColor        = false
tpBtn.Parent                 = hudGui
do
	local sc = Instance.new("UIScale"); sc.Parent = tpBtn
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
	tpBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.12 }):Play()
		TweenService:Create(tpBtn, ti, { Rotation = -6 }):Play()
	end)
	tpBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.0 }):Play()
		TweenService:Create(tpBtn, ti, { Rotation = 0 }):Play()
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
local panelScale = Instance.new("UIScale"); panelScale.Parent = panel
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

local closeBtn = Instance.new("TextButton")
closeBtn.Size                   = UDim2.fromOffset(40, 40)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "✕"
closeBtn.TextSize               = 26
closeBtn.Font                   = FONT
closeBtn.TextColor3             = X_RED
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 4
closeBtn.Parent                 = header

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

-- ── Movement lock ──────────────────────────────────────────────────────────
local locked = false
local function lockMove() if not locked then locked = true; if _G["__lockMovement"] then _G["__lockMovement"]() end end end
local function unlockMove() if locked then locked = false; if _G["__unlockMovement"] then _G["__unlockMovement"]() end end end

local function closePanel()
	gui.Enabled = false
	unlockMove()
end

local function openPanel()
	gui.Enabled = true
	lockMove()
	panelScale.Scale = 0.8
	TweenService:Create(panelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Buduj przyciski lokalizacji
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
		TeleportTo:FireServer(loc.key)
		closePanel()
	end)
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
