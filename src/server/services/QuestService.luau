-- QuestService.luau
-- Codzienne/cykliczne questy: 3 aktywne losowane z puli, refresh co X godzin.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage.Config)
local PlayerDataService = require(ServerScriptService.PlayerDataService)

local Events            = ReplicatedStorage:WaitForChild("Events")
local QuestInit         = Events:WaitForChild("QuestInit")
local QuestUpdate       = Events:WaitForChild("QuestUpdate")
local ClaimQuest        = Events:WaitForChild("ClaimQuest")
local ClaimQuestResult  = Events:WaitForChild("ClaimQuestResult")

local QuestService = {}

-- ── Helpery ───────────────────────────────────────────────────────────────

local function findQuestById(id: string)
	for _, q in ipairs(Config.Quests) do
		if q.id == id then return q end
	end
	return nil
end

local function shuffle(t: { any })
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

-- Snapshot do wysłania do klienta — pełen stan questów
local function snapshotFor(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data.Quests then return nil end
	return {
		activeIds = data.Quests.activeIds,
		progress  = data.Quests.progress,
		claimed   = data.Quests.claimed,
		refreshAt = data.Quests.refreshAt,
	}
end

-- ── Refresh aktywnego setu ───────────────────────────────────────────────

function QuestService.RefreshQuests(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then return end
	data.Quests = data.Quests or {}

	-- Skopiuj pulę i potasuj
	local pool = {}
	for _, q in ipairs(Config.Quests) do table.insert(pool, q.id) end
	shuffle(pool)

	local active = {}
	for i = 1, math.min(Config.QuestActiveCount, #pool) do
		table.insert(active, pool[i])
	end

	data.Quests.activeIds = active
	data.Quests.progress  = {}
	data.Quests.claimed   = {}
	data.Quests.refreshAt = os.time() + Config.QuestRefreshHours * 3600
end

-- Sprawdza czy quest set wymaga refreshu (czas upłynął lub brak setu) i robi go
local function ensureFreshSet(player: Player): boolean
	local data = PlayerDataService.GetData(player)
	if not data then return false end
	data.Quests = data.Quests or {}
	if not data.Quests.activeIds or #data.Quests.activeIds == 0
		or (data.Quests.refreshAt or 0) <= os.time() then
		QuestService.RefreshQuests(player)
		return true
	end
	return false
end

-- ── Increment progresu ──────────────────────────────────────────────────

-- Dopasowuje quest do akcji.
-- type:
--   "collect"       (rarity, amount)
--   "collect_any"   (amount)
--   "earn"          (amount)
--   "search_kosz"   (amount=1)
--   "empty_backpack"(amount=1)
--   "buy_skill"     (amount=1)
local function questMatches(quest: any, actionType: string, params: any): boolean
	if quest.kind == actionType then
		-- collect wymaga zgodnej rzadkości
		if actionType == "collect" then
			return quest.rarity == params.rarity
		end
		return true
	end
	-- collect_any łapie każde "collect"
	if quest.kind == "collect_any" and actionType == "collect" then
		return true
	end
	return false
end

function QuestService.AddProgress(player: Player, actionType: string, params: any?)
	params = params or {}
	local data = PlayerDataService.GetData(player)
	if not data or not data.Quests or not data.Quests.activeIds then return end

	-- Przed jakąkolwiek aktualizacją: sprawdź czy nie minął refresh time
	if ensureFreshSet(player) then
		QuestInit:FireClient(player, snapshotFor(player))
		return  -- po refreshu progress jest 0; ta akcja przepadnie
	end

	local inc = (params :: any).amount or 1
	local changed = {}

	for _, qid in ipairs(data.Quests.activeIds) do
		if data.Quests.claimed[qid] then continue end
		local quest = findQuestById(qid)
		if not quest then continue end
		if questMatches(quest, actionType, params) then
			local cur = data.Quests.progress[qid] or 0
			local newVal = math.min(cur + inc, quest.target)
			if newVal ~= cur then
				data.Quests.progress[qid] = newVal
				changed[qid] = newVal
			end
		end
	end

	-- Wyślij update do klienta tylko jeśli coś się zmieniło
	if next(changed) then
		QuestUpdate:FireClient(player, { progress = data.Quests.progress })
	end
end

-- ── Claim ────────────────────────────────────────────────────────────────

local function tryClaim(player: Player, questId: string)
	local data = PlayerDataService.GetData(player)
	if not data or not data.Quests or not data.Quests.activeIds then
		ClaimQuestResult:FireClient(player, { success = false, reason = "noset" })
		return
	end

	-- Refresh jeśli minął czas
	if ensureFreshSet(player) then
		QuestInit:FireClient(player, snapshotFor(player))
		ClaimQuestResult:FireClient(player, { success = false, reason = "refreshed" })
		return
	end

	if not table.find(data.Quests.activeIds, questId) then
		ClaimQuestResult:FireClient(player, { success = false, reason = "notactive" })
		return
	end
	if data.Quests.claimed[questId] then
		ClaimQuestResult:FireClient(player, { success = false, reason = "already" })
		return
	end

	local quest = findQuestById(questId)
	if not quest then
		ClaimQuestResult:FireClient(player, { success = false, reason = "bad" })
		return
	end

	local cur = data.Quests.progress[questId] or 0
	if cur < quest.target then
		ClaimQuestResult:FireClient(player, { success = false, reason = "incomplete" })
		return
	end

	-- Nagroda
	local r = quest.reward
	if r.kind == "zl" then
		data.Zlotowki    += r.amount
		data.TotalEarned += r.amount
		PlayerDataService.UpdateLeaderstats(player)
	end

	data.Quests.claimed[questId] = true

	ClaimQuestResult:FireClient(player, {
		success = true,
		questId = questId,
		reward  = r,
	})
end

ClaimQuest.OnServerEvent:Connect(tryClaim)

-- ── Init przy dołączeniu gracza ──────────────────────────────────────────

local function initPlayer(player: Player)
	-- Czekamy aż PlayerDataService załaduje
	task.wait(1)
	if not player.Parent then return end
	ensureFreshSet(player)
	local snap = snapshotFor(player)
	if snap then
		QuestInit:FireClient(player, snap)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(initPlayer, player)
end)

-- Już obecni gracze (przy reloadzie skryptu w Studio)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayer, p)
end

return QuestService
