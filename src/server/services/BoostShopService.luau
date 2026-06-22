-- BoostShopService.luau
-- Developer Products w Robux. Aktualnie 1 produkt: x2 KASA z butelkomatu na 10 minut.
-- ProcessReceipt handler — Roblox wywołuje to gdy gracz finalizuje zakup.
local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local Events             = ReplicatedStorage:WaitForChild("Events")
local BoostStatusUpdate  = Events:WaitForChild("BoostStatusUpdate")
local PromptBoostPurchase = Events:WaitForChild("PromptBoostPurchase")

local BoostShopService = {}

local doubleEarnUntil: { [Player]: number } = {}   -- [player] = os.clock() do kiedy aktywny

-- Public: użyte przez BottleService butelkomat
function BoostShopService.GetEarnMultiplier(player: Player): number
	local until_ = doubleEarnUntil[player]
	if until_ and os.clock() < until_ then
		return Config.BoostShop.DoubleEarn.Multiplier or 2
	end
	return 1
end

local function syncBoostStatus(player: Player)
	local until_ = doubleEarnUntil[player]
	local remaining = 0
	if until_ then remaining = math.max(0, until_ - os.clock()) end
	BoostStatusUpdate:FireClient(player, {
		doubleEarnRemainingSec = remaining,
		productId              = Config.BoostShop.DoubleEarn.ProductId,
		priceRobux             = Config.BoostShop.DoubleEarn.PriceRobux,
	})
end

local function activateDoubleEarn(player: Player)
	local duration = Config.BoostShop.DoubleEarn.DurationSec or 600
	local now = os.clock()
	-- Jeśli już ma aktywny, doliczamy do końca (cumulative)
	local current = doubleEarnUntil[player]
	if current and current > now then
		doubleEarnUntil[player] = current + duration
	else
		doubleEarnUntil[player] = now + duration
	end
	syncBoostStatus(player)
	print(string.format("[BoostShop] %s aktywował x2 KASA — koniec za %ds",
		player.Name, math.floor(doubleEarnUntil[player] - now)))
end

-- Paczka złotówek za Robux — dolicza PLN do salda gracza (jak deska VIP: ProcessReceipt).
local function grantMoney(player: Player, amount: number)
	local data = PlayerDataService.GetData(player)
	if not data then return end
	data.Zlotowki    = (data.Zlotowki or 0) + amount
	data.TotalEarned = (data.TotalEarned or 0) + amount  -- liczy się do leaderboardu
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)
	print(string.format("[BoostShop] %s otrzymał %d PLN (paczka Robux)", player.Name, amount))
end

-- ── ProcessReceipt: Roblox wywołuje to po finalizacji zakupu ─────────────────
MarketplaceService.ProcessReceipt = function(receiptInfo)
	print(string.format("[BoostShop] ProcessReceipt: PlayerId=%d ProductId=%s",
		receiptInfo.PlayerId, tostring(receiptInfo.ProductId)))
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Gracz wyszedł przed odbiorem — Roblox spróbuje ponownie później
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == Config.BoostShop.DoubleEarn.ProductId then
		activateDoubleEarn(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Paczki złotówek (Developer Products)
	for _, pack in ipairs(Config.BoostShop.MoneyPacks or {}) do
		if pack.ProductId ~= 0 and receiptInfo.ProductId == pack.ProductId then
			grantMoney(player, pack.Amount)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	-- Deski w Robux (np. VIP) — DeskaService to standalone Script, więc grant idzie
	-- przez BindableEvent GrantDeckEvent (nie require, bo to Script a nie ModuleScript).
	for _, deck in ipairs(Config.Decks or {}) do
		if deck.CostType == "Robux" and deck.RobuxProductId == receiptInfo.ProductId and deck.RobuxProductId ~= 0 then
			local ev = ServerScriptService:FindFirstChild("GrantDeckEvent")
			if ev then
				ev:Fire(player, deck.key)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			warn("[BoostShop] GrantDeckEvent nie istnieje — DeskaService nie wystartował?")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	-- Nieznany ProductId
	warn("[BoostShop] Nieznany ProductId:", receiptInfo.ProductId)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ── Klient prosi o otwarcie okna zakupu Robux ────────────────────────────────
PromptBoostPurchase.OnServerEvent:Connect(function(player: Player, productKey: string)
	if productKey == "DoubleEarn" then
		local id = Config.BoostShop.DoubleEarn.ProductId
		if not id or id == 0 then
			warn("[BoostShop] Brak ProductId w Config — wpisz swój z dashboard Roblox")
			return
		end
		print(string.format("[BoostShop] %s → PromptProductPurchase(ProductId=%d)", player.Name, id))
		MarketplaceService:PromptProductPurchase(player, id)
		return
	end
	-- Paczki złotówek
	for _, pack in ipairs(Config.BoostShop.MoneyPacks or {}) do
		if productKey == pack.key then
			if not pack.ProductId or pack.ProductId == 0 then
				warn("[BoostShop] Brak ProductId paczki", pack.key)
				return
			end
			print(string.format("[BoostShop] %s → PromptProductPurchase(%s, %d)", player.Name, pack.key, pack.ProductId))
			MarketplaceService:PromptProductPurchase(player, pack.ProductId)
			return
		end
	end
end)

-- ── Heartbeat tick — odświeża klienta co 1s (timer w HUD) ───────────────────
task.spawn(function()
	while true do
		task.wait(1)
		for player, until_ in pairs(doubleEarnUntil) do
			if os.clock() >= until_ then
				doubleEarnUntil[player] = nil
				syncBoostStatus(player)
				print("[BoostShop]", player.Name, "boost x2 skończony")
			else
				syncBoostStatus(player)
			end
		end
	end
end)

-- Initial sync
Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	syncBoostStatus(player)
end)

Players.PlayerRemoving:Connect(function(p) doubleEarnUntil[p] = nil end)

return BoostShopService
