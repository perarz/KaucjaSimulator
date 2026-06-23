-- KoszService.luau
-- Kosze do przeszukiwania: ProximityPrompt HoldDuration=2, losowa rzadkość, cooldown per kosz

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage.Config)
local Util              = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local QuestService      = require(ServerScriptService.QuestService)

local Events     = ReplicatedStorage:WaitForChild("Events")
local KoszResult = Events:WaitForChild("KoszResult")
local UpdateHUD  = Events:WaitForChild("UpdateHUD")

local KoszService = {}

local KOSZ_HOLD_DURATION = 2.0
local KOSZ_COOLDOWN_SEC  = 30      -- ile sekund kosz jest "pusty" po przeszukaniu
local KOSZ_PROMPT_DIST   = 12  -- było 7 — przy crowdzie 40+ graczy ciężko podejść

local rarityOrder = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }

-- Weighted random — używa tych samych szans co spawn butelek.
-- Z LuckLevel>=1: chances dla Rzadka/Epicka/Legendarna/Mityczny × LuckMultiplier, Zwykla resztą.
-- Mityczna w koszach zostaje na 0 (zgodnie z BottleSpawnChance) — tylko w strefie tier 5.
local function pickRarity(data: { [string]: any }?): string
	local base = Config.BottleSpawnChance
	local zw, rz, ep, le, my = base.Zwykla, base.Rzadka, base.Epicka, base.Legendarna, (base.Mityczny or 0)
	if data and (data.LuckLevel or 0) >= 1 then
		local m = Config.LuckUpgrade.LuckMultiplier
		rz, ep, le, my = rz * m, ep * m, le * m, my * m
		zw = math.max(0, 1 - rz - ep - le - my)
	end
	local chances = { Zwykla = zw, Rzadka = rz, Epicka = ep, Legendarna = le, Mityczny = my }
	local roll = math.random()
	local cumulative = 0
	for _, rarity in ipairs(rarityOrder) do
		cumulative += chances[rarity]
		if roll <= cumulative then return rarity end
	end
	return "Zwykla"
end

-- Weighted random ilości dropu na podstawie Config.KoszDropQuantity
local function pickQuantity(rarity: string): number
	local weights = Config.KoszDropQuantity and Config.KoszDropQuantity[rarity]
	if not weights or #weights == 0 then return 1 end

	local total = 0
	for _, w in ipairs(weights) do total += w[2] end

	local roll = math.random() * total
	local cumulative = 0
	for _, w in ipairs(weights) do
		cumulative += w[2]
		if roll <= cumulative then return w[1] end
	end
	return weights[1][1]
end

local function anchorPartOf(kosz: Instance): BasePart?
	if kosz:IsA("BasePart") then return kosz :: BasePart end
	if kosz:IsA("Model") then
		local pp = (kosz :: Model).PrimaryPart
		if pp then return pp end
		for _, d in ipairs(kosz:GetDescendants()) do
			if d:IsA("BasePart") then return d :: BasePart end
		end
	end
	return nil
end

-- Cooldown per kosz przechowywany jako tick() do kiedy niedostępny
local koszCooldownUntil: { [Instance]: number } = {}

local function isOnCooldown(kosz: Instance): boolean
	local until_ = koszCooldownUntil[kosz]
	return until_ ~= nil and tick() < until_
end

local function setupKoszPrompt(kosz: Instance)
	local anchor = anchorPartOf(kosz)
	if not anchor then
		warn("[KoszService] Kosz '" .. kosz.Name .. "' nie ma BasePart — pomijam")
		return
	end

	-- Usuń stary prompt jeśli był
	local existing = anchor:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Przeszukaj kosz"
	prompt.ObjectText            = "Kosz"
	prompt.HoldDuration          = KOSZ_HOLD_DURATION
	prompt.MaxActivationDistance = KOSZ_PROMPT_DIST
	prompt.RequiresLineOfSight   = false
	prompt.UIOffset              = Vector2.new(0, -100)  -- prompt nad głowami innych graczy
	prompt.Parent                = anchor

	prompt.Triggered:Connect(function(player: Player)
		-- Cooldown?
		if isOnCooldown(kosz) then
			KoszResult:FireClient(player, { success = false, reason = "cooldown" })
			return
		end

		local data = PlayerDataService.GetData(player)
		local capacity = Config.BackpackUpgrades[data.BackpackLevel].Capacity
		-- Carried = butelki + syrop + magnesy + pety (single source of truth: Util.getCarriedCount).
		-- BEZ tego kosz pozwalał przekroczyć capacity (pety/magnesy nie były wliczane).
		local carried = Util.getCarriedCount(data)

		-- Plecak całkowicie pełny — w ogóle nie da się przeszukać
		if carried >= capacity then
			KoszResult:FireClient(player, { success = false, reason = "full" })
			return
		end

		-- Losowanie rzadkości + ilości (LuckLevel modyfikuje szanse rzadkości)
		local rarity = pickRarity(data)
		local count  = pickQuantity(rarity)

		-- Sprawdź czy zmieści się CAŁY drop
		if carried + count > capacity then
			KoszResult:FireClient(player, {
				success    = false,
				reason     = "noSpace",
				rarity     = rarity,
				count      = count,
				freeSpace  = capacity - carried,
			})
			return
		end

		-- Aktualizacja danych
		data.BackpackContents[rarity] += count
		data.TotalBottles            += count

		-- Quest progress: każda butelka z kosza liczy się jako collect
		QuestService.AddProgress(player, "collect", { rarity = rarity, amount = count })
		QuestService.AddProgress(player, "search_kosz", { amount = 1 })
		pcall(function()
			local sqs = require(script.Parent.StoryQuestService)
			sqs.AddProgress(player, "collect", count, { rarity = rarity })
		end)

		-- Cooldown na kosza
		koszCooldownUntil[kosz] = tick() + KOSZ_COOLDOWN_SEC

		-- Sync HUD klienta
		UpdateHUD:FireClient(player, {
			backpackContents = data.BackpackContents,
			backpackCapacity = capacity,
		})

		-- Animacja roulette po stronie klienta
		KoszResult:FireClient(player, {
			success = true,
			rarity  = rarity,
			count   = count,
		})
	end)
end

local function setupAllKosze()
	local folder = workspace:FindFirstChild("Kosze")
	if not folder then
		warn("[KoszService] Brak folderu workspace.Kosze — kosze nie będą aktywne")
		return
	end

	for _, kosz in ipairs(folder:GetChildren()) do
		setupKoszPrompt(kosz)
	end

	folder.ChildAdded:Connect(function(child)
		setupKoszPrompt(child)
	end)

	print("[KoszService] Aktywne kosze:", #folder:GetChildren())
end

task.spawn(setupAllKosze)

return KoszService
