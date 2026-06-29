-- BankService.luau
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local RARITIES = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }
local BANK_DS = DataStoreService:GetDataStore("BankData_v1")
local BANK_BASE_CAP = (Config.Bank and Config.Bank.BaseCapacity) or 10
local BANK_UPG_BASE = (Config.Bank and Config.Bank.UpgradeBaseCost) or 1000
local BANK_UPG_STEP = (Config.Bank and Config.Bank.UpgradeCostStep) or 500

local function getBankCapacity(pData): number
	return BANK_BASE_CAP + (pData.BankCapLevel or 0)
end

local function nextUpgradeCost(pData): number
	return BANK_UPG_BASE + (pData.BankCapLevel or 0) * BANK_UPG_STEP
end

local cache: { [Player]: { [string]: number } } = {}

-- Anchor bankiera + dystans do walidacji handlerów (anti-exploit: gracz musi stać przy bankierze).
-- XZ-only distance — ignorujemy Y, bo Util.findAnchor preferuje Head dla R15 (Head jest ~5 studs nad
-- podłogą, HRP gracza ~3 studs). 3D distance łatwo przekraczało budżet przy bankierze na rampie.
local bankAnchor: BasePart? = nil
local BANK_MAX_DIST = 15 -- studs (XZ)
local function isNearBank(player: Player): boolean
	if not bankAnchor then
		return false
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return false
	end
	local d = (hrp :: BasePart).Position - bankAnchor.Position
	local horizSq = d.X * d.X + d.Z * d.Z
	return horizSq <= BANK_MAX_DIST * BANK_MAX_DIST
end

-- Throttle (per-player) na transfery/upgrade — anti-spam
local lastTransferAt: { [Player]: number } = {}
local lastUpgradeAt: { [Player]: number } = {}
local TRANSFER_THROTTLE = 0.3
local UPGRADE_THROTTLE = 0.5

local Events = ReplicatedStorage:WaitForChild("Events")
local BankInit = Events:WaitForChild("BankInit")
local BankDeposit = Events:WaitForChild("BankDeposit")
local BankWithdraw = Events:WaitForChild("BankWithdraw")
local BankResult = Events:WaitForChild("BankResult")
local UpgradeBank = Events:WaitForChild("UpgradeBank")
local UpdateHUD = Events:WaitForChild("UpdateHUD")

local deepCopy = Util.deepCopy

-- Retry z exponential backoff (DataStore throttle/transient errors)
local RETRY_DELAYS = { 0.5, 1.5, 3 }

local function loadBank(player: Player): { [string]: number }
	-- Jeśli poprzedni load failnął (__loadFailed=true), spróbuj znowu — DataStore mógł
	-- już wyzdrowieć. Bez tego cache "zablokowany pusty" trzymał się do końca sesji.
	if cache[player] and not cache[player].__loadFailed then
		return cache[player]
	end
	local key = "BankData_v1_" .. player.UserId
	local lastErr: any = nil
	local ok, res = false, nil
	for attempt = 0, #RETRY_DELAYS do
		ok, res = pcall(function()
			return BANK_DS:GetAsync(key)
		end)
		if ok then
			break
		end
		lastErr = res
		if attempt < #RETRY_DELAYS then
			task.wait(RETRY_DELAYS[attempt + 1])
		end
	end
	local data = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
	if ok and type(res) == "table" then
		for _, r in ipairs(RARITIES) do
			if type(res[r]) == "number" then
				data[r] = math.max(0, math.floor(res[r]))
			end
		end
	elseif not ok then
		warn(
			"[BankService] GetAsync failed po 3 próbach:",
			lastErr,
			"— skarbiec zostanie zainicjowany pusty, ale SaveBank zablokowany"
		)
		data.__loadFailed = true -- gate w saveBank
	end
	cache[player] = data
	return data
end

-- Serializacja per gracz z coalescingiem dirty-flag (patrz PlayerDataService.SaveData).
-- Stary kod robił `return` po wait → ZMIANY CACHE PO STARCIE POPRZEDNIEGO SAVE BYŁY TRACONE
-- (np. ULEPSZ skarbca, transfer butelek tuż przed PlayerRemoving). Fix: pętla repeat-until
-- gwarantuje że każdy saveBank() call powoduje że stan z cache JEST w DataStore.
type SaveState = { inFlight: BindableEvent?, dirty: boolean }
local saveState: { [Player]: SaveState } = {}

local function setBankWithRetry(key: string, d: any): boolean
	local lastErr: any = nil
	for attempt = 0, #RETRY_DELAYS do
		local ok, err = pcall(function()
			BANK_DS:SetAsync(key, d)
		end)
		if ok then
			return true
		end
		lastErr = err
		if attempt < #RETRY_DELAYS then
			task.wait(RETRY_DELAYS[attempt + 1])
		end
	end
	warn("[BankService] SetAsync failed po 3 próbach:", lastErr)
	return false
end

local function saveBank(player: Player)
	local d = cache[player]
	if not d or d.__loadFailed then
		return
	end

	local st = saveState[player]
	if not st then
		st = { inFlight = nil, dirty = false }
		saveState[player] = st
	end

	if st.inFlight then
		st.dirty = true
		st.inFlight.Event:Wait()
		return
	end

	local ev = Instance.new("BindableEvent")
	st.inFlight = ev
	local key = "BankData_v1_" .. player.UserId
	repeat
		st.dirty = false
		local cur = cache[player]
		if not cur or cur.__loadFailed then
			break
		end
		setBankWithRetry(key, cur)
	until not st.dirty
	st.inFlight = nil
	ev:Fire()
end

-- ── ProximityPrompt na workspace.BANK.Bankier ─────────────────────────────
task.spawn(function()
	local bankFolder = workspace:WaitForChild("BANK", 30)
	if not bankFolder then
		warn("[BankService] workspace.BANK nie istnieje")
		return
	end
	local bankier = bankFolder:WaitForChild("Bankier", 15)
	if not bankier then
		warn("[BankService] BANK.Bankier nie istnieje")
		return
	end

	local anchor: BasePart?
	if bankier:IsA("Model") then
		anchor = bankier.PrimaryPart or bankier:FindFirstChildWhichIsA("BasePart")
	elseif bankier:IsA("BasePart") then
		anchor = bankier :: BasePart
	end
	if not anchor then
		warn("[BankService] Bankier nie ma BasePart")
		return
	end
	bankAnchor = anchor -- cache do walidacji dystansu w handlerach

	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Otwórz bank"
		prompt.ObjectText = "Bankier"
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.UIOffset = Vector2.new(0, -100) -- prompt nad głowami innych graczy
		prompt.Parent = anchor
	end

	prompt.Triggered:Connect(function(player: Player)
		local pData = PlayerDataService.GetData(player)
		if (pData.BaseLevel or 0) < 1 then
			BankInit:FireClient(player, { locked = true, reason = "needBase" })
			return
		end
		local bData = loadBank(player)
		BankInit:FireClient(player, {
			bankContents = deepCopy(bData),
			backpackContents = deepCopy(pData.BackpackContents),
			backpackCapacity = Config.BackpackUpgrades[pData.BackpackLevel].Capacity,
			bankCapacity = getBankCapacity(pData),
			bankUpgradeLevel = pData.BankCapLevel or 0,
			bankUpgradeCost = nextUpgradeCost(pData),
			zlotowki = pData.Zlotowki or 0,
			hasSyrup = (pData.Grandpa and pData.Grandpa.hasSyrup) or false,
			-- Pety: zarówno w EQ jak i w banku — klient renderuje sloty
			eqPets = deepCopy(pData.Pets or {}),
			bankPets = deepCopy(pData.BankPets or {}),
			equippedPetId = pData.EquippedPet or "", -- legacy: pierwszy z listy
			equippedPetIds = pData.EquippedPets or {}, -- nowe: lista UUID
			maxEquippedPets = pData.MaxEquippedPets or 1,
		})
	end)
end)

-- ── Walidacja i zapis transferu (deposit i withdraw identyczne po stronie serwera) ──
-- payload (rawBp/rawBk) — butelki per-rzadkość liczby.
-- petIds (eqPetIds / bankPetIds) — listy UUIDów po transferze; conservation: każdy UUID
-- musi być po stronie EQ LUB Banku (nie obu). Niezmienność zbioru UUIDów.
local function handleTransfer(player: Player, rawBp: any, rawBk: any, eqPetIds: any, bankPetIds: any)
	if type(rawBp) ~= "table" or type(rawBk) ~= "table" then
		return false, "invalid"
	end
	-- Pet listy mogą być nil (klient bez petów); normalizujemy
	if eqPetIds == nil then
		eqPetIds = {}
	end
	if bankPetIds == nil then
		bankPetIds = {}
	end
	if type(eqPetIds) ~= "table" or type(bankPetIds) ~= "table" then
		return false, "invalid"
	end

	local pData = PlayerDataService.GetData(player)
	if (pData.BaseLevel or 0) < 1 then
		return false, "locked"
	end
	local bData = loadBank(player)

	-- Conservation check butelek
	for _, r in ipairs(RARITIES) do
		local oldTotal = (pData.BackpackContents[r] or 0) + (bData[r] or 0)
		local bpAmt = math.floor(math.max(0, tonumber(rawBp[r] or 0) or 0))
		local bkAmt = math.floor(math.max(0, tonumber(rawBk[r] or 0) or 0))
		if bpAmt + bkAmt ~= oldTotal then
			return false, "conservation"
		end
	end

	-- Conservation petów: stary zbiór UUIDów musi się równać nowemu (suma EQ + Bank)
	local oldUuids: { [string]: any } = {}
	for _, p in ipairs(pData.Pets or {}) do
		oldUuids[p.id] = p
	end
	for _, p in ipairs(pData.BankPets or {}) do
		oldUuids[p.id] = p
	end

	local newEqSet, newBankSet = {}, {}
	for _, id in ipairs(eqPetIds) do
		if type(id) ~= "string" or not oldUuids[id] then
			return false, "conservation"
		end
		if newEqSet[id] or newBankSet[id] then
			return false, "conservation"
		end
		newEqSet[id] = true
	end
	for _, id in ipairs(bankPetIds) do
		if type(id) ~= "string" or not oldUuids[id] then
			return false, "conservation"
		end
		if newEqSet[id] or newBankSet[id] then
			return false, "conservation"
		end
		newBankSet[id] = true
	end
	-- Wszystkie stare UUIDy musiały trafić do jednego ze zbiorów
	for uuid in pairs(oldUuids) do
		if not (newEqSet[uuid] or newBankSet[uuid]) then
			return false, "conservation"
		end
	end

	-- Capacity check: nowy plecak nie przekracza pojemności.
	-- Budujemy hipotetyczny snapshot (po transferze) i liczymy przez Util.getCarriedCount —
	-- single source of truth (syrop + magnesy + pety + butelki).
	local hasSyrup = pData.Grandpa and pData.Grandpa.hasSyrup or false
	local cap = Config.BackpackUpgrades[pData.BackpackLevel].Capacity
	local newBpContents = {}
	for _, r in ipairs(RARITIES) do
		newBpContents[r] = math.floor(math.max(0, tonumber(rawBp[r] or 0) or 0))
	end
	local simulated = {
		BackpackContents = newBpContents,
		Grandpa = { hasSyrup = hasSyrup },
		MagnetCount = pData.MagnetCount or 0,
		Pets = eqPetIds, -- lista UUIDów, Util używa #, więc liczba slotów się zgadza
	}
	if Util.getCarriedCount(simulated) > cap then
		return false, "overCapacity"
	end

	-- Limity per-kategoria plecaka (BUTELKI 70% / PETY 20%) — spójne ze zbieraniem/jajkami.
	-- Non-regressive: blokujemy tylko gdy transfer ZWIĘKSZA kategorię powyżej limitu
	-- (newCount > cap AND newCount > oldCount). Gracze z legacy nadmiarem (sprzed podziału)
	-- mogą nadal przekładać, byle nie powiększać przepełnionej kategorii. Magnesy nie są
	-- transferowane przez bank, więc akcesoriów nie sprawdzamy.
	local caps = Util.getCategoryCaps(cap, Config.BackpackCategorySplit)
	local newBottles = Util.getBottleCount(simulated)
	if newBottles > caps.bottles and newBottles > Util.getBottleCount(pData) then
		return false, "overCapacity"
	end
	local newPets = #eqPetIds
	if newPets > caps.pets and newPets > #(pData.Pets or {}) then
		return false, "overCapacity"
	end

	-- Bank capacity: butelki + pety razem
	local bankCap = getBankCapacity(pData)
	local bankTotal = #bankPetIds
	for _, r in ipairs(RARITIES) do
		bankTotal += math.floor(math.max(0, tonumber(rawBk[r] or 0) or 0))
	end
	if bankTotal > bankCap then
		return false, "bankFull"
	end

	-- Zastosuj butelki
	for _, r in ipairs(RARITIES) do
		pData.BackpackContents[r] = math.floor(math.max(0, tonumber(rawBp[r] or 0) or 0))
		bData[r] = math.floor(math.max(0, tonumber(rawBk[r] or 0) or 0))
	end
	-- Zastosuj pety — rebuild list z nowych zbiorów, wykorzystując oldUuids dla rarity/class
	local newPets, newBankPets = {}, {}
	for _, id in ipairs(eqPetIds) do
		table.insert(newPets, oldUuids[id])
	end
	for _, id in ipairs(bankPetIds) do
		table.insert(newBankPets, oldUuids[id])
	end
	pData.Pets = newPets
	pData.BankPets = newBankPets

	-- Jeśli któryś z wyposażonych petów trafił do banku — unequip go z listy.
	pData.EquippedPets = pData.EquippedPets or {}
	for i = #pData.EquippedPets, 1, -1 do
		if not newEqSet[pData.EquippedPets[i]] then
			table.remove(pData.EquippedPets, i)
		end
	end
	pData.EquippedPet = pData.EquippedPets[1] or ""

	-- Save w tle — task.spawn nie blokuje BankResult (gracz widzi natychmiast wynik),
	-- ale stan jest persystowany od razu (nie czekamy 60s do auto-save). Coalescing
	-- w obu SaveData/saveBank chroni przed spamem SetAsync gdy gracz robi szybkie transfery.
	task.spawn(PlayerDataService.SaveData, player) -- BackpackContents + EquippedPets + Pets
	task.spawn(saveBank, player) -- BankContents + BankPets

	UpdateHUD:FireClient(player, {
		backpackContents = deepCopy(pData.BackpackContents),
		backpackCapacity = cap,
		hasSyrup = hasSyrup,
	})

	-- Push pet status + sync visual (pet ↔ bank zmienia equipped możliwie)
	pcall(function()
		local PetService = require(script.Parent.PetService)
		PetService.PushStatus(player)
		PetService.ApplyPetEffects(player)
		if PetService.SyncVisual then
			PetService.SyncVisual(player)
		end
	end)

	return true, deepCopy(bData), deepCopy(pData.BackpackContents), cap, deepCopy(pData.Pets), deepCopy(pData.BankPets)
end

local function fireTransferResult(player: Player, ok: boolean, a, b, c, eqPets, bankPets)
	if ok then
		local pData = PlayerDataService.GetData(player)
		BankResult:FireClient(player, {
			success = true,
			bankContents = a,
			backpackContents = b,
			backpackCapacity = c,
			bankCapacity = getBankCapacity(pData),
			eqPets = eqPets,
			bankPets = bankPets,
		})
	else
		BankResult:FireClient(player, { success = false, reason = a })
	end
end

local function guardBankRequest(player: Player, throttleTable, throttleSec: number, denyReason: string): boolean
	local now = os.clock()
	if throttleTable[player] and now - throttleTable[player] < throttleSec then
		-- WAŻNE: zawsze FireClient żeby klient mógł zresetować "ZAPISYWANIE..." — bez tego
		-- przy szybkim double-click POTWIERDŹ drugi request był cicho ignorowany i klient utykał.
		BankResult:FireClient(player, { success = false, reason = "throttled" })
		return false
	end
	throttleTable[player] = now
	if not isNearBank(player) then
		BankResult:FireClient(player, { success = false, reason = denyReason })
		return false
	end
	return true
end

BankDeposit.OnServerEvent:Connect(function(player: Player, payload)
	if type(payload) ~= "table" then
		return
	end
	if not guardBankRequest(player, lastTransferAt, TRANSFER_THROTTLE, "tooFar") then
		return
	end
	fireTransferResult(
		player,
		handleTransfer(
			player,
			payload.newBackpackContents,
			payload.newBankContents,
			payload.newEqPetIds,
			payload.newBankPetIds
		)
	)
end)

BankWithdraw.OnServerEvent:Connect(function(player: Player, payload)
	if type(payload) ~= "table" then
		return
	end
	if not guardBankRequest(player, lastTransferAt, TRANSFER_THROTTLE, "tooFar") then
		return
	end
	fireTransferResult(
		player,
		handleTransfer(
			player,
			payload.newBackpackContents,
			payload.newBankContents,
			payload.newEqPetIds,
			payload.newBankPetIds
		)
	)
end)

-- ── Ulepszanie pojemności skarbca ─────────────────────────────────────────────
UpgradeBank.OnServerEvent:Connect(function(player: Player)
	if not guardBankRequest(player, lastUpgradeAt, UPGRADE_THROTTLE, "tooFar") then
		return
	end
	local pData = PlayerDataService.GetData(player)
	if (pData.BaseLevel or 0) < 1 then
		BankResult:FireClient(player, { success = false, reason = "locked" })
		return
	end
	local cost = nextUpgradeCost(pData)
	if (pData.Zlotowki or 0) < cost then
		BankResult:FireClient(player, { success = false, reason = "broke" })
		return
	end
	pData.Zlotowki = (pData.Zlotowki or 0) - cost
	pData.BankCapLevel = (pData.BankCapLevel or 0) + 1
	PlayerDataService.UpdateLeaderstats(player)
	-- Permanent purchase — immediate save (BankCapLevel mieszka w PlayerData).
	-- Coalescing w SaveData chroni przed spamem SetAsync, więc OK woła się tu mimo yieldu.
	PlayerDataService.SaveData(player)

	-- Story quest hook: ulepszenie skarbca
	pcall(function()
		require(script.Parent.StoryQuestService).AddProgress(player, "upgrade_bank", 1)
	end)

	local bData = loadBank(player)
	BankResult:FireClient(player, {
		success = true,
		bankContents = deepCopy(bData),
		backpackContents = deepCopy(pData.BackpackContents),
		backpackCapacity = Config.BackpackUpgrades[pData.BackpackLevel].Capacity,
		bankCapacity = getBankCapacity(pData),
		bankUpgradeLevel = pData.BankCapLevel,
		bankUpgradeCost = nextUpgradeCost(pData),
		upgraded = true,
	})
end)

-- Auto-save co 60s (równolegle per gracz — analogicznie do PlayerDataService)
task.spawn(function()
	while true do
		task.wait(60)
		for p in pairs(cache) do
			task.spawn(saveBank, p)
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	saveBank(p)
	cache[p] = nil
	saveState[p] = nil
	lastTransferAt[p] = nil
	lastUpgradeAt[p] = nil
end)
-- BindToClose równolegle (jak PlayerDataService): sekwencyjnie nie zdąży przy 10+ graczach
game:BindToClose(function()
	local pending = 0
	local done = Instance.new("BindableEvent")
	for p in pairs(cache) do
		pending += 1
		task.spawn(function()
			saveBank(p)
			pending -= 1
			if pending == 0 then
				done:Fire()
			end
		end)
	end
	if pending > 0 then
		task.delay(25, function()
			if pending > 0 then
				done:Fire()
			end
		end)
		done.Event:Wait()
	end
end)

local BankService = {}

-- Wywoływane przez PlayerDataService.ResetProgress — czyści osobny DataStore BankData_v1
-- (PlayerData_v7 reset go nie obejmuje). Bez tego po resecie postępu butelki w skarbcu
-- zostawały na starym koncie.
function BankService.ResetFor(player: Player)
	cache[player] = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
	BankService.ResetByUserId(player.UserId)
end

-- Wariant nie wymagający obiektu Player — używany przez AdminService gdy admin
-- chce wyczyścić skarbiec offline'owemu graczowi. Po zalogowaniu loadBank pobierze pustą tabelę.
function BankService.ResetByUserId(userId: number)
	local key = "BankData_v1_" .. tostring(userId)
	local empty = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
	for attempt = 0, #RETRY_DELAYS do
		local ok, err = pcall(function()
			BANK_DS:SetAsync(key, empty)
		end)
		if ok then
			return true
		end
		if attempt < #RETRY_DELAYS then
			task.wait(RETRY_DELAYS[attempt + 1])
		end
		if attempt == #RETRY_DELAYS then
			warn("[BankService] ResetByUserId SetAsync failed:", err)
			return false
		end
	end
	return false
end

return BankService
