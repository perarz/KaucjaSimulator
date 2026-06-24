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
local Util   = require(ReplicatedStorage:WaitForChild("Util"))

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── SFX ───────────────────────────────────────────────────────────────────
-- SFX_FOLDER rozwiązywane LENIWIE — NIE blokujemy głównego wątku na replikację
-- workspace.SFX. Wcześniej WaitForChild bez timeoutu mógł opóźnić (lub przy braku
-- folderu zawiesić na zawsze) cały kontroler, a wraz z nim eksport _G.__inventoryWrap,
-- którego MenuController potrzebuje do zamontowania zakładki EKWIPUNEK.
local sfxFolderCache: Instance? = workspace:FindFirstChild("SFX")
local function getSfxFolder(): Instance?
	if not sfxFolderCache then
		sfxFolderCache = workspace:FindFirstChild("SFX")
	end
	return sfxFolderCache
end

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
	local folder = getSfxFolder()
	if not folder then return end
	local template = folder:FindFirstChild(name)
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

-- Kolory zgrupowane w jednej tabeli (zamiast 11 osobnych lokalnych) — Luau ma limit
-- 200 rejestrów lokalnych na funkcję, a ciało skryptu to jeden duży chunk. Konsolidacja
-- stałych w tabele zwalnia rejestry, żeby dodawanie funkcji nie wywalało kompilacji.
local C = {
	BG          = Color3.fromRGB(18, 91, 73),
	PANEL       = Color3.fromRGB(24, 110, 90),
	HEADER      = Color3.fromRGB(0, 53, 39),
	SLOT        = Color3.fromRGB(8, 60, 48),
	SLOT_OC     = Color3.fromRGB(32, 110, 90),
	SLOT_HOV    = Color3.fromRGB(14, 75, 60),
	BORDER      = Color3.fromRGB(5, 25, 20),
	BORDER_SL   = Color3.fromRGB(8, 30, 24),
	WHITE       = Color3.fromRGB(255, 255, 255),
	DIMTEXT     = Color3.fromRGB(175, 175, 175),
	ACCENT_GREEN = Color3.fromRGB(170, 221, 102),
}
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

-- Syrop dziadka — zgrupowane w tabeli (oszczędność rejestrów lokalnych).
local SYRUP_ID = "Syrop_Maple"
local SYRUP = {
	NAME  = "Syrop Dziadka",
	COLOR = (Config.GrandpaQuest and Config.GrandpaQuest.SyrupLight) or Color3.fromRGB(200, 130, 60),
	DESC  = "Syrop klonowy dziadka. Zanieś go staremu — pewnie da ci coś w zamian.",
}

-- Magnes — używany item, NIE stackuje się (1 sztuka = 1 slot). Zgrupowany w tabeli.
local MAGNET_ID = "Magnet"
local MAGNET = {
	NAME  = (Config.Magnet and Config.Magnet.Name) or "Magnes",
	COLOR = (Config.Magnet and Config.Magnet.Color) or Color3.fromRGB(220, 90, 90),
	DESC  = (Config.Magnet and Config.Magnet.Desc) or "Aktywuj, by zbierać butelki automatycznie.",
	IMAGE = Config.Magnet and Config.Magnet.Image,
}

-- Pet slot id prefix: "Pet_<uuid>". Każdy pet = osobny slot (NIE stackuje się — unikalny UUID).
local PET_ID_PREFIX = "Pet_"
local function isPetSlotId(id: string?): boolean
	return id ~= nil and string.sub(id, 1, #PET_ID_PREFIX) == PET_ID_PREFIX
end

local slots: { SlotData? } = {}
for i = 1, SLOT_COUNT do slots[i] = nil end

-- ── EQ sub-tabs (BUTELKI / AKCESORIA / PETY) ───────────────────────────────
-- Filter visualny: każdy slot z itemem należy do jednej z 3 kategorii. Pusty slot
-- jest widoczny we WSZYSTKICH zakładkach (żeby user wiedział że ma wolne miejsce).
-- Drag/auto-fill operuje na globalnych pozycjach 1..SLOT_COUNT, więc kategoryzacja
-- to TYLKO warstwa wizualna — nie zmienia logiki addToInventory/syncMagnetSlots/etc.
local INV_SUBTAB_BOTTLES     = "bottles"
local INV_SUBTAB_ACCESSORIES = "accessories"
local INV_SUBTAB_PETS        = "pets"
local currentInvSubTab = INV_SUBTAB_BOTTLES

local function getInvSubTab(s: SlotData?): string?
	if not s or not s.id then return nil end
	if s.id == MAGNET_ID then return INV_SUBTAB_ACCESSORIES end
	if s.id == SYRUP_ID  then return INV_SUBTAB_ACCESSORIES end  -- syrop pokazywany w AKCESORIACH (item questowy, nie liczy się do limitu)
	if isPetSlotId(s.id) then return INV_SUBTAB_PETS end
	return INV_SUBTAB_BOTTLES
end

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
			slots[i] = { id = SYRUP_ID, color = SYRUP.COLOR, name = SYRUP.NAME, count = 1 }
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
				slots[i] = { id = MAGNET_ID, color = MAGNET.COLOR, name = MAGNET.NAME, count = 1 }
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
					local color = rcfg.color or C.WHITE
					slots[i] = {
						id        = PET_ID_PREFIX .. p.id,
						color     = color,
						name      = p.class,  -- "Sprinter" / "Tank" wyświetlane na slocie
						count     = 1,
						petRarity = p.rarity, -- do obrazka tekstury peta (Config.Pets.Rarities[r].image)
						petGold   = p.gold == true, -- gold pet → osobna tekstura (Config.Pets.GoldUpgrade.Images)
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
	f.BackgroundColor3 = bg or C.BG
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel = 0; f.Parent = parent
	return f
end

local function mkLabel(parent, size, pos, text, textSize, color, xAlign)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = color or C.WHITE
	l.TextSize = textSize or 14
	l.Font = FONT_MAIN
	l.Text = text or ""; l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.BorderSizePixel = 0; l.Parent = parent
	return l
end

local function mkStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color           = color or C.BORDER
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

-- ── Pojemność per-kategoria (BUTELKI 70% / PETY 20% / AKCESORIA 10%) ───────
-- Klucze zwracanej tabeli (bottles/pets/accessories) == wartości INV_SUBTAB_* —
-- dzięki temu caps[currentInvSubTab] działa wprost.
local function getCategoryCaps(): { bottles: number, pets: number, accessories: number }
	return Util.getCategoryCaps(hudData.backpackCapacity or 0, Config.BackpackCategorySplit)
end

-- Liczba itemów danej kategorii w jednostkach POJEMNOŚCI: butelki sumują się
-- (count w stacku), pet/magnes = 1 każdy. Syrop NIE liczy się (item questowy).
local function categoryUnitCount(catId: string): number
	local n = 0
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s then
			if catId == INV_SUBTAB_BOTTLES and string.sub(s.id, 1, 7) == "Bottle_" then
				n += s.count or 0
			elseif catId == INV_SUBTAB_PETS and isPetSlotId(s.id) then
				n += 1
			elseif catId == INV_SUBTAB_ACCESSORIES and s.id == MAGNET_ID then
				n += 1
			end
		end
	end
	return n
end

-- Licznik X/Y w nagłówku EQ — ilość dla AKTUALNEJ zakładki (kategorii).
local function updateCategoryCounter()
	if not invCountLbl then return end
	local caps = getCategoryCaps()
	local cap  = caps[currentInvSubTab] or 0
	invCountLbl.Text = string.format("%d/%d", categoryUnitCount(currentInvSubTab), cap)
end

local function updateHud()
	if walletLabel then
		walletLabel.Text = formatAmount(hudData.zlotowki) .. " PLN"
	end
	updateCategoryCounter()
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
	-- Wyśrodkuj ramkę przy samej górze ekranu (2px od krawędzi).
	ramka.AnchorPoint = Vector2.new(0.5, 0)
	ramka.Position    = UDim2.new(0.5, 0, 0, 2)

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

-- Stare 4 przyciski HUD (zastąpione przyciskiem MENU) — zawijamy w `do end` żeby ich
-- lokalne (BTN_*, STACK_*, stBtn/qBtn/setBtn, attachBtnHover) NIE zajmowały rejestrów
-- głównego chunku. Luau ma limit 200 lokalnych na funkcję; bez tego dodanie sub-zakładek
-- EQ przekraczało limit i CAŁY CollectController nie kompilował się
-- ("Out of local registers ... exceeded limit 200"), przez co EKWIPUNEK nie ładował się.
-- eqBtn jest używany później (toggle EQ), więc deklarujemy go na zewnątrz.
local eqBtn: TextButton
do
local BTN_W, BTN_H, BTN_GAP = 300, 90, 16
-- 4 przyciski w pionie, wycentrowane na Y=0.5
local STACK_H   = 4 * BTN_H + 3 * BTN_GAP
local STACK_TOP = -STACK_H / 2

eqBtn = Instance.new("TextButton")
eqBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
eqBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP)
eqBtn.BackgroundColor3 = C.BG; eqBtn.BackgroundTransparency = 0.05
eqBtn.BorderSizePixel = 0; eqBtn.Text = "EKWIPUNEK"; eqBtn.TextSize = 30
eqBtn.Font = FONT_MAIN; eqBtn.TextColor3 = C.WHITE; eqBtn.AutoButtonColor = false
eqBtn.ZIndex = 2; eqBtn.Parent = hudGui
mkStroke(eqBtn, C.BORDER, 4)
mkCorner(eqBtn, 8)

local stBtn = Instance.new("TextButton")
stBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
stBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP + BTN_H + BTN_GAP)
stBtn.BackgroundColor3 = C.BG; stBtn.BackgroundTransparency = 0.05
stBtn.BorderSizePixel = 0; stBtn.Text = "UMIEJĘTNOŚCI"; stBtn.TextSize = 27
stBtn.Font = FONT_MAIN; stBtn.TextColor3 = C.WHITE; stBtn.AutoButtonColor = false
stBtn.ZIndex = 2; stBtn.Parent = hudGui
mkStroke(stBtn, C.BORDER, 4)
mkCorner(stBtn, 8)

local qBtn = Instance.new("TextButton")
qBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
qBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP + 2 * (BTN_H + BTN_GAP))
qBtn.BackgroundColor3 = C.BG; qBtn.BackgroundTransparency = 0.05
qBtn.BorderSizePixel = 0; qBtn.Text = "QUESTY"; qBtn.TextSize = 30
qBtn.Font = FONT_MAIN; qBtn.TextColor3 = C.WHITE; qBtn.AutoButtonColor = false
qBtn.ZIndex = 2; qBtn.Parent = hudGui
mkStroke(qBtn, C.BORDER, 4)
mkCorner(qBtn, 8)

local setBtn = Instance.new("TextButton")
setBtn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
setBtn.Position = UDim2.new(0, 16, 0.5, STACK_TOP + 3 * (BTN_H + BTN_GAP))
setBtn.BackgroundColor3 = C.BG; setBtn.BackgroundTransparency = 0.05
setBtn.BorderSizePixel = 0; setBtn.Text = "USTAWIENIA"; setBtn.TextSize = 26
setBtn.Font = FONT_MAIN; setBtn.TextColor3 = C.WHITE; setBtn.AutoButtonColor = false
setBtn.ZIndex = 2; setBtn.Parent = hudGui
mkStroke(setBtn, C.BORDER, 4)
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
end  -- koniec do-block starych przycisków HUD (zwalnia rejestry lokalnych)

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
-- Marginesy WEWNĄTRZ slotsContainer (strokes slotów + odstęp od krawędzi paneli sąsiadów).
-- Wcześniej sloty stykały się ze ścianami scrolla → strokes ucinane przez ClipsDescendants.
local SLOT_OUTER_PAD = 10
-- slotsW = pełna szerokość siatki + thickness scrollbara po prawej + marginesy wewnętrzne
local slotsW       = SLOTS_PER_ROW * SLOT_SIZE + (SLOTS_PER_ROW - 1) * SLOT_GAP + SCROLLBAR_THICK + 4 + SLOT_OUTER_PAD * 2
-- slotsH = WIDOCZNA wysokość (VISIBLE_ROWS rzędów) — reszta scrolluje
local slotsH       = VISIBLE_ROWS * SLOT_SIZE + (VISIBLE_ROWS - 1) * SLOT_GAP + SLOT_OUTER_PAD * 2
-- canvasH = pełna wysokość zawartości (wszystkie rzędy) — ScrollingFrame ją używa
local canvasH      = panelRows * SLOT_SIZE + (panelRows - 1) * SLOT_GAP + SLOT_OUTER_PAD * 2
local INV_W_COMPACT = slotsW + PAD * 2
local INV_W_WIDE    = INV_W_COMPACT + INV_DET_W + PAD       -- detail + prawy padding
local INV_W        = INV_W_WIDE  -- zachowane dla pozycji detail panelu poniżej
local INV_H        = slotsH + INV_HEADER_H + PAD * 2

local INV_POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local INV_POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local INV_TW_OPEN  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local INV_TW_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local invPanel = mkFrame(invGui, UDim2.fromOffset(INV_W_COMPACT, INV_H), INV_POS_HIDE, C.PANEL, 0.05)
invPanel.AnchorPoint     = Vector2.new(0.5, 0.5)
invPanel.ClipsDescendants = true
invPanel.ZIndex          = 2
mkStroke(invPanel, C.BORDER, 4)
mkCorner(invPanel, 8)

-- header: UICorner zaokrągla wszystkie rogi; dolne maskujemy prostokątnym fillem
-- + cienki separator C.BORDER jako wizualny rozdział od reszty panelu
local invHeader = mkFrame(invPanel, UDim2.new(1, 0, 0, INV_HEADER_H), UDim2.fromOffset(0, 0),
	C.HEADER, 0)
invHeader.ZIndex = 3
mkCorner(invHeader, 8)
do
	local fill = mkFrame(invHeader, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10), C.HEADER, 0)
	fill.ZIndex = 3
	local sep = mkFrame(invHeader, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), C.BORDER, 0)
	sep.ZIndex = 5
end
local invTitle = mkLabel(invHeader, UDim2.fromOffset(140, 52), UDim2.fromOffset(20, 0),
	"EKWIPUNEK", 15, C.WHITE, Enum.TextXAlignment.Left)
invTitle.ZIndex = 4

invCountLbl = mkLabel(invHeader, UDim2.fromOffset(130, 52), UDim2.fromOffset(170, 0),
	"0/10", 20, C.DIMTEXT, Enum.TextXAlignment.Left)
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
slotsContainer.ScrollBarImageColor3   = C.BORDER
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

-- Detail panel: wszystkie referencje (panel/labelki/przyciski/stan) w jednej tabeli D
-- zamiast 17 osobnych lokalnych — oszczędność rejestrów (limit Luau 200 na chunk).
local D = {}

D.panel = mkFrame(invPanel,
	UDim2.fromOffset(INV_DET_W, slotsH),
	UDim2.fromOffset(INV_DET_X_SHOWN, INV_HEADER_H + PAD),
	C.BG, 0.05)
D.panel.ZIndex = 4
mkStroke(D.panel, C.BORDER, 4)
mkCorner(D.panel, 10)

-- Detail close X
D.closeBtn = Instance.new("TextButton")
D.closeBtn.Size                   = UDim2.fromOffset(30, 30)
D.closeBtn.AnchorPoint            = Vector2.new(1, 0)
D.closeBtn.Position               = UDim2.new(1, -12, 0, 12)
D.closeBtn.BackgroundTransparency = 1
D.closeBtn.BorderSizePixel        = 0
D.closeBtn.Text                   = "X"
D.closeBtn.TextSize               = 22
D.closeBtn.Font                   = FONT_MAIN
D.closeBtn.TextColor3             = X_RED
D.closeBtn.AutoButtonColor        = false
D.closeBtn.ZIndex                 = 6
D.closeBtn.Parent                 = D.panel
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = D.closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	D.closeBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
		D.closeBtn.TextColor3 = X_RED_HOVER
	end)
	D.closeBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		D.closeBtn.TextColor3 = X_RED
	end)
end

-- ViewportFrame z obracającym się modelem itemu (góra panelu)
D.viewport = Instance.new("ViewportFrame")
D.viewport.Size                   = UDim2.new(1, -32, 0, 188)
D.viewport.Position               = UDim2.fromOffset(16, 12)
D.viewport.BackgroundTransparency = 1
D.viewport.Ambient                = Color3.fromRGB(190, 200, 195)
D.viewport.LightColor             = Color3.fromRGB(255, 255, 255)
D.viewport.LightDirection         = Vector3.new(-0.4, -1, -0.3)
D.viewport.ZIndex                 = 5
D.viewport.Parent                 = D.panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = D.viewport
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = D.viewport
end

-- Tytuł (nazwa rzadkości)
D.title = mkLabel(D.panel,
	UDim2.new(1, -56, 0, 32), UDim2.fromOffset(16, 218),
	"", 22, C.WHITE, Enum.TextXAlignment.Left)
D.title.ZIndex = 5

-- Podtytuł — count
D.count = mkLabel(D.panel,
	UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 252),
	"", 13, C.DIMTEXT, Enum.TextXAlignment.Left)
D.count.ZIndex = 5

-- Separator
D.sep1 = mkFrame(D.panel,
	UDim2.new(1, -32, 0, 1), UDim2.fromOffset(16, 286), C.BORDER, 0)
D.sep1.ZIndex = 5

-- "Wartość bazowa: X ZŁ za butelkę"
D.baseLbl = mkLabel(D.panel,
	UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 298),
	"", 13, C.DIMTEXT, Enum.TextXAlignment.Left)
D.baseLbl.ZIndex = 5

-- Łączna wartość bez multipliera (count × base)
D.totalLbl = mkLabel(D.panel,
	UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 322),
	"", 16, C.WHITE, Enum.TextXAlignment.Left)
D.totalLbl.ZIndex = 5

-- Z multiplierem
D.multLbl = mkLabel(D.panel,
	UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 350),
	"", 16, C.ACCENT_GREEN, Enum.TextXAlignment.Left)
D.multLbl.ZIndex = 5

-- Separator
D.sep2 = mkFrame(D.panel,
	UDim2.new(1, -32, 0, 1), UDim2.fromOffset(16, 388), C.BORDER, 0)
D.sep2.ZIndex = 5

-- Opis
D.desc = mkLabel(D.panel,
	UDim2.new(1, -32, 0, 80), UDim2.fromOffset(16, 400),
	"", 13, C.DIMTEXT, Enum.TextXAlignment.Left)
D.desc.TextWrapped     = true
D.desc.TextYAlignment  = Enum.TextYAlignment.Top
D.desc.ZIndex          = 5

-- Przycisk UPUŚĆ (1 sztukę przed graczem) — niedostępny dla syropu (quest item)
local DropBottleEvt = ReplicatedStorage:WaitForChild("Events"):WaitForChild("DropBottle")
D.dropBtn = Instance.new("TextButton")
D.dropBtn.Size                   = UDim2.new(1, -32, 0, 44)
D.dropBtn.AnchorPoint            = Vector2.new(0, 1)
D.dropBtn.Position               = UDim2.new(0, 16, 1, -16)
D.dropBtn.BackgroundColor3       = Color3.fromRGB(180, 70, 70)
D.dropBtn.BorderSizePixel        = 0
D.dropBtn.Text                   = "UPUŚĆ 1 SZTUKĘ"
D.dropBtn.TextSize               = 16
D.dropBtn.Font                   = FONT_MAIN
D.dropBtn.TextColor3             = C.WHITE
D.dropBtn.AutoButtonColor        = false
D.dropBtn.ZIndex                 = 6
D.dropBtn.Parent                 = D.panel

-- Przycisk UŻYJ (tylko dla magnesu) — aktywuje 2-min sweep
D.useBtn = Instance.new("TextButton")
D.useBtn.Size                   = UDim2.new(1, -32, 0, 44)
D.useBtn.AnchorPoint            = Vector2.new(0, 1)
D.useBtn.Position               = UDim2.new(0, 16, 1, -16)
D.useBtn.BackgroundColor3       = MAGNET.COLOR
D.useBtn.BorderSizePixel        = 0
D.useBtn.Text                   = "UŻYJ"
D.useBtn.TextSize               = 18
D.useBtn.Font                   = FONT_MAIN
D.useBtn.TextColor3             = C.WHITE
D.useBtn.AutoButtonColor        = false
D.useBtn.Visible                = false
D.useBtn.ZIndex                 = 6
D.useBtn.Parent                 = D.panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = D.useBtn
	local s = Instance.new("UIStroke"); s.Color = C.BORDER; s.Thickness = 2; s.Parent = D.useBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = D.useBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	D.useBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.04 }):Play()
	end)
	D.useBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
	end)
end
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = D.dropBtn
	local s = Instance.new("UIStroke"); s.Color = C.BORDER; s.Thickness = 2; s.Parent = D.dropBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = D.dropBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	D.dropBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.04 }):Play()
		D.dropBtn.BackgroundColor3 = Color3.fromRGB(220, 90, 90)
	end)
	D.dropBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		D.dropBtn.BackgroundColor3 = Color3.fromRGB(180, 70, 70)
	end)
end

D.visible = false
D.currentRarity = nil

-- ── ViewportFrame: obracający się model itemu w detail panelu ───────────────
-- Templaty: butelki (BottleModels.<rarity> + ReplicatedStorage.Mityczny),
-- syrop (SyrupModel), magnes (MagnetModel/Magnes/Magnet), pety (Pets.PetyZwykle/PetyGold.Pet<Rarity>).
local function findDetailModelTemplate(slotId: string): Instance?
	if slotId == "Zwykla" or slotId == "Rzadka" or slotId == "Epicka" or slotId == "Legendarna" then
		local bm = ReplicatedStorage:FindFirstChild("BottleModels")
		return bm and bm:FindFirstChild(slotId)
	end
	if slotId == "Mityczny" then
		return ReplicatedStorage:FindFirstChild("Mityczny")
	end
	if slotId == SYRUP_ID then
		return ReplicatedStorage:FindFirstChild("SyrupModel")
	end
	if slotId == MAGNET_ID then
		return ReplicatedStorage:FindFirstChild("Magnes")
			or ReplicatedStorage:FindFirstChild("MagnetModel")
			or ReplicatedStorage:FindFirstChild("Magnet")
	end
	if isPetSlotId(slotId) then
		local uuid  = string.sub(slotId, #PET_ID_PREFIX + 1)
		local state = _G["__petsState"]
		local pets  = (state and state.pets) or {}
		for _, p in ipairs(pets) do
			if p.id == uuid then
				local isGold = p.gold == true
				local segs = isGold
					and ((Config.Pets and Config.Pets.GoldModelsFolderPath) or { "Pets", "PetyGold" })
					or  ((Config.Pets and Config.Pets.ModelsFolderPath)     or { "Pets", "PetyZwykle" })
				local folder: Instance? = ReplicatedStorage
				for _, s in ipairs(segs) do folder = folder and folder:FindFirstChild(s) end
				local name = ((Config.Pets and Config.Pets.ModelNamePrefix) or "Pet") .. tostring(p.rarity)
				return folder and folder:FindFirstChild(name)
			end
		end
	end
	return nil
end

-- Klucz cache — pet z gold-flag tworzy inny key (regrant wizualnego modelu po ZŁOTYM upgrade).
local function detailViewportKey(slotId: string): string
	if isPetSlotId(slotId) then
		local uuid  = string.sub(slotId, #PET_ID_PREFIX + 1)
		local state = _G["__petsState"]
		local pets  = (state and state.pets) or {}
		for _, p in ipairs(pets) do
			if p.id == uuid then return slotId .. (p.gold and "|gold" or "") end
		end
	end
	return slotId
end

D.vpModel = nil
D.vpConn  = nil
D.viewportFor = nil

local function clearDetailViewport()
	if D.vpConn  then D.vpConn:Disconnect(); D.vpConn = nil end
	if D.vpModel then D.vpModel:Destroy();   D.vpModel = nil end
	D.viewportFor = nil
end

local function loadDetailViewport(slotId: string)
	local key = detailViewportKey(slotId)
	if D.viewportFor == key and D.vpModel then return end
	clearDetailViewport()
	local tmpl = findDetailModelTemplate(slotId)
	if not tmpl then return end

	local clone
	if tmpl:IsA("Model") then
		clone = tmpl:Clone()
		if not clone.PrimaryPart then
			local p = clone:FindFirstChildWhichIsA("BasePart", true)
			if p then clone.PrimaryPart = p end
		end
	elseif tmpl:IsA("BasePart") then
		clone = Instance.new("Model")
		local p = tmpl:Clone(); p.Parent = clone; clone.PrimaryPart = p
	else
		return
	end
	if not clone.PrimaryPart then clone:Destroy(); return end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
	end

	local cam = D.viewport:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera"); cam.Parent = D.viewport; D.viewport.CurrentCamera = cam
	end

	clone.Parent = D.viewport
	local bbCF, size = clone:GetBoundingBox()
	clone:PivotTo(CFrame.new(-bbCF.Position) * clone:GetPivot())
	local recentered = clone:GetPivot()
	D.vpModel = clone
	D.viewportFor = key

	-- Butelki lekko nachylone w bok (~10°) dla bardziej dynamicznego look'u
	local isBottle = (slotId == "Zwykla" or slotId == "Rzadka" or slotId == "Epicka"
		or slotId == "Legendarna" or slotId == "Mityczny")
	local tilt = isBottle and CFrame.Angles(0, 0, math.rad(10)) or CFrame.new()

	local maxE = math.max(size.X, size.Y, size.Z)
	if maxE <= 0 then maxE = 4 end
	local dist = maxE * 1.9 + 2
	cam.FieldOfView = 45
	cam.CFrame = CFrame.new(Vector3.new(0, size.Y * 0.12, dist), Vector3.zero)

	local angle = 0
	D.vpConn = RunService.RenderStepped:Connect(function(dt)
		if not clone.Parent then return end
		angle += dt * 0.9
		clone:PivotTo(CFrame.Angles(0, angle, 0) * tilt * recentered)
	end)
end

D.dropBtn.MouseButton1Click:Connect(function()
	local r = D.currentRarity
	if not r or r == SYRUP_ID or r == MAGNET_ID then return end
	if (hudData.backpackContents[r] or 0) <= 0 then return end
	DropBottleEvt:FireServer(r)
end)

D.useBtn.MouseButton1Click:Connect(function()
	if D.currentRarity ~= MAGNET_ID then return end
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

D.petEquipBtn = Instance.new("TextButton")
D.petEquipBtn.Size                   = UDim2.new(1, -32, 0, 44)
D.petEquipBtn.AnchorPoint            = Vector2.new(0, 1)
D.petEquipBtn.Position               = UDim2.new(0, 16, 1, -68)  -- nad WYRZUĆ
D.petEquipBtn.BackgroundColor3       = C.ACCENT_GREEN
D.petEquipBtn.BorderSizePixel        = 0
D.petEquipBtn.Text                   = "ZAŁÓŻ"
D.petEquipBtn.TextSize               = 16
D.petEquipBtn.Font                   = FONT_MAIN
D.petEquipBtn.TextColor3             = Color3.new(0, 0, 0)
D.petEquipBtn.AutoButtonColor        = false
D.petEquipBtn.Visible                = false
D.petEquipBtn.ZIndex                 = 6
D.petEquipBtn.Parent                 = D.panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = D.petEquipBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = D.petEquipBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	D.petEquipBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	D.petEquipBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

D.petDiscardBtn = Instance.new("TextButton")
D.petDiscardBtn.Size                   = UDim2.new(1, -32, 0, 44)
D.petDiscardBtn.AnchorPoint            = Vector2.new(0, 1)
D.petDiscardBtn.Position               = UDim2.new(0, 16, 1, -16)
D.petDiscardBtn.BackgroundColor3       = Color3.fromRGB(180, 70, 70)
D.petDiscardBtn.BorderSizePixel        = 0
D.petDiscardBtn.Text                   = "WYRZUĆ"
D.petDiscardBtn.TextSize               = 16
D.petDiscardBtn.Font                   = FONT_MAIN
D.petDiscardBtn.TextColor3             = C.WHITE
D.petDiscardBtn.AutoButtonColor        = false
D.petDiscardBtn.Visible                = false
D.petDiscardBtn.ZIndex                 = 6
D.petDiscardBtn.Parent                 = D.panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = D.petDiscardBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = D.petDiscardBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	D.petDiscardBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	D.petDiscardBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- Helper: czy ten UUID jest w EquippedPets (lista wyposażonych petów).
-- Po refaktorze 1→2 sloty: equippedIds to lista, equippedId (legacy) to pierwszy z listy.
local function isUuidEquipped(uuid: string, state): boolean
	if not state then return false end
	local list = state.equippedIds
	if type(list) == "table" then
		for _, id in ipairs(list) do if id == uuid then return true end end
		return false
	end
	return (state.equippedId or "") == uuid
end

-- Pet click handlers (PO definicji buttonów żeby uniknąć order bug)
D.petEquipBtn.MouseButton1Click:Connect(function()
	if not isPetSlotId(D.currentRarity) then return end
	local uuid = string.sub(D.currentRarity, #PET_ID_PREFIX + 1)
	local state = _G["__petsState"]
	playSfx("Click")
	if isUuidEquipped(uuid, state) then
		UnequipPetEvt:FireServer(uuid)
	else
		EquipPetEvt:FireServer(uuid)
	end
end)

D.petDiscardBtn.MouseButton1Click:Connect(function()
	if not isPetSlotId(D.currentRarity) then return end
	local uuid = string.sub(D.currentRarity, #PET_ID_PREFIX + 1)
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
	if not D.currentRarity then return end
	local rarity = D.currentRarity
	loadDetailViewport(rarity)

	-- Quest item: syrop dziadka — inny widok (bez wartości / mnożnika)
	if rarity == SYRUP_ID then
		D.title.Text       = SYRUP.NAME
		D.title.TextColor3 = SYRUP.COLOR
		D.count.Text       = "Posiadasz: 1 sztukę"
		D.baseLbl.Text     = "Przedmiot zadania"
		D.totalLbl.Text    = "Nie sprzedasz tego w butelkomacie"
		D.multLbl.Text     = ""
		D.desc.Text        = SYRUP.DESC
		return
	end

	-- Pet — każdy slot to konkretny pet (id = "Pet_<uuid>")
	if isPetSlotId(rarity) then
		local uuid = string.sub(rarity, #PET_ID_PREFIX + 1)
		local state = _G["__petsState"]
		local pets  = (state and state.pets) or {}
		local thisEquipped = isUuidEquipped(uuid, state)
		local equippedCount = (state and state.equippedIds) and #state.equippedIds or ((state and state.equippedId and state.equippedId ~= "") and 1 or 0)
		local maxEq = (state and state.maxEquipped) or 1
		local pet
		for _, p in ipairs(pets) do
			if p.id == uuid then pet = p; break end
		end
		if not pet then
			D.title.Text = "Pet"
			D.count.Text = "(usunięty)"
			D.baseLbl.Text = ""
			D.totalLbl.Text = ""
			D.multLbl.Text = ""
			D.desc.Text = ""
			return
		end
		local rcfg = (Config.Pets and Config.Pets.Rarities and Config.Pets.Rarities[pet.rarity]) or {}
		local ccfg = (Config.Pets and Config.Pets.Classes and Config.Pets.Classes[pet.class]) or {}
		local color = rcfg.color or C.WHITE
		local rname = rcfg.displayName or pet.rarity
		local isGold = pet.gold == true
		local statMul = isGold and ((Config.Pets.GoldUpgrade and Config.Pets.GoldUpgrade.StatMultiplier) or 1.15) or 1
		local GOLD_COLOR = Color3.fromRGB(239, 199, 95)

		D.title.Text       = isGold and string.format("ZŁOTY %s %s", rname, pet.class)
			or string.format("%s %s", rname, pet.class)
		D.title.TextColor3 = isGold and GOLD_COLOR or color
		if thisEquipped then
			D.count.Text       = string.format("WYPOSAŻONY ✓  (%d/%d)", equippedCount, maxEq)
			D.count.TextColor3 = C.ACCENT_GREEN
		else
			D.count.Text       = string.format("Wolne sloty: %d/%d", maxEq - equippedCount, maxEq)
			D.count.TextColor3 = C.DIMTEXT
		end
		D.baseLbl.Text     = string.format("Mnożnik kasy: ×%.2f", (rcfg.moneyMul or 1) * statMul)
		local bonus = math.floor(((ccfg.bonuses and ccfg.bonuses[pet.rarity]) or 0) * statMul + 0.5)
		if ccfg.effect == "speed" then
			D.totalLbl.Text = string.format("Speed bonus: +%d (chodzenie i deska)", bonus)
		elseif ccfg.effect == "hp" then
			D.totalLbl.Text = string.format("HP bonus: +%d", bonus)
		else
			D.totalLbl.Text = ""
		end
		D.multLbl.Text = isGold and "✦ ZŁOTY PET — +15% do statystyk" or ""
		D.multLbl.TextColor3 = GOLD_COLOR
		D.desc.Text    = "Tylko 1 pet może być wyposażony naraz. Wyrzucenie usuwa pet na stałe."
		return
	end

	-- Magnes — każdy slot to OSOBNA sztuka (count zawsze 1, klikany pojedynczo)
	if rarity == MAGNET_ID then
		local mState = _G["__magnetState"] or { count = 0, active = false, secondsLeft = 0 }
		D.title.Text       = MAGNET.NAME
		D.title.TextColor3 = MAGNET.COLOR
		D.count.Text       = "1 sztuka"
		D.baseLbl.Text     = string.format("Czas działania: %d s", Config.Magnet.DurationSec)
		D.totalLbl.Text    = string.format("Promień: ×%.1f", Config.Magnet.RadiusMultiplier)
		if mState.active then
			D.multLbl.Text = string.format("AKTYWNY — zostało %ds", math.ceil(mState.secondsLeft or 0))
			D.multLbl.TextColor3 = MAGNET.COLOR
		else
			D.multLbl.Text = ""
		end
		D.desc.Text        = MAGNET.DESC
		return
	end

	local count = hudData.backpackContents[rarity] or 0
	local color = RARITY_COLORS[rarity] or C.WHITE
	local baseVal = Config.BottleValues[rarity] or 0
	local mult = getMultiplier()

	D.title.Text       = rarity
	D.title.TextColor3 = color
	D.count.Text       = "Posiadasz: " .. count .. " sztuk"
	D.baseLbl.Text     = "Wartość bazowa: " .. formatAmount(baseVal) .. " ZŁ / sztukę"
	local total = count * baseVal
	D.totalLbl.Text    = "Razem (×1): " .. formatAmount(total) .. " ZŁ"
	local totalMult = total * mult
	D.multLbl.Text     = string.format("Z mnożnikiem (×%.1f): %s ZŁ", mult, formatAmount(totalMult))
	D.desc.Text        = BOTTLE_DESC[rarity] or ""
end

-- Placeholder pokazywany w detail panelu gdy żaden item nie jest wybrany
D.placeholder = Instance.new("TextLabel")
D.placeholder.AnchorPoint            = Vector2.new(0.5, 0.5)
D.placeholder.Position               = UDim2.fromScale(0.5, 0.5)
D.placeholder.Size                   = UDim2.new(1, -32, 0, 120)
D.placeholder.BackgroundTransparency = 1
D.placeholder.Text                   = "Kliknij item\naby zobaczyć szczegóły"
D.placeholder.Font                   = FONT_MAIN
D.placeholder.TextSize               = 16
D.placeholder.TextColor3             = C.DIMTEXT
D.placeholder.TextXAlignment         = Enum.TextXAlignment.Center
D.placeholder.TextYAlignment         = Enum.TextYAlignment.Center
D.placeholder.TextWrapped            = true
D.placeholder.ZIndex                 = 5
D.placeholder.Parent                 = D.panel

local function setInvDetailContentVisible(visible: boolean)
	D.title.Visible    = visible
	D.count.Visible    = visible
	D.sep1.Visible     = visible
	D.baseLbl.Visible  = visible
	D.totalLbl.Visible = visible
	D.multLbl.Visible  = visible
	D.sep2.Visible     = visible
	D.desc.Visible     = visible
	D.closeBtn.Visible = visible
	local isPet = visible and isPetSlotId(D.currentRarity)
	-- DROP: tylko dla butelek (nie syrop, nie magnes, nie pet)
	D.dropBtn.Visible  = visible
		and D.currentRarity ~= SYRUP_ID
		and D.currentRarity ~= MAGNET_ID
		and not isPet
	-- UŻYJ: tylko dla magnesu
	D.useBtn.Visible   = visible and D.currentRarity == MAGNET_ID
	if D.useBtn.Visible then
		local mState = _G["__magnetState"] or { count = 0, active = false }
		local canUse = (mState.count or 0) > 0 and not mState.active
		D.useBtn.BackgroundColor3 = canUse and MAGNET.COLOR or Color3.fromRGB(90, 90, 90)
		D.useBtn.Text = mState.active and "AKTYWNY…" or (canUse and "UŻYJ" or "BRAK MAGNESÓW")
		D.useBtn.AutoButtonColor = false
	end
	-- PET: ZAŁÓŻ/ZDEJMIJ + WYRZUĆ
	D.petEquipBtn.Visible   = isPet
	D.petDiscardBtn.Visible = isPet
	if isPet then
		local uuid = string.sub(D.currentRarity, #PET_ID_PREFIX + 1)
		local state = _G["__petsState"]
		local thisEquipped = isUuidEquipped(uuid, state)
		local equippedCount = (state and state.equippedIds) and #state.equippedIds or 0
		local maxEq = (state and state.maxEquipped) or 1
		if thisEquipped then
			D.petEquipBtn.Text            = "ZDEJMIJ"
			D.petEquipBtn.BackgroundColor3 = Color3.fromRGB(190, 150, 60)
			D.petEquipBtn.TextColor3       = C.WHITE
			D.petEquipBtn.AutoButtonColor  = false
		elseif equippedCount >= maxEq then
			D.petEquipBtn.Text            = string.format("PEŁNE SLOTY (%d/%d)", equippedCount, maxEq)
			D.petEquipBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
			D.petEquipBtn.TextColor3       = C.WHITE
			D.petEquipBtn.AutoButtonColor  = false
		else
			D.petEquipBtn.Text            = "ZAŁÓŻ"
			D.petEquipBtn.BackgroundColor3 = C.ACCENT_GREEN
			D.petEquipBtn.TextColor3       = Color3.new(0, 0, 0)
			D.petEquipBtn.AutoButtonColor  = false
		end
	end
	D.viewport.Visible = visible
	if not visible then clearDetailViewport() end
	D.placeholder.Visible = not visible
end

local function showInvDetail(rarity: string)
	-- Zawsze pokazuj detale klikniętego itemu (bez toggle na tej samej rzadkości).
	-- Chowanie: tylko X w detail panelu albo zamknięcie ekwipunku.
	D.currentRarity = rarity
	refreshInvDetail()
	setInvDetailContentVisible(true)
	D.visible = true
end

local function hideInvDetail()
	if not D.visible then return end
	D.visible = false
	D.currentRarity = nil
	setInvDetailContentVisible(false)
end

D.closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); hideInvDetail() end)

-- Initial state — placeholder widoczny, X i content schowane
setInvDetailContentVisible(false)

-- ── Wrapper EKWIPUNEK dla MenuController ─────────────────────────────────
-- Mounted bez własnej ramki/headera — pasek zakładek menu już to robi.
-- Layout: count label "X/Y" u góry, sloty po lewej, detail panel po prawej.
local INV_TOP_LBL_H = 28
local INV_SUBTAB_H  = 44   -- pasek sub-zakładek BUTELKI / AKCESORIA / PETY
local INV_SUBTAB_GAP = 10  -- gap pod sub-tabami przed slotsContainerem
local INV_CONTENT_Y_OFF = INV_TOP_LBL_H + INV_SUBTAB_H + INV_SUBTAB_GAP

local inventoryWrap = Instance.new("Frame")
inventoryWrap.Size                   = UDim2.fromOffset(slotsW + INV_DET_GAP + INV_DET_W,
	slotsH + INV_CONTENT_Y_OFF)
inventoryWrap.BackgroundTransparency = 1
inventoryWrap.BorderSizePixel        = 0
inventoryWrap.AnchorPoint            = Vector2.new(0.5, 0.5)
inventoryWrap.Position               = UDim2.fromScale(0.5, 0.5)
inventoryWrap.Parent                 = invPanel  -- domyślnie w hidden invGui

-- Eksport NATYCHMIASTOWY — MenuController czeka maks 10s, jeśli UI poniżej erroruje
-- (np. nowe sub-zakładki), EQ i tak będzie widoczne w menu. Pety/butelki ładują się
-- przez updateInventory() niezależnie od sub-tab bara.
_G["__inventoryWrap"]  = inventoryWrap
_G["__inventoryReady"] = true

-- Reparent + reposition: header niewidoczny, content w wrapie
invHeader.Visible    = false

invCountLbl.Parent   = inventoryWrap
invCountLbl.Position = UDim2.fromOffset(0, 0)
invCountLbl.Size     = UDim2.fromOffset(slotsW, INV_TOP_LBL_H)
invCountLbl.TextXAlignment = Enum.TextXAlignment.Left
invCountLbl.TextColor3 = C.DIMTEXT

-- Sub-tab pill bar (BUTELKI / AKCESORIA / PETY) — pod count label, nad slotami.
local subTabBar = Instance.new("Frame")
subTabBar.Size                   = UDim2.fromOffset(slotsW, INV_SUBTAB_H)
subTabBar.Position               = UDim2.fromOffset(0, INV_TOP_LBL_H)
subTabBar.BackgroundColor3       = C.HEADER
subTabBar.BorderSizePixel        = 0
subTabBar.Parent                 = inventoryWrap
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, INV_SUBTAB_H / 2); c.Parent = subTabBar
	local s = Instance.new("UIStroke"); s.Color = C.BORDER; s.Thickness = 2; s.Parent = subTabBar
end

local SUB_TAB_DEFS = {
	{ id = INV_SUBTAB_BOTTLES,     label = "BUTELKI" },
	{ id = INV_SUBTAB_ACCESSORIES, label = "AKCESORIA" },
	{ id = INV_SUBTAB_PETS,        label = "PETY" },
}
local subTabBtns: { TextButton } = {}
local SUB_PAD     = 6
local subInnerW   = slotsW - SUB_PAD * 2
local subCellW    = subInnerW / #SUB_TAB_DEFS

-- Bubble indicator (active highlight)
local subBubble = Instance.new("Frame")
subBubble.Size                   = UDim2.fromOffset(subCellW, INV_SUBTAB_H - SUB_PAD * 2)
subBubble.Position               = UDim2.fromOffset(SUB_PAD, SUB_PAD)
subBubble.BackgroundColor3       = C.ACCENT_GREEN
subBubble.BorderSizePixel        = 0
subBubble.ZIndex                 = 2
subBubble.Parent                 = subTabBar
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, (INV_SUBTAB_H - SUB_PAD * 2) / 2); c.Parent = subBubble
end

for i, def in ipairs(SUB_TAB_DEFS) do
	local btn = Instance.new("TextButton")
	btn.Size                   = UDim2.fromOffset(subCellW, INV_SUBTAB_H - SUB_PAD * 2)
	btn.Position               = UDim2.fromOffset(SUB_PAD + (i - 1) * subCellW, SUB_PAD)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel        = 0
	btn.Text                   = def.label
	btn.Font                   = FONT_MAIN
	btn.TextSize               = 17
	btn.TextColor3             = C.DIMTEXT
	btn.AutoButtonColor        = false
	btn.ZIndex                 = 3
	btn.Parent                 = subTabBar
	subTabBtns[i] = btn
end

slotsContainer.Parent   = inventoryWrap
slotsContainer.Position = UDim2.fromOffset(0, INV_CONTENT_Y_OFF)

D.panel.Parent   = inventoryWrap
D.panel.Position = UDim2.fromOffset(slotsW + INV_DET_GAP, INV_CONTENT_Y_OFF)

-- (Eksport _G["__inventoryWrap"] przeniesiony wyżej — patrz po inventoryWrap.Parent = invPanel.)

-- ── Slot frames ───────────────────────────────────────────────────────────

-- Tablice referencji per-slot zgrupowane w jednej tabeli SL (zamiast 13 osobnych
-- lokalnych) — oszczędność rejestrów lokalnych (limit Luau 200 na chunk).
local SL = {
	frames   = {},   -- { Frame }
	accents  = {},   -- { Frame } (legacy, używane w startDrag)
	names    = {},   -- { TextLabel }
	counts   = {},   -- { TextLabel }
	scales   = {},   -- { UIScale }
	strokes  = {},   -- { UIStroke }
	petGlows = {},   -- { Frame } gradient overlay dla petów
	petGrads = {},   -- { UIGradient }
	petImgs  = {},   -- { ImageLabel } tekstura peta per rzadkość
	legGlows = {},   -- { Frame }
	legGrads = {},   -- { UIGradient }
	mytGlows = {},   -- { Frame }
	mytGrads = {},   -- { UIGradient }
}

local function darken(c: Color3, mix: number): Color3
	return Color3.new(c.R * (1 - mix), c.G * (1 - mix), c.B * (1 - mix))
end

for i = 1, SLOT_COUNT do
	local col = (i - 1) % SLOTS_PER_ROW
	local row = math.floor((i - 1) / SLOTS_PER_ROW)

	-- AnchorPoint w środku, by UIScale rosło ze środka. +SLOT_OUTER_PAD = wewnętrzny margines
	-- żeby strokes slotów nie były ucinane przez ScrollingFrame ClipsDescendants.
	local sf = mkFrame(slotsContainer,
		UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE),
		UDim2.new(0,
			col * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE/2 + SLOT_OUTER_PAD,
			0,
			row * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE/2 + SLOT_OUTER_PAD),
		C.SLOT, 0)
	sf.AnchorPoint = Vector2.new(0.5, 0.5)
	sf.ClipsDescendants = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.BORDER_SL; stroke.Thickness = 3
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
	local accent = mkFrame(sf, UDim2.new(0, 1, 0, 1), UDim2.new(0, 0, 0, 0), C.WHITE, 1)
	accent.Visible = false

	local nameLbl = mkLabel(sf, UDim2.new(1, -16, 0, 22), UDim2.new(0, 12, 0, 8), "", 17, C.WHITE)
	nameLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	nameLbl.TextStrokeTransparency = 0.3
	nameLbl.ZIndex = 2
	local cntLbl  = mkLabel(sf, UDim2.new(1, -12, 0, 40), UDim2.new(0, 0, 1, -46),
		"", 32, C.WHITE, Enum.TextXAlignment.Right)
	cntLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	cntLbl.TextStrokeTransparency = 0.2
	cntLbl.ZIndex = 2

	SL.frames[i]    = sf
	SL.accents[i]   = accent
	SL.names[i]  = nameLbl
	SL.counts[i] = cntLbl
	SL.scales[i]    = scale
	SL.strokes[i]   = stroke
	SL.legGlows[i]  = legGlow
	SL.legGrads[i]  = legGrad

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
	SL.mytGlows[i] = mytGlow
	SL.mytGrads[i] = mytGrad

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
	SL.petGlows[i] = petGlow
	SL.petGrads[i] = petGrad

	-- Tekstura peta — obrazek per rzadkość, mieści się w kwadracie slotu (z marginesem).
	-- Nad glow/tłem, pod tekstem (nazwa klasy / count mają wyższy ZIndex).
	local petImg = Instance.new("ImageLabel")
	petImg.Size                   = UDim2.fromScale(0.82, 0.82)
	petImg.Position               = UDim2.fromScale(0.5, 0.46)
	petImg.AnchorPoint            = Vector2.new(0.5, 0.5)
	petImg.BackgroundTransparency = 1
	petImg.ScaleType              = Enum.ScaleType.Fit  -- cały obrazek mieści się w slocie
	petImg.Image                  = ""
	petImg.Visible                = false
	petImg.ZIndex                 = 1  -- nad glow (0), pod tekstem nazwy/count (2)
	petImg.Parent                 = sf
	SL.petImgs[i] = petImg
end

-- ── Render ────────────────────────────────────────────────────────────────

local function renderSlot(i: number)
	local data = slots[i]
	if data then
		SL.frames[i].BackgroundColor3 = darken(data.color, 0.45)
		SL.strokes[i].Color           = data.color
		SL.strokes[i].Thickness       = 3
		SL.names[i].Text           = data.name
		SL.names[i].TextColor3     = C.WHITE
		SL.counts[i].Text          = tostring(data.count)
		SL.counts[i].TextColor3    = C.WHITE
		SL.legGlows[i].Visible        = (data.name == "Legendarna")
		SL.mytGlows[i].Visible        = (data.name == "Mityczny")
		-- Pet slot — pokaż diagonalny gradient w kolorze peta
		local isPet = isPetSlotId(data.id)
		SL.petGlows[i].Visible = isPet
		local img = SL.petImgs[i]  -- generyczny ImageLabel slotu (pet ALBO tekstura butelki)
		if isPet then
			-- ColorSequence: kolor rzadkości → biel → kolor rzadkości
			SL.petGrads[i].Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   data.color),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1,   data.color),
			})
			-- Ukryj zwykły count (1) dla peta — pokażemy emoji klasy
			-- (SL.names jest "Sprinter"/"Tank", count "1" pomijamy bo każdy pet = 1)
			SL.counts[i].Text = ""
			-- Tekstura peta per rzadkość (gold pet → osobna tekstura z GoldUpgrade.Images)
			local rcfg = (Config.Pets and Config.Pets.Rarities and Config.Pets.Rarities[data.petRarity]) or {}
			local petTex = rcfg.image
			if data.petGold then
				local gimg = Config.Pets and Config.Pets.GoldUpgrade and Config.Pets.GoldUpgrade.Images
				petTex = (gimg and gimg[data.petRarity]) or petTex
			end
			if img then
				img.Image   = petTex or ""
				img.Visible = (petTex ~= nil)
				-- Huge ma natywnie mniejszą grafikę — powiększamy żeby pasował do butelek
				local sc = (data.petRarity == "Huge") and 0.98 or 0.82
				img.Size = UDim2.fromScale(sc, sc)
			end
		elseif img then
			-- Butelka — tekstura per rzadkość; magnes — tekstura z Config. Syrop bez obrazka.
			local itemImg
			if string.sub(data.id, 1, 7) == "Bottle_" then
				itemImg = Config.BottleImages and Config.BottleImages[data.name]
			elseif data.id == MAGNET_ID then
				itemImg = MAGNET.IMAGE
			end
			if itemImg then
				img.Image   = itemImg
				img.Visible = true
				img.Size    = UDim2.fromScale(0.82, 0.82)
			else
				img.Visible = false
			end
		end
	else
		SL.frames[i].BackgroundColor3 = C.SLOT
		SL.strokes[i].Color           = C.BORDER_SL
		SL.strokes[i].Thickness       = 3
		SL.names[i].Text           = ""
		SL.counts[i].Text          = ""
		SL.legGlows[i].Visible        = false
		SL.mytGlows[i].Visible        = false
		SL.petGlows[i].Visible        = false
		if SL.petImgs[i] then SL.petImgs[i].Visible = false end
	end
end

-- Forward: scheduleLayoutSync używany przez updateInventory, definicja niżej
local scheduleLayoutSync: () -> ()

-- Filter sub-zakładek (BUTELKI/AKCESORIA/PETY) — ustawia SL.frames[i].Visible.
-- Pusty slot widoczny we wszystkich zakładkach (żeby user widział wolne miejsce).
-- Pozycja komórki w packed gridzie (AnchorPoint slotu = 0.5,0.5 → środek komórki).
local function packedSlotPosition(packIdx: number): UDim2  -- packIdx 0-based
	local col = packIdx % SLOTS_PER_ROW
	local row = math.floor(packIdx / SLOTS_PER_ROW)
	return UDim2.new(0,
		col * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE / 2 + SLOT_OUTER_PAD,
		0,
		row * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE / 2 + SLOT_OUTER_PAD)
end

-- Layout aktualnej zakładki: itemy danej kategorii pakowane od lewego-górnego rogu,
-- potem PUSTE komórki do pojemności kategorii (70/20/10). Reszta slotów ukryta.
-- Pozycje przeliczane dynamicznie — drag używa hover per-frame (hoveredSlot), więc
-- repozycjonowanie ramek slotów jest bezpieczne i nie psuje przeciągania.
local function applyInvSubTabFilter()
	-- Safety: jeśli sub-tab UI nie wystartowało (np. error przy Instance.new), nie ruszaj layoutu.
	if #subTabBtns < #SUB_TAB_DEFS then return end

	local caps = getCategoryCaps()
	local cap  = caps[currentInvSubTab] or 0

	-- Zbierz indeksy: itemy aktualnej kategorii (w kolejności slotów) + puste sloty.
	local itemIdx: { number }  = {}
	local emptyIdx: { number } = {}
	for i = 1, SLOT_COUNT do
		local s = slots[i]
		if s == nil then
			table.insert(emptyIdx, i)
		elseif getInvSubTab(s) == currentInvSubTab then
			table.insert(itemIdx, i)
		end
	end

	-- Komórki = pojemność kategorii, nie mniej niż liczba itemów (legacy overflow nie znika).
	local totalCells  = math.max(#itemIdx, cap)
	local emptyNeeded = math.max(0, totalCells - #itemIdx)

	-- Ukryj wszystko, potem pokaż+ustaw pozycje: najpierw itemy, potem puste komórki.
	for i = 1, SLOT_COUNT do
		if SL.frames[i] then SL.frames[i].Visible = false end
	end

	local pack = 0
	for _, i in ipairs(itemIdx) do
		local sf = SL.frames[i]
		if sf then
			sf.Position = packedSlotPosition(pack)
			sf.Visible  = true
			pack += 1
		end
	end
	for k = 1, emptyNeeded do
		local i = emptyIdx[k]
		if not i then break end
		local sf = SL.frames[i]
		if sf then
			sf.Position = packedSlotPosition(pack)
			sf.Visible  = true
			pack += 1
		end
	end

	-- CanvasSize wg liczby rzędów pokazanych komórek (scroll gdy > VISIBLE_ROWS).
	local rows   = math.max(1, math.ceil(pack / SLOTS_PER_ROW))
	slotsContainer.CanvasSize = UDim2.fromOffset(0, rows * SLOT_SIZE + (rows - 1) * SLOT_GAP)

	updateCategoryCounter()
end

local function setInvSubTab(idx: number)
	local def = SUB_TAB_DEFS[idx]
	if not def then return end
	if currentInvSubTab == def.id then
		-- Nawet bez zmiany — odśwież filter (np. po przeładowaniu petów/butelek po stronie serwera)
		applyInvSubTabFilter()
		return
	end
	currentInvSubTab = def.id

	-- Bubble move
	local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(subBubble, ti, {
		Position = UDim2.fromOffset(SUB_PAD + (idx - 1) * subCellW, SUB_PAD),
	}):Play()
	-- Tab text colors
	for i, b in ipairs(subTabBtns) do
		b.TextColor3 = (i == idx) and Color3.new(0, 0, 0) or C.DIMTEXT
	end

	-- Zamknij detail panel — mógł pokazywać item z innej kategorii (teraz ukryty).
	hideInvDetail()
	applyInvSubTabFilter()
end

-- Initial: tab 1 (BUTELKI) aktywny, czarny tekst na zielonym bubbliem.
subTabBtns[1].TextColor3 = Color3.new(0, 0, 0)
for i, btn in ipairs(subTabBtns) do
	local idx = i
	btn.MouseButton1Click:Connect(function() playSfx("Click"); setInvSubTab(idx) end)
end

local function updateInventory()
	for i = 1, SLOT_COUNT do renderSlot(i) end
	applyInvSubTabFilter()
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
					color = RARITY_COLORS[s.rarity] or C.WHITE,
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
					color = RARITY_COLORS[s.rarity] or C.WHITE,
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
						color = RARITY_COLORS[s.rarity] or C.WHITE,
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
			SL.strokes[i].Color = Color3.fromRGB(
				255,
				200 + math.floor(pulse * 55),
				60  + math.floor(pulse * 195))
			SL.strokes[i].Thickness = 3 + pulse * 2.5
			SL.legGrads[i].Rotation = (SL.legGrads[i].Rotation + 80 * dt) % 360
		elseif data and data.name == "Mityczny" then
			local pulse = (math.sin(t * 4.0) + 1) * 0.5
			SL.strokes[i].Color = Color3.fromRGB(
				80  + math.floor(pulse * 100),
				20  + math.floor(pulse * 60),
				140 + math.floor(pulse * 100))
			SL.strokes[i].Thickness = 3 + pulse * 2.5
			SL.mytGrads[i].Rotation = (SL.mytGrads[i].Rotation + 60 * dt) % 360
		elseif data and isPetSlotId(data.id) then
			-- Pet: diagonalny shimmer (45° wolniej niż legendary) — odróżnia od butelek
			SL.petGrads[i].Rotation = (SL.petGrads[i].Rotation + 45 * dt) % 360
			-- Subtelny pulse stroke w kolorze peta
			local pulse = (math.sin(t * 3.0) + 1) * 0.5  -- 0..1
			SL.strokes[i].Thickness = 3 + pulse * 1.5
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
		SL.frames[i].BackgroundColor3 = C.SLOT_HOV
		local hoverStroke = SL.frames[i]:FindFirstChildOfClass("UIStroke") :: UIStroke
		if hoverStroke then hoverStroke.Color = C.BORDER_SL end
	else
		renderSlot(i)
		local s = SL.frames[i]:FindFirstChildOfClass("UIStroke") :: UIStroke
		if s then s.Color = C.BORDER end
	end
end

-- MouseEnter / MouseLeave na każdym slocie — to jest nasze hit-testing
local SLOT_TI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for i = 1, SLOT_COUNT do
	local idx = i
	SL.frames[i].MouseEnter:Connect(function()
		hoveredSlot = idx
		TweenService:Create(SL.scales[idx], SLOT_TI, { Scale = 1.06 }):Play()
		if drag.active then
			setSlotHighlight(idx, true)
		end
	end)
	SL.frames[i].MouseLeave:Connect(function()
		if hoveredSlot == idx then hoveredSlot = nil end
		TweenService:Create(SL.scales[idx], SLOT_TI, { Scale = 1.00 }):Play()
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
		C.SLOT_OC, 0.05)
	g.ZIndex  = 100
	g.Active  = false   -- przepuszcza eventy do slotów poniżej
	mkStroke(g, data.color, 2)

	local acc = mkFrame(g, UDim2.new(0, 3, 1, 0), UDim2.new(0, 0, 0, 0), data.color, 0)
	acc.ZIndex = 101
	local nl = mkLabel(g, UDim2.new(1, -8, 0, 13), UDim2.new(0, 6, 0, 4), data.name, 9, data.color)
	nl.ZIndex = 101
	local cl = mkLabel(g, UDim2.new(1, -5, 0, 20), UDim2.new(0, 0, 1, -22),
		tostring(data.count), 17, C.WHITE, Enum.TextXAlignment.Right)
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
	SL.frames[slotIdx].BackgroundColor3        = C.SLOT
	SL.accents[slotIdx].Visible                = false
	SL.names[slotIdx].Visible               = false
	SL.counts[slotIdx].Visible              = false

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
				slots[fromIdx] = { id = rarityId, name = src and src.name or "", color = src and src.color or C.WHITE, count = splitN }
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
	SL.accents[fromIdx].Visible   = true
	SL.names[fromIdx].Visible  = true
	SL.counts[fromIdx].Visible = true

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
	SL.frames[i].InputBegan:Connect(function(input)
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
		D.visible = false
		D.currentRarity = nil
		invPanel.Size = UDim2.fromOffset(INV_W_COMPACT, INV_H)

		TweenService:Create(invPanel,   INV_TW_CLOSE, { Position = INV_POS_HIDE }):Play()
		local tw = TweenService:Create(invOverlay, INV_TW_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not inventoryOpen then invGui.Enabled = false end
		end)
		tw:Play()
	end

	eqBtn.TextColor3             = C.WHITE
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
				if D.visible then refreshInvDetail() end
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
	if D.visible then refreshInvDetail() end
end)

CollectBottleResult.OnClientEvent:Connect(function(result)
	if result.success then
		hudData.bottlesCarried                   = result.bottlesCarried
		hudData.backpackCapacity                 = result.capacity
		hudData.backpackContents[result.rarity] += 1
		addToInventory(result.rarity)
		updateHud(); updateInventory()
		if D.visible then refreshInvDetail() end
		showFloatingText(result.rarity, RARITY_COLORS[result.rarity] or C.WHITE)
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
		showFloatingText("SYROP DZIADKA", SYRUP.COLOR)
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
_G["__petsState"] = { pets = {}, equippedId = "", equippedIds = {}, maxEquipped = 1, bankPets = {}, bonuses = {} }
PetStatusUpdateEvt.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	_G["__petsState"] = {
		pets        = data.pets or {},
		equippedId  = data.equippedId or "",                    -- legacy: pierwszy z listy
		equippedIds = data.equippedIds or {},                    -- lista UUID
		maxEquipped = data.maxEquipped or 1,                     -- ile slotów dostępnych
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
	if D.visible and isPetSlotId(D.currentRarity) then
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
		if D.visible and D.currentRarity == MAGNET_ID then
			refreshInvDetail()
			setInvDetailContentVisible(true)
		end
	end)
end)

