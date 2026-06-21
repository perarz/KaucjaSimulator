-- StoryQuestService.luau
-- Linia fabularna: chain questów (Config.StoryQuests) wykonywanych po kolei.
-- Hooki AddProgress wywoływane z BottleService/UpgradeService/ShopService/GrandpaService.
-- Stan w PlayerData: StoryQuestIndex (1-based), StoryQuestProgress.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local Events             = ReplicatedStorage:WaitForChild("Events")
local StoryQuestInit     = Events:WaitForChild("StoryQuestInit")
local StoryQuestUpdate   = Events:WaitForChild("StoryQuestUpdate")
local StoryQuestComplete = Events:WaitForChild("StoryQuestComplete")
local StoryQuestClaim    = Events:WaitForChild("StoryQuestClaim")

local QUESTS = Config.StoryQuests or {}

local StoryQuestService = {}

local function currentQuest(data): any?
	local idx = data.StoryQuestIndex or 1
	if idx < 1 or idx > #QUESTS then return nil end
	return QUESTS[idx]
end

local function snapshot(data): { [string]: any }
	local q = currentQuest(data)
	if not q then
		return { idx = data.StoryQuestIndex or 1, done = true, total = #QUESTS }
	end
	local prog = math.min(data.StoryQuestProgress or 0, q.target)
	return {
		idx       = data.StoryQuestIndex,
		total     = #QUESTS,
		id        = q.id,
		desc      = q.desc,
		target    = q.target,
		progress  = prog,
		reward    = q.reward,
		done      = false,
		readyToClaim = (prog >= q.target),  -- gotowy do odbioru — klient pokazuje ODBIERZ
	}
end

-- Sprawdza czy gracz już SPEŁNIA warunki questa swoim aktualnym stanem
-- (np. ma najlepszy plecak / dostatecznie kupił skille). Jeśli tak, zwraca progres == target.
-- Wywoływane przy fireInit dla świeżego questa (progress == 0).
local function preFillProgress(data, q): number
	if q.kind == "buy_backpack" then
		-- Jeśli gracz ma już cokolwiek lepsze niż starter (BackpackLevel >= 2) → zalicz
		if (data.BackpackLevel or 1) >= 2 then return q.target end
	elseif q.kind == "buy_skill" then
		-- Suma kupionych skilli (BaseLevel + Speed + Mult + Luck)
		local total = (data.BaseLevel or 0)
		            + (data.SpeedLevel or 0)
		            + (data.MultiplierLevel or 0)
		            + (data.LuckLevel or 0)
		return math.min(total, q.target)
	elseif q.kind == "buy_deck" then
		-- Jeśli quest celuje w konkretną deskę (deckKey), sprawdź czy gracz już ją ma.
		-- Bez deckKey — wystarczy jakakolwiek deska.
		if q.deckKey then
			if data.OwnedDecks and data.OwnedDecks[q.deckKey] then return q.target end
		else
			if data.OwnedDecks and next(data.OwnedDecks) then return q.target end
		end
	elseif q.kind == "buy_egg" then
		-- Ma już jakiegokolwiek peta → otworzył przynajmniej jedno jajko
		if (data.Pets and #data.Pets > 0) or (data.BankPets and #data.BankPets > 0) then return q.target end
	elseif q.kind == "equip_pet" then
		if data.EquippedPet and data.EquippedPet ~= "" then return q.target end
	elseif q.kind == "upgrade_bank" then
		if (data.BankCapLevel or 0) >= 1 then return q.target end
	elseif q.kind == "pet_rarity" then
		-- Ma już peta tej rzadkości w EQ lub skarbcu
		local function hasRarity(list): boolean
			if not list then return false end
			for _, p in ipairs(list) do if p.rarity == q.petRarity then return true end end
			return false
		end
		if hasRarity(data.Pets) or hasRarity(data.BankPets) then return q.target end
	end
	return 0
end

local function fireInit(player: Player)
	local data = PlayerDataService.GetData(player)
	local q = currentQuest(data)
	-- Pre-fill świeżego questa stanem gracza — jak ma już najlepszy plecak / wybrane skille,
	-- quest startuje od razu jako gotowy do odbioru.
	if q and (data.StoryQuestProgress or 0) == 0 then
		local preFill = preFillProgress(data, q)
		if preFill > 0 then
			data.StoryQuestProgress = preFill
		end
	end
	StoryQuestInit:FireClient(player, snapshot(data))
end

-- Wypłaca nagrodę + przechodzi do następnego questa. Wywoływane przez StoryQuestClaim
-- (gracz klika ODBIERZ). Wcześniej tylko ustawiamy readyToClaim w snapshot.
local function claimAndAdvance(player: Player)
	local data = PlayerDataService.GetData(player)
	local q = currentQuest(data)
	if not q then return false end
	-- Walidacja: progres musi osiągnąć target
	if (data.StoryQuestProgress or 0) < q.target then return false end

	-- Wypłata
	data.Zlotowki = (data.Zlotowki or 0) + (q.reward or 0)
	data.TotalEarned = (data.TotalEarned or 0) + (q.reward or 0)
	PlayerDataService.UpdateLeaderstats(player)

	-- WYKONANO + reward
	StoryQuestComplete:FireClient(player, {
		idx    = data.StoryQuestIndex,
		id     = q.id,
		desc   = q.desc,
		reward = q.reward,
	})

	-- Przejdź do następnego questa
	data.StoryQuestIndex    = (data.StoryQuestIndex or 1) + 1
	data.StoryQuestProgress = 0
	PlayerDataService.SaveData(player)

	-- Klient po 2s pokaże następnego questa (centralny reveal)
	task.delay(2.5, function()
		if player.Parent then fireInit(player) end
	end)
	return true
end

-- ── AddProgress(player, kind, amount?, params?) ───────────────────────────
-- Wywoływane z innych serwisów. params może zawierać dodatkowe pola (np. rarity).
-- Mapowanie kind → matching quest.kind:
--   "collect"         — zbieranie butelek (BottleService/KoszService). params.rarity = string
--   "deposit"         — butelkomat (EmptyBackpack success)
--   "buy_skill"       — kupno węzła w drzewku
--   "buy_backpack"    — kupno plecaka w sklepie
--   "buy_deck"        — kupno deski (DeskaService.grantDeckInternal)
--   "grandpa_done"    — ukończenie questa dziadka
--   "buy_egg"         — kupno/otwarcie jajka (PetService.OpenEgg)
--   "equip_pet"       — założenie peta (PetService EquipPet)
--   "upgrade_bank"    — ulepszenie skarbca (BankService UpgradeBank)
--   "pet_rarity"      — wylosowanie peta danej rzadkości. params.rarity = q.petRarity
function StoryQuestService.AddProgress(player: Player, kind: string, amount: number?, params: any?)
	if not player or not player.Parent then return end
	local data = PlayerDataService.GetData(player)
	local q = currentQuest(data)
	if not q then return end

	local matched = false
	if     q.kind == "collect_any"    and kind == "collect"      then matched = true
	elseif q.kind == "collect_rarity" and kind == "collect" and params and params.rarity == q.rarity then matched = true
	elseif q.kind == "deposit"        and kind == "deposit"      then matched = true
	elseif q.kind == "buy_skill"      and kind == "buy_skill"    then matched = true
	elseif q.kind == "buy_backpack"   and kind == "buy_backpack" then matched = true
	elseif q.kind == "buy_deck"       and kind == "buy_deck"     then
		-- Quest może targetować konkretną deskę (deckKey) lub dowolną
		if q.deckKey then
			if params and params.deckKey == q.deckKey then matched = true end
		else
			matched = true
		end
	elseif q.kind == "grandpa_done"   and kind == "grandpa_done" then matched = true
	elseif q.kind == "buy_egg"        and kind == "buy_egg"      then matched = true
	elseif q.kind == "equip_pet"      and kind == "equip_pet"    then matched = true
	elseif q.kind == "upgrade_bank"   and kind == "upgrade_bank" then matched = true
	elseif q.kind == "pet_rarity"     and kind == "pet_rarity" and params and params.rarity == q.petRarity then matched = true
	end
	if not matched then return end

	data.StoryQuestProgress = (data.StoryQuestProgress or 0) + (amount or 1)
	if data.StoryQuestProgress > q.target then
		data.StoryQuestProgress = q.target
	end
	-- Cap'ujemy ale NIE wypłacamy automatycznie. Gracz musi kliknąć ODBIERZ → StoryQuestClaim.
	-- BEZ SaveData tutaj — SetAsync yielduje (1-2s) i blokowałby CollectBottle response (SFX/VFX delay).
	-- Persystencja: auto-save co 60s + PlayerRemoving + BindToClose. Akceptowalne ryzyko utraty <60s postępu.
	StoryQuestUpdate:FireClient(player, snapshot(data))
end

-- ── StoryQuestClaim (gracz klika ODBIERZ) ─────────────────────────────────
StoryQuestClaim.OnServerEvent:Connect(function(player: Player)
	if not player or not player.Parent then return end
	claimAndAdvance(player)
end)

-- ── PlayerAdded sync ──────────────────────────────────────────────────────
local function onPlayer(p: Player)
	-- Daj kilka sekund na PlayerDataService load
	task.wait(2)
	if not p.Parent then return end
	fireInit(p)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end

print("[StoryQuestService] Gotowy — " .. #QUESTS .. " questów w linii fabularnej")

return StoryQuestService
