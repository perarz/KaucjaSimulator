-- BankService.luau
local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local RARITIES = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }
local BANK_DS  = DataStoreService:GetDataStore("BankData_v1")
local BANK_CAPACITY = 10  -- max butelek (suma wszystkich rzadkości) w skarbcu

local cache: { [Player]: { [string]: number } } = {}

local Events      = ReplicatedStorage:WaitForChild("Events")
local BankInit    = Events:WaitForChild("BankInit")
local BankDeposit = Events:WaitForChild("BankDeposit")
local BankWithdraw= Events:WaitForChild("BankWithdraw")
local BankResult  = Events:WaitForChild("BankResult")
local UpdateHUD   = Events:WaitForChild("UpdateHUD")

local function deepCopy(t: { [string]: any }): { [string]: any }
	local c = {}
	for k, v in pairs(t) do c[k] = type(v) == "table" and deepCopy(v) or v end
	return c
end

local function loadBank(player: Player): { [string]: number }
	if cache[player] then return cache[player] end
	local key = "BankData_v1_" .. player.UserId
	local ok, res = pcall(function() return BANK_DS:GetAsync(key) end)
	local data = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
	if ok and type(res) == "table" then
		for _, r in ipairs(RARITIES) do
			if type(res[r]) == "number" then data[r] = math.max(0, math.floor(res[r])) end
		end
	elseif not ok then
		warn("[BankService] GetAsync failed:", res)
	end
	cache[player] = data
	return data
end

local function saveBank(player: Player)
	local d = cache[player]
	if not d then return end
	local key = "BankData_v1_" .. player.UserId
	local ok, err = pcall(function() BANK_DS:SetAsync(key, d) end)
	if not ok then warn("[BankService] SetAsync failed:", err) end
end

-- ── ProximityPrompt na workspace.BANK.Bankier ─────────────────────────────
task.spawn(function()
	local bankFolder = workspace:WaitForChild("BANK", 30)
	if not bankFolder then warn("[BankService] workspace.BANK nie istnieje") return end
	local bankier = bankFolder:WaitForChild("Bankier", 15)
	if not bankier then warn("[BankService] BANK.Bankier nie istnieje") return end

	local anchor: BasePart?
	if bankier:IsA("Model") then
		anchor = bankier.PrimaryPart or bankier:FindFirstChildWhichIsA("BasePart")
	elseif bankier:IsA("BasePart") then
		anchor = bankier :: BasePart
	end
	if not anchor then warn("[BankService] Bankier nie ma BasePart") return end

	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText          = "Otwórz bank"
		prompt.ObjectText          = "Bankier"
		prompt.MaxActivationDistance = 8
		prompt.HoldDuration        = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent              = anchor
	end

	prompt.Triggered:Connect(function(player: Player)
		local pData = PlayerDataService.GetData(player)
		if (pData.BaseLevel or 0) < 1 then
			BankInit:FireClient(player, { locked = true, reason = "needBase" })
			return
		end
		local bData = loadBank(player)
		BankInit:FireClient(player, {
			bankContents     = deepCopy(bData),
			backpackContents = deepCopy(pData.BackpackContents),
			backpackCapacity = Config.BackpackUpgrades[pData.BackpackLevel].Capacity,
			bankCapacity     = BANK_CAPACITY,
			hasSyrup         = (pData.Grandpa and pData.Grandpa.hasSyrup) or false,
		})
	end)
end)

-- ── Walidacja i zapis transferu (deposit i withdraw identyczne po stronie serwera) ──
local function handleTransfer(player: Player, rawBp: any, rawBk: any)
	if type(rawBp) ~= "table" or type(rawBk) ~= "table" then
		return false, "invalid"
	end

	local pData = PlayerDataService.GetData(player)
	if (pData.BaseLevel or 0) < 1 then
		return false, "locked"
	end
	local bData = loadBank(player)

	-- Conservation check: suma per rzadkość musi być niezmieniona
	for _, r in ipairs(RARITIES) do
		local oldTotal = (pData.BackpackContents[r] or 0) + (bData[r] or 0)
		local bpAmt    = math.floor(math.max(0, tonumber(rawBp[r] or 0) or 0))
		local bkAmt    = math.floor(math.max(0, tonumber(rawBk[r] or 0) or 0))
		if bpAmt + bkAmt ~= oldTotal then
			return false, "conservation"
		end
	end

	-- Capacity check: nowy plecak nie przekracza pojemności
	local hasSyrup = pData.Grandpa and pData.Grandpa.hasSyrup or false
	local cap      = Config.BackpackUpgrades[pData.BackpackLevel].Capacity
	local carried  = hasSyrup and 1 or 0
	for _, r in ipairs(RARITIES) do
		carried += math.floor(math.max(0, tonumber(rawBp[r] or 0) or 0))
	end
	if carried > cap then return false, "overCapacity" end

	-- Bank capacity check: suma wszystkich rzadkości w skarbcu <= BANK_CAPACITY
	local bankTotal = 0
	for _, r in ipairs(RARITIES) do
		bankTotal += math.floor(math.max(0, tonumber(rawBk[r] or 0) or 0))
	end
	if bankTotal > BANK_CAPACITY then return false, "bankFull" end

	-- Zastosuj
	for _, r in ipairs(RARITIES) do
		pData.BackpackContents[r] = math.floor(math.max(0, tonumber(rawBp[r] or 0) or 0))
		bData[r]                  = math.floor(math.max(0, tonumber(rawBk[r] or 0) or 0))
	end

	PlayerDataService.SaveData(player)
	saveBank(player)

	UpdateHUD:FireClient(player, {
		backpackContents = deepCopy(pData.BackpackContents),
		backpackCapacity = cap,
		hasSyrup        = hasSyrup,
	})

	return true, deepCopy(bData), deepCopy(pData.BackpackContents), cap
end

BankDeposit.OnServerEvent:Connect(function(player: Player, payload)
	if type(payload) ~= "table" then return end
	local ok, a, b, c = handleTransfer(player, payload.newBackpackContents, payload.newBankContents)
	if ok then
		BankResult:FireClient(player, { success = true, bankContents = a, backpackContents = b, backpackCapacity = c })
	else
		BankResult:FireClient(player, { success = false, reason = a })
	end
end)

BankWithdraw.OnServerEvent:Connect(function(player: Player, payload)
	if type(payload) ~= "table" then return end
	local ok, a, b, c = handleTransfer(player, payload.newBackpackContents, payload.newBankContents)
	if ok then
		BankResult:FireClient(player, { success = true, bankContents = a, backpackContents = b, backpackCapacity = c })
	else
		BankResult:FireClient(player, { success = false, reason = a })
	end
end)

-- Auto-save co 60s
task.spawn(function()
	while true do
		task.wait(60)
		for p in pairs(cache) do saveBank(p) end
	end
end)

Players.PlayerRemoving:Connect(function(p) saveBank(p); cache[p] = nil end)
game:BindToClose(function() for p in pairs(cache) do saveBank(p) end end)

return {}
