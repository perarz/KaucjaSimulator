-- AdminService.luau
-- Prosty panel admina: walidacja, broadcast tekstu na ekran wszystkim graczom, kasa/butelki dla siebie.
-- Lista adminów w Config.Admins (nazwy lub UserIds).
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MessagingService  = game:GetService("MessagingService")
local DataStoreService  = game:GetService("DataStoreService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local Events         = ReplicatedStorage:WaitForChild("Events")
local AdminInit      = Events:WaitForChild("AdminInit")
local AdminAction    = Events:WaitForChild("AdminAction")
local AdminBroadcast = Events:WaitForChild("AdminBroadcast")
local UpdateHUD      = Events:WaitForChild("UpdateHUD")

-- ── Cross-server (globalne akcje admina) ────────────────────────────────────
-- Broadcast i dodanie kodu działają na WSZYSTKICH serwerach, nie tylko na tym
-- gdzie admin kliknął. Live propagacja przez MessagingService; kody dodatkowo
-- utrwalane w DataStore żeby serwery startujące PÓŹNIEJ też je miały.
-- Lokalnie stosujemy od razu (instant feedback + działa w Studio), a echo z
-- własnego serwera ignorujemy po game.JobId żeby nie zdublować.
local TOPIC_BROADCAST = "AdminBroadcast"
local TOPIC_ADDCODE   = "AdminAddCode"
local codesStore      = DataStoreService:GetDataStore("AdminCodes_v1")
local CODES_KEY       = "ALL"

local function applyBroadcast(msg: string, from: string)
	AdminBroadcast:FireAllClients({ message = msg, from = from })
end

local function applyCode(code: string, reward: number)
	Config.Codes = Config.Codes or {}
	Config.Codes[code] = { reward = reward }
end

-- Subskrypcja eventów z innych serwerów (pomijamy własne echo po JobId)
task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC_BROADCAST, function(packet)
			local d = packet.Data
			if type(d) ~= "table" or d.serverId == game.JobId then return end
			if type(d.message) == "string" then
				applyBroadcast(d.message, tostring(d.from or "Admin"))
			end
		end)
	end)
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC_ADDCODE, function(packet)
			local d = packet.Data
			if type(d) ~= "table" or d.serverId == game.JobId then return end
			if type(d.code) == "string" and tonumber(d.reward) then
				applyCode(d.code, tonumber(d.reward) :: number)
			end
		end)
	end)
end)

-- Załaduj globalne kody utrwalone wcześniej (żeby ten świeży serwer też je miał)
task.spawn(function()
	local ok, stored = pcall(function() return codesStore:GetAsync(CODES_KEY) end)
	if ok and type(stored) == "table" then
		local n = 0
		for code, reward in pairs(stored) do
			if type(code) == "string" and type(reward) == "number" then
				applyCode(code, reward); n += 1
			end
		end
		if n > 0 then print(string.format("[AdminService] Załadowano %d globalnych kodów", n)) end
	end
end)

local function isAdmin(player: Player): boolean
	local list = Config.Admins or {}
	for _, entry in ipairs(list) do
		if type(entry) == "string" and entry == player.Name then return true end
		if type(entry) == "number" and entry == player.UserId then return true end
	end
	return false
end

-- Sync isAdmin do klienta na join (klient użyje tego do enable F2)
Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	AdminInit:FireClient(player, { isAdmin = isAdmin(player) })
end)

-- Anti-spam: 1 akcja na 0.3s
local lastAction: { [Player]: number } = {}
AdminAction.OnServerEvent:Connect(function(player: Player, payload)
	if not isAdmin(player) then return end
	if type(payload) ~= "table" then return end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.3 then return end
	lastAction[player] = now

	local action = payload.action
	if action == "broadcast" then
		local msg = tostring(payload.message or "")
		if #msg == 0 or #msg > 200 then return end
		-- Lokalnie od razu + rozgłoś na pozostałe serwery (live)
		applyBroadcast(msg, player.Name)
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(TOPIC_BROADCAST, {
					message = msg, from = player.Name, serverId = game.JobId,
				})
			end)
		end)
		print(string.format("[AdminService] %s broadcast (global): %s", player.Name, msg))

	elseif action == "giveZl" then
		local amount = tonumber(payload.amount) or 0
		if amount <= 0 or amount > 1000000 then return end
		local data = PlayerDataService.GetData(player)
		data.Zlotowki = (data.Zlotowki or 0) + amount
		PlayerDataService.UpdateLeaderstats(player)
		print(string.format("[AdminService] %s otrzymał %d zł", player.Name, amount))

	elseif action == "giveBottles" then
		local rarity = tostring(payload.rarity or "")
		local count  = tonumber(payload.count) or 0
		if count <= 0 or count > 1000 then return end
		if not Config.BottleValues[rarity] then return end
		local data = PlayerDataService.GetData(player)
		data.BackpackContents = data.BackpackContents or {}
		data.BackpackContents[rarity] = (data.BackpackContents[rarity] or 0) + count
		local cap = Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity
		UpdateHUD:FireClient(player, {
			backpackContents = data.BackpackContents,
			backpackCapacity = cap,
			hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
		})
		print(string.format("[AdminService] %s otrzymał %d × %s", player.Name, count, rarity))

	elseif action == "giveMagnet" then
		local count = tonumber(payload.count) or 0
		if count <= 0 or count > 100 then return end
		local ok, MagnetService = pcall(function() return require(script.Parent.MagnetService) end)
		if ok and MagnetService then
			MagnetService.Grant(player, count)
			print(string.format("[AdminService] %s otrzymał %d × magnes", player.Name, count))
		end

	elseif action == "kick" then
		local target = Players:FindFirstChild(tostring(payload.target or ""))
		if target then target:Kick("[Admin] " .. tostring(payload.reason or "Kick")) end

	elseif action == "addCode" then
		-- Dodaje globalny kod promocyjny. CodeService czyta Config.Codes server-side,
		-- więc mutacja tu działa lokalnie. Dodatkowo: utrwalamy w DataStore (serwery
		-- startujące później) + rozgłaszamy przez MessagingService (live serwery).
		local code = string.upper(string.gsub(tostring(payload.code or ""), "%s", ""))
		local reward = tonumber(payload.reward) or 0
		if #code == 0 or #code > 32 then return end
		if reward <= 0 or reward > 1000000 then return end
		applyCode(code, reward)  -- lokalnie od razu
		task.spawn(function()
			-- Utrwalenie (atomowy merge) — żeby świeże serwery też miały kod
			pcall(function()
				codesStore:UpdateAsync(CODES_KEY, function(old)
					old = (type(old) == "table") and old or {}
					old[code] = reward
					return old
				end)
			end)
			-- Live propagacja do innych serwerów
			pcall(function()
				MessagingService:PublishAsync(TOPIC_ADDCODE, {
					code = code, reward = reward, serverId = game.JobId,
				})
			end)
		end)
		print(string.format("[AdminService] %s dodał kod (global) %s = %d zł", player.Name, code, reward))
	end
end)

Players.PlayerRemoving:Connect(function(p) lastAction[p] = nil end)

print("[AdminService] gotowy. Admini:", table.concat(Config.Admins or {}, ", "))
return {}
