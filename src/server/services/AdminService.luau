-- AdminService.luau
-- Prosty panel admina: walidacja, broadcast tekstu na ekran wszystkim graczom, kasa/butelki dla siebie.
-- Lista adminów w Config.Admins (nazwy lub UserIds).
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local Events         = ReplicatedStorage:WaitForChild("Events")
local AdminInit      = Events:WaitForChild("AdminInit")
local AdminAction    = Events:WaitForChild("AdminAction")
local AdminBroadcast = Events:WaitForChild("AdminBroadcast")
local UpdateHUD      = Events:WaitForChild("UpdateHUD")

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
		AdminBroadcast:FireAllClients({ message = msg, from = player.Name })
		print(string.format("[AdminService] %s broadcast: %s", player.Name, msg))

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
		-- Dodaje runtime'owy kod promocyjny — żyje do restartu serwera.
		-- CodeService czyta Config.Codes server-side, więc mutacja tu działa.
		local code = string.upper(string.gsub(tostring(payload.code or ""), "%s", ""))
		local reward = tonumber(payload.reward) or 0
		if #code == 0 or #code > 32 then return end
		if reward <= 0 or reward > 1000000 then return end
		Config.Codes = Config.Codes or {}
		Config.Codes[code] = { reward = reward }
		print(string.format("[AdminService] %s dodał kod %s = %d zł", player.Name, code, reward))
	end
end)

Players.PlayerRemoving:Connect(function(p) lastAction[p] = nil end)

print("[AdminService] gotowy. Admini:", table.concat(Config.Admins or {}, ", "))
return {}
