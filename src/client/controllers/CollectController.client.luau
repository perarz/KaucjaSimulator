-- CollectController.luau
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local BUTELKOMAT_TAG = "Butelkomat"

local Events              = ReplicatedStorage:WaitForChild("Events")
local CollectBottle       = Events:WaitForChild("CollectBottle")
local CollectBottleResult = Events:WaitForChild("CollectBottleResult")
local EmptyBackpack       = Events:WaitForChild("EmptyBackpack")
local EmptyBackpackResult = Events:WaitForChild("EmptyBackpackResult")
local UpdateHUD           = Events:WaitForChild("UpdateHUD")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── SFX ───────────────────────────────────────────────────────────────────
local SFX_FOLDER = workspace:WaitForChild("SFX")

local function getOrCreateSfxGroup(): SoundGroup
	local existing = SoundService:FindFirstChild("SfxGroup")
	if existing and existing:IsA("SoundGroup") then return existing :: SoundGroup end
	local g = Instance.new("SoundGroup")
	g.Name   = "SfxGroup"
	g.Volume = 1
	g.Parent = SoundService
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

local function getHRP(): BasePart?
	local char = localPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart
end

-- ── Stałe ─────────────────────────────────────────────────────────────────

local RARITY_ORDER  = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }
local RARITY_COLORS = Config.BottleColors

local SLOT_COUNT       = 60     -- max items w EQ (capacity L4=50 + pety/magnesy/syrop + headroom)
local SLOTS_PER_ROW    = 5
local SLOT_SIZE        = 140
local SLOT_GAP         = 12
local PAD              = 30
local VISIBLE_ROWS     = 4      -- ile rzędów widzimy bez scrollowania (reszta scrolluje)
local SCROLLBAR_THICK  = 8

local C_BG        = Color3.fromRGB(18, 91, 73)
local C_PANEL     = Color3.fromRGB(24, 110, 90)
local C_HEADER    = Color3.fromRGB(0, 53, 39)
local C_SLOT      = Color3.fromRGB(8, 60, 48)
local C_SLOT_OC   = Color3.fromRGB(32, 110, 90)
local C_SLOT_HOV  = Color3.fromRGB(14, 75, 60)
local C_BORDER    = Color3.fromRGB(5, 25, 20)
local C_BORDER_SL = Color3.fromRGB(8, 30, 24)
local C_WHITE     = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT   = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)
local FONT_MAIN   = Enum.Font.GothamBlack

-- ── Typy ──────────────────────────────────────────────────────────────────

type SlotData = { id: string, color: Color3, name: string, count: number }

-- ── Stan lokalny ──────────────────────────────────────────────────────────

local hudData = {
	zlotowki         = 0,
	bottlesCarried   = 0,
	backpackCapacity = Config.BackpackUpgrades[1].Capacity,
	backpackContents = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 },
	hasSyrup         = false,  -- quest item dziadka, zajmuje 1 slot
}

-- Syrop dziadka — kolory i opis dla slotu/detal panelu
local SYRUP_ID    = "Syrop_Maple"
local SYRUP_NAME  = "Syrop Dziadka"
local SYRUP_COLOR = Config.GrandpaQuest and Config.GrandpaQuest.SyrupLight
	or Color3.fromRGB(200, 130, 60)
local SYRUP_DESC  = "Syrop klonowy dziadka. Zanieś go staremu — pewnie da ci coś w zamian."

-- Magnes — używany item, NIE stackuje się (1 sztuka = 1 slot)
local MAGNET_ID    = "Magnet"
local MAGNET_NAME  = (Config.Magnet and Config.Magnet.Name) or "Magnes"
local MAGNET_COLOR = (Config.Magnet and Config.Magnet.Color) or Color3.fromRGB(220, 90, 90)
local MAGNET_DESC  = (Config.Magnet and Config.Magnet.Desc) or "Aktywuj, by zbierać butelki automatycznie."

-- Pet slot id prefix: "Pet_<uuid>". Każdy pet = osobny slot (NIE stackuje się — unikalny UUID).
local PET_ID_PREFIX = "Pet_"
local function isPetSlotId(id: string?): boolean
	return id ~= nil and string.sub(id, 1, #PET_ID_PREFIX) == PET_ID_PREFIX
end

local slots: { SlotData? } = {}
for i = 1, SLOT_COUNT do slots[i] = nil end

-- ── Zarządzanie slotami ───────────────────────────────────────────────────

local function addToInventory(rarity: string)
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id == "Bottle_" .. rarity then
			slots[i].count += 1
			return
		end
	end
	for i = 1, SLOT_COUNT do
		if not slots[i] then
			slots[i] = { id = "Bottle_" .. rarity, color = RARITY_COLORS[rarity], name = rarity, count = 1 }
			return
		end
	end
end

local function clearRarityFromInventory(rarity: string)
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id == "Bottle_" .. rarity then
			slots[i] = nil
			return
		end
	end
end

local function clearSyrupFromInventory()
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id == SYRUP_ID then
			slots[i] = nil
			return
		end
	end
end

local function addSyrupToInventory()
	-- Idempotentne: nie dubluje syropu
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id == SYRUP_ID then return end
	end
	for i = 1, SLOT_COUNT do
		if not slots[i] then
			slots[i] = { id = SYRUP_ID, color = SYRUP_COLOR, name = SYRUP_NAME, count = 1 }
			return
		end
	end
end

-- Magnes — każdy egzemplarz to oddzielny slot (count = 1). Synchronizuje liczbę
-- slotów magnesu z `_G.__magnetState.count` ustawionym przez MagnetController.
local function countMagnetSlots(): number
	local n = 0
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id == MAGNET_ID then n += 1 end
	end
	return n
end

local function syncMagnetSlots()
	local state = _G["__magnetState"]
	local target = (state and tonumber(state.count)) or 0
	local current = countMagnetSlots()
	if target == current then return end
	if target > current then
		local toAdd = target - current
		for i = 1, SLOT_COUNT do
			if toAdd <= 0 then break end
			if not slots[i] then
				slots[i] = { id = MAGNET_ID, color = MAGNET_COLOR, name = MAGNET_NAME, count = 1 }
				toAdd -= 1
			end
		end
	else
		local toRemove = current - target
		for i = SLOT_COUNT, 1, -1 do
			if toRemove <= 0 then break end
			if slots[i] and slots[i].id == MAGNET_ID then
				slots[i] = nil
				toRemove -= 1
			end
		end
	end
end

-- ── Pety ──────────────────────────────────────────────────────────────────
-- Każdy pet = osobny slot (id = "Pet_<uuid>"). Sync z _G.__petsState.pets — lista
-- pełna; usuwamy te których nie ma w state (np. discard/equip-to-bank), dodajemy nowe.
local function syncPetSlots()
	local state = _G["__petsState"]
	local pets = (state and state.pets) or {}

	-- Set istniejących UUID server-side
	local serverSet: { [string]: any } = {}
	for _, p in ipairs(pets) do
		if p and p.id then serverSet[p.id] = p end
	end

	-- 1) Usuń sloty których pet już nie istnieje
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and isPetSlotId(s.id) then
			local uuid = string.sub(s.id, #PET_ID_PREFIX + 1)
			if not serverSet[uuid] then
				slots[i] = nil
			end
		end
	end

	-- 2) Dodaj nowe pety które jeszcze nie mają slotu
	local presentSet: { [string]: boolean } = {}
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and isPetSlotId(s.id) then
			presentSet[string.sub(s.id, #PET_ID_PREFIX + 1)] = true
		end
	end
	for _, p in ipairs(pets) do
		if not presentSet[p.id] then
			-- Znajdź pierwszy wolny slot
			for i = 1, SLOT_COUNT do
				if not slots[i] then
					local rcfg = (Config.Pets and Config.Pets.Rarities and Config.Pets.Rarities[p.rarity]) or {}
					local color = rcfg.color or C_WHITE
					slots[i] = {
						id    = PET_ID_PREFIX .. p.id,
						color = color,
						name  = p.class,  -- "Sprinter" / "Tank" wyświetlane na slocie
						count = 1,
					}
					presentSet[p.id] = true
					break
				end
			end
		end
	end
end

-- Synchronizuje sloty z serwerowym stanem (hudData.backpackContents).
-- ZACHOWUJE split-layout gdy łączne liczby per-rzadkość się zgadzają.
-- Inaczej minimalnie modyfikuje: dolicza do istniejących slotów albo wyzeruje nadmiar.
local function syncSlotsFromContents()
	-- Policz aktualne sumy per rzadkość w slotach
	local currentTotals: { [string]: number } = {}
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and s.id and string.sub(s.id, 1, 7) == "Bottle_" then
			currentTotals[s.name] = (currentTotals[s.name] or 0) + s.count
		end
	end

	-- Dla każdej rzadkości dopasuj sumę do targetu z serwera
	for _, rarity in ipairs(RARITY_ORDER) do
		local target  = hudData.backpackContents[rarity] or 0
		local current = currentTotals[rarity] or 0
		local diff    = target - current
		if diff > 0 then
			-- Trzeba dodać: najpierw dolicz do pierwszego istniejącego slotu tej rzadkości
			local added = false
			for i = 1, SLOT_COUNT do
				if slots[i] and slots[i].name == rarity then
					slots[i].count += diff
					added = true
					break
				end
			end
			if not added then
				for i = 1, SLOT_COUNT do
					if not slots[i] then
						slots[i] = { id = "Bottle_" .. rarity, color = RARITY_COLORS[rarity], name = rarity, count = diff }
						break
					end
				end
			end
		elseif diff < 0 then
			-- Trzeba odjąć: zdejmuj z końca, zerując całe sloty jeśli trzeba
			local toRemove = -diff
			for i = SLOT_COUNT, 1, -1 do
				if toRemove <= 0 then break end
				if slots[i] and slots[i].name == rarity then
					if slots[i].count <= toRemove then
						toRemove -= slots[i].count
						slots[i] = nil
					else
						slots[i].count -= toRemove
						toRemove = 0
					end
				end
			end
		end
	end

	-- Syrop dziadka — niezależnie od butelek
	local hasSyrupSlot = false
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id == SYRUP_ID then hasSyrupSlot = true; break end
	end
	if hudData.hasSyrup and not hasSyrupSlot then
		addSyrupToInventory()
	elseif not hudData.hasSyrup and hasSyrupSlot then
		clearSyrupFromInventory()
	end

	-- Magnes — sync slotów do _G.__magnetState.count
	syncMagnetSlots()
	-- Pety — sync slotów do _G.__petsState.pets
	syncPetSlots()
end

-- ── Helpers UI ────────────────────────────────────────────────────────────

local function mkFrame(parent, size, pos, bg, alpha)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos
	f.BackgroundColor3 = bg or C_BG
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel = 0; f.Parent = parent
	return f
end

local function mkLabel(parent, size, pos, text, textSize, color, xAlign)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = color or C_WHITE
	l.TextSize = textSize or 14
	l.Font = FONT_MAIN
	l.Text = text or ""; l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.BorderSizePixel = 0; l.Parent = parent
	return l
end

local function mkStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color           = color or C_BORDER
	s.Thickness       = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = parent
end

local function mkCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

-- ── HUD ScreenGui ─────────────────────────────────────────────────────────

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "HUD"; hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true; hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Parent = playerGui

-- Wallet: używamy zewnętrznego ScreenGui "Money" wstawionego do StarterGui przez usera.
-- Struktura: PlayerGui.Money.Ramka (ImageLabel) → PLN (TextLabel pod ramką).
-- Ruszamy tylko Ramka (anchor top-center). PLN zostaje w swoim miejscu względem Ramka.
-- walletLabel = TextLabel PLN; updateHud() musi tolerować nil (rezolwuje się asynchronicznie).
local walletLabel: TextLabel = nil :: any
-- Hookup w task.spawn poniżej, PO definicji formatAmount (bo closure go używa).

local invCountLbl: TextLabel? = nil

-- Wstawia przecinki co 3 cyfry w części całkowitej: "100000000" → "100,000,000"
local function withThousandSeparators(intStr: string): string
	-- Obsłuż znak minus
	local sign = ""
	if string.sub(intStr, 1, 1) == "-" then
		sign = "-"; intStr = string.sub(intStr, 2)
	end
	-- gsub iteracyjnie wstawia przecinek przed każdą grupę 3 cyfr od końca
	local out = intStr
	while true do
		local replaced
		out, replaced = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return sign .. out
end

-- Formatuje kwotę w złotówkach z przecinkami co 3 cyfry:
-- integer → "100,000,000"; float → "100,000,000.50"
-- Tolerancja 0.005 żeby uniknąć fałszywych decimali od liczb zmiennoprzecinkowych
local function formatAmount(amount: number): string
	local rounded = math.floor(amount * 100 + 0.5) / 100
	local intPart = math.floor(math.abs(rounded))
	local intStr  = withThousandSeparators(tostring(intPart))
	if rounded < 0 then intStr = "-" .. intStr end
	if math.abs(rounded - math.floor(rounded)) < 0.005 then
		return intStr
	end
	-- Część po przecinku — 2 cyfry, bez separatorów
	local fracPart = math.floor(math.abs(rounded) * 100 + 0.5) % 100
	return string.format("%s.%02d", intStr, fracPart)
end

local function updateHud()
	if walletLabel then
		walletLabel.Text = formatAmount(hudData.zlotowki) .. " PLN"
	end
	if invCountLbl then
		invCountLbl.Text = string.format("%d/%d", hudData.bottlesCarried, hudData.backpackCapacity)
	end
end

-- Hookup zewnętrznego Money ScreenGui — wykonywany PO definicji formatAmount/updateHud
-- (closure capture'uje formatAmount jako upvalue — musi być zadeklarowany przed task.spawn).
--
-- BUGFIX (portfel pokazuje "Label" zamiast kasy): Money ma domyślnie ResetOnSpawn=true,
-- więc przy respawnie (śmierć PvP, DeathDrop instant respawn, reset postępu) Roblox niszczy
-- stary Money i klonuje świeży. Świeży PLN TextLabel ma domyślny tekst "Label", a stary
-- `walletLabel` wskazuje na zniszczony obiekt → updateHud pisze w martwy label.
-- Dlatego rebindujemy przy KAŻDYM nowym Money GUI (ChildAdded) + sync widoczności.
local currentMoneyGui: ScreenGui? = nil
local walletLastEnabled = true

local function hookupWallet(moneyGui: ScreenGui)
	moneyGui.ResetOnSpawn   = false
	moneyGui.IgnoreGuiInset = true
	moneyGui.DisplayOrder   = 50
	currentMoneyGui = moneyGui

	local ramka = moneyGui:WaitForChild("Ramka", 10)
	if not ramka then
		warn("[CollectController] Brak Money.Ramka — wallet HUD nie pokaże złotówek")
		return
	end
	-- Wyśrodkuj ramkę wysoko na górze ekranu — negatywny Y żeby Ramka wjechała wyżej
	-- (PLN siedzi pod Ramką, więc gdy Ramka idzie w górę, PLN też się podnosi razem z nią)
	ramka.AnchorPoint = Vector2.new(0.5, 0)
	ramka.Position    = UDim2.new(0.5, 0, 0, -60)

	local plnLbl = ramka:WaitForChild("PLN", 10)
	if not plnLbl or not plnLbl:IsA("TextLabel") then
		warn("[CollectController] Brak Money.Ramka.PLN (TextLabel)")
		return
	end
	walletLabel = plnLbl
	updateHud()  -- natychmiast wpisz aktualne saldo zamiast domyślnego "Label"

	-- Zsynchronizuj widoczność z aktualnym stanem modalnych UI (świeży klon jest Enabled=true)
	local shouldShow = (tonumber(_G["__moveLockCount"]) or 0) == 0
	moneyGui.Enabled  = shouldShow
	walletLastEnabled = shouldShow
end

task.spawn(function()
	local moneyGui = playerGui:WaitForChild("Money", 15)
	if not moneyGui or not moneyGui:IsA("ScreenGui") then
		warn("[CollectController] Brak PlayerGui.Money (ScreenGui) — wallet HUD nie pokaże złotówek")
		return
	end
	hookupWallet(moneyGui)
end)

-- Re-bind gdy pojawi się świeży Money (respawn / ResetOnSpawn) — inaczej widać "Label".
playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and child.Name == "Money" and child ~= currentMoneyGui then
		task.spawn(hookupWallet, child)
	end
end)

-- Chowanie Money gdy otwarte jakieś modalne UI (menu/sklepy/bank/quest/kosz).
-- Wszystkie te kontrolery wołają _G["__lockMovement"]/__unlockMovement
-- które zwiększają/zmniejszają _G["__moveLockCount"]. Heartbeat toggluje Enabled.
-- Podpięty RAZ, referuje currentMoneyGui (przeżywa rebind przy respawnie).
RunService.Heartbeat:Connect(function()
	local mg = currentMoneyGui
	if not mg then return end
	local count = tonumber(_G["__moveLockCount"]) or 0
	local shouldShow = count == 0
	if shouldShow ~= walletLastEnabled then
		mg.Enabled = shouldShow
		walletLastEnabled = shouldShow
	end
end)

local BTN_W, BTN_H, BTN_GAP = 300, 90, 16
-- 4 przyciski w pionie, wycentrowane na Y=0.5
local STACK_H   = 4 * BTN_H + 3 * BTN_GAP
local STACK_TOP = -STACK_H / 2

local eqBtn = Instance.new("TextButton")
eqBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
eqBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP)
eqBtn.BackgroundColor3 = C_BG; eqBtn.BackgroundTransparency = 0.05
eqBtn.BorderSizePixel = 0; eqBtn.Text = "EKWIPUNEK"; eqBtn.TextSize = 30
eqBtn.Font = FONT_MAIN; eqBtn.TextColor3 = C_WHITE; eqBtn.AutoButtonColor = false
eqBtn.ZIndex = 2; eqBtn.Parent = hudGui
mkStroke(eqBtn, C_BORDER, 4)
mkCorner(eqBtn, 8)

local stBtn = Instance.new("TextButton")
stBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
stBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP + BTN_H + BTN_GAP)
stBtn.BackgroundColor3 = C_BG; stBtn.BackgroundTransparency = 0.05
stBtn.BorderSizePixel = 0; stBtn.Text = "UMIEJĘTNOŚCI"; stBtn.TextSize = 27
stBtn.Font = FONT_MAIN; stBtn.TextColor3 = C_WHITE; stBtn.AutoButtonColor = false
stBtn.ZIndex = 2; stBtn.Parent = hudGui
mkStroke(stBtn, C_BORDER, 4)
mkCorner(stBtn, 8)

local qBtn = Instance.new("TextButton")
qBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
qBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP + 2 * (BTN_H + BTN_GAP))
qBtn.BackgroundColor3 = C_BG; qBtn.BackgroundTransparency = 0.05
qBtn.BorderSizePixel = 0; qBtn.Text = "QUESTY"; qBtn.TextSize = 30
qBtn.Font = FONT_MAIN; qBtn.TextColor3 = C_WHITE; qBtn.AutoButtonColor = false
qBtn.ZIndex = 2; qBtn.Parent = hudGui
mkStroke(qBtn, C_BORDER, 4)
mkCorner(qBtn, 8)

local setBtn = Instance.new("TextButton")
setBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
setBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP + 3 * (BTN_H + BTN_GAP))
setBtn.BackgroundColor3 = C_BG; setBtn.BackgroundTransparency = 0.05
setBtn.BorderSizePixel = 0; setBtn.Text = "USTAWIENIA"; setBtn.TextSize = 26
setBtn.Font = FONT_MAIN; setBtn.TextColor3 = C_WHITE; setBtn.AutoButtonColor = false
setBtn.ZIndex = 2; setBtn.Parent = hudGui
mkStroke(setBtn, C_BORDER, 4)
mkCorner(setBtn, 8)

-- Hover animacja dla przycisków HUD
local function attachBtnHover(btn: TextButton, baseW: number, baseH: number)
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = btn
	local tweenIn  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenOut = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, tweenIn,  { Scale = 1.06 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, tweenOut, { Scale = 1.00 }):Play()
	end)
end
attachBtnHover(eqBtn, BTN_W, BTN_H)
attachBtnHover(stBtn, BTN_W, BTN_H)
attachBtnHover(qBtn, BTN_W, BTN_H)
attachBtnHover(setBtn, BTN_W, BTN_H)

-- Nowy UI (MenuController) zastępuje te 4 przyciski jednym przyciskiem MENU
-- z paskiem zakładek. Stare przyciski ukrywamy ale zostawiamy (click handlery żyją).
eqBtn.Visible  = false
stBtn.Visible  = false
qBtn.Visible   = false
setBtn.Visible = false

-- Otwieranie drzewka przez przycisk (SkillTreeController nasłuchuje klawisza U)
stBtn.MouseButton1Click:Connect(function()
	if _G["__skillTreeToggle"] then
		_G["__skillTreeToggle"]()
	end
end)

-- Otwieranie panelu questów przez przycisk (QuestController nasłuchuje klawisza Q)
qBtn.MouseButton1Click:Connect(function()
	if _G["__questToggle"] then
		_G["__questToggle"]()
	end
end)

-- Otwieranie ustawień
setBtn.MouseButton1Click:Connect(function()
	if _G["__settingsToggle"] then
		_G["__settingsToggle"]()
	end
end)

-- ── Inventory ScreenGui ───────────────────────────────────────────────────

local invGui = Instance.new("ScreenGui")
invGui.Name           = "Inventory"
invGui.ResetOnSpawn   = false
invGui.IgnoreGuiInset = true
invGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
invGui.Enabled        = false
invGui.Parent         = playerGui

-- przyciemnienie tła (klik zamyka)
local invOverlay = Instance.new("TextButton")
invOverlay.Size                   = UDim2.fromScale(1, 1)
invOverlay.BackgroundColor3       = Color3.new(0, 0, 0)
invOverlay.BackgroundTransparency = 1
invOverlay.BorderSizePixel        = 0
invOverlay.Text                   = ""
invOverlay.AutoButtonColor        = false
invOverlay.ZIndex                 = 1
invOverlay.Parent                 = invGui

local INV_HEADER_H = 52
local INV_DET_W    = 480      -- szerokość detail panelu po prawej (wider w nowym menu)
local INV_DET_GAP  = 24       -- gap między slotami a detail panelem
local panelRows    = math.ceil(SLOT_COUNT / SLOTS_PER_ROW)
-- slotsW = pełna szerokość siatki + thickness scrollbara po prawej
local slotsW       = SLOTS_PER_ROW * SLOT_SIZE + (SLOTS_PER_ROW - 1) * SLOT_GAP + SCROLLBAR_THICK + 4
-- slotsH = WIDOCZNA wysokość (VISIBLE_ROWS rzędów) — reszta scrolluje
local slotsH       = VISIBLE_ROWS * SLOT_SIZE + (VISIBLE_ROWS - 1) * SLOT_GAP
-- canvasH = pełna wysokość zawartości (wszystkie rzędy) — ScrollingFrame ją używa
local canvasH      = panelRows * SLOT_SIZE + (panelRows - 1) * SLOT_GAP
local INV_W_COMPACT = slotsW + PAD * 2
local INV_W_WIDE    = INV_W_COMPACT + INV_DET_W + PAD       -- detail + prawy padding
local INV_W        = INV_W_WIDE  -- zachowane dla pozycji detail panelu poniżej
local INV_H        = slotsH + INV_HEADER_H + PAD * 2

local INV_POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local INV_POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local INV_TW_OPEN  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local INV_TW_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local invPanel = mkFrame(invGui, UDim2.fromOffset(INV_W_COMPACT, INV_H), INV_POS_HIDE, C_PANEL, 0.05)
invPanel.AnchorPoint     = Vector2.new(0.5, 0.5)
invPanel.ClipsDescendants = true
invPanel.ZIndex          = 2
mkStroke(invPanel, C_BORDER, 4)
mkCorner(invPanel, 8)

-- header: UICorner zaokrągla wszystkie rogi; dolne maskujemy prostokątnym fillem
-- + cienki separator C_BORDER jako wizualny rozdział od reszty panelu
local invHeader = mkFrame(invPanel, UDim2.new(1, 0, 0, INV_HEADER_H), UDim2.fromOffset(0, 0),
	C_HEADER, 0)
invHeader.ZIndex = 3
mkCorner(invHeader, 8)
do
	local fill = mkFrame(invHeader, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10), C_HEADER, 0)
	fill.ZIndex = 3
	local sep = mkFrame(invHeader, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), C_BORDER, 0)
	sep.ZIndex = 5
end
local invTitle = mkLabel(invHeader, UDim2.fromOffset(140, 52), UDim2.fromOffset(20, 0),
	"EKWIPUNEK", 15, C_WHITE, Enum.TextXAlignment.Left)
invTitle.ZIndex = 4

invCountLbl = mkLabel(invHeader, UDim2.fromOffset(130, 52), UDim2.fromOffset(170, 0),
	"0/10", 20, C_DIMTEXT, Enum.TextXAlignment.Left)
invCountLbl.ZIndex = 4

local X_RED        = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER  = Color3.fromRGB(255, 110, 110)

local invCloseBtn = Instance.new("TextButton")
invCloseBtn.Size                   = UDim2.fromOffset(36, 36)
invCloseBtn.AnchorPoint            = Vector2.new(1, 0.5)
invCloseBtn.Position               = UDim2.new(1, -12, 0.5, 0)
invCloseBtn.BackgroundTransparency = 1
invCloseBtn.BorderSizePixel        = 0
invCloseBtn.Text                   = "X"
invCloseBtn.TextSize               = 24
invCloseBtn.Font                   = FONT_MAIN
invCloseBtn.TextColor3             = X_RED
invCloseBtn.AutoButtonColor        = false
invCloseBtn.ZIndex                 = 5
invCloseBtn.Parent                 = invHeader

-- Hover animacja przycisku X
do
	local xScale = Instance.new("UIScale")
	xScale.Scale = 1
	xScale.Parent = invCloseBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	invCloseBtn.MouseEnter:Connect(function()
		TweenService:Create(xScale, ti, { Scale = 1.18 }):Play()
		invCloseBtn.TextColor3 = X_RED_HOVER
	end)
	invCloseBtn.MouseLeave:Connect(function()
		TweenService:Create(xScale, ti, { Scale = 1.00 }):Play()
		invCloseBtn.TextColor3 = X_RED
	end)
end

-- sloty po lewej stronie panelu (PAD od lewej), detail panel po prawej
-- ScrollingFrame — VISIBLE_ROWS rzędów widocznych, reszta scrolluje
local slotsContainer = Instance.new("ScrollingFrame")
slotsContainer.Size                   = UDim2.fromOffset(slotsW, slotsH)
slotsContainer.Position               = UDim2.fromOffset(PAD, INV_HEADER_H + PAD)
slotsContainer.BackgroundTransparency = 1
slotsContainer.BorderSizePixel        = 0
slotsContainer.CanvasSize             = UDim2.fromOffset(0, canvasH)
slotsContainer.ScrollBarThickness     = SCROLLBAR_THICK
slotsContainer.ScrollBarImageColor3   = C_BORDER
slotsContainer.ScrollingDirection     = Enum.ScrollingDirection.Y
slotsContainer.ZIndex                 = 3
slotsContainer.Parent                 = invPanel

-- ── Detail panel (po prawej) — wysuwa się po kliknięciu w slot ────────────

local BOTTLE_DESC = {
	Zwykla     = "Najpospolitsza butelka. Łatwo ją zebrać, ale wart niewiele.",
	Rzadka     = "Mniej powszechna. Lekko trudniej znaleźć.",
	Epicka     = "Cenny okaz. Trudno trafić, świeci na mapie.",
	Legendarna = "Najrzadsza spośród zwykłych. Bardzo cenna.",
	Mityczny   = "Mityczna butelka. Tylko w strefie tier 5 — najcenniejsza w grze.",
}

-- Detail panel zaczyna się dokładnie na prawej krawędzi compact panelu —
-- gdy panel jest zwinięty, klipuje się 1:1 do prawego brzegu i niczego nie widać
local INV_DET_X_SHOWN  = INV_W_COMPACT

local invDetPanel = mkFrame(invPanel,
	UDim2.fromOffset(INV_DET_W, slotsH),
	UDim2.fromOffset(INV_DET_X_SHOWN, INV_HEADER_H + PAD),
	C_BG, 0.05)
invDetPanel.ZIndex = 4
mkStroke(invDetPanel, C_BORDER, 4)
mkCorner(invDetPanel, 10)

-- Detail close X
local invDetCloseBtn = Instance.new("TextButton")
invDetCloseBtn.Size                   = UDim2.fromOffset(30, 30)
invDetCloseBtn.AnchorPoint            = Vector2.new(1, 0)
invDetCloseBtn.Position               = UDim2.new(1, -12, 0, 12)
invDetCloseBtn.BackgroundTransparency = 1
invDetCloseBtn.BorderSizePixel        = 0
invDetCloseBtn.Text                   = "X"
invDetCloseBtn.TextSize               = 22
invDetCloseBtn.Font                   = FONT_MAIN
invDetCloseBtn.TextColor3             = X_RED
invDetCloseBtn.AutoButtonColor        = false
invDetCloseBtn.ZIndex                 = 6
invDetCloseBtn.Parent                 = invDetPanel
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = invDetCloseBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	invDetCloseBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
		invDetCloseBtn.TextColor3 = X_RED_HOVER
	end)
	invDetCloseBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		invDetCloseBtn.TextColor3 = X_RED
	end)
end

-- Tytuł (nazwa rzadkości)
local invDetTitle = mkLabel(invDetPanel,
	UDim2.new(1, -56, 0, 32), UDim2.fromOffset(16, 18),
	"", 22, C_WHITE, Enum.TextXAlignment.Left)
invDetTitle.ZIndex = 5

-- Podtytuł — count
local invDetCount = mkLabel(invDetPanel,
	UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 52),
	"", 13, C_DIMTEXT, Enum.TextXAlignment.Left)
invDetCount.ZIndex = 5

-- Separator
local invDetSep1 = mkFrame(invDetPanel,
	UDim2.new(1, -32, 0, 1), UDim2.fromOffset(16, 86), C_BORDER, 0)
invDetSep1.ZIndex = 5

-- "Wartość bazowa: X ZŁ za butelkę"
local invDetBaseLbl = mkLabel(invDetPanel,
	UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 98),
	"", 13, C_DIMTEXT, Enum.TextXAlignment.Left)
invDetBaseLbl.ZIndex = 5

-- Łączna wartość bez multipliera (count × base)
local invDetTotalLbl = mkLabel(invDetPanel,
	UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 122),
	"", 16, C_WHITE, Enum.TextXAlignment.Left)
invDetTotalLbl.ZIndex = 5

-- Z multiplierem
local invDetMultLbl = mkLabel(invDetPanel,
	UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 150),
	"", 16, C_ACCENT_GREEN, Enum.TextXAlignment.Left)
invDetMultLbl.ZIndex = 5

-- Separator
local invDetSep2 = mkFrame(invDetPanel,
	UDim2.new(1, -32, 0, 1), UDim2.fromOffset(16, 188), C_BORDER, 0)
invDetSep2.ZIndex = 5

-- Opis
local invDetDesc = mkLabel(invDetPanel,
	UDim2.new(1, -32, 0, 100), UDim2.fromOffset(16, 200),
	"", 13, C_DIMTEXT, Enum.TextXAlignment.Left)
invDetDesc.TextWrapped     = true
invDetDesc.TextYAlignment  = Enum.TextYAlignment.Top
invDetDesc.ZIndex          = 5

-- Przycisk UPUŚĆ (1 sztukę przed graczem) — niedostępny dla syropu (quest item)
local DropBottleEvt = ReplicatedStorage:WaitForChild("Events"):WaitForChild("DropBottle")
local invDetDropBtn = Instance.new("TextButton")
invDetDropBtn.Size                   = UDim2.new(1, -32, 0, 44)
invDetDropBtn.AnchorPoint            = Vector2.new(0, 1)
invDetDropBtn.Position               = UDim2.new(0, 16, 1, -16)
invDetDropBtn.BackgroundColor3       = Color3.fromRGB(180, 70, 70)
invDetDropBtn.BorderSizePixel        = 0
invDetDropBtn.Text                   = "UPUŚĆ 1 SZTUKĘ"
invDetDropBtn.TextSize               = 16
invDetDropBtn.Font                   = FONT_MAIN
invDetDropBtn.TextColor3             = C_WHITE
invDetDropBtn.AutoButtonColor        = false
invDetDropBtn.ZIndex                 = 6
invDetDropBtn.Parent                 = invDetPanel

-- Przycisk UŻYJ (tylko dla magnesu) — aktywuje 2-min sweep
local invDetUseBtn = Instance.new("TextButton")
invDetUseBtn.Size                   = UDim2.new(1, -32, 0, 44)
invDetUseBtn.AnchorPoint            = Vector2.new(0, 1)
invDetUseBtn.Position               = UDim2.new(0, 16, 1, -16)
invDetUseBtn.BackgroundColor3       = MAGNET_COLOR
invDetUseBtn.BorderSizePixel        = 0
invDetUseBtn.Text                   = "UŻYJ"
invDetUseBtn.TextSize               = 18
invDetUseBtn.Font                   = FONT_MAIN
invDetUseBtn.TextColor3             = C_WHITE
invDetUseBtn.AutoButtonColor        = false
invDetUseBtn.Visible                = false
invDetUseBtn.ZIndex                 = 6
invDetUseBtn.Parent                 = invDetPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = invDetUseBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = invDetUseBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = invDetUseBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	invDetUseBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.04 }):Play()
	end)
	invDetUseBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
	end)
end
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = invDetDropBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = invDetDropBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = invDetDropBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	invDetDropBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.04 }):Play()
		invDetDropBtn.BackgroundColor3 = Color3.fromRGB(220, 90, 90)
	end)
	invDetDropBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		invDetDropBtn.BackgroundColor3 = Color3.fromRGB(180, 70, 70)
	end)
end

local invDetVisible: boolean = false
local invDetCurrentRarity: string? = nil

invDetDropBtn.MouseButton1Click:Connect(function()
	local r = invDetCurrentRarity
	if not r or r == SYRUP_ID or r == MAGNET_ID then return end
	if (hudData.backpackContents[r] or 0) <= 0 then return end
	DropBottleEvt:FireServer(r)
end)

invDetUseBtn.MouseButton1Click:Connect(function()
	if invDetCurrentRarity ~= MAGNET_ID then return end
	local mState = _G["__magnetState"] or { count = 0, active = false }
	if (mState.count or 0) <= 0 or mState.active then return end
	playSfx("Click")
	if _G["__magnetTryUse"] then _G["__magnetTryUse"]() end
	hideInvDetail()
end)

-- Handlery petów PONIŻEJ definicji buttonów (linia ~859) — order issue jeśli tu

-- ── Pet buttons (ZAŁÓŻ/ZDEJMIJ + WYRZUĆ) ──────────────────────────────────
local PetEvents          = ReplicatedStorage:WaitForChild("Events")
local EquipPetEvt        = PetEvents:WaitForChild("EquipPet")
local UnequipPetEvt      = PetEvents:WaitForChild("UnequipPet")
local DiscardPetEvt      = PetEvents:WaitForChild("DiscardPet")

local invDetPetEquipBtn = Instance.new("TextButton")
invDetPetEquipBtn.Size                   = UDim2.new(1, -32, 0, 44)
invDetPetEquipBtn.AnchorPoint            = Vector2.new(0, 1)
invDetPetEquipBtn.Position               = UDim2.new(0, 16, 1, -68)  -- nad WYRZUĆ
invDetPetEquipBtn.BackgroundColor3       = C_ACCENT_GREEN
invDetPetEquipBtn.BorderSizePixel        = 0
invDetPetEquipBtn.Text                   = "ZAŁÓŻ"
invDetPetEquipBtn.TextSize               = 16
invDetPetEquipBtn.Font                   = FONT_MAIN
invDetPetEquipBtn.TextColor3             = Color3.new(0, 0, 0)
invDetPetEquipBtn.AutoButtonColor        = false
invDetPetEquipBtn.Visible                = false
invDetPetEquipBtn.ZIndex                 = 6
invDetPetEquipBtn.Parent                 = invDetPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = invDetPetEquipBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = invDetPetEquipBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	invDetPetEquipBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	invDetPetEquipBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

local invDetPetDiscardBtn = Instance.new("TextButton")
invDetPetDiscardBtn.Size                   = UDim2.new(1, -32, 0, 44)
invDetPetDiscardBtn.AnchorPoint            = Vector2.new(0, 1)
invDetPetDiscardBtn.Position               = UDim2.new(0, 16, 1, -16)
invDetPetDiscardBtn.BackgroundColor3       = Color3.fromRGB(180, 70, 70)
invDetPetDiscardBtn.BorderSizePixel        = 0
invDetPetDiscardBtn.Text                   = "WYRZUĆ"
invDetPetDiscardBtn.TextSize               = 16
invDetPetDiscardBtn.Font                   = FONT_MAIN
invDetPetDiscardBtn.TextColor3             = C_WHITE
invDetPetDiscardBtn.AutoButtonColor        = false
invDetPetDiscardBtn.Visible                = false
invDetPetDiscardBtn.ZIndex                 = 6
invDetPetDiscardBtn.Parent                 = invDetPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = invDetPetDiscardBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = invDetPetDiscardBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	invDetPetDiscardBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	invDetPetDiscardBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- Pet click handlers (PO definicji buttonów żeby uniknąć order bug)
invDetPetEquipBtn.MouseButton1Click:Connect(function()
	if not isPetSlotId(invDetCurrentRarity) then return end
	local uuid = string.sub(invDetCurrentRarity, #PET_ID_PREFIX + 1)
	local state = _G["__petsState"]
	local equippedId = (state and state.equippedId) or ""
	playSfx("Click")
	if uuid == equippedId then
		UnequipPetEvt:FireServer()
	else
		EquipPetEvt:FireServer(uuid)
	end
end)

invDetPetDiscardBtn.MouseButton1Click:Connect(function()
	if not isPetSlotId(invDetCurrentRarity) then return end
	local uuid = string.sub(invDetCurrentRarity, #PET_ID_PREFIX + 1)
	playSfx("Click")
	DiscardPetEvt:FireServer(uuid)
	hideInvDetail()
end)

-- (rejestracja listenera __magnetAddListener jest na końcu pliku — po definicji updateInventory)

local INV_DET_TI_OPEN  = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local INV_DET_TI_CLOSE = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function getMultiplier(): number
	-- Pobiera aktualny mnożnik z SkillTreeController (0 = brak, czyli 1.0)
	local st = _G["__skillTreeState"]
	local lvl = st and st.data and st.data.MultiplierLevel or 0
	if lvl > 0 then return Config.MultiplierUpgrades[lvl].Multiplier end
	return 1.0
end

local function refreshInvDetail()
	if not invDetCurrentRarity then return end
	local rarity = invDetCurrentRarity

	-- Quest item: syrop dziadka — inny widok (bez wartości / mnożnika)
	if rarity == SYRUP_ID then
		invDetTitle.Text       = SYRUP_NAME
		invDetTitle.TextColor3 = SYRUP_COLOR
		invDetCount.Text       = "Posiadasz: 1 sztukę"
		invDetBaseLbl.Text     = "Przedmiot zadania"
		invDetTotalLbl.Text    = "Nie sprzedasz tego w butelkomacie"
		invDetMultLbl.Text     = ""
		invDetDesc.Text        = SYRUP_DESC
		return
	end

	-- Pet — każdy slot to konkretny pet (id = "Pet_<uuid>")
	if isPetSlotId(rarity) then
		local uuid = string.sub(rarity, #PET_ID_PREFIX + 1)
		local state = _G["__petsState"]
		local pets  = (state and state.pets) or {}
		local equippedId = (state and state.equippedId) or ""
		local pet
		for _, p in ipairs(pets) do
			if p.id == uuid then pet = p; break end
		end
		if not pet then
			invDetTitle.Text = "Pet"
			invDetCount.Text = "(usunięty)"
			invDetBaseLbl.Text = ""
			invDetTotalLbl.Text = ""
			invDetMultLbl.Text = ""
			invDetDesc.Text = ""
			return
		end
		local rcfg = (Config.Pets and Config.Pets.Rarities and Config.Pets.Rarities[pet.rarity]) or {}
		local ccfg = (Config.Pets and Config.Pets.Classes and Config.Pets.Classes[pet.class]) or {}
		local color = rcfg.color or C_WHITE
		local rname = rcfg.displayName or pet.rarity

		invDetTitle.Text       = string.format("%s %s", rname, pet.class)
		invDetTitle.TextColor3 = color
		invDetCount.Text       = (uuid == equippedId) and "WYPOSAŻONY ✓" or "1 sztuka"
		invDetCount.TextColor3 = (uuid == equippedId) and C_ACCENT_GREEN or C_DIMTEXT
		invDetBaseLbl.Text     = string.format("Mnożnik kasy: ×%.1f", rcfg.moneyMul or 1)
		local bonus = (ccfg.bonuses and ccfg.bonuses[pet.rarity]) or 0
		if ccfg.effect == "speed" then
			invDetTotalLbl.Text = string.format("Speed bonus: +%d (chodzenie i deska)", bonus)
		elseif ccfg.effect == "hp" then
			invDetTotalLbl.Text = string.format("HP bonus: +%d", bonus)
		else
			invDetTotalLbl.Text = ""
		end
		invDetMultLbl.Text = ""
		invDetDesc.Text    = "Tylko 1 pet może być wyposażony naraz. Wyrzucenie usuwa pet na stałe."
		return
	end

	-- Magnes — każdy slot to OSOBNA sztuka (count zawsze 1, klikany pojedynczo)
	if rarity == MAGNET_ID then
		local mState = _G["__magnetState"] or { count = 0, active = false, secondsLeft = 0 }
		invDetTitle.Text       = MAGNET_NAME
		invDetTitle.TextColor3 = MAGNET_COLOR
		invDetCount.Text       = "1 sztuka"
		invDetBaseLbl.Text     = string.format("Czas działania: %d s", Config.Magnet.DurationSec)
		invDetTotalLbl.Text    = string.format("Promień: ×%.1f", Config.Magnet.RadiusMultiplier)
		if mState.active then
			invDetMultLbl.Text = string.format("AKTYWNY — zostało %ds", math.ceil(mState.secondsLeft or 0))
			invDetMultLbl.TextColor3 = MAGNET_COLOR
		else
			invDetMultLbl.Text = ""
		end
		invDetDesc.Text        = MAGNET_DESC
		return
	end

	local count = hudData.backpackContents[rarity] or 0
	local color = RARITY_COLORS[rarity] or C_WHITE
	local baseVal = Config.BottleValues[rarity] or 0
	local mult = getMultiplier()

	invDetTitle.Text       = rarity
	invDetTitle.TextColor3 = color
	invDetCount.Text       = "Posiadasz: " .. count .. " sztuk"
	invDetBaseLbl.Text     = "Wartość bazowa: " .. formatAmount(baseVal) .. " ZŁ / sztukę"
	local total = count * baseVal
	invDetTotalLbl.Text    = "Razem (×1): " .. formatAmount(total) .. " ZŁ"
	local totalMult = total * mult
	invDetMultLbl.Text     = string.format("Z mnożnikiem (×%.1f): %s ZŁ", mult, formatAmount(totalMult))
	invDetDesc.Text        = BOTTLE_DESC[rarity] or ""
end

-- Placeholder pokazywany w detail panelu gdy żaden item nie jest wybrany
local invDetPlaceholder = Instance.new("TextLabel")
invDetPlaceholder.AnchorPoint            = Vector2.new(0.5, 0.5)
invDetPlaceholder.Position               = UDim2.fromScale(0.5, 0.5)
invDetPlaceholder.Size                   = UDim2.new(1, -32, 0, 120)
invDetPlaceholder.BackgroundTransparency = 1
invDetPlaceholder.Text                   = "Kliknij item\naby zobaczyć szczegóły"
invDetPlaceholder.Font                   = FONT_MAIN
invDetPlaceholder.TextSize               = 16
invDetPlaceholder.TextColor3             = C_DIMTEXT
invDetPlaceholder.TextXAlignment         = Enum.TextXAlignment.Center
invDetPlaceholder.TextYAlignment         = Enum.TextYAlignment.Center
invDetPlaceholder.TextWrapped            = true
invDetPlaceholder.ZIndex                 = 5
invDetPlaceholder.Parent                 = invDetPanel

local function setInvDetailContentVisible(visible: boolean)
	invDetTitle.Visible    = visible
	invDetCount.Visible    = visible
	invDetSep1.Visible     = visible
	invDetBaseLbl.Visible  = visible
	invDetTotalLbl.Visible = visible
	invDetMultLbl.Visible  = visible
	invDetSep2.Visible     = visible
	invDetDesc.Visible     = visible
	invDetCloseBtn.Visible = visible
	local isPet = visible and isPetSlotId(invDetCurrentRarity)
	-- DROP: tylko dla butelek (nie syrop, nie magnes, nie pet)
	invDetDropBtn.Visible  = visible
		and invDetCurrentRarity ~= SYRUP_ID
		and invDetCurrentRarity ~= MAGNET_ID
		and not isPet
	-- UŻYJ: tylko dla magnesu
	invDetUseBtn.Visible   = visible and invDetCurrentRarity == MAGNET_ID
	if invDetUseBtn.Visible then
		local mState = _G["__magnetState"] or { count = 0, active = false }
		local canUse = (mState.count or 0) > 0 and not mState.active
		invDetUseBtn.BackgroundColor3 = canUse and MAGNET_COLOR or Color3.fromRGB(90, 90, 90)
		invDetUseBtn.Text = mState.active and "AKTYWNY…" or (canUse and "UŻYJ" or "BRAK MAGNESÓW")
		invDetUseBtn.AutoButtonColor = false
	end
	-- PET: ZAŁÓŻ/ZDEJMIJ + WYRZUĆ
	invDetPetEquipBtn.Visible   = isPet
	invDetPetDiscardBtn.Visible = isPet
	if isPet then
		local uuid = string.sub(invDetCurrentRarity, #PET_ID_PREFIX + 1)
		local state = _G["__petsState"]
		local equippedId = (state and state.equippedId) or ""
		if uuid == equippedId then
			invDetPetEquipBtn.Text            = "ZDEJMIJ"
			invDetPetEquipBtn.BackgroundColor3 = Color3.fromRGB(190, 150, 60)
			invDetPetEquipBtn.TextColor3       = C_WHITE
		else
			invDetPetEquipBtn.Text            = "ZAŁÓŻ"
			invDetPetEquipBtn.BackgroundColor3 = C_ACCENT_GREEN
			invDetPetEquipBtn.TextColor3       = Color3.new(0, 0, 0)
		end
	end
	invDetPlaceholder.Visible = not visible
end

local function showInvDetail(rarity: string)
	-- Zawsze pokazuj detale klikniętego itemu (bez toggle na tej samej rzadkości).
	-- Chowanie: tylko X w detail panelu albo zamknięcie ekwipunku.
	invDetCurrentRarity = rarity
	refreshInvDetail()
	setInvDetailContentVisible(true)
	invDetVisible = true
end

local function hideInvDetail()
	if not invDetVisible then return end
	invDetVisible = false
	invDetCurrentRarity = nil
	setInvDetailContentVisible(false)
end

invDetCloseBtn.MouseButton1Click:Connect(function() playSfx("Click"); hideInvDetail() end)

-- Initial state — placeholder widoczny, X i content schowane
setInvDetailContentVisible(false)

-- ── Wrapper EKWIPUNEK dla MenuController ─────────────────────────────────
-- Mounted bez własnej ramki/headera — pasek zakładek menu już to robi.
-- Layout: count label "X/Y" u góry, sloty po lewej, detail panel po prawej.
local INV_TOP_LBL_H = 28
local inventoryWrap = Instance.new("Frame")
inventoryWrap.Size                   = UDim2.fromOffset(slotsW + INV_DET_GAP + INV_DET_W, slotsH + INV_TOP_LBL_H)
inventoryWrap.BackgroundTransparency = 1
inventoryWrap.BorderSizePixel        = 0
inventoryWrap.AnchorPoint            = Vector2.new(0.5, 0.5)
inventoryWrap.Position               = UDim2.fromScale(0.5, 0.5)
inventoryWrap.Parent                 = invPanel  -- domyślnie w hidden invGui

-- Reparent + reposition: header niewidoczny, content w wrapie
invHeader.Visible    = false

invCountLbl.Parent   = inventoryWrap
invCountLbl.Position = UDim2.fromOffset(0, 0)
invCountLbl.Size     = UDim2.fromOffset(slotsW, INV_TOP_LBL_H)
invCountLbl.TextXAlignment = Enum.TextXAlignment.Left
invCountLbl.TextColor3 = C_DIMTEXT

slotsContainer.Parent   = inventoryWrap
slotsContainer.Position = UDim2.fromOffset(0, INV_TOP_LBL_H)

invDetPanel.Parent   = inventoryWrap
invDetPanel.Position = UDim2.fromOffset(slotsW + INV_DET_GAP, INV_TOP_LBL_H)

-- Eksport dla MenuController
_G["__inventoryWrap"]  = inventoryWrap
_G["__inventoryReady"] = true

-- ── Slot frames ───────────────────────────────────────────────────────────

local slotFrames:    { Frame }     = {}
local slotAccents:   { Frame }     = {}    -- ukryty (legacy, używany w startDrag)
local slotNameLbls:  { TextLabel } = {}
local slotCountLbls: { TextLabel } = {}
local slotScales:    { UIScale }   = {}
local slotStrokes:   { UIStroke }  = {}
local slotPetGlows:  { Frame }     = {}    -- gradient overlay dla petów (diagonalna animacja)
local slotPetGrads:  { UIGradient } = {}
local slotLegGlows:  { Frame }     = {}
local slotLegGrads:  { UIGradient } = {}
local slotMytGlows:  { Frame }     = {}
local slotMytGrads:  { UIGradient } = {}

local function darken(c: Color3, mix: number): Color3
	return Color3.new(c.R * (1 - mix), c.G * (1 - mix), c.B * (1 - mix))
end

for i = 1, SLOT_COUNT do
	local col = (i - 1) % SLOTS_PER_ROW
	local row = math.floor((i - 1) / SLOTS_PER_ROW)

	-- AnchorPoint w środku, by UIScale rosło ze środka
	local sf = mkFrame(slotsContainer,
		UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
		UDim2.new(0,
			col * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE/2,
			0,
			row * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE/2),
		C_SLOT, 0)
	sf.AnchorPoint = Vector2.new(0.5, 0.5)
	sf.ClipsDescendants = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = C_BORDER_SL; stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = sf
	mkCorner(sf, 12)

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = sf

	-- Legendary glow overlay (pod tekstem, na slocie)
	local legGlow = Instance.new("Frame")
	legGlow.Size = UDim2.fromScale(1, 1)
	legGlow.Position = UDim2.fromScale(0, 0)
	legGlow.BackgroundColor3 = Color3.fromRGB(255, 230, 100)
	legGlow.BackgroundTransparency = 0.4
	legGlow.BorderSizePixel = 0
	legGlow.Visible = false
	legGlow.ZIndex = 0
	legGlow.Parent = sf
	mkCorner(legGlow, 12)

	local legGrad = Instance.new("UIGradient")
	legGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 235, 130)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 40)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 235, 130)),
	})
	legGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.15),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1,   0.15),
	})
	legGrad.Rotation = 0
	legGrad.Parent = legGlow

	-- Legacy "accent" — niewidoczny ale potrzebny dla startDrag
	local accent = mkFrame(sf, UDim2.new(0, 1, 0, 1), UDim2.new(0, 0, 0, 0), C_WHITE, 1)
	accent.Visible = false

	local nameLbl = mkLabel(sf, UDim2.new(1, -16, 0, 22), UDim2.new(0, 12, 0, 8), "", 17, C_WHITE)
	nameLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	nameLbl.TextStrokeTransparency = 0.3
	nameLbl.ZIndex = 2
	local cntLbl  = mkLabel(sf, UDim2.new(1, -12, 0, 40), UDim2.new(0, 0, 1, -46),
		"", 32, C_WHITE, Enum.TextXAlignment.Right)
	cntLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	cntLbl.TextStrokeTransparency = 0.2
	cntLbl.ZIndex = 2

	slotFrames[i]    = sf
	slotAccents[i]   = accent
	slotNameLbls[i]  = nameLbl
	slotCountLbls[i] = cntLbl
	slotScales[i]    = scale
	slotStrokes[i]   = stroke
	slotLegGlows[i]  = legGlow
	slotLegGrads[i]  = legGrad

	-- Mythic glow overlay (fiolet ↔ czarny) — taka sama mechanika jak Legendary
	local mytGlow = Instance.new("Frame")
	mytGlow.Size = UDim2.fromScale(1, 1)
	mytGlow.Position = UDim2.fromScale(0, 0)
	mytGlow.BackgroundColor3 = Color3.fromRGB(80, 30, 140)
	mytGlow.BackgroundTransparency = 0.35
	mytGlow.BorderSizePixel = 0
	mytGlow.Visible = false
	mytGlow.ZIndex = 0
	mytGlow.Parent = sf
	mkCorner(mytGlow, 12)
	local mytGrad = Instance.new("UIGradient")
	mytGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(150, 50, 220)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10,  0,  20)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(150, 50, 220)),
	})
	mytGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.15),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1,   0.15),
	})
	mytGrad.Rotation = 0
	mytGrad.Parent = mytGlow
	slotMytGlows[i] = mytGlow
	slotMytGrads[i] = mytGrad

	-- Pet glow overlay — diagonalny gradient (45°) z kolorem peta + bielą.
	-- Rotuje wolniej niż Legendary/Mythic, transparency mniej intensywna — subtelniejszy efekt.
	local petGlow = Instance.new("Frame")
	petGlow.Size = UDim2.fromScale(1, 1)
	petGlow.Position = UDim2.fromScale(0, 0)
	petGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)  -- nadpisywane w renderSlot per pet
	petGlow.BackgroundTransparency = 0.55
	petGlow.BorderSizePixel = 0
	petGlow.Visible = false
	petGlow.ZIndex = 0
	petGlow.Parent = sf
	mkCorner(petGlow, 12)
	local petGrad = Instance.new("UIGradient")
	petGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 255, 255)),
	})  -- ColorSequence ustawiany dynamicznie w renderSlot (per pet color)
	petGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.85),
		NumberSequenceKeypoint.new(0.5,  0.10),
		NumberSequenceKeypoint.new(1,    0.85),
	})
	petGrad.Rotation = 45
	petGrad.Parent = petGlow
	slotPetGlows[i] = petGlow
	slotPetGrads[i] = petGrad
end

-- ── Render ────────────────────────────────────────────────────────────────

local function renderSlot(i: number)
	local data = slots[i]
	if data then
		slotFrames[i].BackgroundColor3 = darken(data.color, 0.45)
		slotStrokes[i].Color           = data.color
		slotStrokes[i].Thickness       = 3
		slotNameLbls[i].Text           = data.name
		slotNameLbls[i].TextColor3     = C_WHITE
		slotCountLbls[i].Text          = tostring(data.count)
		slotCountLbls[i].TextColor3    = C_WHITE
		slotLegGlows[i].Visible        = (data.name == "Legendarna")
		slotMytGlows[i].Visible        = (data.name == "Mityczny")
		-- Pet slot — pokaż diagonalny gradient w kolorze peta
		local isPet = isPetSlotId(data.id)
		slotPetGlows[i].Visible = isPet
		if isPet then
			-- ColorSequence: kolor rzadkości → biel → kolor rzadkości
			slotPetGrads[i].Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   data.color),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1,   data.color),
			})
			-- Ukryj zwykły count (1) dla peta — pokażemy emoji klasy
			-- (slotNameLbls jest "Sprinter"/"Tank", count "1" pomijamy bo każdy pet = 1)
			slotCountLbls[i].Text = ""
		end
	else
		slotFrames[i].BackgroundColor3 = C_SLOT
		slotStrokes[i].Color           = C_BORDER_SL
		slotStrokes[i].Thickness       = 3
		slotNameLbls[i].Text           = ""
		slotCountLbls[i].Text          = ""
		slotLegGlows[i].Visible        = false
		slotMytGlows[i].Visible        = false
		slotPetGlows[i].Visible        = false
	end
end

-- Forward: scheduleLayoutSync używany przez updateInventory, definicja niżej
local scheduleLayoutSync: () -> ()

local function updateInventory()
	for i = 1, SLOT_COUNT do renderSlot(i) end
	scheduleLayoutSync()
end

-- Wysyłanie layoutu do serwera (debounce 0.5s)
local SyncInventoryLayout = ReplicatedStorage:WaitForChild("Events"):WaitForChild("SyncInventoryLayout")
local pendingSyncJob: thread? = nil
scheduleLayoutSync = function()
	if pendingSyncJob then task.cancel(pendingSyncJob) end
	pendingSyncJob = task.delay(0.5, function()
		pendingSyncJob = nil
		-- Wysyłamy LAYOUT z pozycjami slotów (nie tylko ordered list) żeby pozycje persystowały
		local layout = {}
		for i = 1, SLOT_COUNT do
			local s = slots[i]
			if s and s.id and string.sub(s.id, 1, 7) == "Bottle_" then
				layout[tostring(i)] = { rarity = s.name, count = s.count }
			end
		end
		SyncInventoryLayout:FireServer(layout)
	end)
end

-- Shared inventory layout API — zachowuje DOKŁADNE pozycje slotów (np. stack w slocie 7 zostaje w slocie 7).
-- Format: { [slotIdx] = { rarity, count } }. Używane przez BankController + persystencję na serwerze.
_G["__inventoryGetLayout"] = function(): { [number]: { rarity: string, count: number } }
	local out = {}
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and s.id and string.sub(s.id, 1, 7) == "Bottle_" then
			out[i] = { rarity = s.name, count = s.count }
		end
	end
	return out
end

_G["__inventorySetLayout"] = function(layout: { [number]: { rarity: string, count: number } })
	-- Zeruj sloty butelek (syrop zachowany na swojej pozycji)
	for i = 1, SLOT_COUNT do
		if slots[i] and slots[i].id and string.sub(slots[i].id, 1, 7) == "Bottle_" then
			slots[i] = nil
		end
	end
	-- Wstaw każdy stack na jego ZAPISANY slot
	local function isProtected(idx: number): boolean
		local sl = slots[idx]
		return sl ~= nil and (sl.id == SYRUP_ID or sl.id == MAGNET_ID or isPetSlotId(sl.id))
	end
	for slotIdx, s in pairs(layout) do
		local i = tonumber(slotIdx)
		if i and i >= 1 and i <= SLOT_COUNT then
			-- Nie nadpisuj syropu ani magnesu — jeśli ten slot zajęty, znajdź wolny niżej
			if isProtected(i) then
				for j = 1, SLOT_COUNT do
					if not slots[j] then i = j; break end
				end
			end
			if not isProtected(i) then
				slots[i] = {
					id    = "Bottle_" .. s.rarity,
					name  = s.rarity,
					color = RARITY_COLORS[s.rarity] or C_WHITE,
					count = s.count,
				}
			end
		end
	end
	updateInventory()
end

-- Stacks API (uporządkowana lista, używane przez Bank UI który nie zna pozycji)
_G["__inventoryGetStacks"] = function(): { { rarity: string, count: number } }
	local out = {}
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and s.id and string.sub(s.id, 1, 7) == "Bottle_" then
			table.insert(out, { rarity = s.name, count = s.count })
		end
	end
	return out
end

-- setStacks: bank zapisuje stacki BEZ pozycji, więc układamy je inteligentnie:
-- najpierw próbujemy zachować obecny porządek butelek (jeśli sumy się zgadzają),
-- inaczej wypełniamy od początku omijając zajęte sloty.
_G["__inventorySetStacks"] = function(stacks: { { rarity: string, count: number } })
	-- Policz aktualne stacki + zapamiętaj ich pozycje per rzadkość
	local existingPositions: { [string]: { number } } = {}
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s and s.id and string.sub(s.id, 1, 7) == "Bottle_" then
			existingPositions[s.name] = existingPositions[s.name] or {}
			table.insert(existingPositions[s.name], i)
			slots[i] = nil  -- czyścimy, wrzucimy z powrotem niżej
		end
	end

	-- Wstaw każdy stack — najpierw szukamy starej pozycji tej rzadkości, inaczej pierwszego wolnego slotu
	for _, s in ipairs(stacks) do
		local placed = false
		local positions = existingPositions[s.rarity]
		if positions and #positions > 0 then
			local idx = table.remove(positions, 1)
			local prot = slots[idx] and (slots[idx].id == SYRUP_ID or slots[idx].id == MAGNET_ID or isPetSlotId(slots[idx].id))
			if not prot then
				slots[idx] = {
					id    = "Bottle_" .. s.rarity,
					name  = s.rarity,
					color = RARITY_COLORS[s.rarity] or C_WHITE,
					count = s.count,
				}
				placed = true
			end
		end
		if not placed then
			for j = 1, SLOT_COUNT do
				if not slots[j] then
					slots[j] = {
						id    = "Bottle_" .. s.rarity,
						name  = s.rarity,
						color = RARITY_COLORS[s.rarity] or C_WHITE,
						count = s.count,
					}
					break
				end
			end
		end
	end
	updateInventory()
end

-- ── VFX Legendarnej ───────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function(dt)
	local t = tick()
	for i = 1, SLOT_COUNT do
		local data = slots[i]
		if data and data.name == "Legendarna" then
			local pulse = (math.sin(t * 4.5) + 1) * 0.5  -- 0..1
			slotStrokes[i].Color = Color3.fromRGB(
				255,
				200 + math.floor(pulse * 55),
				60  + math.floor(pulse * 195))
			slotStrokes[i].Thickness = 3 + pulse * 2.5
			slotLegGrads[i].Rotation = (slotLegGrads[i].Rotation + 80 * dt) % 360
		elseif data and data.name == "Mityczny" then
			local pulse = (math.sin(t * 4.0) + 1) * 0.5
			slotStrokes[i].Color = Color3.fromRGB(
				80  + math.floor(pulse * 100),
				20  + math.floor(pulse * 60),
				140 + math.floor(pulse * 100))
			slotStrokes[i].Thickness = 3 + pulse * 2.5
			slotMytGrads[i].Rotation = (slotMytGrads[i].Rotation + 60 * dt) % 360
		elseif data and isPetSlotId(data.id) then
			-- Pet: diagonalny shimmer (45° wolniej niż legendary) — odróżnia od butelek
			slotPetGrads[i].Rotation = (slotPetGrads[i].Rotation + 45 * dt) % 360
			-- Subtelny pulse stroke w kolorze peta
			local pulse = (math.sin(t * 3.0) + 1) * 0.5  -- 0..1
			slotStrokes[i].Thickness = 3 + pulse * 1.5
		end
	end
end)

-- ── Drag & Drop ───────────────────────────────────────────────────────────

local drag = { active = false, fromSlot = 0, startPos = Vector2.zero, moved = false, isSplit = false, splitCount = 0 }
local ghost: Frame?        = nil
local hoveredSlot: number? = nil
local recentlyDragged      = false
local DRAG_CLICK_THRESHOLD = 5  -- piksele — ponizej tego = klik (pokaż detail)

local function ghostPositionFromMouse(): UDim2
	local mouse = UserInputService:GetMouseLocation()
	-- IgnoreGuiInset=true: pozycja 1:1 ze screen coordinates
	return UDim2.new(0, mouse.X - SLOT_SIZE / 2, 0, mouse.Y - SLOT_SIZE / 2)
end

-- Podświetlenie hovered slotu
local function setSlotHighlight(i: number, on: boolean)
	if drag.active and i == drag.fromSlot then return end
	if on then
		slotFrames[i].BackgroundColor3 = C_SLOT_HOV
		local hoverStroke = slotFrames[i]:FindFirstChildOfClass("UIStroke") :: UIStroke
		if hoverStroke then hoverStroke.Color = C_BORDER_SL end
	else
		renderSlot(i)
		local s = slotFrames[i]:FindFirstChildOfClass("UIStroke") :: UIStroke
		if s then s.Color = C_BORDER end
	end
end

-- MouseEnter / MouseLeave na każdym slocie — to jest nasze hit-testing
local SLOT_TI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for i = 1, SLOT_COUNT do
	local idx = i
	slotFrames[i].MouseEnter:Connect(function()
		hoveredSlot = idx
		TweenService:Create(slotScales[idx], SLOT_TI, { Scale = 1.06 }):Play()
		if drag.active then
			setSlotHighlight(idx, true)
		end
	end)
	slotFrames[i].MouseLeave:Connect(function()
		if hoveredSlot == idx then hoveredSlot = nil end
		TweenService:Create(slotScales[idx], SLOT_TI, { Scale = 1.00 }):Play()
		if drag.active then
			setSlotHighlight(idx, false)
		end
	end)
end

-- Dedykowany ScreenGui dla ghost'a — wysoki DisplayOrder żeby renderował się
-- na wierzchu Menu podczas drag (invGui może być disabled gdy wrap w menu)
local ghostGui = Instance.new("ScreenGui")
ghostGui.Name           = "InventoryGhost"
ghostGui.ResetOnSpawn   = false
ghostGui.IgnoreGuiInset = true
ghostGui.DisplayOrder   = 100
ghostGui.Parent         = playerGui

local function buildGhost(data: SlotData)
	local g = mkFrame(ghostGui,
		UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
		ghostPositionFromMouse(),
		C_SLOT_OC, 0.05)
	g.ZIndex  = 100
	g.Active  = false   -- przepuszcza eventy do slotów poniżej
	mkStroke(g, data.color, 2)

	local acc = mkFrame(g, UDim2.new(0, 3, 1, 0), UDim2.new(0, 0, 0, 0), data.color, 0)
	acc.ZIndex = 101
	local nl = mkLabel(g, UDim2.new(1, -8, 0, 13), UDim2.new(0, 6, 0, 4), data.name, 9, data.color)
	nl.ZIndex = 101
	local cl = mkLabel(g, UDim2.new(1, -5, 0, 20), UDim2.new(0, 0, 1, -22),
		tostring(data.count), 17, C_WHITE, Enum.TextXAlignment.Right)
	cl.ZIndex = 101
	cl.TextStrokeColor3 = Color3.new(0, 0, 0); cl.TextStrokeTransparency = 0.3

	return g
end

-- Right-click split drag: zabiera połowę i zaczyna drag z ghostem. Drop na inny slot → place lub merge.
local function splitInvSlot(slotIdx: number)
	if drag.active then return end
	local src = slots[slotIdx]
	if not src or src.count < 2 then return end
	if src.id == SYRUP_ID or src.id == MAGNET_ID or isPetSlotId(src.id) then return end  -- syropu/magnesu/petów nie dzielimy
	local half = math.floor(src.count / 2)
	if half < 1 then return end
	slots[slotIdx].count -= half
	drag.active     = true
	drag.fromSlot   = slotIdx
	drag.startPos   = UserInputService:GetMouseLocation()
	drag.moved      = false
	drag.isSplit    = true
	drag.splitCount = half
	-- Ghost: kopia źródła ze zmniejszonym count
	ghost = buildGhost({ id = src.id, name = src.name, color = src.color, count = half } :: SlotData)
	renderSlot(slotIdx)  -- odśwież source żeby pokazać zmniejszony count
end

local function startDrag(slotIdx: number)
	if not slots[slotIdx] then return end

	drag.active   = true
	drag.fromSlot = slotIdx
	drag.startPos = UserInputService:GetMouseLocation()
	drag.moved    = false

	-- Ukryj zawartość source slotu
	slotFrames[slotIdx].BackgroundColor3        = C_SLOT
	slotAccents[slotIdx].Visible                = false
	slotNameLbls[slotIdx].Visible               = false
	slotCountLbls[slotIdx].Visible              = false

	ghost = buildGhost(slots[slotIdx] :: SlotData)
end

local function endDrag()
	if not drag.active then return end

	local fromIdx = drag.fromSlot
	local target  = hoveredSlot
	local swapped = false

	if drag.isSplit then
		-- Split-drag: połowa "płynie" jako ghost. Drop logic:
		local splitN = drag.splitCount
		local src = slots[fromIdx]
		local rarityId = src and src.id

		local function restoreToSource()
			if slots[fromIdx] then
				slots[fromIdx].count += splitN
			elseif rarityId then
				slots[fromIdx] = { id = rarityId, name = src and src.name or "", color = src and src.color or C_WHITE, count = splitN }
			end
		end

		if not (drag.moved and target and rarityId) then
			restoreToSource()
		elseif target == fromIdx then
			restoreToSource()
		else
			local tgt = slots[target]
			if tgt then
				if tgt.id == rarityId then
					tgt.count += splitN  -- merge
				else
					restoreToSource()  -- inna rzadkość — cancel
				end
			else
				slots[target] = { id = rarityId, name = src.name, color = src.color, count = splitN }
			end
		end

		if target then setSlotHighlight(target, false) end
		if ghost then ghost:Destroy(); ghost = nil end
		hoveredSlot   = nil
		drag.active   = false
		drag.fromSlot = 0
		drag.isSplit  = false
		drag.splitCount = 0
		updateInventory()
		return
	end

	-- Merge gdy upuszczamy butelki tej samej rzadkości — sumujemy counta zamiast swapować.
	-- Inne kombinacje (różne rzadkości, syrop, magnes, pet) → swap jak dotychczas.
	if target and target ~= fromIdx then
		local src = slots[fromIdx]
		local tgt = slots[target]
		local isBottleMerge = src and tgt
			and string.sub(src.id, 1, 7) == "Bottle_"
			and src.id == tgt.id  -- ta sama rzadkość
		if isBottleMerge then
			tgt.count += src.count
			slots[fromIdx] = nil
			setSlotHighlight(target, false)
			swapped = true
		else
			local tmp      = slots[fromIdx]
			slots[fromIdx] = slots[target]
			slots[target]  = tmp
			setSlotHighlight(target, false)
			swapped = true
		end
	end

	-- Przywróć widoczność source slotu
	slotAccents[fromIdx].Visible   = true
	slotNameLbls[fromIdx].Visible  = true
	slotCountLbls[fromIdx].Visible = true

	if ghost then ghost:Destroy(); ghost = nil end

	hoveredSlot   = nil
	drag.active   = false
	drag.fromSlot = 0

	updateInventory()

	-- Jeśli to był klik (nie drag) bez swapu → pokaż detail itemu
	if not swapped and not drag.moved then
		local slotData = slots[fromIdx]
		if slotData then
			if string.sub(slotData.id, 1, 7) == "Bottle_" then
				playSfx("Click")
				showInvDetail(slotData.name)  -- np. "Zwykla"
			elseif slotData.id == SYRUP_ID then
				playSfx("Click")
				showInvDetail(SYRUP_ID)
			elseif slotData.id == MAGNET_ID then
				playSfx("Click")
				showInvDetail(MAGNET_ID)
			elseif isPetSlotId(slotData.id) then
				playSfx("Click")
				showInvDetail(slotData.id)  -- pełne "Pet_<uuid>"
			end
		end
	end

	-- Blokuje overlay-click przez chwilę żeby drop nie zamknął EQ
	recentlyDragged = true
	task.delay(0.15, function() recentlyDragged = false end)
end

for i = 1, SLOT_COUNT do
	local idx = i
	slotFrames[i].InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			startDrag(idx)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			splitInvSlot(idx)
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and drag.active and ghost then
		ghost.Position = ghostPositionFromMouse()
		-- Wykryj czy mysz znacząco się ruszyła — odróżnia drag od kliknięcia
		if not drag.moved then
			local cur = UserInputService:GetMouseLocation()
			if (cur - drag.startPos).Magnitude > DRAG_CLICK_THRESHOLD then
				drag.moved = true
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not drag.active then return end
	-- LMB-drag kończony LMB-up; split-drag (RMB) kończony RMB-up
	local mb1 = input.UserInputType == Enum.UserInputType.MouseButton1 and not drag.isSplit
	local mb2 = input.UserInputType == Enum.UserInputType.MouseButton2 and drag.isSplit
	if (mb1 or mb2) and drag.active then
		endDrag()
	end
end)

-- ── Toggle EQ ─────────────────────────────────────────────────────────────

local inventoryOpen = false

local function setInventoryOpen(open: boolean)
	if not open and drag.active then endDrag() end
	inventoryOpen = open

	if open then
		invGui.Enabled         = true
		invPanel.Position      = INV_POS_HIDE
		invOverlay.BackgroundTransparency = 1
		TweenService:Create(invPanel,   INV_TW_OPEN, { Position = INV_POS_SHOW }):Play()
		TweenService:Create(invOverlay, INV_TW_OPEN, { BackgroundTransparency = 0.30 }):Play()
	else
		-- Reset detail panelu
		invDetVisible = false
		invDetCurrentRarity = nil
		invPanel.Size = UDim2.fromOffset(INV_W_COMPACT, INV_H)

		TweenService:Create(invPanel,   INV_TW_CLOSE, { Position = INV_POS_HIDE }):Play()
		local tw = TweenService:Create(invOverlay, INV_TW_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not inventoryOpen then invGui.Enabled = false end
		end)
		tw:Play()
	end

	eqBtn.TextColor3             = C_WHITE
	eqBtn.BackgroundTransparency = 0.05
end

invCloseBtn.MouseButton1Click:Connect(function() setInventoryOpen(false) end)
eqBtn.MouseButton1Click:Connect(function() setInventoryOpen(not inventoryOpen) end)

-- Klawisz I + toggle: otwiera MenuController na zakładce 1 (EKWIPUNEK)
_G["__inventoryToggle"] = function()
	if _G["__menuSetActiveTab"] then
		_G["__menuOpen"]()
		_G["__menuSetActiveTab"](1)
	else
		setInventoryOpen(not inventoryOpen)  -- fallback
	end
end
_G["__inventoryOpen"]  = _G["__inventoryToggle"]
_G["__inventoryClose"] = function() setInventoryOpen(false) end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.I then
		if _G["__inventoryToggle"] then _G["__inventoryToggle"]() end
	end
end)

-- ── Floating text (zbieranie butelek) ─────────────────────────────────────

local function showFloatingText(text: string, color: Color3)
	local hrp = getHRP()
	if not hrp then return end

	local offX = (math.random(0, 1) == 0 and -1 or 1) * math.random(0, 2)

	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.fromOffset(320, 88)
	bb.StudsOffset    = Vector3.new(offX, 3.5, 0)
	bb.Adornee        = hrp
	bb.AlwaysOnTop    = true
	bb.LightInfluence = 0
	bb.Parent         = playerGui

	-- cień (lekko przesunięty)
	local shadow = Instance.new("TextLabel")
	shadow.Size                   = UDim2.fromScale(1, 1)
	shadow.Position               = UDim2.fromOffset(3, 3)
	shadow.BackgroundTransparency = 1
	shadow.TextColor3             = Color3.new(0, 0, 0)
	shadow.TextTransparency       = 0.35
	shadow.TextSize               = 14
	shadow.Font                   = FONT_MAIN
	shadow.Text                   = text
	shadow.ZIndex                 = 1
	shadow.Parent                 = bb

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = color
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.05
	lbl.TextSize               = 14
	lbl.Font                   = FONT_MAIN
	lbl.Text                   = text
	lbl.ZIndex                 = 2
	lbl.Parent                 = bb

	-- POP: szybkie powiększenie z odbiciem
	local popInfo = TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(lbl,    popInfo, { TextSize = 52 }):Play()
	TweenService:Create(shadow, popInfo, { TextSize = 52 }):Play()

	-- float + zanik po popie
	task.delay(0.20, function()
		local fadeInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(lbl,    fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(shadow, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(bb,     fadeInfo, { StudsOffset = Vector3.new(offX, 10, 0) }):Play()
	end)

	task.delay(1.35, function() if bb.Parent then bb:Destroy() end end)
end

-- ── Earn text (przy sprzedaży do butelkomatu — większe +ZŁ) ───────────────

local function showEarnText(amount: number, color: Color3)
	local hrp = getHRP()
	if not hrp then return end

	local offX = (math.random(0, 1) == 0 and -1 or 1) * math.random(1, 3)

	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.fromOffset(340, 100)
	bb.StudsOffset    = Vector3.new(offX, 5, 0)
	bb.Adornee        = hrp
	bb.AlwaysOnTop    = true
	bb.LightInfluence = 0
	bb.Parent         = playerGui

	local shadow = Instance.new("TextLabel")
	shadow.Size                   = UDim2.fromScale(1, 1)
	shadow.Position               = UDim2.fromOffset(4, 4)
	shadow.BackgroundTransparency = 1
	shadow.TextColor3             = Color3.new(0, 0, 0)
	shadow.TextTransparency       = 0.3
	shadow.TextSize               = 16
	shadow.Font                   = FONT_MAIN
	shadow.Text                   = "+" .. formatAmount(amount) .. " ZŁ"
	shadow.ZIndex                 = 1
	shadow.Parent                 = bb

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = color
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0
	lbl.TextSize               = 16
	lbl.Font                   = FONT_MAIN
	lbl.Text                   = "+" .. formatAmount(amount) .. " ZŁ"
	lbl.ZIndex                 = 2
	lbl.Parent                 = bb

	local popInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(lbl,    popInfo, { TextSize = 64 }):Play()
	TweenService:Create(shadow, popInfo, { TextSize = 64 }):Play()

	task.delay(0.22, function()
		local fadeInfo = TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(lbl,    fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(shadow, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(bb,     fadeInfo, { StudsOffset = Vector3.new(offX, 13, 0) }):Play()
	end)

	task.delay(1.5, function() if bb.Parent then bb:Destroy() end end)
end

-- ── Billboard message ──────────────────────────────────────────────────────

local function showBillboardMessage(text: string, duration: number)
	local hrp = getHRP()
	if not hrp then return end

	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.fromOffset(260, 52)
	bb.StudsOffset    = Vector3.new(0, 5, 0)
	bb.Adornee        = hrp
	bb.AlwaysOnTop    = true
	bb.LightInfluence = 0
	bb.Parent         = playerGui

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = Color3.fromRGB(255, 80, 80)
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.1
	lbl.TextSize               = 26
	lbl.Font                   = FONT_MAIN
	lbl.Text                   = text
	lbl.TextWrapped            = true
	lbl.TextXAlignment         = Enum.TextXAlignment.Center
	lbl.Parent                 = bb

	TweenService:Create(lbl, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = 34 }):Play()

	task.delay(duration - 0.4, function()
		TweenService:Create(lbl, TweenInfo.new(0.4, Enum.EasingStyle.Quad),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(duration, function() if bb.Parent then bb:Destroy() end end)
end

-- ── GUI podsumowania butelkomatu (ekranowy popup z licznikiem) ─────────────

local function showButelkomatSummary(bottlesReturned: number, earned: number)
	-- przyciemnienie
	local dim = Instance.new("Frame")
	dim.Size                   = UDim2.fromScale(1, 1)
	dim.BackgroundColor3       = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel        = 0
	dim.ZIndex                 = 50
	dim.Parent                 = hudGui

	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.52 }):Play()

	-- panel główny (pop-in z 0×0)
	local panel = Instance.new("Frame")
	panel.AnchorPoint            = Vector2.new(0.5, 0.5)
	panel.Position               = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size                   = UDim2.fromOffset(0, 0)
	panel.BackgroundColor3       = Color3.fromRGB(8, 8, 20)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel        = 0
	panel.ClipsDescendants       = true
	panel.ZIndex                 = 51
	panel.Parent                 = hudGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent       = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color     = Color3.fromRGB(255, 205, 55)
	panelStroke.Thickness = 4
	panelStroke.Parent    = panel

	-- nagłówek
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size                   = UDim2.new(1, 0, 0, 38)
	titleLbl.Position               = UDim2.fromOffset(0, 18)
	titleLbl.BackgroundTransparency = 1
	titleLbl.TextColor3             = Color3.fromRGB(255, 205, 55)
	titleLbl.TextSize               = 18
	titleLbl.Font                   = FONT_MAIN
	titleLbl.Text                   = "BUTELKOMAT"
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Center
	titleLbl.ZIndex                 = 52
	titleLbl.Parent                 = panel

	-- separator
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(0.7, 0, 0, 1)
	sep.AnchorPoint      = Vector2.new(0.5, 0)
	sep.Position         = UDim2.new(0.5, 0, 0, 58)
	sep.BackgroundColor3 = Color3.fromRGB(60, 55, 20)
	sep.BorderSizePixel  = 0
	sep.ZIndex           = 52
	sep.Parent           = panel

	-- duże zarobki (licznik)
	local earnLbl = Instance.new("TextLabel")
	earnLbl.Size                   = UDim2.new(1, 0, 0, 88)
	earnLbl.Position               = UDim2.fromOffset(0, 62)
	earnLbl.BackgroundTransparency = 1
	earnLbl.TextColor3             = Color3.fromRGB(75, 235, 115)
	earnLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	earnLbl.TextStrokeTransparency = 0.15
	earnLbl.TextSize               = 72
	earnLbl.Font                   = FONT_MAIN
	earnLbl.Text                   = "+0 ZŁ"
	earnLbl.TextXAlignment         = Enum.TextXAlignment.Center
	earnLbl.ZIndex                 = 52
	earnLbl.Parent                 = panel

	-- liczba butelek
	local bottlesLbl = Instance.new("TextLabel")
	bottlesLbl.Size                   = UDim2.new(1, 0, 0, 28)
	bottlesLbl.Position               = UDim2.fromOffset(0, 158)
	bottlesLbl.BackgroundTransparency = 1
	bottlesLbl.TextColor3             = Color3.fromRGB(130, 130, 190)
	bottlesLbl.TextSize               = 18
	bottlesLbl.Font                   = FONT_MAIN
	bottlesLbl.Text                   = bottlesReturned .. " butelek oddanych"
	bottlesLbl.TextXAlignment         = Enum.TextXAlignment.Center
	bottlesLbl.ZIndex                 = 52
	bottlesLbl.Parent                 = panel

	-- pop-in animacja panelu
	TweenService:Create(panel, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(430, 200) }):Play()

	-- licznik: 0 → earned w 0.9s (startuje 0.3s po otwarciu)
	-- Animacja int-step dla czytelności, ostatni krok pokazuje pełną kwotę z groszami
	local steps  = 28
	for i = 1, steps do
		local step = i
		task.delay(0.3 + (step / steps) * 0.9, function()
			if not earnLbl.Parent then return end
			if step == steps then
				earnLbl.Text = "+" .. formatAmount(earned) .. " ZŁ"
			else
				earnLbl.Text = "+" .. math.floor(earned * step / steps) .. " ZŁ"
			end
		end)
	end

	-- zamknięcie: zanik + shrink
	task.delay(2.6, function()
		TweenService:Create(dim, TweenInfo.new(0.45, Enum.EasingStyle.Quint),
			{ BackgroundTransparency = 1 }):Play()
		TweenService:Create(panel, TweenInfo.new(0.45, Enum.EasingStyle.Quint),
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(430, 60) }):Play()
		task.delay(0.45, function()
			if dim.Parent   then dim:Destroy()   end
			if panel.Parent then panel:Destroy() end
		end)
	end)
end

-- ── Animacja deposit ──────────────────────────────────────────────────────

local function playDepositEffects(breakdown: { [string]: number }, finalTotal: number)
	local count = 0
	for _, r in ipairs(RARITY_ORDER) do if (breakdown[r] or 0) > 0 then count += 1 end end

	local delay = 0; local done = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		local earned = breakdown[rarity] or 0
		if earned > 0 then
			done += 1
			local d, r, e, last = delay, rarity, earned, (done == count)
			task.delay(d, function()
				showEarnText(e, RARITY_COLORS[r])
				-- Saldo złotówek aktualizuje leaderstats.Changed automatycznie
				hudData.backpackContents[r] = 0
				clearRarityFromInventory(r)
				local total = 0
				for _, v in pairs(hudData.backpackContents) do total += v end
				if hudData.hasSyrup then total += 1 end  -- syrop nie sprzedaje się w butelkomacie
				hudData.bottlesCarried = total
				updateHud(); updateInventory()
				if invDetVisible then refreshInvDetail() end
			end)
			delay += 0.35
		end
	end
end

-- ── Listeners RemoteEvent ──────────────────────────────────────────────────

-- Leaderstats: Roblox replikuje automatycznie — brak RemoteEvent potrzebny do złotówek
local function watchLeaderstats()
	local ls = localPlayer:WaitForChild("leaderstats", 15)
	if not ls then return end
	local zlVal = ls:WaitForChild("Zlotowki", 10)
	if not zlVal then return end
	hudData.zlotowki = zlVal.Value
	updateHud()
	zlVal.Changed:Connect(function(newVal)
		hudData.zlotowki = newVal
		updateHud()
	end)
end
task.spawn(watchLeaderstats)

local initialStacksLoaded = false

UpdateHUD.OnClientEvent:Connect(function(data)
	-- Złotówki pominięte — obsługuje watchLeaderstats powyżej
	hudData.backpackCapacity = data.backpackCapacity
	hudData.backpackContents = data.backpackContents
	if data.hasSyrup ~= nil then hudData.hasSyrup = data.hasSyrup end
	local total = 0
	for _, v in pairs(data.backpackContents) do total += v end
	if hudData.hasSyrup then total += 1 end
	-- Magnes: każdy zajmuje 1 slot. Liczba z payloadu (jeśli serwer wysłał) lub z _G state.
	local magnetCount = tonumber(data.magnetCount)
	if not magnetCount then
		local m = _G["__magnetState"]
		magnetCount = (m and tonumber(m.count)) or 0
	end
	total += magnetCount
	-- Pety — każdy = 1 slot
	local ps = _G["__petsState"]
	total += (ps and ps.pets and #ps.pets) or 0
	hudData.bottlesCarried = total

	-- Pierwsza wiadomość z inventoryStacks (layout per-slot) — wczytaj zapisany układ + pozycje
	if not initialStacksLoaded and type(data.inventoryStacks) == "table" then
		initialStacksLoaded = true
		-- Sprawdź czy mamy jakieś dane (sklep z PlayerData może być pusty {} dla nowego gracza)
		local hasAny = false
		for _ in pairs(data.inventoryStacks) do hasAny = true; break end
		if hasAny then
			-- Konwersja klucz-string → klucz-number (DataStore zwraca stringi)
			local layout = {}
			for k, v in pairs(data.inventoryStacks) do
				local i = tonumber(k); if i then layout[i] = v end
			end
			_G["__inventorySetLayout"](layout)
		end
		-- Smart resync na wypadek gdyby contents różniły się od layoutu (np. picked between sesjami)
		syncSlotsFromContents()
	else
		initialStacksLoaded = true
		syncSlotsFromContents()
	end
	updateHud(); updateInventory()
	if invDetVisible then refreshInvDetail() end
end)

CollectBottleResult.OnClientEvent:Connect(function(result)
	if result.success then
		hudData.bottlesCarried                   = result.bottlesCarried
		hudData.backpackCapacity                 = result.capacity
		hudData.backpackContents[result.rarity] += 1
		addToInventory(result.rarity)
		updateHud(); updateInventory()
		if invDetVisible then refreshInvDetail() end
		showFloatingText(result.rarity, RARITY_COLORS[result.rarity] or C_WHITE)
		playSfx("PickingUp")
	else
		if result.reason == "full" then
			showBillboardMessage("Plecak pelny! Idz do butelkomatu", 2)
		end
	end
end)

EmptyBackpackResult.OnClientEvent:Connect(function(result)
	if result.success then
		playSfx("Money")
		showButelkomatSummary(result.bottlesReturned, result.earned)
		playDepositEffects(result.breakdown or {}, result.newTotal)
	else
		if result.reason == "empty" then
			showBillboardMessage("Nie masz butelek!", 2)
		end
	end
end)

-- ── Pickup syropu dziadka ─────────────────────────────────────────────────
local SyrupPickupResult = ReplicatedStorage.Events:WaitForChild("SyrupPickupResult")
SyrupPickupResult.OnClientEvent:Connect(function(result)
	if result.success then
		-- UpdateHUD już zaktualizował hudData.hasSyrup + bottlesCarried
		showFloatingText("SYROP DZIADKA", SYRUP_COLOR)
		playSfx("PickingUp")
	else
		if result.reason == "full" then
			showBillboardMessage("Plecak pelny! Idz do butelkomatu", 2)
		end
	end
end)

-- ── ProximityPrompty butelek ──────────────────────────────────────────────

local function connectBottle(bottle: Instance)
	local function attachPrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function() CollectBottle:FireServer(bottle) end)
			return true
		end
		return false
	end

	-- Jeśli prompt już jest zreplikowany — podłącz od razu
	local existing = bottle:FindFirstChildWhichIsA("ProximityPrompt", true)
	if existing then
		attachPrompt(existing)
		return
	end

	-- Inaczej czekaj aż dojedzie do klienta
	local conn
	conn = bottle.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			if conn then conn:Disconnect() end
			attachPrompt(d)
		end
	end)
end

local function watchBottles()
	local folder = workspace:WaitForChild("Bottles", 10)
	if not folder then return end
	for _, child in ipairs(folder:GetChildren()) do connectBottle(child) end
	folder.ChildAdded:Connect(function(child) connectBottle(child) end)
end

task.spawn(watchBottles)

-- ── ProximityPrompty butelkomatu ──────────────────────────────────────────

-- Podłącza ProximityPrompt na części otagowanej jako Butelkomat
local function connectTaggedPart(part: Instance)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function() EmptyBackpack:FireServer() end)
	else
		-- Prompt może pojawić się chwilę po tagu (replikacja serwera)
		part.ChildAdded:Connect(function(child)
			if child:IsA("ProximityPrompt") then
				child.Triggered:Connect(function() EmptyBackpack:FireServer() end)
			end
		end)
	end
end

local function watchButelkomaty()
	-- Podłącz wszystkie już otagowane części
	for _, part in ipairs(CollectionService:GetTagged(BUTELKOMAT_TAG)) do
		connectTaggedPart(part)
	end
	-- Nasłuchuj na nowe (np. AutomatKaucyjny tagowany przez serwer przy starcie)
	CollectionService:GetInstanceAddedSignal(BUTELKOMAT_TAG):Connect(connectTaggedPart)
end

task.spawn(watchButelkomaty)

updateHud()
updateInventory()

-- ── Pet listener ──────────────────────────────────────────────────────────
-- PetService wysyła PetStatusUpdate przy każdej zmianie petów. Aktualizujemy
-- _G.__petsState (czytane też przez Bank/SprintController) + syncujemy sloty.
local PetStatusUpdateEvt = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PetStatusUpdate")
_G["__petsState"] = { pets = {}, equippedId = "", bankPets = {}, bonuses = {} }
PetStatusUpdateEvt.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	_G["__petsState"] = {
		pets        = data.pets or {},
		equippedId  = data.equippedId or "",
		bankPets    = data.bankPets or {},
		hasGamepass = data.hasGamepass == true,
		bonuses     = data.bonuses or {},
	}
	syncPetSlots()
	-- bottlesCarried zależy od liczby petów (każdy = 1 slot)
	local total = 0
	for _, v in pairs(hudData.backpackContents) do total += v end
	if hudData.hasSyrup then total += 1 end
	local m = _G["__magnetState"]
	total += (m and tonumber(m.count)) or 0
	total += #(_G["__petsState"].pets or {})
	hudData.bottlesCarried = total
	updateHud()
	updateInventory()
	if invDetVisible and isPetSlotId(invDetCurrentRarity) then
		refreshInvDetail()
		setInvDetailContentVisible(true)
	end
end)

-- ── Magnet listener ───────────────────────────────────────────────────────
-- MUSI być na końcu pliku — closure odwołuje się do `updateInventory` i innych
-- helperów, które w Lua resolve'ują się jako globalne (nil) jeśli są zadeklarowane
-- po miejscu definicji closure'a. Przez to slot magnesu nie odświeżał się od razu
-- po użyciu (dopiero gdy inny mechanizm wymusił render).
task.spawn(function()
	for _ = 1, 50 do
		if _G["__magnetAddListener"] then break end
		task.wait(0.1)
	end
	if not _G["__magnetAddListener"] then return end
	_G["__magnetAddListener"](function()
		-- Magnes wpływa na pojemność — przelicz bottlesCarried (z petami)
		local total = 0
		for _, v in pairs(hudData.backpackContents) do total += v end
		if hudData.hasSyrup then total += 1 end
		local m = _G["__magnetState"]
		total += (m and tonumber(m.count)) or 0
		local ps = _G["__petsState"]
		total += (ps and ps.pets and #ps.pets) or 0
		hudData.bottlesCarried = total
		updateHud()

		syncMagnetSlots()
		updateInventory()
		if invDetVisible and invDetCurrentRarity == MAGNET_ID then
			refreshInvDetail()
			setInvDetailContentVisible(true)
		end
	end)
end)

