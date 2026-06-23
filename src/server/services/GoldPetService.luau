-- GoldPetService.luau
-- Ulepszanie peta na ZŁOTEGO — rig "steve10die" w workspace.PUSTYNIA.
--
-- Mechanika:
--   • Gracz zaznacza 1-5 petów TEJ SAMEJ rzadkości (musi mieć obrazek w Config.Pets.GoldUpgrade.Images).
--   • Liczba petów = procent szansy (1=20% … 5=100%).
--   • ZAKRĘĆ → pety są "stake'owane" (usuwane z plecaka od razu — przepadają niezależnie od wyniku).
--   • Wygrana → 1 gold pet (rarity = wsadu, klasa = klasa większości, statystyki ×StatMultiplier);
--               trafia do EQ dopiero po ODBIERZ.
--   • Przegrana → wsad przepada; gracz może kupić REROLL (Robux) i kręcić tym samym wsadem w nieskończoność.
--   • 2x LUCK (Robux) — jednorazowo na spin, podwaja procent (cap 100%).
--
-- Stake'owane pety trzymane w `session.stakedPets` (pełne obiekty) — przegrana je gubi,
-- wygrana konsumuje (i tak były już zdjęte z data.Pets). Zamknięcie/relog = forfeit.
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local MarketplaceService  = game:GetService("MarketplaceService")
local HttpService         = game:GetService("HttpService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Util              = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PetService        = require(script.Parent:WaitForChild("PetService"))

local Events             = ReplicatedStorage:WaitForChild("Events")
local OpenGoldUpgrade    = Events:WaitForChild("OpenGoldUpgrade")
local GoldUpgradeSpin    = Events:WaitForChild("GoldUpgradeSpin")
local GoldUpgradeResult  = Events:WaitForChild("GoldUpgradeResult")
local GoldUpgradeClaim   = Events:WaitForChild("GoldUpgradeClaim")
local GoldUpgradeBuy     = Events:WaitForChild("GoldUpgradeBuy")
local GoldUpgradeProduct = Events:WaitForChild("GoldUpgradeProduct")

local cfg  = Config.Pets
local gcfg = cfg.GoldUpgrade

local GoldPetService = {}

-- ── Stan sesji per gracz ────────────────────────────────────────────────────
-- stakedPets: lista obiektów petów zablokowanych w maszynie (nil = brak stake).
-- wonPet:     gold pet czekający na ODBIERZ.
-- rerollCredit / doubleLuckPending: zakupione Robux, konsumowane per spin.
type Session = {
	stakedPets: { any }?,
	rarity: string?,
	class: string?,
	wonPet: any?,
	rerollCredit: boolean,
	doubleLuckPending: boolean,
}
local sessions: { [Player]: Session } = {}

local function getSession(player: Player): Session
	local s = sessions[player]
	if not s then
		s = { rerollCredit = false, doubleLuckPending = false }
		sessions[player] = s
	end
	return s
end

-- ── Anchor riga (cache do walidacji dystansu) ───────────────────────────────
local rigAnchor: BasePart? = nil

local function isNearRig(player: Player): boolean
	if not rigAnchor then return false end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	return ((hrp :: BasePart).Position - rigAnchor.Position).Magnitude <= (gcfg.MaxDist or 18)
end

-- ── Helpery ─────────────────────────────────────────────────────────────────
local function isEligibleRarity(rarity: string): boolean
	return gcfg.Images[rarity] ~= nil
end

local function newGoldPet(rarity: string, class: string)
	return {
		id     = HttpService:GenerateGUID(false),
		rarity = rarity,
		class  = class,
		gold   = true,
	}
end

-- Klasa większości wśród wsadu (remis → losowo).
local function majorityClass(pets: { any }): string
	local counts: { [string]: number } = {}
	for _, p in ipairs(pets) do
		counts[p.class] = (counts[p.class] or 0) + 1
	end
	local best, bestN = nil, -1
	local tied = {}
	for class, n in pairs(counts) do
		if n > bestN then best, bestN = class, n; tied = { class }
		elseif n == bestN then table.insert(tied, class) end
	end
	if #tied > 1 then
		return tied[math.random(1, #tied)]
	end
	return best or "Sprinter"
end

-- Snapshot petów do klienta (lewy panel = EQ).
local function petsSnapshot(data): { any }
	local out = {}
	for _, p in ipairs(data.Pets or {}) do
		table.insert(out, { id = p.id, rarity = p.rarity, class = p.class, gold = p.gold == true })
	end
	return out
end

-- Forfeit aktualnego stake'u + reset sesji. Pending wonPet jest GRANTOWANY (player-friendly).
local function resetSession(player: Player, grantPending: boolean)
	local s = sessions[player]
	if not s then return end
	if grantPending and s.wonPet then
		local data = PlayerDataService.GetData(player)
		if data then
			data.Pets = data.Pets or {}
			-- Pojemność: zostały zdjęte ≥1 pety przy stake, więc miejsce jest — ale sprawdzamy.
			local caps = Util.getCategoryCaps(Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity, Config.BackpackCategorySplit)
			if Util.getPetCount(data) + 1 <= caps.pets then
				table.insert(data.Pets, s.wonPet)
				PetService.PushHud(player)
				PetService.PushStatus(player)
			end
		end
	end
	-- stakedPets (nie-wygrane) przepadają — były już zdjęte z data.Pets.
	sessions[player] = nil
end

-- ── Open (ProximityPrompt riga) ─────────────────────────────────────────────
local function openFor(player: Player)
	-- Nowa sesja: forfeit poprzedniego stake'u, grant ewentualnego pending wina.
	resetSession(player, true)
	local data = PlayerDataService.GetData(player)
	OpenGoldUpgrade:FireClient(player, {
		pets          = petsSnapshot(data),
		percentPerPet = gcfg.PercentPerPet,
		maxSelect     = gcfg.MaxSelect,
		images        = gcfg.Images,
		rerollImage   = gcfg.Reroll.Image,
		luckImage     = gcfg.DoubleLuck.Image,
		spinSeconds   = gcfg.SpinSeconds,
		spinRotations = gcfg.SpinRotations,
		statMul       = gcfg.StatMultiplier,
	})
end

-- ── Spin ────────────────────────────────────────────────────────────────────
local lastSpinAt: { [Player]: number } = {}

local function fireResult(player: Player, payload)
	GoldUpgradeResult:FireClient(player, payload)
end

local function doSpin(player: Player, payload)
	if not player or not player.Parent then return end
	local now = os.clock()
	if (lastSpinAt[player] or 0) + (gcfg.Throttle or 0.4) > now then return end
	lastSpinAt[player] = now

	if not isNearRig(player) then
		fireResult(player, { ok = false, reason = "tooFar" })
		return
	end

	local data = PlayerDataService.GetData(player)
	local s = getSession(player)

	local staked, rarity, class

	if s.stakedPets then
		-- Stan po przegranej → wymaga zakupionego reroll.
		if not s.rerollCredit then
			fireResult(player, { ok = false, reason = "needReroll" })
			return
		end
		s.rerollCredit = false
		staked = s.stakedPets
		rarity = s.rarity
		class  = s.class
	else
		-- Świeży spin → walidacja wsadu.
		if type(payload) ~= "table" or type(payload.petIds) ~= "table" then
			fireResult(player, { ok = false, reason = "invalid" })
			return
		end
		local ids = payload.petIds
		local n = #ids
		if n < 1 or n > (gcfg.MaxSelect or 5) then
			fireResult(player, { ok = false, reason = "invalid" })
			return
		end
		-- Mapuj UUID → pet z data.Pets, sprawdzaj unikalność + tę samą rzadkość.
		local seen: { [string]: boolean } = {}
		local picked = {}
		local pickedRarity
		for _, id in ipairs(ids) do
			if type(id) ~= "string" or seen[id] then
				fireResult(player, { ok = false, reason = "invalid" }); return
			end
			seen[id] = true
			local found
			for _, p in ipairs(data.Pets or {}) do
				if p.id == id then found = p; break end
			end
			if not found then
				fireResult(player, { ok = false, reason = "invalid" }); return
			end
			if pickedRarity == nil then
				pickedRarity = found.rarity
			elseif found.rarity ~= pickedRarity then
				fireResult(player, { ok = false, reason = "mixedRarity" }); return
			end
			table.insert(picked, found)
		end
		if not isEligibleRarity(pickedRarity) then
			fireResult(player, { ok = false, reason = "badRarity" }); return
		end

		-- Stake: usuń wybrane pety z data.Pets (przepadają niezależnie od wyniku).
		local removeSet: { [string]: boolean } = {}
		for _, p in ipairs(picked) do removeSet[p.id] = true end
		local kept = {}
		local equippedRemoved = false
		for _, p in ipairs(data.Pets or {}) do
			if removeSet[p.id] then
				if data.EquippedPet == p.id then
					data.EquippedPet = ""
					equippedRemoved = true
				end
			else
				table.insert(kept, p)
			end
		end
		data.Pets = kept

		staked = picked
		rarity = pickedRarity
		class  = majorityClass(picked)
		s.stakedPets = staked
		s.rarity = rarity
		s.class  = class

		PetService.PushHud(player)
		PetService.PushStatus(player)
		if equippedRemoved then
			PetService.ApplyPetEffects(player)
			PetService.SyncVisual(player)
		end
	end

	-- Procent szansy
	local base = #staked * (gcfg.PercentPerPet or 20)
	local luckUsed = false
	if s.doubleLuckPending then
		s.doubleLuckPending = false
		luckUsed = true
	end
	local percent = math.clamp(luckUsed and base * 2 or base, 0, 100)

	-- Roll
	local won = (math.random() * 100) < percent

	if won then
		local goldPet = newGoldPet(rarity, class)
		s.wonPet = goldPet
		s.stakedPets = nil   -- po wygranej nie ma już co rerollować
		s.rerollCredit = false
		fireResult(player, {
			ok        = true,
			won       = true,
			percent   = percent,
			luckUsed  = luckUsed,
			goldRarity = rarity,
			goldClass  = class,
			goldImage  = gcfg.Images[rarity],
			pets      = petsSnapshot(data),
		})
	else
		-- Wsad zostaje stake'owany — możliwy reroll.
		fireResult(player, {
			ok        = true,
			won       = false,
			percent   = percent,
			luckUsed  = luckUsed,
			canReroll = true,
			pets      = petsSnapshot(data),
		})
	end
end

GoldUpgradeSpin.OnServerEvent:Connect(function(player, payload)
	doSpin(player, payload)
end)

-- ── Claim (ODBIERZ) ─────────────────────────────────────────────────────────
GoldUpgradeClaim.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not (s and s.wonPet) then return end
	local data = PlayerDataService.GetData(player)
	local caps = Util.getCategoryCaps(Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity, Config.BackpackCategorySplit)
	if Util.getPetCount(data) + 1 > caps.pets then
		fireResult(player, { ok = false, reason = "full" })
		return
	end
	data.Pets = data.Pets or {}
	table.insert(data.Pets, s.wonPet)
	s.wonPet = nil
	sessions[player] = nil
	PetService.PushHud(player)
	PetService.PushStatus(player)
	fireResult(player, { ok = true, claimed = true, pets = petsSnapshot(data) })
end)

-- ── Robux: prompt + receipt routing ─────────────────────────────────────────
GoldUpgradeBuy.OnServerEvent:Connect(function(player, kind)
	local productId
	if kind == "reroll" then
		productId = gcfg.Reroll.ProductId
	elseif kind == "luck" then
		productId = gcfg.DoubleLuck.ProductId
	else
		return
	end
	if not productId or productId == 0 then
		warn("[GoldPet] Brak ProductId dla", kind)
		return
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end)

-- Wołane przez BoostShopService.ProcessReceipt (single ProcessReceipt w grze).
-- Zwraca true jeśli ten ProductId należy do gold-upgrade (i został zastosowany).
function GoldPetService.HandleReceipt(player: Player, productId: number): boolean
	if productId == gcfg.Reroll.ProductId then
		local s = getSession(player)
		-- Reroll ma sens tylko gdy jest aktywny przegrany stake.
		if s.stakedPets then
			s.rerollCredit = true
		end
		GoldUpgradeProduct:FireClient(player, { kind = "reroll", ok = true, hasStake = s.stakedPets ~= nil })
		return true
	elseif productId == gcfg.DoubleLuck.ProductId then
		local s = getSession(player)
		s.doubleLuckPending = true
		GoldUpgradeProduct:FireClient(player, { kind = "luck", ok = true })
		return true
	end
	return false
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(p)
	resetSession(p, true)  -- grant pending win, forfeit stake
	sessions[p]    = nil
	lastSpinAt[p]  = nil
end)

-- ── ProximityPrompt na rigu steve10die ───────────────────────────────────────
local findAnchor = Util.findAnchor

task.spawn(function()
	-- Znajdź riga: workspace.PUSTYNIA.steve10die → fallback rekursywnie po całym workspace.
	local rig
	local container = workspace:WaitForChild(gcfg.RigContainer, 30)
	if container then
		rig = container:FindFirstChild(gcfg.RigName, true)
	end
	if not rig then
		rig = workspace:FindFirstChild(gcfg.RigName, true)
	end
	if not rig then
		warn(string.format("[GoldPet] Nie znaleziono riga '%s' (szukano w workspace.%s i całym workspace)",
			gcfg.RigName, gcfg.RigContainer))
		return
	end

	local anchor = findAnchor(rig)
	if not anchor then
		warn("[GoldPet] Rig nie ma żadnego BasePart:", rig:GetFullName())
		return
	end
	rigAnchor = anchor

	-- Sprzątnij stare prompty
	for _, c in ipairs(rig:GetDescendants()) do
		if c:IsA("ProximityPrompt") then c:Destroy() end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Ulepsz peta na złotego"
	prompt.ObjectText            = "Złota Maszyna"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.GamepadKeyCode        = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = anchor
	prompt.Triggered:Connect(function(player)
		openFor(player)
	end)

	print(string.format("[GoldPet] Rig gotowy → %s (anchor=%s)", rig:GetFullName(), anchor.Name))
end)

print("[GoldPetService] gotowy")

return GoldPetService
