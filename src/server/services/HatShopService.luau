-- HatShopService.luau
-- Sklep czapek (workspace.SKLEP2.Cashier). 1 produkt: Czapka — jednorazowy zakup.
-- Koszt: 10× Legendarna + 1× Mityczna + 5000 zł. Bonusy permanentne: +HP, +stamina, +speed.
-- Akcesorium kopiowane z ReplicatedStorage.Czapka i przyklejane na każdym spawn.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Util              = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local Events           = ReplicatedStorage:WaitForChild("Events")
local OpenHatShop      = Events:WaitForChild("OpenHatShop")
local BuyHat           = Events:WaitForChild("BuyHat")
local BuyHatResult     = Events:WaitForChild("BuyHatResult")
local HatStatusUpdate  = Events:WaitForChild("HatStatusUpdate")
local UpdateHUD        = Events:WaitForChild("UpdateHUD")

local HAT_TAG = "__ShopHat"

-- Anchor + throttle do walidacji BuyHat (anti-exploit)
local hatAnchor: BasePart? = nil
local HAT_MAX_DIST = 15
local lastBuyAt: { [Player]: number } = {}
local BUY_THROTTLE = 0.5
local function isNearHatShop(player: Player): boolean
	if not hatAnchor then return false end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	return ((hrp :: BasePart).Position - hatAnchor.Position).Magnitude <= HAT_MAX_DIST
end
Players.PlayerRemoving:Connect(function(p) lastBuyAt[p] = nil end)

-- ── Setup ProximityPrompt na workspace.SKLEP2.Cashier ────────────────────────
local findAnchor = Util.findAnchor

task.spawn(function()
	print("[HatShopService] === diagnostyka startowa ===")
	local sklep = workspace:WaitForChild("SKLEP2", 30)
	if not sklep then warn("[HatShopService] Brak workspace.SKLEP2") return end
	print("[HatShopService] SKLEP2 znaleziony:", sklep:GetFullName(), "class=" .. sklep.ClassName)

	local cashier = sklep:WaitForChild("Cashier", 15)
	if not cashier then warn("[HatShopService] Brak SKLEP2.Cashier") return end
	print("[HatShopService] Cashier znaleziony:", cashier:GetFullName(), "class=" .. cashier.ClassName)

	local anchor = findAnchor(cashier)
	if not anchor then
		warn("[HatShopService] Cashier nie ma żadnego BasePart — dzieci:")
		for _, c in ipairs(cashier:GetChildren()) do
			warn("  -", c.Name, c.ClassName)
		end
		return
	end
	print("[HatShopService] Anchor wybrany:", anchor:GetFullName(), "rozmiar=" .. tostring(anchor.Size))
	hatAnchor = anchor  -- cache do walidacji dystansu w BuyHat

	-- Usuń stary prompt jeśli istnieje (mógł wcześniej siedzieć na złym partsie)
	for _, c in ipairs(cashier:GetDescendants()) do
		if c:IsA("ProximityPrompt") and c.ActionText == "Sklep z czapkami" then
			c:Destroy()
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Sklep z czapkami"
	prompt.ObjectText            = "Kasjer"
	prompt.MaxActivationDistance = 14
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.UIOffset              = Vector2.new(0, -100)
	prompt.Parent                = anchor

	prompt.Triggered:Connect(function(player: Player)
		OpenHatShop:FireClient(player)
	end)

	print("[HatShopService] ProximityPrompt dodany do:", anchor:GetFullName())
end)

-- ── Bonusy: HP + akcesorium na spawn ─────────────────────────────────────────
local function clearOldHat(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:GetAttribute(HAT_TAG) then d:Destroy() end
	end
end

local function applyHatEffects(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data.HatOwned then return end

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- HP bonus — DELEGATE do PetService (single source of truth dla MaxHealth = 100 + hat + pet).
	-- Bez tego dwa serwisy race'owały by się o MaxHealth (kto ostatni, ten wygrywa, pet bonus by ginął).
	local okP, PetService = pcall(function() return require(script.Parent.PetService) end)
	if okP and PetService then
		PetService.ApplyPetEffects(player)
	else
		-- Fallback gdy PetService jeszcze nie wczytany
		hum.MaxHealth = 100 + (Config.HatShop.HpBonus or 0)
		hum.Health = hum.MaxHealth
	end

	-- Akcesorium (czapka graficznie)
	clearOldHat(char)
	local template = ReplicatedStorage:FindFirstChild(Config.HatShop.Template)
	if template and template:IsA("Accessory") then
		local clone = template:Clone()
		clone:SetAttribute(HAT_TAG, true)
		hum:AddAccessory(clone)
	elseif template then
		warn("[HatShopService] ReplicatedStorage." .. Config.HatShop.Template .. " musi być Accessory, jest:", template.ClassName)
	end
end

local function fireHatStatus(player: Player)
	local data = PlayerDataService.GetData(player)
	HatStatusUpdate:FireClient(player, {
		owned        = data.HatOwned == true,
		speedBonus   = Config.HatShop.SpeedBonus,
		staminaBonus = Config.HatShop.StaminaBonus,
		hpBonus      = Config.HatShop.HpBonus,
	})
end

-- ── Zakup ───────────────────────────────────────────────────────────────────
BuyHat.OnServerEvent:Connect(function(player: Player)
	-- Throttle + dystans od Cashiera
	local now = os.clock()
	if lastBuyAt[player] and now - lastBuyAt[player] < BUY_THROTTLE then return end
	lastBuyAt[player] = now
	if not isNearHatShop(player) then
		BuyHatResult:FireClient(player, { success = false, reason = "tooFar" })
		return
	end

	local data = PlayerDataService.GetData(player)
	if data.HatOwned then
		BuyHatResult:FireClient(player, { success = false, reason = "already" })
		return
	end

	local shop = Config.HatShop
	-- Sprawdź zł
	if (data.Zlotowki or 0) < shop.CostZl then
		BuyHatResult:FireClient(player, { success = false, reason = "broke" })
		return
	end
	-- Sprawdź butelki
	for rarity, count in pairs(shop.CostBottles) do
		if (data.BackpackContents[rarity] or 0) < count then
			BuyHatResult:FireClient(player, { success = false, reason = "bottles", rarity = rarity, need = count })
			return
		end
	end

	-- Pobierz zasoby
	data.Zlotowki -= shop.CostZl
	for rarity, count in pairs(shop.CostBottles) do
		data.BackpackContents[rarity] -= count
	end
	data.HatOwned = true

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	-- Sync HUD (zmiana BackpackContents)
	local cap = Config.BackpackUpgrades[data.BackpackLevel].Capacity
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = cap,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
	})

	applyHatEffects(player)
	fireHatStatus(player)
	BuyHatResult:FireClient(player, { success = true })
end)

-- ── Spawn hook ──────────────────────────────────────────────────────────────
local function onCharacter(player: Player, character: Model)
	character:WaitForChild("Humanoid", 5)
	task.wait(0.2)
	applyHatEffects(player)
	fireHatStatus(player)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
	-- Pierwsza sync gdy dane gotowe
	task.spawn(function()
		task.wait(2)
		fireHatStatus(player)
		if player.Character then onCharacter(player, player.Character) end
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
	if p.Character then task.spawn(onCharacter, p, p.Character) end
end

return {}
