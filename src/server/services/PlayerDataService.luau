-- PlayerDataService.luau
local Players         = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config          = require(ReplicatedStorage.Config)
local Util            = require(ReplicatedStorage:WaitForChild("Util"))

local PlayerDataService = {}

local store = DataStoreService:GetDataStore(Config.DataStoreKey)

local DEFAULT_DATA = {
	Zlotowki        = 0,
	TotalEarned     = 0,
	BaseLevel       = 0,   -- 0 = Fundament nie kupiony, 1 = kupiony
	MultiplierLevel = 0,   -- 0 = nic nie kupiono, 1+ = kupiony poziom
	BackpackLevel   = 1,
	SpeedLevel      = 0,   -- 0 = nic nie kupiono, 1+ = kupiony poziom
	LuckLevel       = 0,   -- 0 = brak, 1 = kupiony (odnoga od Mult L2, podwaja szczęście w koszach)
	StaminaLevel    = 0,   -- 0 = brak, 1 = kupiony (odnoga od Speed L2, +50 max stamina)
	TotalBottles    = 0,
	BackpackContents = {
		Zwykla    = 0,
		Rzadka    = 0,
		Epicka    = 0,
		Legendarna = 0,
		Mityczny  = 0,
	},
	Quests = {
		activeIds = {},   -- { questId1, questId2, questId3 }
		progress  = {},   -- [questId] = number
		claimed   = {},   -- [questId] = true
		refreshAt = 0,    -- os.time() do kiedy ważne; po przekroczeniu — refresh
	},
	HasSeenIntro = false,  -- true po obejrzeniu cutsceny przy pierwszym wejściu
	Grandpa = {
		state         = "none",  -- "none" | "active" | "done"
		syrupLocation = 0,       -- 1|2|3 — losowane przy przyjęciu questa
		hasSyrup      = false,   -- true gdy gracz podniesie syrop
	},
	RedeemedCodes = {},  -- [codeKey] = true — kody promocyjne już użyte (jednorazowe per gracz)
	OwnedDecks    = {},     -- [deckKey] = true — posiadane deski (skateboardy)
	OwnedZones    = {},     -- [zoneKey] = true — odblokowane strefy z bramkami (Pustynia, ...)
	EquippedDeck  = "",     -- klucz wyposażonej deski ("" = brak; R jeździ najlepszą posiadaną)
	HatOwned      = false,  -- czapka z HatShop — permanentny zakup, daje +HP +stamina +speed
	BankCapLevel  = 0,      -- liczba kupionych ulepszeń pojemności skarbca (każde +1 cap, koszt rośnie liniowo)
	StoryQuestIndex    = 1, -- numer aktualnego questa fabularnego (1-based). > #Config.StoryQuests = wszystkie zrobione
	StoryQuestProgress = 0, -- postęp w aktualnym quest'cie
	-- Layout slotów ekwipunku — lista stacków { rarity, count } w kolejności wyświetlania.
	-- Pozwala zachować splity (np. Zwykla 5+5) między sesjami. Klient wysyła SyncInventoryLayout przy każdej zmianie.
	-- Walidowane przez serwer: suma per rzadkość MUSI równać się BackpackContents.
	InventoryStacks = {},
	-- Magnes (used-item z ekwipunku). MagnetCount = ile sztuk w plecaku.
	-- Każdy magnes zajmuje 1 slot (NIE stackuje się — 1 slot = 1 sztuka).
	-- Po użyciu count -= 1, serwer aktywuje 2-min sweep.
	MagnetCount        = 0,
	-- Boost'y trzymane jako epoch os.time() — przeżywają restart serwera.
	-- 0 = nieaktywny. Po restarcie jeśli value > os.time(), serwis restartuje timer z remaining.
	MagnetActiveUntil  = 0,    -- magnet sweep timer
	DoubleEarnUntil    = 0,    -- x2 KASA boost (Robux)
	-- Pety: lista posiadanych petów + UUID wyposażonego.
	-- Każdy pet = { id (UUID string), rarity (string), class (string) }.
	-- Zajmuje 1 slot pojemności (tak jak butelka). Equipped daje bonusy (money/speed/HP).
	-- BankPets — pety przechowywane w skarbcu (osobno od EQ, jak butelki w banku).
	Pets               = {},
	EquippedPet        = "",    -- legacy single-pet (zostawione dla migracji starych zapisów)
	EquippedPets       = {},    -- lista UUID wyposażonych petów, max len = MaxEquippedPets
	MaxEquippedPets    = 1,     -- zwiększane przez PetSlotShop (workspace.Poland) — 1→2 za 7000 zł + 10 Mit
	BankPets           = {},
	-- ── Statystyki (panel STATS, zapisywane w DataStore) ──────────────────────
	-- StatsBottles = ile butelek danej rzadkości gracz zebrał łącznie (lifetime).
	-- TotalBottles (wyżej) = suma wszystkich zebranych. StatPvpKills = kille w PVPZone.
	-- StatAccessoriesUsed = ile razy użyto akcesoriów (magnesy itp.).
	StatsBottles = {
		Zwykla     = 0,
		Rzadka     = 0,
		Epicka     = 0,
		Legendarna = 0,
		Mityczny   = 0,
	},
	StatPvpKills        = 0,
	StatAccessoriesUsed = 0,
	StatEggsOpened      = 0,   -- ile jajek z petem gracz otworzył (panel STATS)
}

local deepCopy = Util.deepCopy

local cache: { [Player]: { [string]: any } } = {}

local function mergeWithDefaults(data: { [string]: any }): { [string]: any }
	local merged = deepCopy(DEFAULT_DATA)
	for k, v in pairs(data) do
		if type(v) == "table" and type(merged[k]) == "table" then
			for k2, v2 in pairs(v) do
				merged[k][k2] = v2
			end
		else
			merged[k] = v
		end
	end
	-- Migracja: legacy `EquippedPet` (single string) → `EquippedPets` (list).
	-- Starzy gracze mają tylko EquippedPet — pierwszy load zamieniamy na nową listę.
	if (not merged.EquippedPets or #merged.EquippedPets == 0)
		and type(merged.EquippedPet) == "string" and merged.EquippedPet ~= ""
	then
		merged.EquippedPets = { merged.EquippedPet }
	end
	if type(merged.MaxEquippedPets) ~= "number" or merged.MaxEquippedPets < 1 then
		merged.MaxEquippedPets = 1
	end
	return merged
end

-- Retry z exponential backoff dla GetAsync/SetAsync.
-- DataStore może zwrócić błąd przy throttlu (>60 req/min) lub transientach Roblox —
-- bez retry pierwszy fail oznacza utratę zapisu (przy SaveData) lub załadowanie
-- DEFAULT_DATA na świeżego gracza ze starym progresem (przy GetAsync) i nadpis.
local RETRY_DELAYS = { 0.5, 1.5, 3 }  -- 3 próby łącznie

local function getWithRetry(key: string): (boolean, any)
	local lastErr: any = nil
	for attempt = 0, #RETRY_DELAYS do
		local ok, result = pcall(function() return store:GetAsync(key) end)
		if ok then return true, result end
		lastErr = result
		if attempt < #RETRY_DELAYS then task.wait(RETRY_DELAYS[attempt + 1]) end
	end
	return false, lastErr
end

local function setWithRetry(key: string, data: any): boolean
	local lastErr: any = nil
	for attempt = 0, #RETRY_DELAYS do
		local ok, err = pcall(function() store:SetAsync(key, data) end)
		if ok then return true end
		lastErr = err
		if attempt < #RETRY_DELAYS then task.wait(RETRY_DELAYS[attempt + 1]) end
	end
	warn("[PlayerDataService] SetAsync failed po 3 próbach:", lastErr)
	return false
end

function PlayerDataService.GetData(player: Player): { [string]: any }
	if cache[player] then
		return cache[player]
	end

	local key = Config.DataStoreKey .. "_" .. player.UserId
	local data = {}

	local ok, result = getWithRetry(key)

	if ok and result then
		data = mergeWithDefaults(result)
	else
		if not ok then
			-- KRYTYCZNE: po 3 fail'ach nie ładujemy DEFAULT_DATA, żeby nie zniszczyć stanu gracza.
			-- Oznaczamy cache jako "nieprawidłowy" — SaveData go odrzuci, gracz dostanie kick.
			warn("[PlayerDataService] GetAsync failed po 3 próbach dla", player.Name, ":", result,
				"— gracz zostanie kickowany, żeby nie nadpisać postępu")
			task.spawn(function()
				player:Kick("Błąd ładowania postępu (DataStore). Spróbuj ponownie za chwilę.")
			end)
			data = mergeWithDefaults({})
			data.__loadFailed = true  -- gate w SaveData
		else
			-- ok=true, result=nil → nowy gracz, brak rekordu — OK
			data = mergeWithDefaults({})
		end
	end

	cache[player] = data
	return data
end

-- Koalescencja zapisów per gracz — przy zamykaniu playtesta PlayerRemoving i BindToClose
-- odpalają SaveData dla tego samego klucza niemal jednocześnie. Dwa SetAsync na ten sam
-- klucz = "DataStore request was added to queue". Drugie wywołanie czeka na trwający zapis
-- zamiast dublować request.
local saveInFlight: { [Player]: BindableEvent } = {}

function PlayerDataService.SaveData(player: Player)
	local data = cache[player]
	if not data then return end
	if data.__loadFailed then return end  -- nie nadpisuj stanu gdy load się nie udał

	local inflight = saveInFlight[player]
	if inflight then
		-- Zapis tego gracza już trwa — poczekaj na jego koniec, nie odpalaj drugiego SetAsync.
		inflight.Event:Wait()
		return
	end

	local ev = Instance.new("BindableEvent")
	saveInFlight[player] = ev
	local key = Config.DataStoreKey .. "_" .. player.UserId
	setWithRetry(key, data)
	saveInFlight[player] = nil
	ev:Fire()
end

-- Auto-save co 60 sekund (równolegle per gracz — sekwencyjny zapycha kolejkę DataStore
-- przy >10 graczach, każdy SetAsync yielduje 1-2s).
task.spawn(function()
	while true do
		task.wait(60)
		for player, _ in pairs(cache) do
			task.spawn(PlayerDataService.SaveData, player)
		end
	end
end)

-- Tworzy leaderstats dla gracza (Roblox auto-replikuje je do klientów)
local function createLeaderstats(player: Player)
	local data = PlayerDataService.GetData(player)
	local ls = Instance.new("Folder")
	ls.Name   = "leaderstats"
	ls.Parent = player

	-- NumberValue — wspiera grosze (np. 10.50)
	local zl = Instance.new("NumberValue")
	zl.Name   = "Zlotowki"
	zl.Value  = math.floor(data.Zlotowki * 100) / 100  -- zaokrąglone do 2 miejsc
	zl.Parent = ls

	-- TotalEarned do leaderboardu — integer wystarczy (ranking sortuje po int)
	local te = Instance.new("IntValue")
	te.Name   = "Zarobki"
	te.Value  = math.floor(data.TotalEarned)
	te.Parent = ls
end

-- Synchronizuje values w leaderstats z aktualnym cache gracza
function PlayerDataService.UpdateLeaderstats(player: Player)
	local data = cache[player]
	if not data then return end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local zl = ls:FindFirstChild("Zlotowki")
	local te = ls:FindFirstChild("Zarobki")
	if zl then zl.Value = math.floor(data.Zlotowki * 100) / 100 end
	if te then te.Value = math.floor(data.TotalEarned) end
end

local function fireInitialHUD(player: Player)
	local data = PlayerDataService.GetData(player)
	local evts = ReplicatedStorage:WaitForChild("Events")
	local updateHUDEvent = evts:WaitForChild("UpdateHUD")
	local skillTreeInit  = evts:WaitForChild("SkillTreeInit")
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(0.3)
	-- Zlotowki pominięte — klient czyta je z leaderstats (auto-replikacja)
	updateHUDEvent:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = Config.BackpackUpgrades[data.BackpackLevel].Capacity,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
		inventoryStacks  = data.InventoryStacks,
	})
	skillTreeInit:FireClient(player, {
		speedLevel      = data.SpeedLevel      or 0,
		multiplierLevel = data.MultiplierLevel or 0,
		baseLevel       = data.BaseLevel       or 0,
		luckLevel       = data.LuckLevel       or 0,
		staminaLevel    = data.StaminaLevel    or 0,
	})
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		PlayerDataService.GetData(player)  -- wczytaj dane (blokuje wątek do czasu odpowiedzi DS)
		createLeaderstats(player)          -- teraz cache jest gotowy → poprawne wartości
		fireInitialHUD(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerDataService.SaveData(player)
	cache[player] = nil
end)

-- Klient wysyła layout slotów po każdej zmianie (split/swap/itp.)
-- Walidacja: suma per rzadkość MUSI równać się BackpackContents (anti-cheat).
do
	local evts = ReplicatedStorage:WaitForChild("Events")
	local SyncInventoryLayout = evts:WaitForChild("SyncInventoryLayout")
	local VALID_RARITIES = { Zwykla = true, Rzadka = true, Epicka = true, Legendarna = true, Mityczny = true }

	SyncInventoryLayout.OnServerEvent:Connect(function(player: Player, rawLayout: any)
		if type(rawLayout) ~= "table" then return end
		local data = PlayerDataService.GetData(player)
		if not data.BackpackContents then return end

		-- Format: { [slotIdxString] = { rarity, count } }
		-- Suma per rzadkość + walidacja każdej pozycji
		local totals = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
		local cleaned = {}
		for k, s in pairs(rawLayout) do
			local slotIdx = tonumber(k)
			if type(s) ~= "table" or not slotIdx then return end
			if slotIdx < 1 or slotIdx > 50 or slotIdx ~= math.floor(slotIdx) then return end
			local r = s.rarity
			local c = tonumber(s.count)
			if type(r) ~= "string" or not VALID_RARITIES[r] then return end
			if not c or c <= 0 or c ~= math.floor(c) then return end
			totals[r] += c
			cleaned[tostring(slotIdx)] = { rarity = r, count = c }
		end

		-- Sprawdź czy suma per rzadkość matches BackpackContents
		for r in pairs(VALID_RARITIES) do
			if totals[r] ~= (data.BackpackContents[r] or 0) then
				return  -- mismatch — ignoruj
			end
		end

		data.InventoryStacks = cleaned
	end)
end

-- Reset progresu — gracz prosi z Settings. Czyścimy cache + DataStore, teleportujemy z powrotem żeby wszystko świeżo wczytało.
do
	local TeleportService = game:GetService("TeleportService")
	local RunService      = game:GetService("RunService")
	local evts = ReplicatedStorage:WaitForChild("Events")
	local ResetProgress = evts:WaitForChild("ResetProgress")
	local lastResetAt: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(p) lastResetAt[p] = nil end)
	ResetProgress.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastResetAt[player] and now - lastResetAt[player] < 5 then return end
		lastResetAt[player] = now
		cache[player] = deepCopy(DEFAULT_DATA)
		PlayerDataService.SaveData(player)
		-- Bank ma osobny DataStore (BankData_v1) — wyczyść też tam, inaczej skarbiec
		-- przeżywa reset postępu.
		local okB, BankService = pcall(function()
			return require(script.Parent.BankService)
		end)
		if okB and BankService and BankService.ResetFor then
			pcall(function() BankService.ResetFor(player) end)
		end
		-- Despawn syropu jeśli był w świecie
		local ok, SyrupService = pcall(function()
			return require(script.Parent.SyrupService)
		end)
		if ok and SyrupService then
			pcall(function() SyrupService.DespawnFor(player) end)
		end
		task.delay(0.3, function()
			if not (player and player.Parent) then return end
			if RunService:IsStudio() then
				-- TeleportService nie działa w Studio — kickujemy z czytelnym komunikatem
				player:Kick("[Studio] Postęp zresetowany. Uruchom playtest ponownie.")
				return
			end
			local ok, err = pcall(function()
				TeleportService:Teleport(game.PlaceId, player)
			end)
			if not ok then
				warn("[PlayerDataService] Teleport failed:", err)
				player:Kick("Postęp zresetowany. Dołącz ponownie do gry.")
			end
		end)
	end)
end

-- BindToClose: zapisz wszystkich równolegle (limit ~30s w Roblox, sekwencyjnie nie zdąży
-- gdy serwer ma 10+ graczy a SetAsync yielduje 1-2s każdy).
game:BindToClose(function()
	local pending = 0
	local done = Instance.new("BindableEvent")
	for player, _ in pairs(cache) do
		pending += 1
		task.spawn(function()
			PlayerDataService.SaveData(player)
			pending -= 1
			if pending == 0 then done:Fire() end
		end)
	end
	if pending > 0 then
		-- Czekaj na koniec wszystkich SaveData (lub timeout 25s żeby zostawić bufor BindToClose)
		task.delay(25, function() if pending > 0 then done:Fire() end end)
		done.Event:Wait()
	end
end)

return PlayerDataService
