-- PlayerDataService.luau
local Players         = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config          = require(ReplicatedStorage.Config)

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
	HatOwned      = false,  -- czapka z HatShop — permanentny zakup, daje +HP +stamina +speed
	-- Layout slotów ekwipunku — lista stacków { rarity, count } w kolejności wyświetlania.
	-- Pozwala zachować splity (np. Zwykla 5+5) między sesjami. Klient wysyła SyncInventoryLayout przy każdej zmianie.
	-- Walidowane przez serwer: suma per rzadkość MUSI równać się BackpackContents.
	InventoryStacks = {},
}

local function deepCopy(t: { [string]: any }): { [string]: any }
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return copy
end

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
	return merged
end

function PlayerDataService.GetData(player: Player): { [string]: any }
	if cache[player] then
		return cache[player]
	end

	local key = Config.DataStoreKey .. "_" .. player.UserId
	local data = {}

	local ok, result = pcall(function()
		return store:GetAsync(key)
	end)

	if ok and result then
		data = mergeWithDefaults(result)
	else
		if not ok then
			warn("[PlayerDataService] GetAsync failed for", player.Name, ":", result)
		end
		data = mergeWithDefaults({})
	end

	cache[player] = data
	return data
end

function PlayerDataService.SaveData(player: Player)
	local data = cache[player]
	if not data then return end

	local key = Config.DataStoreKey .. "_" .. player.UserId
	local ok, err = pcall(function()
		store:SetAsync(key, data)
	end)

	if not ok then
		warn("[PlayerDataService] SetAsync failed for", player.Name, ":", err)
	end
end

-- Auto-save co 60 sekund
task.spawn(function()
	while true do
		task.wait(60)
		for player, _ in pairs(cache) do
			PlayerDataService.SaveData(player)
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
	ResetProgress.OnServerEvent:Connect(function(player)
		cache[player] = deepCopy(DEFAULT_DATA)
		PlayerDataService.SaveData(player)
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

game:BindToClose(function()
	for player, _ in pairs(cache) do
		PlayerDataService.SaveData(player)
	end
end)

return PlayerDataService
