-- StatsService.luau
-- Panel STATS — odpowiada na StatsRequest snapshotem statystyk gracza.
-- Wszystkie liczby pochodzą z DataStore (PlayerData): TotalBottles, StatsBottles[rarity],
-- StatPvpKills, StatAccessoriesUsed, Zlotowki + wyliczony "najlepszy pet".
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local Events       = ReplicatedStorage:WaitForChild("Events")
local StatsRequest = Events:WaitForChild("StatsRequest")
local StatsData    = Events:WaitForChild("StatsData")

local StatsService = {}

-- Anty-spam: 1 request / 0.5s
local lastReq: { [Player]: number } = {}

-- Najlepszy pet: najwyższa rzadkość (Config.Pets.Rarities[r].order), remis → gold > zwykły.
-- Szukamy w EQ (data.Pets) i skarbcu (data.BankPets).
local function bestPet(data): string
	local petCfg = Config.Pets and Config.Pets.Rarities
	local best, bestScore = nil, -1
	local function consider(p)
		if not (p and p.rarity) then return end
		local order = (petCfg and petCfg[p.rarity] and petCfg[p.rarity].order) or 0
		-- gold dolicza +0.5 żeby wygrywał remisy tej samej rzadkości
		local score = order * 2 + (p.gold and 1 or 0)
		if score > bestScore then bestScore = score; best = p end
	end
	for _, p in ipairs(data.Pets or {}) do consider(p) end
	for _, p in ipairs(data.BankPets or {}) do consider(p) end
	if not best then return "Brak" end
	local rname = (petCfg and petCfg[best.rarity] and petCfg[best.rarity].displayName) or best.rarity
	return string.format("%s%s %s", best.gold and "Złoty " or "", rname, best.class or "")
end

local function buildSnapshot(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then return nil end
	local sb = data.StatsBottles or {}
	return {
		nick        = player.DisplayName ~= "" and player.DisplayName or player.Name,
		userId      = player.UserId,
		pln         = data.Zlotowki or 0,
		totalBottles = data.TotalBottles or 0,
		bottles = {
			Zwykla     = sb.Zwykla or 0,
			Rzadka     = sb.Rzadka or 0,
			Epicka     = sb.Epicka or 0,
			Legendarna = sb.Legendarna or 0,
			Mityczny   = sb.Mityczny or 0,
		},
		pvpKills        = data.StatPvpKills or 0,
		bestPet         = bestPet(data),
		accessoriesUsed = data.StatAccessoriesUsed or 0,
	}
end

StatsRequest.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if (lastReq[player] or 0) + 0.5 > now then return end
	lastReq[player] = now
	local snap = buildSnapshot(player)
	if snap then StatsData:FireClient(player, snap) end
end)

Players.PlayerRemoving:Connect(function(p) lastReq[p] = nil end)

print("[StatsService] gotowy")
return StatsService
