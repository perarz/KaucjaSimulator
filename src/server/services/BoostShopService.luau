-- BoostShopService.luau
-- Developer Products w Robux. Aktualnie 1 produkt: x2 KASA z butelkomatu na 10 minut.
-- ProcessReceipt handler — Roblox wywołuje to gdy gracz finalizuje zakup.
local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

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

-- ── ProcessReceipt: Roblox wywołuje to po finalizacji zakupu ─────────────────
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Gracz wyszedł przed odbiorem — Roblox spróbuje ponownie później
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == Config.BoostShop.DoubleEarn.ProductId then
		activateDoubleEarn(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Deski w Robux (np. VIP) — grant przez DeskaService
	local okDeska, DeskaService = pcall(function()
		return require(script.Parent:WaitForChild("DeskaService"))
	end)
	if okDeska and DeskaService then
		local deck = DeskaService.GetDeckByProductId(receiptInfo.ProductId)
		if deck then
			DeskaService.GrantDeck(player, deck.key)
			return Enum.ProductPurchaseDecision.PurchaseGranted
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
		MarketplaceService:PromptProductPurchase(player, id)
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
