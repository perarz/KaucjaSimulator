-- PetSlotShopController.client.luau
-- UI confirm dialog dla zakupu dodatkowego slotu na peta (PetSlotShopService).
-- Pattern: jak HatShop / BackpackShop — overlay + panel z opisem + ceną + KUP/ZAMKNIJ.
-- Otwiera się przez `OpenPetSlotShop`. Wynik przez `BuyPetSlotResult`.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")

local Events            = ReplicatedStorage:WaitForChild("Events")
local OpenPetSlotShop   = Events:WaitForChild("OpenPetSlotShop")
local BuyPetSlot        = Events:WaitForChild("BuyPetSlot")
local BuyPetSlotResult  = Events:WaitForChild("BuyPetSlotResult")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local FONT      = Enum.Font.GothamBlack
local C_BG      = Color3.fromRGB(18, 91, 73)
local C_PANEL   = Color3.fromRGB(24, 110, 90)
local C_HEADER  = Color3.fromRGB(0, 53, 39)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_WHITE   = Color3.new(1, 1, 1)
local C_DIM     = Color3.fromRGB(180, 200, 195)
local C_ACCENT  = Color3.fromRGB(170, 221, 102)
local C_GOLD    = Color3.fromRGB(239, 199, 95)
local C_DANGER  = Color3.fromRGB(220, 70, 70)

local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl   = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

-- ── ScreenGui scaffold ──────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "PetSlotShop"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 30
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.Parent                 = gui

local PANEL_W, PANEL_H = 480, 460

local panel = Instance.new("Frame")
panel.AnchorPoint       = Vector2.new(0.5, 0.5)
panel.Position          = UDim2.fromScale(0.5, 0.5)
panel.Size              = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3  = C_BG
panel.BorderSizePixel   = 0
panel.Parent            = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = panel
end

local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 14); fill.Position = UDim2.new(0, 0, 1, -14)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.Parent = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -76, 1, 0)
title.Position               = UDim2.fromOffset(20, 0)
title.BackgroundTransparency = 1
title.Text                   = "DODATKOWY SLOT NA PETA"
title.Font                   = FONT
title.TextSize               = 22
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.Parent                 = header

-- X-close — wspólny styl ze STATS (asset 124962493500922)
local closeBtn = Instance.new("ImageButton")
closeBtn.Size                   = UDim2.fromOffset(46, 46)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Image                  = "rbxassetid://124962493500922"
closeBtn.ScaleType              = Enum.ScaleType.Fit
closeBtn.AutoButtonColor        = false
closeBtn.Parent                 = header
do
	local sc = Instance.new("UIScale"); sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	closeBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.15 }):Play() end)
	closeBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- Body
local body = Instance.new("Frame")
body.Position               = UDim2.fromOffset(20, 84)
body.Size                   = UDim2.new(1, -40, 1, -84 - 80)  -- minus header minus przyciski u dołu
body.BackgroundTransparency = 1
body.Parent                 = panel

local descLbl = Instance.new("TextLabel")
descLbl.Size                   = UDim2.new(1, 0, 0, 90)
descLbl.Position               = UDim2.fromOffset(0, 0)
descLbl.BackgroundTransparency = 1
descLbl.Text                   = "Odblokuj 2-gi slot na peta. Możesz wyposażyć dwa pety naraz — bonusy się sumują (×kasy, +speed, +HP)."
descLbl.Font                   = FONT
descLbl.TextSize               = 16
descLbl.TextColor3             = C_DIM
descLbl.TextXAlignment         = Enum.TextXAlignment.Left
descLbl.TextYAlignment         = Enum.TextYAlignment.Top
descLbl.TextWrapped            = true
descLbl.Parent                 = body

-- Cena: zł
local costZlLbl = Instance.new("TextLabel")
costZlLbl.Position               = UDim2.fromOffset(0, 110)
costZlLbl.Size                   = UDim2.new(1, 0, 0, 30)
costZlLbl.BackgroundTransparency = 1
costZlLbl.Text                   = "Cena: — zł"
costZlLbl.Font                   = FONT
costZlLbl.TextSize               = 20
costZlLbl.TextColor3             = C_GOLD
costZlLbl.TextXAlignment         = Enum.TextXAlignment.Left
costZlLbl.Parent                 = body

-- Cena: butelki
local costBottlesLbl = Instance.new("TextLabel")
costBottlesLbl.Position               = UDim2.fromOffset(0, 144)
costBottlesLbl.Size                   = UDim2.new(1, 0, 0, 30)
costBottlesLbl.BackgroundTransparency = 1
costBottlesLbl.Text                   = "Wymaga: —"
costBottlesLbl.Font                   = FONT
costBottlesLbl.TextSize               = 16
costBottlesLbl.TextColor3             = C_ACCENT
costBottlesLbl.TextXAlignment         = Enum.TextXAlignment.Left
costBottlesLbl.Parent                 = body

-- Status (po fail/sukcesie)
local statusLbl = Instance.new("TextLabel")
statusLbl.Position               = UDim2.fromOffset(0, 180)
statusLbl.Size                   = UDim2.new(1, 0, 0, 60)
statusLbl.BackgroundTransparency = 1
statusLbl.Text                   = ""
statusLbl.Font                   = FONT
statusLbl.TextSize               = 14
statusLbl.TextColor3             = C_DANGER
statusLbl.TextXAlignment         = Enum.TextXAlignment.Left
statusLbl.TextWrapped            = true
statusLbl.Parent                 = body

-- Przycisk KUP
local buyBtn = Instance.new("TextButton")
buyBtn.AnchorPoint          = Vector2.new(0.5, 1)
buyBtn.Position             = UDim2.new(0.5, 0, 1, -20)
buyBtn.Size                 = UDim2.fromOffset(280, 56)
buyBtn.BackgroundColor3     = C_ACCENT
buyBtn.BorderSizePixel      = 0
buyBtn.Text                 = "ULEPSZ"
buyBtn.Font                 = FONT
buyBtn.TextSize             = 22
buyBtn.TextColor3           = Color3.new(0, 0, 0)
buyBtn.AutoButtonColor      = false
buyBtn.Parent               = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = buyBtn
	local sc = Instance.new("UIScale"); sc.Parent = buyBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	buyBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.05 }):Play() end)
	buyBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- ── Open/close ──────────────────────────────────────────────────────────────
local isOpen = false
local locked = false

local function lockMove()
	if not locked then
		locked = true
		if _G["__lockMovement"] then _G["__lockMovement"]() end
		if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("PETSLOT_SHOP") end
	end
end
local function unlockMove()
	if locked then
		locked = false
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
		if _G["__hudPanelClose"] then _G["__hudPanelClose"]("PETSLOT_SHOP") end
	end
end

local function setOpen(open: boolean)
	if isOpen == open then return end
	isOpen = open
	gui.Enabled = open
	if open then lockMove() else unlockMove() end
	if open then
		statusLbl.Text = ""
		panel.Size = UDim2.fromOffset(PANEL_W * 0.85, PANEL_H * 0.85)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(PANEL_W, PANEL_H) }):Play()
	end
end

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)
overlay.MouseButton1Click:Connect(function() end)  -- klik w tło NIE zamyka (jak inne sklepy)

UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and isOpen then setOpen(false) end
end)

-- ── Listeners ───────────────────────────────────────────────────────────────
OpenPetSlotShop.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	costZlLbl.Text = string.format("Cena: %d zł", payload.costZl or 0)
	-- CostBottles: { Mityczny = 10 } → "Wymaga: 10× Mityczny butelek (z EQ)"
	local parts = {}
	for rarity, count in pairs(payload.costBottles or {}) do
		table.insert(parts, string.format("%d× %s", count, rarity))
	end
	costBottlesLbl.Text = "Wymaga: " .. (table.concat(parts, ", ")) .. " (z EQ)"
	setOpen(true)
end)

buyBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	statusLbl.Text = "..."
	statusLbl.TextColor3 = C_DIM
	BuyPetSlot:FireServer()
end)

BuyPetSlotResult.OnClientEvent:Connect(function(res)
	if type(res) ~= "table" then return end
	if res.success then
		statusLbl.TextColor3 = C_ACCENT
		statusLbl.Text = string.format("Slot odblokowany! Max petów: %d", res.maxEquippedPets or 2)
		playSfx("Buy")
		task.delay(1.6, function() if isOpen then setOpen(false) end end)
	else
		statusLbl.TextColor3 = C_DANGER
		if res.reason == "tooFar" then
			statusLbl.Text = "Jesteś za daleko od NPC."
		elseif res.reason == "already" then
			statusLbl.Text = string.format("Już masz odblokowane %d sloty.", res.maxEquippedPets or 2)
		elseif res.reason == "broke" then
			statusLbl.Text = string.format("Za mało zł. Potrzeba: %d, masz: %d", res.need or 0, res.have or 0)
		elseif res.reason == "bottles" then
			statusLbl.Text = string.format("Za mało butelek. Potrzeba %d× %s (masz %d) — z EQ, nie z banku.",
				res.need or 0, tostring(res.rarity or "?"), res.have or 0)
		else
			statusLbl.Text = "Nie udało się kupić."
		end
	end
end)

print("[PetSlotShopController] gotowy")
