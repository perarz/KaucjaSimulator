-- PetSlotShopService.luau
-- NPC (workspace.<Config.PetSlotShop.NpcModel>, np. Poland) → ProximityPrompt "Kup dodatkowy slot na peta".
-- Po Triggered → wysyła klientowi `OpenPetSlotShop` (klient otwiera UI confirm dialog).
-- Klient klika KUP → `BuyPetSlot:FireServer` → walidacja atomowa:
--   1) MaxEquippedPets == FromMax (anty-spam podwójnego zakupu)
--   2) data.Zlotowki >= CostZl
--   3) data.BackpackContents[rarity] >= count dla każdej z CostBottles
--   4) Deductuj zł + butelki + sync InventoryStacks (TEGO HatShop NIE robił — był bug)
--   5) MaxEquippedPets = ToMax
--   6) Save + UpdateHUD + PetStatusUpdate + BuyPetSlotResult

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)
local PetService        = require(script.Parent.PetService)

local Events            = ReplicatedStorage:WaitForChild("Events")
local OpenPetSlotShop   = Events:WaitForChild("OpenPetSlotShop")
local BuyPetSlot        = Events:WaitForChild("BuyPetSlot")
local BuyPetSlotResult  = Events:WaitForChild("BuyPetSlotResult")
local UpdateHUD         = Events:WaitForChild("UpdateHUD")

local cfg = Config.PetSlotShop
local shopAnchor: BasePart? = nil

-- ── Anchor lookup ───────────────────────────────────────────────────────────
local function findAnchor(model: Instance): BasePart?
	if model:IsA("BasePart") then return model end
	if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function setupNpc()
	local npc = workspace:FindFirstChild(cfg.NpcModel)
	if not npc then
		warn(string.format("[PetSlotShopService] Brak workspace.%s (NPC pomijany)", cfg.NpcModel))
		return
	end
	local anchor = findAnchor(npc)
	if not anchor then
		warn(string.format("[PetSlotShopService] workspace.%s nie ma BasePart", cfg.NpcModel))
		return
	end
	shopAnchor = anchor

	for _, c in ipairs(anchor:GetChildren()) do
		if c:IsA("ProximityPrompt") then c:Destroy() end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = cfg.PromptText or "Kup dodatkowy slot na peta"
	prompt.ObjectText            = string.format("%d zł + 10 Mitycznych", cfg.CostZl)
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = anchor

	prompt.Triggered:Connect(function(player: Player)
		OpenPetSlotShop:FireClient(player, {
			costZl      = cfg.CostZl,
			costBottles = cfg.CostBottles,
			fromMax     = cfg.FromMax,
			toMax       = cfg.ToMax,
		})
	end)

	print(string.format("[PetSlotShopService] NPC gotowy (workspace.%s, koszt %d zł + 10 Mit, %d→%d slot)",
		cfg.NpcModel, cfg.CostZl, cfg.FromMax, cfg.ToMax))
end

setupNpc()

-- ── Zakup ──────────────────────────────────────────────────────────────────
local SHOP_RANGE = 15

local function isNearShop(player: Player): boolean
	if not shopAnchor then return false end
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hrp then return false end
	return (hrp.Position - shopAnchor.Position).Magnitude <= SHOP_RANGE
end

-- Sync InventoryStacks z BackpackContents (po deducie butelek).
-- HatShop tego NIE robi → układ EQ rozjeżdża się z faktycznym stanem (bug zgłoszony).
-- Tu sprzątamy: dla każdej rzadkości — ile butelek jest w BackpackContents tyle MA być w stack'ach,
-- nadmiarowe stacki tej rzadkości są zmniejszane / usuwane od końca.
local function reconcileInventoryStacks(data, rarity: string)
	if type(data.InventoryStacks) ~= "table" then return end
	local target = data.BackpackContents[rarity] or 0
	local current = 0
	for _, s in ipairs(data.InventoryStacks) do
		if s.rarity == rarity then current += (s.count or 0) end
	end
	if current <= target then return end  -- nic do zrobienia (np. stacks już zsync)
	local excess = current - target
	for i = #data.InventoryStacks, 1, -1 do
		if excess <= 0 then break end
		local s = data.InventoryStacks[i]
		if s and s.rarity == rarity then
			local take = math.min(excess, s.count or 0)
			s.count = (s.count or 0) - take
			excess = excess - take
			if s.count <= 0 then table.remove(data.InventoryStacks, i) end
		end
	end
end

local lastBuyAt: { [Player]: number } = {}
local BUY_THROTTLE = 1.0

BuyPetSlot.OnServerEvent:Connect(function(player: Player)
	-- Anty-spam
	local now = os.clock()
	if (lastBuyAt[player] or 0) + BUY_THROTTLE > now then return end
	lastBuyAt[player] = now

	if not isNearShop(player) then
		BuyPetSlotResult:FireClient(player, { success = false, reason = "tooFar" })
		return
	end

	local data = PlayerDataService.GetData(player)
	if not data then return end

	-- (1) Sprawdzanie poziomu — gracz musi mieć FromMax
	if (data.MaxEquippedPets or 1) ~= cfg.FromMax then
		BuyPetSlotResult:FireClient(player, { success = false, reason = "already",
			maxEquippedPets = data.MaxEquippedPets or 1 })
		return
	end

	-- (2) Sprawdzanie zł
	if (data.Zlotowki or 0) < cfg.CostZl then
		BuyPetSlotResult:FireClient(player, { success = false, reason = "broke",
			need = cfg.CostZl, have = data.Zlotowki or 0 })
		return
	end

	-- (3) Sprawdzanie butelek — TYLKO z EQ (BackpackContents), nie z banku
	data.BackpackContents = data.BackpackContents or {}
	for rarity, count in pairs(cfg.CostBottles) do
		if (data.BackpackContents[rarity] or 0) < count then
			BuyPetSlotResult:FireClient(player, { success = false, reason = "bottles",
				rarity = rarity, need = count, have = data.BackpackContents[rarity] or 0 })
			return
		end
	end

	-- (4) ATOMOWO deductuj zł + butelki + zsync InventoryStacks
	data.Zlotowki = data.Zlotowki - cfg.CostZl
	for rarity, count in pairs(cfg.CostBottles) do
		data.BackpackContents[rarity] = (data.BackpackContents[rarity] or 0) - count
		reconcileInventoryStacks(data, rarity)  -- ← FIX bug'a HatShop'a
	end
	data.MaxEquippedPets = cfg.ToMax

	-- (5) Save + sync
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	-- Sync HUD (zmiana BackpackContents + InventoryStacks → klient layout musi się przeliczyć)
	local cap = Config.BackpackUpgrades[data.BackpackLevel] and Config.BackpackUpgrades[data.BackpackLevel].Capacity or 10
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = cap,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
	})

	-- Sync pet status (maxEquipped++)
	PetService.PushStatus(player)

	BuyPetSlotResult:FireClient(player, { success = true, maxEquippedPets = data.MaxEquippedPets })
end)

Players.PlayerRemoving:Connect(function(p)
	lastBuyAt[p] = nil
end)

return {}
