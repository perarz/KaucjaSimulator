-- BankController.client.luau
-- Standalone GUI banku. Otwiera się po E przy Bankierze — od razu split-view SKARBIEC/EKWIPUNEK.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

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

-- Movement lock — ref-counted, współdzielony między UI (Bank/Shop/Quest/DeckShop/Kosz).
-- Pierwszy ładujący się kontroler definiuje, reszta tylko wywołuje.
if not _G["__lockMovement"] then
	local controls
	task.spawn(function()
		local lp = Players.LocalPlayer
		local ok, pm = pcall(function()
			return require(lp:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		end)
		if ok and pm then controls = pm:GetControls() end
	end)
	_G["__moveLockCount"] = 0
	_G["__lockMovement"] = function()
		_G["__moveLockCount"] = (_G["__moveLockCount"] or 0) + 1
		if controls then controls:Disable() end
	end
	_G["__unlockMovement"] = function()
		_G["__moveLockCount"] = math.max(0, (_G["__moveLockCount"] or 0) - 1)
		if controls and _G["__moveLockCount"] == 0 then controls:Enable() end
	end
end

local Config      = require(ReplicatedStorage:WaitForChild("Config"))
local Events      = ReplicatedStorage:WaitForChild("Events")
local BankInit    = Events:WaitForChild("BankInit")
local BankDeposit = Events:WaitForChild("BankDeposit")
local BankWithdraw= Events:WaitForChild("BankWithdraw")
local BankResult  = Events:WaitForChild("BankResult")
local UpdateHUD   = Events:WaitForChild("UpdateHUD")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta ────────────────────────────────────────────────────────────────────
local C_BG           = Color3.fromRGB(18, 91, 73)
local C_PANEL        = Color3.fromRGB(24, 110, 90)
local C_HEADER       = Color3.fromRGB(0, 53, 39)
local C_SLOT         = Color3.fromRGB(8, 60, 48)
local C_SLOT_HOV     = Color3.fromRGB(14, 75, 60)
local C_BORDER       = Color3.fromRGB(5, 25, 20)
local C_BORDER_SL    = Color3.fromRGB(8, 30, 24)
local C_WHITE        = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT      = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)
local C_CONFIRM      = Color3.fromRGB(28, 115, 58)
local X_RED          = Color3.fromRGB(220, 70, 70)
local X_RED_HOV      = Color3.fromRGB(255, 110, 110)
local FONT_MAIN      = Enum.Font.GothamBlack

local RARITY_ORDER  = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }
local RARITY_COLORS = Config.BottleColors

-- ── Wymiary ───────────────────────────────────────────────────────────────────
local SLOT_B       = 78
local GAP_B        = 14
local COLS_B       = 5     -- 5 kolumn (jak główny ekwipunek)
local SLOT_COUNT_B = 15    -- 15 slotów na sztywno (jak ekwipunek) — split layout nie ginie
local MAX_VIS_ROWS = 3     -- 3 rzędy widoczne (jak ekwipunek)
local SLOTS_W_B    = COLS_B * SLOT_B + (COLS_B - 1) * GAP_B
local VIS_H_B      = MAX_VIS_ROWS * SLOT_B + (MAX_VIS_ROWS - 1) * GAP_B
local INNER_PAD    = 16
local INNER_HDR_H  = 46
local INNER_W      = SLOTS_W_B + INNER_PAD * 2
local INNER_H      = INNER_HDR_H + VIS_H_B + INNER_PAD * 2
local DIV_W        = 60
local TR_PAD       = 20   -- padding zewnętrzny panelu
local TR_HEADER_H  = 56
local TR_BTM_GAP   = 22   -- odstęp między panelami a przyciskami
local TR_BOTTOM_H  = 78
local TR_W         = INNER_W * 2 + DIV_W + TR_PAD * 2
local TR_H         = TR_HEADER_H + TR_PAD + INNER_H + TR_BTM_GAP + TR_BOTTOM_H + TR_PAD

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function mkFrame(parent, size, pos, bg, alpha)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos
	f.BackgroundColor3 = bg or C_BG
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel = 0; f.Parent = parent
	return f
end

local function mkLabel(parent, size, pos, text, ts, color, xAlign)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = color or C_WHITE; l.TextSize = ts or 14
	l.Font = FONT_MAIN; l.Text = text or ""
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.BorderSizePixel = 0; l.Parent = parent
	return l
end

local function mkCorner(parent, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = parent
end

local function mkStroke(parent, color, th)
	local s = Instance.new("UIStroke")
	s.Color = color or C_BORDER; s.Thickness = th or 4
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = parent
end

local function darken(c: Color3, m: number): Color3
	return Color3.new(c.R * (1 - m), c.G * (1 - m), c.B * (1 - m))
end

local TI_HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function attachHover(btn: TextButton, scl: number)
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = btn
	btn.MouseEnter:Connect(function() TweenService:Create(sc, TI_HOVER, { Scale = scl or 1.06 }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(sc, TI_HOVER, { Scale = 1 }):Play() end)
end

local function mkInnerHeader(parent, w, h, label)
	local ih = mkFrame(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(0, 0), C_HEADER, 0)
	ih.ZIndex = 4; mkCorner(ih, 8)
	mkFrame(ih, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10), C_HEADER, 0).ZIndex = 4
	mkFrame(ih, UDim2.new(1, 0, 0, 2),  UDim2.new(0, 0, 1,  -2), C_BORDER, 0).ZIndex = 6
	local lbl = mkLabel(ih, UDim2.new(1, 0, 1, 0), UDim2.fromOffset(0, 0),
		label, 15, C_ACCENT_GREEN, Enum.TextXAlignment.Center)
	lbl.ZIndex = 5
end

-- Forward
local closeBank
local lockedPanel: Frame? = nil

-- ── ScreenGui ─────────────────────────────────────────────────────────────────
local bankGui = Instance.new("ScreenGui")
bankGui.Name           = "BankGui"
bankGui.ResetOnSpawn   = false
bankGui.IgnoreGuiInset = true
bankGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
bankGui.DisplayOrder   = 50
bankGui.Enabled        = false
bankGui.Parent         = playerGui

local dimOverlay = Instance.new("TextButton")
dimOverlay.Size                   = UDim2.fromScale(1, 1)
dimOverlay.BackgroundColor3       = Color3.new(0, 0, 0)
dimOverlay.BackgroundTransparency = 1
dimOverlay.BorderSizePixel        = 0
dimOverlay.Text                   = ""
dimOverlay.AutoButtonColor        = false
dimOverlay.ZIndex                 = 1
dimOverlay.Parent                 = bankGui

-- ── Główny panel (split-view) ─────────────────────────────────────────────────
local trPanel = mkFrame(bankGui,
	UDim2.fromOffset(TR_W, TR_H),
	UDim2.new(0.5, 0, 0.5, 0),
	C_PANEL, 0.05)
trPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
trPanel.ZIndex           = 2
trPanel.ClipsDescendants = true
trPanel.Visible          = false
mkStroke(trPanel, C_BORDER, 4); mkCorner(trPanel, 8)

-- Header z tytułem i X
do
	local hdr = mkFrame(trPanel,
		UDim2.fromOffset(TR_W, TR_HEADER_H),
		UDim2.fromOffset(0, 0), C_HEADER, 0)
	hdr.ZIndex = 3; mkCorner(hdr, 8)
	mkFrame(hdr, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10), C_HEADER, 0).ZIndex = 3
	mkFrame(hdr, UDim2.new(1, 0, 0, 2),  UDim2.new(0, 0, 1,  -2), C_BORDER, 0).ZIndex = 5
	mkLabel(hdr, UDim2.new(1, -56, 1, 0), UDim2.fromOffset(0, 0),
		"BANK KAUCYJNY", 18, C_WHITE, Enum.TextXAlignment.Center).ZIndex = 4

	-- Counter SKARBIEC X/10 — pod tytułem po lewej
	local _ = nil  -- placeholder; counter zostanie utworzony niżej i przypięty do bankInner

	local xBtn = Instance.new("TextButton")
	xBtn.Size = UDim2.fromOffset(36, 36); xBtn.AnchorPoint = Vector2.new(1, 0.5)
	xBtn.Position = UDim2.new(1, -12, 0.5, 0)
	xBtn.BackgroundTransparency = 1; xBtn.BorderSizePixel = 0
	xBtn.Text = "X"; xBtn.TextSize = 22; xBtn.Font = FONT_MAIN
	xBtn.TextColor3 = X_RED; xBtn.AutoButtonColor = false; xBtn.ZIndex = 6; xBtn.Parent = hdr
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = xBtn
	xBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, TI_HOVER, { Scale = 1.18 }):Play(); xBtn.TextColor3 = X_RED_HOV
	end)
	xBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, TI_HOVER, { Scale = 1 }):Play(); xBtn.TextColor3 = X_RED
	end)
	xBtn.MouseButton1Click:Connect(function() playSfx("Click"); if closeBank then closeBank() end end)
end

-- Panel SKARBIEC (lewy)
local bankInner = mkFrame(trPanel,
	UDim2.fromOffset(INNER_W, INNER_H),
	UDim2.fromOffset(TR_PAD, TR_HEADER_H + TR_PAD),
	C_BG, 0.05)
bankInner.ZIndex = 3; mkStroke(bankInner, C_BORDER, 4); mkCorner(bankInner, 8)
mkInnerHeader(bankInner, INNER_W, INNER_HDR_H, "SKARBIEC")

-- Counter X/10 — pokazuje wykorzystaną pojemność skarbca
local bankCounter = mkLabel(bankInner,
	UDim2.fromOffset(80, 24),
	UDim2.new(1, -90, 0, 12),
	"0/10", 14, C_ACCENT_GREEN, Enum.TextXAlignment.Right)
bankCounter.ZIndex = 5

local bankScroll = Instance.new("ScrollingFrame")
bankScroll.Size                   = UDim2.fromOffset(SLOTS_W_B, VIS_H_B)
bankScroll.Position               = UDim2.fromOffset(INNER_PAD, INNER_HDR_H + INNER_PAD)
bankScroll.BackgroundTransparency = 1; bankScroll.BorderSizePixel = 0
bankScroll.ScrollBarThickness     = 6
bankScroll.ScrollBarImageColor3   = Color3.fromRGB(8, 50, 35)
bankScroll.CanvasSize             = UDim2.fromOffset(0, 0)
bankScroll.ZIndex                 = 4; bankScroll.Parent = bankInner

-- Panel EKWIPUNEK (prawy)
local invInner = mkFrame(trPanel,
	UDim2.fromOffset(INNER_W, INNER_H),
	UDim2.fromOffset(TR_PAD + INNER_W + DIV_W, TR_HEADER_H + TR_PAD),
	C_BG, 0.05)
invInner.ZIndex = 3; mkStroke(invInner, C_BORDER, 4); mkCorner(invInner, 8)
mkInnerHeader(invInner, INNER_W, INNER_HDR_H, "EKWIPUNEK")

-- Counter X/cap — wykorzystana pojemność plecaka
local invCounter = mkLabel(invInner,
	UDim2.fromOffset(80, 24),
	UDim2.new(1, -90, 0, 12),
	"0/10", 14, C_ACCENT_GREEN, Enum.TextXAlignment.Right)
invCounter.ZIndex = 5

local invScroll = Instance.new("ScrollingFrame")
invScroll.Size                    = UDim2.fromOffset(SLOTS_W_B, VIS_H_B)
invScroll.Position                = UDim2.fromOffset(INNER_PAD, INNER_HDR_H + INNER_PAD)
invScroll.BackgroundTransparency  = 1; invScroll.BorderSizePixel = 0
invScroll.ScrollBarThickness      = 6
invScroll.ScrollBarImageColor3    = Color3.fromRGB(8, 50, 35)
invScroll.CanvasSize              = UDim2.fromOffset(0, 0)
invScroll.ZIndex                  = 4; invScroll.Parent = invInner

-- Środkowy separator ⇌
do
	local div = mkFrame(trPanel,
		UDim2.fromOffset(DIV_W, INNER_H),
		UDim2.fromOffset(TR_PAD + INNER_W, TR_HEADER_H + TR_PAD),
		C_PANEL, 1)
	div.ZIndex = 3
	local arr = mkLabel(div, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0),
		"⇌", 34, C_DIMTEXT, Enum.TextXAlignment.Center)
	arr.TextYAlignment = Enum.TextYAlignment.Center; arr.ZIndex = 4
end

-- Dolny pasek z przyciskami
local BOTTOM_Y = TR_HEADER_H + TR_PAD + INNER_H + TR_BTM_GAP
local bottomBar = mkFrame(trPanel,
	UDim2.fromOffset(TR_W, TR_BOTTOM_H),
	UDim2.fromOffset(0, BOTTOM_Y),
	C_HEADER, 0)
bottomBar.ZIndex = 3
mkFrame(bottomBar, UDim2.new(1, 0, 0, 2), UDim2.fromOffset(0, 0), C_BORDER, 0).ZIndex = 4

-- Bottom bar layout (AnchorPoint=(0.5,0.5), więc Position = ŚRODEK przycisku):
--   [ZAMKNIJ 130w]  ←24px gap→  [POTWIERDŹ 220w]  ←24px gap→  [ULEPSZ 220w]
--   center=-199                 center=0                       center=+244
-- POTWIERDŹ dokładnie na środku paska. ZAMKNIJ i ULEPSZ symetrycznie po bokach.

-- POTWIERDŹ — środek paska
local confirmBtn = Instance.new("TextButton")
confirmBtn.Size             = UDim2.fromOffset(220, 52)
confirmBtn.AnchorPoint      = Vector2.new(0.5, 0.5)
confirmBtn.Position         = UDim2.new(0.5, 0, 0.5, 0)
confirmBtn.BackgroundColor3 = C_CONFIRM; confirmBtn.BackgroundTransparency = 0.05
confirmBtn.BorderSizePixel  = 0; confirmBtn.Text = "POTWIERDŹ"
confirmBtn.TextSize         = 20; confirmBtn.Font = FONT_MAIN
confirmBtn.TextColor3       = C_WHITE; confirmBtn.AutoButtonColor = false
confirmBtn.ZIndex           = 4; confirmBtn.Parent = bottomBar
mkStroke(confirmBtn, C_BORDER, 4); mkCorner(confirmBtn, 8); attachHover(confirmBtn, 1.05)

-- ZAMKNIJ — lewo od POTWIERDŹ (right edge POTWIERDŹ = -110, gap 24, ZAMKNIJ right edge = -134, center = -199)
local closeBtn2 = Instance.new("TextButton")
closeBtn2.Size             = UDim2.fromOffset(130, 52)
closeBtn2.AnchorPoint      = Vector2.new(0.5, 0.5)
closeBtn2.Position         = UDim2.new(0.5, -199, 0.5, 0)
closeBtn2.BackgroundColor3 = C_BG; closeBtn2.BackgroundTransparency = 0.05
closeBtn2.BorderSizePixel  = 0; closeBtn2.Text = "ZAMKNIJ"
closeBtn2.TextSize         = 18; closeBtn2.Font = FONT_MAIN
closeBtn2.TextColor3       = C_WHITE; closeBtn2.AutoButtonColor = false
closeBtn2.ZIndex           = 4; closeBtn2.Parent = bottomBar
mkStroke(closeBtn2, C_BORDER, 4); mkCorner(closeBtn2, 8); attachHover(closeBtn2, 1.05)
closeBtn2.MouseButton1Click:Connect(function() playSfx("Click"); if closeBank then closeBank() end end)

-- ULEPSZ — prawo od POTWIERDŹ (left edge POTWIERDŹ = +110, gap 24, ULEPSZ left edge = +134, center = +244)
local C_UPG = Color3.fromRGB(195, 145, 55)  -- amber/muted gold (jak Multiplier accent)
local upgradeBtn = Instance.new("TextButton")
upgradeBtn.Size             = UDim2.fromOffset(220, 52)
upgradeBtn.AnchorPoint      = Vector2.new(0.5, 0.5)
upgradeBtn.Position         = UDim2.new(0.5, 244, 0.5, 0)
upgradeBtn.BackgroundColor3 = C_UPG; upgradeBtn.BackgroundTransparency = 0.05
upgradeBtn.BorderSizePixel  = 0; upgradeBtn.Text = "ULEPSZ — 1000 zł"
upgradeBtn.TextSize         = 18; upgradeBtn.Font = FONT_MAIN
upgradeBtn.TextColor3       = C_WHITE; upgradeBtn.AutoButtonColor = false
upgradeBtn.ZIndex           = 4; upgradeBtn.Parent = bottomBar
mkStroke(upgradeBtn, C_BORDER, 4); mkCorner(upgradeBtn, 8); attachHover(upgradeBtn, 1.05)
local UpgradeBank = Events:WaitForChild("UpgradeBank")
local currentUpgCost = 1000
upgradeBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	UpgradeBank:FireServer()
end)

-- ── Stan gry ──────────────────────────────────────────────────────────────────
local currentCapacity = 10
local currentBankCap  = 10
local currentHasSyrup = false
-- Magnes w EQ — każdy zajmuje 1 slot pojemności (zmniejsza efektywny cap dla butelek)
local function currentMagnetCount(): number
	local m = _G["__magnetState"]
	return (m and tonumber(m.count)) or 0
end
-- Pety w EQ — każdy zajmuje 1 slot (do Kroku 3 nie transferują się do banku, więc po stronie EQ
-- pozostają i blokują miejsce dla butelek).
local function currentPetCount(): number
	local p = _G["__petsState"]
	return (p and p.pets and #p.pets) or 0
end

-- Slot może być butelką (rarity + count) ALBO petem (pet = {id, rarity, class}).
-- Petowy slot ma count = 1 i pole `pet` ustawione. Bottle slot ma `pet` = nil.
type SlotData = { rarity: string, count: number, pet: { id: string, rarity: string, class: string }? }

local function isPetSlot(s: SlotData?): boolean
	return s ~= nil and s.pet ~= nil
end

-- Mapowanie rzadkości peta → kolor (z Config.Pets, fallback C_WHITE)
local function petColor(rarity: string): Color3
	local rcfg = Config.Pets and Config.Pets.Rarities and Config.Pets.Rarities[rarity]
	return (rcfg and rcfg.color) or Color3.fromRGB(255, 255, 255)
end

local bankSlotArr: { [number]: SlotData? } = {}
local invSlotArr:  { [number]: SlotData? } = {}

-- Autorytatywny stan SERWERA (z BankInit / udanego BankResult). Używany żeby przy
-- zamknięciu banku BEZ POTWIERDŹ wykryć niezatwierdzony transfer i NIE utrwalić
-- niespójnego layoutu (inaczej butelki znikają z widoku na zawsze).
local serverBpContents:   { [string]: number } = {}
local serverBankContents: { [string]: number } = {}
local serverEqPetIds:   { [string]: boolean } = {}
local serverBankPetIds: { [string]: boolean } = {}

local bankFrames:   { Frame }      = {}; local bankNameLbls: { TextLabel } = {}
local bankCntLbls:  { TextLabel }  = {}; local bankStrokes:  { UIStroke }  = {}
local bankScales:   { UIScale }    = {}; local bankLegGlows: { Frame }     = {}
local bankLegGrads: { UIGradient } = {}; local bankMytGlows: { Frame }     = {}
local bankMytGrads: { UIGradient } = {}

local invFrames:   { Frame }      = {}; local invNameLbls: { TextLabel } = {}
local invCntLbls:  { TextLabel }  = {}; local invStrokes:  { UIStroke }  = {}
local invScales:   { UIScale }    = {}; local invLegGlows: { Frame }     = {}
local invLegGrads: { UIGradient } = {}; local invMytGlows: { Frame }     = {}
local invMytGrads: { UIGradient } = {}

local drag = { active = false, panel = "", slotIdx = 0, startPos = Vector2.zero, moved = false, isSplit = false, splitCount = 0 }
local hovPanel:   string? = nil
local hovSlotIdx: number? = nil
local ghost:      Frame?  = nil
local DRAG_THR = 5

local function ghostPos(): UDim2
	local m = UserInputService:GetMouseLocation()
	return UDim2.new(0, m.X - SLOT_B / 2, 0, m.Y - SLOT_B / 2)
end

local function slotArr(p: string) return p == "bank" and bankSlotArr or invSlotArr end
local function frms(p: string)    return p == "bank" and bankFrames   or invFrames end
local function nmLbls(p: string)  return p == "bank" and bankNameLbls or invNameLbls end
local function ctLbls(p: string)  return p == "bank" and bankCntLbls  or invCntLbls end
local function stks(p: string)    return p == "bank" and bankStrokes  or invStrokes end
local function lgGs(p: string)    return p == "bank" and bankLegGlows or invLegGlows end
local function lgGrs(p: string)   return p == "bank" and bankLegGrads or invLegGrads end
local function mgGs(p: string)    return p == "bank" and bankMytGlows or invMytGlows end
local function mgGrs(p: string)   return p == "bank" and bankMytGrads or invMytGrads end

-- ── Render ────────────────────────────────────────────────────────────────────
local function renderSlot(panel: string, i: number)
	local sf = frms(panel)[i]; if not sf then return end
	local data = slotArr(panel)[i]
	if data and isPetSlot(data) then
		-- PET — kolor per rzadkość, nazwa = klasa, count ukryty
		local col = petColor(data.pet.rarity)
		sf.BackgroundColor3         = darken(col, 0.55)
		stks(panel)[i].Color        = col
		stks(panel)[i].Thickness    = 3
		nmLbls(panel)[i].Text       = data.pet.class  -- "Sprinter" / "Tank"
		nmLbls(panel)[i].TextColor3 = col
		ctLbls(panel)[i].Text       = (data.pet.class == "Tank") and "🛡️" or "💨"
		ctLbls(panel)[i].TextColor3 = C_WHITE
		lgGs(panel)[i].Visible      = false
		mgGs(panel)[i].Visible      = false
	elseif data then
		sf.BackgroundColor3         = darken(RARITY_COLORS[data.rarity], 0.45)
		stks(panel)[i].Color        = RARITY_COLORS[data.rarity]
		stks(panel)[i].Thickness    = 3
		nmLbls(panel)[i].Text       = data.rarity
		nmLbls(panel)[i].TextColor3 = C_WHITE
		ctLbls(panel)[i].Text       = tostring(data.count)
		ctLbls(panel)[i].TextColor3 = C_WHITE
		lgGs(panel)[i].Visible      = (data.rarity == "Legendarna")
		mgGs(panel)[i].Visible      = (data.rarity == "Mityczny")
	else
		sf.BackgroundColor3      = C_SLOT
		stks(panel)[i].Color     = C_BORDER_SL
		stks(panel)[i].Thickness = 3
		nmLbls(panel)[i].Text    = ""
		ctLbls(panel)[i].Text    = ""
		lgGs(panel)[i].Visible   = false
		mgGs(panel)[i].Visible   = false
	end
end

local function bankTotalCount(): number
	-- Liczymy pety i butelki — każdy slot = 1 lub count (dla bottles)
	local n = 0
	for _, s in pairs(bankSlotArr) do
		if s then
			if isPetSlot(s) then n += 1 else n += s.count end
		end
	end
	return n
end

local function invTotalCount(): number
	-- Bottle slots: count; pet slots: 1.
	-- Syrop/magnes są poza widokiem bank UI (zostają w głównym EQ).
	local n = 0
	local petsInBankPanel = 0
	for _, s in pairs(invSlotArr) do
		if s then
			if isPetSlot(s) then
				n += 1
				petsInBankPanel += 1
			else
				n += s.count
			end
		end
	end
	if currentHasSyrup then n += 1 end
	n += currentMagnetCount()
	-- currentPetCount() liczy WSZYSTKIE pety gracza (z _G.__petsState); ale niektóre mogą
	-- już być w invSlotArr (widzialne w bank UI). Żeby nie liczyć podwójnie, dodajemy
	-- tylko te NIE w panelu EQ banku. Ale w naszym modelu pety w EQ ZAWSZE są w invSlotArr
	-- po BankInit. Tu zostawiamy +0 — petsInBankPanel pokrywa wszystkie pety w EQ.
	return n
end

local function renderAll()
	for i = 1, SLOT_COUNT_B do
		renderSlot("bank", i)
		renderSlot("inv",  i)
	end
	-- Bank counter X/10 — czerwony gdy przekroczy max
	local nb = bankTotalCount()
	bankCounter.Text = string.format("%d/%d", nb, currentBankCap)
	bankCounter.TextColor3 = (nb > currentBankCap) and Color3.fromRGB(255, 90, 90) or C_ACCENT_GREEN
	-- Inv counter X/cap — czerwony gdy przekroczy pojemność plecaka
	local ni = invTotalCount()
	invCounter.Text = string.format("%d/%d", ni, currentCapacity)
	invCounter.TextColor3 = (ni > currentCapacity) and Color3.fromRGB(255, 90, 90) or C_ACCENT_GREEN
end

-- ── Staging ───────────────────────────────────────────────────────────────────
local function buildStaging(bankC: { [string]: number }, invC: { [string]: number }, cap: number)
	for i = 1, cap do bankSlotArr[i] = nil; invSlotArr[i] = nil end
	local bi, ii = 1, 1
	for _, r in ipairs(RARITY_ORDER) do
		if (bankC[r] or 0) > 0 and bi <= cap then
			bankSlotArr[bi] = { rarity = r, count = bankC[r] }; bi += 1
		end
		if (invC[r] or 0) > 0 and ii <= cap then
			invSlotArr[ii] = { rarity = r, count = invC[r] }; ii += 1
		end
	end
end

-- Smart resync dowolnej tablicy slotów do nowych totals — zachowuje split layout gdy się da.
local function smartResyncArr(arr: { [number]: SlotData? }, newContents: { [string]: number }, cap: number)
	local currentTotals: { [string]: number } = {}
	for i = 1, cap do
		local s = arr[i]
		if s then currentTotals[s.rarity] = (currentTotals[s.rarity] or 0) + s.count end
	end
	for _, r in ipairs(RARITY_ORDER) do
		local target  = newContents[r] or 0
		local current = currentTotals[r] or 0
		local diff = target - current
		if diff > 0 then
			local added = false
			for i = 1, cap do
				if arr[i] and arr[i].rarity == r then
					arr[i].count += diff; added = true; break
				end
			end
			if not added then
				for i = 1, cap do
					if not arr[i] then
						arr[i] = { rarity = r, count = diff }; break
					end
				end
			end
		elseif diff < 0 then
			local toRemove = -diff
			for i = cap, 1, -1 do
				if toRemove <= 0 then break end
				if arr[i] and arr[i].rarity == r then
					if arr[i].count <= toRemove then
						toRemove -= arr[i].count
						arr[i] = nil
					else
						arr[i].count -= toRemove
						toRemove = 0
					end
				end
			end
		end
	end
end

local function smartResyncInv(newContents: { [string]: number }, cap: number)
	smartResyncArr(invSlotArr, newContents, cap)
end

local function arrayToContents(arr: { [number]: SlotData? }, cap: number): { [string]: number }
	-- Tylko butelki (pety pomijamy)
	local c = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
	for i = 1, cap do
		local s = arr[i]
		if s and not isPetSlot(s) then c[s.rarity] = (c[s.rarity] or 0) + s.count end
	end
	return c
end

-- Wyciąga listę UUIDów petów z arr
local function arrayToPetIds(arr: { [number]: SlotData? }, cap: number): { string }
	local ids = {}
	for i = 1, cap do
		local s = arr[i]
		if s and isPetSlot(s) then table.insert(ids, s.pet.id) end
	end
	return ids
end

-- Zbiór UUIDów z listy petów serwera ({ {id=...}, ... }) → { [id]=true }
local function petIdSet(list: any): { [string]: boolean }
	local set = {}
	if type(list) == "table" then
		for _, pet in ipairs(list) do
			if type(pet) == "table" and pet.id then set[tostring(pet.id)] = true end
		end
	end
	return set
end

-- ── Budowanie ramek slotów ────────────────────────────────────────────────────
local function clearSlotFrames()
	for _, f in ipairs(bankFrames) do if f.Parent then f:Destroy() end end
	for _, f in ipairs(invFrames)  do if f.Parent then f:Destroy() end end
	bankFrames = {}; bankNameLbls = {}; bankCntLbls = {}
	bankStrokes = {}; bankScales = {}; bankLegGlows = {}; bankLegGrads = {}
	bankMytGlows = {}; bankMytGrads = {}
	invFrames = {}; invNameLbls = {}; invCntLbls = {}
	invStrokes = {}; invScales = {}; invLegGlows = {}; invLegGrads = {}
	invMytGlows = {}; invMytGrads = {}
end

local SLOT_TI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local startDrag -- forward
local endDrag   -- forward
local splitSlot -- forward

local function makeSlotInScroll(scroll: ScrollingFrame, i: number)
	local col = (i - 1) % COLS_B
	local row = math.floor((i - 1) / COLS_B)
	local sf = mkFrame(scroll,
		UDim2.fromOffset(SLOT_B, SLOT_B),
		UDim2.new(0, col * (SLOT_B + GAP_B) + SLOT_B / 2, 0, row * (SLOT_B + GAP_B) + SLOT_B / 2),
		C_SLOT, 0)
	sf.AnchorPoint = Vector2.new(0.5, 0.5); sf.ClipsDescendants = true; sf.ZIndex = 5
	local st = Instance.new("UIStroke")
	st.Color = C_BORDER_SL; st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = sf
	mkCorner(sf, 10)
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = sf

	local lg = Instance.new("Frame")
	lg.Size = UDim2.fromScale(1, 1); lg.BackgroundColor3 = Color3.fromRGB(255, 230, 100)
	lg.BackgroundTransparency = 0.4; lg.BorderSizePixel = 0
	lg.Visible = false; lg.ZIndex = 0; lg.Parent = sf; mkCorner(lg, 10)
	local lgr = Instance.new("UIGradient")
	lgr.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 235, 130)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 40)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 235, 130)),
	})
	lgr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.15),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1,   0.15),
	}); lgr.Parent = lg

	-- Mythic glow: rotujący gradient fiolet ↔ czarny
	local mg = Instance.new("Frame")
	mg.Size = UDim2.fromScale(1, 1); mg.BackgroundColor3 = Color3.fromRGB(80, 30, 140)
	mg.BackgroundTransparency = 0.35; mg.BorderSizePixel = 0
	mg.Visible = false; mg.ZIndex = 0; mg.Parent = sf; mkCorner(mg, 10)
	local mgr = Instance.new("UIGradient")
	mgr.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(150, 50, 220)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10,  0,  20)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(150, 50, 220)),
	})
	mgr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.15),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1,   0.15),
	}); mgr.Parent = mg

	local nl = mkLabel(sf, UDim2.new(1, -8, 0, 16), UDim2.new(0, 5, 0, 5), "", 11, C_WHITE)
	nl.TextStrokeColor3 = Color3.new(0, 0, 0); nl.TextStrokeTransparency = 0.3; nl.ZIndex = 6
	local cl = mkLabel(sf, UDim2.new(1, -6, 0, 24), UDim2.new(0, 0, 1, -28),
		"", 22, C_WHITE, Enum.TextXAlignment.Right)
	cl.TextStrokeColor3 = Color3.new(0, 0, 0); cl.TextStrokeTransparency = 0.2; cl.ZIndex = 6

	return sf, sc, nl, cl, st, lg, lgr, mg, mgr
end

local function buildSlotFrames(cap: number)
	clearSlotFrames()
	local rows    = math.ceil(cap / COLS_B)
	local canvasH = rows * SLOT_B + (rows - 1) * GAP_B
	-- Viewport zawsze ma rozmiar VIS_H_B (3 rzędy), żeby panel zawsze pokazywał pełne 3 rzędy
	-- nawet jak items'ów jest mało. Canvas może być mniejszy (mało slotów) albo większy (scroll).

	bankScroll.Size       = UDim2.fromOffset(SLOTS_W_B, VIS_H_B)
	bankScroll.CanvasSize = UDim2.fromOffset(SLOTS_W_B, math.max(canvasH, VIS_H_B))
	invScroll.Size        = UDim2.fromOffset(SLOTS_W_B, VIS_H_B)
	invScroll.CanvasSize  = UDim2.fromOffset(SLOTS_W_B, math.max(canvasH, VIS_H_B))

	for i = 1, cap do
		local idx = i

		local sf, sc, nl, cl, st, lg, lgr, mg, mgr = makeSlotInScroll(bankScroll, i)
		bankFrames[i]=sf; bankScales[i]=sc; bankNameLbls[i]=nl
		bankCntLbls[i]=cl; bankStrokes[i]=st; bankLegGlows[i]=lg; bankLegGrads[i]=lgr
		bankMytGlows[i]=mg; bankMytGrads[i]=mgr

		sf.MouseEnter:Connect(function()
			hovPanel = "bank"; hovSlotIdx = idx
			TweenService:Create(sc, SLOT_TI, { Scale = 1.06 }):Play()
			if drag.active and not (drag.panel == "bank" and drag.slotIdx == idx) then
				sf.BackgroundColor3 = C_SLOT_HOV
			end
		end)
		sf.MouseLeave:Connect(function()
			if hovPanel == "bank" and hovSlotIdx == idx then hovPanel = nil; hovSlotIdx = nil end
			TweenService:Create(sc, SLOT_TI, { Scale = 1 }):Play()
			renderSlot("bank", idx)
		end)
		sf.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 then
				if startDrag then startDrag("bank", idx) end
			elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
				if splitSlot then splitSlot("bank", idx) end
			end
		end)

		local sf2, sc2, nl2, cl2, st2, lg2, lgr2, mg2, mgr2 = makeSlotInScroll(invScroll, i)
		invFrames[i]=sf2; invScales[i]=sc2; invNameLbls[i]=nl2
		invCntLbls[i]=cl2; invStrokes[i]=st2; invLegGlows[i]=lg2; invLegGrads[i]=lgr2
		invMytGlows[i]=mg2; invMytGrads[i]=mgr2

		sf2.MouseEnter:Connect(function()
			hovPanel = "inv"; hovSlotIdx = idx
			TweenService:Create(sc2, SLOT_TI, { Scale = 1.06 }):Play()
			if drag.active and not (drag.panel == "inv" and drag.slotIdx == idx) then
				sf2.BackgroundColor3 = C_SLOT_HOV
			end
		end)
		sf2.MouseLeave:Connect(function()
			if hovPanel == "inv" and hovSlotIdx == idx then hovPanel = nil; hovSlotIdx = nil end
			TweenService:Create(sc2, SLOT_TI, { Scale = 1 }):Play()
			renderSlot("inv", idx)
		end)
		sf2.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 then
				if startDrag then startDrag("inv", idx) end
			elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
				if splitSlot then splitSlot("inv", idx) end
			end
		end)
	end
end

-- ── Drag & Drop ───────────────────────────────────────────────────────────────
local function buildGhost(data: SlotData): Frame
	local isPet = isPetSlot(data)
	local c = isPet and petColor(data.pet.rarity) or RARITY_COLORS[data.rarity]
	local g = mkFrame(bankGui, UDim2.fromOffset(SLOT_B, SLOT_B), ghostPos(), darken(c, 0.3), 0.08)
	g.ZIndex = 100; g.Active = false; mkCorner(g, 10); mkStroke(g, c, 2)
	local nameText = isPet and data.pet.class or data.rarity
	local nl = mkLabel(g, UDim2.new(1,-6,0,14), UDim2.new(0,5,0,4), nameText, 10, C_WHITE)
	nl.ZIndex = 101
	local cntText = isPet and ((data.pet.class == "Tank") and "🛡️" or "💨") or tostring(data.count)
	local cl = mkLabel(g, UDim2.new(1,-4,0,22), UDim2.new(0,0,1,-26),
		cntText, 18, C_WHITE, Enum.TextXAlignment.Right)
	cl.TextStrokeColor3 = Color3.new(0,0,0); cl.TextStrokeTransparency = 0.3; cl.ZIndex = 101
	return g
end

local function showCapacityError(msg: string?)
	local lbl = mkLabel(trPanel,
		UDim2.fromOffset(420, 30),
		UDim2.new(0.5, -210, 0, BOTTOM_Y - 36),
		msg or "ZA MAŁO MIEJSCA W PLECAKU!", 14, Color3.fromRGB(255, 80, 80), Enum.TextXAlignment.Center)
	lbl.ZIndex = 10
	TweenService:Create(lbl, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = 16 }):Play()
	task.delay(1.8, function()
		TweenService:Create(lbl, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		task.delay(0.35, function() if lbl.Parent then lbl:Destroy() end end)
	end)
end

-- Helper: ile slotów zajmuje (1 dla peta, count dla butelek)
local function slotSize(s: SlotData?): number
	if not s then return 0 end
	if isPetSlot(s) then return 1 end
	return s.count
end

local function performTransfer(fromP: string, toP: string, fromIdx: number, toIdx: number)
	local fromArr = slotArr(fromP); local toArr = slotArr(toP)
	local src = fromArr[fromIdx]; if not src then return end
	local tgt = toArr[toIdx]

	-- Czy to merge butelek (ta sama rzadkość, oba NIE pety) — pety nigdy nie merge'ują
	local isBottleMerge = src and tgt
		and not isPetSlot(src) and not isPetSlot(tgt)
		and src.rarity == tgt.rarity

	local curInvTotal = 0
	for _, s in pairs(invSlotArr) do curInvTotal += slotSize(s) end
	local invCap = currentCapacity - (currentHasSyrup and 1 or 0) - currentMagnetCount()

	local function invTotalAfter(): number
		if fromP == "inv" and toP == "bank" then
			if isBottleMerge then return curInvTotal - slotSize(src)
			elseif tgt then return curInvTotal - slotSize(src) + slotSize(tgt)
			else return curInvTotal - slotSize(src) end
		elseif fromP == "bank" and toP == "inv" then
			if isBottleMerge then return curInvTotal + slotSize(src)
			elseif tgt then return curInvTotal - slotSize(tgt) + slotSize(src)
			else return curInvTotal + slotSize(src) end
		end
		return curInvTotal
	end

	if invTotalAfter() > invCap then showCapacityError(); return end

	if tgt then
		if isBottleMerge then
			tgt.count += src.count; fromArr[fromIdx] = nil
		else
			toArr[toIdx] = src; fromArr[fromIdx] = tgt  -- swap (też pet ↔ pet, pet ↔ bottle)
		end
	else
		toArr[toIdx] = src; fromArr[fromIdx] = nil
	end
end

startDrag = function(panel: string, idx: number)
	local arr = slotArr(panel); if not arr[idx] then return end
	drag.active = true; drag.panel = panel; drag.slotIdx = idx
	drag.startPos = UserInputService:GetMouseLocation(); drag.moved = false
	drag.isSplit = false; drag.splitCount = 0
	local sf = frms(panel)[idx]
	sf.BackgroundColor3        = C_SLOT
	nmLbls(panel)[idx].Visible = false
	ctLbls(panel)[idx].Visible = false
	lgGs(panel)[idx].Visible   = false
	ghost = buildGhost(arr[idx] :: SlotData)
end

-- Right-click split drag: od razu zabiera połowę i pokazuje ghost do dragowania.
-- Source pozostaje widoczne ze zmniejszonym count.
splitSlot = function(panel: string, idx: number)
	if drag.active then return end
	local arr = slotArr(panel)
	local src = arr[idx]
	if not src or isPetSlot(src) or src.count < 2 then return end  -- petów nie dzielimy
	local half = math.floor(src.count / 2)
	if half < 1 then return end
	-- Zmniejsz źródło, zostaw widoczne — drag pokaże ghost z połową
	arr[idx].count -= half
	drag.active     = true
	drag.panel      = panel
	drag.slotIdx    = idx
	drag.startPos   = UserInputService:GetMouseLocation()
	drag.moved      = false
	drag.isSplit    = true
	drag.splitCount = half
	ghost = buildGhost({ rarity = src.rarity, count = half })
	renderSlot(panel, idx)
end

local function endSplitDrag()
	local fromP    = drag.panel
	local fromIdx  = drag.slotIdx
	local fromArr  = slotArr(fromP)
	local toP      = hovPanel
	local toIdx    = hovSlotIdx
	local splitN   = drag.splitCount
	local rarity   = fromArr[fromIdx] and fromArr[fromIdx].rarity

	if ghost then ghost:Destroy(); ghost = nil end

	local function restoreToSource()
		if fromArr[fromIdx] then
			fromArr[fromIdx].count += splitN
		else
			fromArr[fromIdx] = { rarity = rarity :: string, count = splitN }
		end
	end

	-- Brak targetu / nie ruszono myszką / drop na siebie → cancel (zwróć do źródła)
	if not (drag.moved and toP and toIdx and rarity) then
		restoreToSource()
	elseif toP == fromP and toIdx == fromIdx then
		restoreToSource()
	else
		local toArr = slotArr(toP)
		local target = toArr[toIdx]
		if target then
			if target.rarity == rarity then
				target.count += splitN  -- merge same rarity
			else
				restoreToSource()  -- różne rzadkości — cancel
			end
		else
			-- Pusty slot: capacity check gdy idziemy do inv
			if toP == "inv" and fromP ~= "inv" then
				local invTotal = 0
				for _, s in pairs(invSlotArr) do if s then invTotal += s.count end end
				-- invCap = pojemność dostępna dla zawartości panelu EQ (butelki + pety w invSlotArr).
	-- Syrop i magnes są poza widokiem bank UI, więc je odejmujemy. Pety NIE odejmujemy
	-- — są częścią invSlotArr, więc liczą się w invTotal po drugiej stronie checka.
	local invCap = currentCapacity - (currentHasSyrup and 1 or 0) - currentMagnetCount()
				if invTotal + splitN > invCap then
					showCapacityError("ZA MAŁO MIEJSCA W PLECAKU!")
					restoreToSource()
				else
					toArr[toIdx] = { rarity = rarity, count = splitN }
				end
			else
				toArr[toIdx] = { rarity = rarity, count = splitN }
			end
		end
	end

	hovPanel = nil; hovSlotIdx = nil
	drag.active = false; drag.panel = ""; drag.slotIdx = 0
	drag.isSplit = false; drag.splitCount = 0
	renderAll()
end

endDrag = function()
	if not drag.active then return end
	if drag.isSplit then endSplitDrag(); return end

	local fromP = drag.panel; local fromIdx = drag.slotIdx
	local toP = hovPanel; local toIdx = hovSlotIdx
	nmLbls(fromP)[fromIdx].Visible = true
	ctLbls(fromP)[fromIdx].Visible = true
	if ghost then ghost:Destroy(); ghost = nil end
	if drag.moved and toP and toIdx then
		if fromP == toP then
			if toIdx ~= fromIdx then
				local arr = slotArr(fromP); arr[fromIdx], arr[toIdx] = arr[toIdx], arr[fromIdx]
			end
		else
			performTransfer(fromP, toP, fromIdx, toIdx)
		end
	end
	hovPanel = nil; hovSlotIdx = nil
	drag.active = false; drag.panel = ""; drag.slotIdx = 0
	renderAll()
end

UserInputService.InputChanged:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseMovement and drag.active and ghost then
		ghost.Position = ghostPos()
		if not drag.moved then
			local cur = UserInputService:GetMouseLocation()
			if (cur - drag.startPos).Magnitude > DRAG_THR then drag.moved = true end
		end
	end
end)

UserInputService.InputEnded:Connect(function(inp)
	if not drag.active then return end
	-- LMB-drag kończony LMB-up; split-drag (RMB) kończony RMB-up
	if (inp.UserInputType == Enum.UserInputType.MouseButton1 and not drag.isSplit)
	or (inp.UserInputType == Enum.UserInputType.MouseButton2 and drag.isSplit) then
		endDrag()
	end
end)

-- ── VFX Legendarnej / Mityczny (Heartbeat) ────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	local t = tick()
	for i = 1, SLOT_COUNT_B do
		for _, p in ipairs({ "bank", "inv" }) do
			local data = slotArr(p)[i]
			if data and data.rarity == "Legendarna" then
				local lg = lgGs(p)[i]; local st = stks(p)[i]; local gr = lgGrs(p)[i]
				if lg and lg.Visible and st and gr then
					local pulse = (math.sin(t * 4.5) + 1) * 0.5
					st.Color     = Color3.fromRGB(255, 200 + math.floor(pulse * 55), 60 + math.floor(pulse * 195))
					st.Thickness = 3 + pulse * 2.5
					gr.Rotation  = (gr.Rotation + 80 * dt) % 360
				end
			elseif data and data.rarity == "Mityczny" then
				local mg = mgGs(p)[i]; local st = stks(p)[i]; local mgr = mgGrs(p)[i]
				if mg and mg.Visible and st and mgr then
					local pulse = (math.sin(t * 4.0) + 1) * 0.5
					st.Color     = Color3.fromRGB(80 + math.floor(pulse * 100), 20 + math.floor(pulse * 60), 140 + math.floor(pulse * 100))
					st.Thickness = 3 + pulse * 2.5
					mgr.Rotation = (mgr.Rotation + 60 * dt) % 360
				end
			end
		end
	end
end)

-- ── Open / Close ──────────────────────────────────────────────────────────────
local TW_OPEN  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TW_CLOSE = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- Helper: zapisz aktualny layout invSlotArr do shared inventory layout (CollectController) — Z POZYCJAMI
local function syncInvLayoutToShared()
	if not _G["__inventorySetLayout"] then return end
	-- Filtrujemy pety — CollectController syncuje je z _G.__petsState po PetStatusUpdate.
	local layout = {}
	for i = 1, SLOT_COUNT_B do
		local s = invSlotArr[i]
		if s and not isPetSlot(s) then
			layout[i] = { rarity = s.rarity, count = s.count }
		end
	end
	_G["__inventorySetLayout"](layout)
end

-- Cache split layout banku w session (przeżywa close → open)
-- Filtrujemy pety — ich pozycje pochodzą z serwera (BankInit.bankPets).
local function saveBankLayoutToCache()
	local cache = {}
	for i = 1, SLOT_COUNT_B do
		local s = bankSlotArr[i]
		if s and not isPetSlot(s) then
			cache[i] = { rarity = s.rarity, count = s.count }
		end
	end
	_G["__bankLayoutCache"] = cache
end

local bankMoveLocked = false
local function bankUnlockMove()
	if bankMoveLocked then bankMoveLocked = false; _G["__unlockMovement"]() end
end
local function bankLockMove()
	if not bankMoveLocked then bankMoveLocked = true; _G["__lockMovement"]() end
end

-- Czy obecny układ slotów różni się od autorytatywnego stanu serwera?
-- (niezatwierdzony transfer EQ↔SKARBIEC). Jeśli tak — zamknięcie bez POTWIERDŹ
-- NIE może utrwalić layoutu, bo zniknęłyby przeniesione butelki/pety.
local function hasUncommittedChanges(): boolean
	local invC  = arrayToContents(invSlotArr,  SLOT_COUNT_B)
	local bankC = arrayToContents(bankSlotArr, SLOT_COUNT_B)
	for _, r in ipairs(RARITY_ORDER) do
		if (invC[r] or 0)  ~= (serverBpContents[r] or 0)   then return true end
		if (bankC[r] or 0) ~= (serverBankContents[r] or 0) then return true end
	end
	-- Pety — porównaj zbiory UUIDów per strona
	local function petSetMatches(arr, serverSet): boolean
		local seen = {}
		for _, id in ipairs(arrayToPetIds(arr, SLOT_COUNT_B)) do
			if not serverSet[id] then return false end
			seen[id] = true
		end
		for id in pairs(serverSet) do if not seen[id] then return false end end
		return true
	end
	if not petSetMatches(invSlotArr,  serverEqPetIds)   then return true end
	if not petSetMatches(bankSlotArr, serverBankPetIds) then return true end
	return false
end

closeBank = function()
	bankUnlockMove()
	if drag.active then endDrag() end
	-- Utrwalamy layout TYLKO gdy realny panel transferu był otwarty (nie locked)
	-- ORAZ układ == stan serwera (sam rearrange / brak transferu).
	-- Niezatwierdzony transfer porzucamy — CollectController zachowuje prawdziwy stan EQ.
	if trPanel.Visible and not hasUncommittedChanges() then
		syncInvLayoutToShared()  -- zapisz split layout do głównego ekwipunku
		saveBankLayoutToCache()  -- zapisz split layout banku do session cache
	end
	TweenService:Create(trPanel, TW_CLOSE,
		{ Position = UDim2.new(0.5, 0, 0.55, 0), BackgroundTransparency = 1 }):Play()
	if lockedPanel and lockedPanel.Visible then
		TweenService:Create(lockedPanel, TW_CLOSE,
			{ Position = UDim2.new(0.5, 0, 0.55, 0), BackgroundTransparency = 1 }):Play()
	end
	local tw = TweenService:Create(dimOverlay, TW_CLOSE, { BackgroundTransparency = 1 })
	tw.Completed:Connect(function()
		bankGui.Enabled  = false
		trPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
		trPanel.BackgroundTransparency = 0.05
		trPanel.Visible  = false
		if lockedPanel then
			lockedPanel.Visible = false
			lockedPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
			lockedPanel.BackgroundTransparency = 0.05
		end
	end)
	tw:Play()
end

-- ESC zamyka bank
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and bankGui.Enabled then
		closeBank()
	end
end)

-- ── POTWIERDŹ ─────────────────────────────────────────────────────────────────
confirmBtn.MouseButton1Click:Connect(function()
	local newBp = arrayToContents(invSlotArr,  SLOT_COUNT_B)
	local newBk = arrayToContents(bankSlotArr, SLOT_COUNT_B)
	local newEqPets   = arrayToPetIds(invSlotArr,  SLOT_COUNT_B)
	local newBankPets = arrayToPetIds(bankSlotArr, SLOT_COUNT_B)
	-- Wyślij jako deposit (serwer waliduje conservation butelek + petów)
	BankDeposit:FireServer({
		newBackpackContents = newBp,
		newBankContents     = newBk,
		newEqPetIds         = newEqPets,
		newBankPetIds       = newBankPets,
	})
	confirmBtn.Text             = "ZAPISYWANIE..."
	confirmBtn.BackgroundColor3 = Color3.fromRGB(20, 80, 40)
end)

-- ── Zdarzenia serwera ─────────────────────────────────────────────────────────
-- ── Locked panel (gdy BaseLevel < 1) ─────────────────────────────────────────
lockedPanel = mkFrame(bankGui,
	UDim2.fromOffset(440, 220),
	UDim2.new(0.5, 0, 0.5, 0),
	C_PANEL, 0.05)
lockedPanel.AnchorPoint = Vector2.new(0.5, 0.5)
lockedPanel.ZIndex      = 2
lockedPanel.Visible     = false
mkStroke(lockedPanel, C_BORDER, 4); mkCorner(lockedPanel, 8)

do
	local hdr = mkFrame(lockedPanel,
		UDim2.new(1, 0, 0, 50),
		UDim2.fromOffset(0, 0), C_HEADER, 0)
	hdr.ZIndex = 3; mkCorner(hdr, 8)
	mkFrame(hdr, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10), C_HEADER, 0).ZIndex = 3
	mkFrame(hdr, UDim2.new(1, 0, 0, 2),  UDim2.new(0, 0, 1,  -2), C_BORDER, 0).ZIndex = 5
	mkLabel(hdr, UDim2.new(1, -56, 1, 0), UDim2.fromOffset(0, 0),
		"BANK ZAMKNIĘTY", 18, X_RED, Enum.TextXAlignment.Center).ZIndex = 4

	local xBtn = Instance.new("TextButton")
	xBtn.Size = UDim2.fromOffset(36, 36); xBtn.AnchorPoint = Vector2.new(1, 0.5)
	xBtn.Position = UDim2.new(1, -12, 0.5, 0)
	xBtn.BackgroundTransparency = 1; xBtn.BorderSizePixel = 0
	xBtn.Text = "X"; xBtn.TextSize = 22; xBtn.Font = FONT_MAIN
	xBtn.TextColor3 = X_RED; xBtn.AutoButtonColor = false; xBtn.ZIndex = 6; xBtn.Parent = hdr
	xBtn.MouseButton1Click:Connect(function() playSfx("Click"); if closeBank then closeBank() end end)
end

mkLabel(lockedPanel,
	UDim2.new(1, -32, 0, 90),
	UDim2.fromOffset(16, 70),
	"Aby korzystać ze skarbca,\nkup najpierw FUNDAMENT\nw drzewku umiejętności (klawisz U).",
	17, C_WHITE, Enum.TextXAlignment.Center).TextYAlignment = Enum.TextYAlignment.Center

BankInit.OnClientEvent:Connect(function(data)
	bankLockMove()
	-- Locked: gracz nie ma BaseLevel >= 1
	if data and data.locked then
		bankGui.Enabled  = true
		trPanel.Visible  = false  -- normal panel chowany
		lockedPanel.Visible = true
		lockedPanel.Position = UDim2.new(0.5, 0, 0.55, 0)
		lockedPanel.BackgroundTransparency = 1
		dimOverlay.BackgroundTransparency = 1
		TweenService:Create(lockedPanel, TW_OPEN,
			{ Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 0.05 }):Play()
		TweenService:Create(dimOverlay, TW_OPEN, { BackgroundTransparency = 0.35 }):Play()
		return
	end
	lockedPanel.Visible = false
	currentCapacity  = data.backpackCapacity
	currentBankCap   = tonumber(data.bankCapacity) or 10
	currentHasSyrup  = data.hasSyrup or false
	currentUpgCost   = tonumber(data.bankUpgradeCost) or currentUpgCost
	upgradeBtn.Text  = string.format("ULEPSZ — %d zł", currentUpgCost)
	-- Snapshot autorytatywnego stanu serwera (do wykrycia niezatwierdzonych transferów)
	serverBpContents   = data.backpackContents or {}
	serverBankContents = data.bankContents or {}
	serverEqPetIds     = petIdSet(data.eqPets)
	serverBankPetIds   = petIdSet(data.bankPets)
	buildSlotFrames(SLOT_COUNT_B)

	-- Bank side: prefer in-session split layout (jeśli totals się zgadzają z serwerem), fallback do flat contents
	for i = 1, SLOT_COUNT_B do bankSlotArr[i] = nil end
	local bankLayout = _G["__bankLayoutCache"]
	local layoutOk = false
	if type(bankLayout) == "table" then
		local layoutTotals: { [string]: number } = {}
		for _, v in pairs(bankLayout) do
			layoutTotals[v.rarity] = (layoutTotals[v.rarity] or 0) + v.count
		end
		layoutOk = true
		for _, r in ipairs(RARITY_ORDER) do
			if (layoutTotals[r] or 0) ~= (data.bankContents[r] or 0) then layoutOk = false; break end
		end
	end
	if layoutOk then
		for slotIdx, v in pairs(bankLayout) do
			local i = tonumber(slotIdx)
			if i and i >= 1 and i <= SLOT_COUNT_B then
				bankSlotArr[i] = { rarity = v.rarity, count = v.count }
			end
		end
	else
		local bi = 1
		for _, r in ipairs(RARITY_ORDER) do
			if (data.bankContents[r] or 0) > 0 and bi <= SLOT_COUNT_B then
				bankSlotArr[bi] = { rarity = r, count = data.bankContents[r] }; bi += 1
			end
		end
	end
	-- Dodaj pety z banku (po butelkach) — wypełniaj pierwsze wolne sloty
	if type(data.bankPets) == "table" then
		for _, pet in ipairs(data.bankPets) do
			for i = 1, SLOT_COUNT_B do
				if not bankSlotArr[i] then
					bankSlotArr[i] = { rarity = "_pet", count = 1, pet = pet }
					break
				end
			end
		end
	end

	-- Inv side: PREFER shared layout z głównego ekwipunku (Z POZYCJAMI — 1:1 mapping),
	-- ALE tylko gdy sumy butelek == data.backpackContents (jak bank side z layoutOk).
	-- Inaczej (stale/niespójny layout) butelki nie zgadzałyby się z serwerem i POTWIERDŹ
	-- zwracał "conservation" → "BŁĄD ZAPISU". Fallback do flat contents z serwera.
	for i = 1, SLOT_COUNT_B do invSlotArr[i] = nil end
	local sharedLayout = _G["__inventoryGetLayout"] and _G["__inventoryGetLayout"]()
	local invLayoutOk = false
	if type(sharedLayout) == "table" then
		local layoutTotals: { [string]: number } = {}
		local any = false
		for _, s in pairs(sharedLayout) do
			any = true
			layoutTotals[s.rarity] = (layoutTotals[s.rarity] or 0) + s.count
		end
		if any then
			invLayoutOk = true
			for _, r in ipairs(RARITY_ORDER) do
				if (layoutTotals[r] or 0) ~= (data.backpackContents[r] or 0) then invLayoutOk = false; break end
			end
		end
	end
	if invLayoutOk then
		for slotIdx, s in pairs(sharedLayout) do
			local i = tonumber(slotIdx)
			if i and i >= 1 and i <= SLOT_COUNT_B then
				invSlotArr[i] = { rarity = s.rarity, count = s.count }
			end
		end
	else
		-- Fallback: build z flat contents (pierwsze wejście lub niespójny layout)
		local ii = 1
		for _, r in ipairs(RARITY_ORDER) do
			if (data.backpackContents[r] or 0) > 0 and ii <= SLOT_COUNT_B then
				invSlotArr[ii] = { rarity = r, count = data.backpackContents[r] }; ii += 1
			end
		end
	end
	-- Dodaj pety z EQ (po butelkach) — wypełniaj pierwsze wolne sloty
	if type(data.eqPets) == "table" then
		for _, pet in ipairs(data.eqPets) do
			for i = 1, SLOT_COUNT_B do
				if not invSlotArr[i] then
					invSlotArr[i] = { rarity = "_pet", count = 1, pet = pet }
					break
				end
			end
		end
	end
	renderAll()

	-- Animacja wejścia
	bankGui.Enabled  = true
	trPanel.Visible  = true
	trPanel.Position = UDim2.new(0.5, 0, 0.55, 0)
	trPanel.BackgroundTransparency = 1
	dimOverlay.BackgroundTransparency = 1
	TweenService:Create(trPanel, TW_OPEN,
		{ Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(dimOverlay, TW_OPEN, { BackgroundTransparency = 0.35 }):Play()
end)

-- UpdateHUD: gdy gracz np. podniósł butelkę w trakcie otwartego banku — resync inwentarza
UpdateHUD.OnClientEvent:Connect(function(data)
	if not bankGui.Enabled then return end
	if not data or type(data.backpackContents) ~= "table" then return end
	if drag.active then return end  -- nie ruszamy podczas dragowania
	currentCapacity = tonumber(data.backpackCapacity) or currentCapacity
	currentHasSyrup = data.hasSyrup or false
	smartResyncInv(data.backpackContents, SLOT_COUNT_B)
	-- Pickup w trakcie otwartego banku to nowy stan serwera EQ — odśwież snapshot
	serverBpContents = data.backpackContents or serverBpContents
	renderAll()
end)

BankResult.OnClientEvent:Connect(function(result)
	confirmBtn.Text             = "POTWIERDŹ"
	confirmBtn.BackgroundColor3 = C_CONFIRM
	if result.success then
		-- Smart resync — zachowuje split layout który gracz ustawił (np. 10 → 5+5)
		currentCapacity = tonumber(result.backpackCapacity) or currentCapacity
		if result.bankCapacity then currentBankCap = tonumber(result.bankCapacity) or currentBankCap end
		if result.bankUpgradeCost then
			currentUpgCost  = tonumber(result.bankUpgradeCost) or currentUpgCost
			upgradeBtn.Text = string.format("ULEPSZ — %d zł", currentUpgCost)
		end
		-- ULEPSZ to tylko zmiana pojemności — NIC nie przenosi w slotach. Odpowiedź serwera
		-- nie zawiera eqPets/bankPets, więc resync poniżej wyczyściłby pety z widoku.
		-- Aktualizujemy tylko licznik X/N (renderAll) i kończymy.
		if result.upgraded then
			renderAll()
			return
		end
		-- Najpierw czyścimy pety z obu arrays (server zwraca świeże listy), potem resync butelek
		for i = 1, SLOT_COUNT_B do
			if bankSlotArr[i] and isPetSlot(bankSlotArr[i]) then bankSlotArr[i] = nil end
			if invSlotArr[i]  and isPetSlot(invSlotArr[i])  then invSlotArr[i]  = nil end
		end
		smartResyncArr(bankSlotArr, result.bankContents, SLOT_COUNT_B)
		smartResyncArr(invSlotArr,  result.backpackContents, SLOT_COUNT_B)
		-- Re-add pets z server response
		if type(result.eqPets) == "table" then
			for _, pet in ipairs(result.eqPets) do
				for i = 1, SLOT_COUNT_B do
					if not invSlotArr[i] then invSlotArr[i] = { rarity = "_pet", count = 1, pet = pet }; break end
				end
			end
		end
		if type(result.bankPets) == "table" then
			for _, pet in ipairs(result.bankPets) do
				for i = 1, SLOT_COUNT_B do
					if not bankSlotArr[i] then bankSlotArr[i] = { rarity = "_pet", count = 1, pet = pet }; break end
				end
			end
		end
		-- Transfer zatwierdzony — odśwież snapshot serwera (kolejne zamknięcie bez zmian
		-- nie zgłosi fałszywie "niezatwierdzonych" transferów)
		serverBpContents   = result.backpackContents or serverBpContents
		serverBankContents = result.bankContents or serverBankContents
		serverEqPetIds     = petIdSet(result.eqPets)
		serverBankPetIds   = petIdSet(result.bankPets)
		syncInvLayoutToShared()  -- po confirm zapisz nowy layout do głównego ekwipunku
		saveBankLayoutToCache()  -- też zaktualizuj cache banku
		renderAll()
	else
		local msg = "BŁĄD ZAPISU"
		if result.reason == "overCapacity" then msg = "ZA MAŁO MIEJSCA W PLECAKU!"
		elseif result.reason == "bankFull" then msg = "SKARBIEC PEŁNY! (MAX " .. currentBankCap .. ")"
		elseif result.reason == "locked" then msg = "BANK ZABLOKOWANY — KUP FUNDAMENT"
		elseif result.reason == "broke" then msg = "ZA MAŁO ZŁ NA ULEPSZENIE"
		end
		showCapacityError(msg)
	end
end)
