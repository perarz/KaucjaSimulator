-- PetService.luau
-- System petów — single source of truth dla otwierania jajek, equip/unequip/discard,
-- bonusów (money/speed/HP) i broadcastów do klienta.
--
-- Pety:
--   • każdy = { id (uuid), rarity, class } — 1 slot pojemności w plecaku
--   • equipped (max Config.Pets.MaxEquipped, na razie 1) — daje bonus money + speed + HP
--   • drop weighted RNG (Config.Pets.Rarities/.ClassWeights)
--   • DataStore: data.Pets / data.EquippedPet / data.BankPets / data.HasTripleEgg (cache)
--
-- Struktura zaprojektowana żeby dodanie rzadkości/klasy = wpis w Config.
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService  = game:GetService("MarketplaceService")
local HttpService         = game:GetService("HttpService")
local RunService          = game:GetService("RunService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Util              = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local Events                = ReplicatedStorage:WaitForChild("Events")
local OpenPetGablota        = Events:WaitForChild("OpenPetGablota")
local BuyEggOpen            = Events:WaitForChild("BuyEggOpen")
local PetRouletteResult     = Events:WaitForChild("PetRouletteResult")
local EquipPet              = Events:WaitForChild("EquipPet")
local UnequipPet            = Events:WaitForChild("UnequipPet")
local DiscardPet            = Events:WaitForChild("DiscardPet")
local PetStatusUpdate       = Events:WaitForChild("PetStatusUpdate")
local PromptPetGamepassBuy  = Events:WaitForChild("PromptPetGamepassBuy")
local UpdateHUD             = Events:WaitForChild("UpdateHUD")

local cfg = Config.Pets

local PetService = {}

-- Cache: czy gracz posiada gamepass (1 raz na sesję — async call kosztuje, więc cache)
local gamepassCache: { [Player]: boolean } = {}
-- Anty-spam OpenEgg
local lastOpenAt: { [Player]: number } = {}
-- Anty-spam EquipPet/UnequipPet/DiscardPet
local lastPetActionAt: { [Player]: number } = {}
local PET_ACTION_THROTTLE = 0.3
-- Anchor gabloty (cache do walidacji dystansu w BuyEggOpen)
local petGablotaAnchor: BasePart? = nil
local GABLOTA_MAX_DIST = 18
local function isNearGablota(player: Player): boolean
	if not petGablotaAnchor then return false end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	return ((hrp :: BasePart).Position - petGablotaAnchor.Position).Magnitude <= GABLOTA_MAX_DIST
end
-- Aktywne wizualne pety per gracz: mapa petId → entry. Każdy equipped pet ma własny visual.
type VisEntry = { model: Instance, primary: BasePart, slotIdx: number }
local activeVisual: { [Player]: { [string]: VisEntry } } = {}

-- ── Helpery ───────────────────────────────────────────────────────────────

local function rarityCfg(rarity: string)
	return cfg.Rarities[rarity]
end
local function classCfg(class: string)
	return cfg.Classes[class]
end

local function listRaritiesOrdered(): { string }
	local arr = {}
	for k in pairs(cfg.Rarities) do table.insert(arr, k) end
	table.sort(arr, function(a, b) return cfg.Rarities[a].order < cfg.Rarities[b].order end)
	return arr
end

local function newPet(rarity: string, class: string)
	return {
		id     = HttpService:GenerateGUID(false),
		rarity = rarity,
		class  = class,
	}
end

-- Weighted random po nazwach z tabeli {key = weight, ...}
local function weightedPick(weights: { [string]: number }): string?
	local total = 0
	for _, w in pairs(weights) do total += w end
	if total <= 0 then return nil end
	local roll, cum = math.random() * total, 0
	for k, w in pairs(weights) do
		cum += w
		if roll <= cum then return k end
	end
	-- fallback
	local last
	for k in pairs(weights) do last = k end
	return last
end

local function rollRarity(): string
	local weights = {}
	for k, v in pairs(cfg.Rarities) do weights[k] = v.weight end
	return weightedPick(weights) or "Common"
end

local function rollClass(): string
	return weightedPick(cfg.ClassWeights) or "Sprinter"
end

-- ── Carry capacity (pety zajmują slot pojemności) ───────────────────────────
-- Inny serwis (BottleService/SyrupService/MagnetService/ZabkaService) liczy
-- carried sumując: bottles + (syrup ? 1 : 0) + magnetCount + #Pets.
-- Tutaj ekspozujemy helper dla PetService.OpenEgg.
local function countCarried(data): number
	local n = 0
	for _, c in pairs(data.BackpackContents) do n += c end
	if data.Grandpa and data.Grandpa.hasSyrup then n += 1 end
	n += data.MagnetCount or 0
	n += #(data.Pets or {})
	return n
end

local function getCapacity(data): number
	return Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity
end

-- ── Bonus accessors (używane przez BottleService/SprintController/DeskaService) ─
-- Zwracają 0/1 jeśli nic nie wyposażone — nigdy nie crashują na pustym data.

-- Lista wyposażonych petów (rozwiązuje UUID-y w listę pet-tabel z data.Pets).
-- Idempotent: ignoruje UUID-y które już nie istnieją (np. po wyrzuceniu).
local function getEquippedPets(data): { any }
	local out = {}
	if not data then return out end
	local ids = data.EquippedPets or {}
	if #ids == 0 then return out end
	local byId: { [string]: any } = {}
	for _, p in ipairs(data.Pets or {}) do byId[p.id] = p end
	for _, id in ipairs(ids) do
		local p = byId[id]
		if p then table.insert(out, p) end
	end
	return out
end

-- Legacy single — pierwszy z listy (dla kodu który jeszcze nie wie o N petach).
local function findEquippedPet(data)
	local list = getEquippedPets(data)
	return list[1]
end

-- Helper: jest petId w EquippedPets?
local function isEquipped(data, petId: string): boolean
	for _, id in ipairs(data.EquippedPets or {}) do
		if id == petId then return true end
	end
	return false
end

-- Helper: usuń petId z EquippedPets (modyfikuje listę w miejscu).
local function unequipById(data, petId: string)
	local ids = data.EquippedPets or {}
	for i = #ids, 1, -1 do
		if ids[i] == petId then table.remove(ids, i) end
	end
	-- Sync legacy field żeby stary kod (jeśli gdzieś jeszcze został) widział pierwszy
	data.EquippedPet = ids[1] or ""
end

-- Helper: dodaj petId do EquippedPets (jeśli jest miejsce i nie ma duplikatu).
-- Zwraca true jeśli equipped, false jeśli max reached lub duplicate.
local function equipById(data, petId: string): boolean
	if isEquipped(data, petId) then return false end
	data.EquippedPets = data.EquippedPets or {}
	local maxN = math.max(1, data.MaxEquippedPets or 1)
	if #data.EquippedPets >= maxN then return false end
	table.insert(data.EquippedPets, petId)
	data.EquippedPet = data.EquippedPets[1] or ""
	return true
end

-- Mnożnik gold peta (+15% do statystyk). Zwykły pet → 1.
local function goldMul(pet): number
	if pet and pet.gold then
		return (cfg.GoldUpgrade and cfg.GoldUpgrade.StatMultiplier) or 1
	end
	return 1
end

-- Bonusy sumują się z wszystkich wyposażonych petów.
-- Money: multiplikatywnie (np. 1.3 × 1.5 = 1.95). Speed/HP: addytywnie.
function PetService.GetMoneyMul(player: Player): number
	if not player or not player.Parent then return 1 end
	local data = PlayerDataService.GetData(player)
	local mul = 1
	for _, p in ipairs(getEquippedPets(data)) do
		local rcfg = rarityCfg(p.rarity)
		mul = mul * (((rcfg and rcfg.moneyMul) or 1) * goldMul(p))
	end
	return mul
end

function PetService.GetSpeedBonus(player: Player): number
	if not player or not player.Parent then return 0 end
	local data = PlayerDataService.GetData(player)
	local total = 0
	for _, p in ipairs(getEquippedPets(data)) do
		local ccfg = classCfg(p.class)
		if ccfg and ccfg.effect == "speed" then
			total = total + math.floor(((ccfg.bonuses[p.rarity]) or 0) * goldMul(p) + 0.5)
		end
	end
	return total
end

function PetService.GetHpBonus(player: Player): number
	if not player or not player.Parent then return 0 end
	local data = PlayerDataService.GetData(player)
	local total = 0
	for _, p in ipairs(getEquippedPets(data)) do
		local ccfg = classCfg(p.class)
		if ccfg and ccfg.effect == "hp" then
			total = total + math.floor(((ccfg.bonuses[p.rarity]) or 0) * goldMul(p) + 0.5)
		end
	end
	return total
end

-- ── Visual pet (server-side spawn, wszyscy widzą) ──────────────────────────
local PET_FOLLOW_DIST   = 4.5   -- studs za graczem
local PET_HEIGHT_OFFSET = 2.5   -- studs nad ziemią
local PET_LERP_SPEED    = 8     -- jak szybko pet doganiał gracza (większa = sztywniej)
local PET_BOB_AMP       = 0.35  -- amplituda unoszenia sin (studs)
local PET_BOB_FREQ      = 2.0   -- częstotliwość

local function getActivePetsFolder(): Folder
	local f = workspace:FindFirstChild("ActivePets")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ActivePets"
		f.Parent = workspace
	end
	return f :: Folder
end

local function petModelTemplate(rarity: string, isGold: boolean?): Instance?
	-- Gold pety: ReplicatedStorage.Pets.PetyGold; zwykłe: ReplicatedStorage.Pets.PetyZwykle.
	local segments = isGold and (cfg.GoldModelsFolderPath or { "Pets", "PetyGold" })
		or (cfg.ModelsFolderPath or { "Pets", "PetyZwykle" })
	local name = (cfg.ModelNamePrefix or "Pet") .. rarity
	local folder: Instance? = ReplicatedStorage
	for _, segment in ipairs(segments) do
		folder = folder and folder:FindFirstChild(segment)
	end
	return folder and folder:FindFirstChild(name)
end

-- Despawn ALL visuals for a player (no specific pet).
local function despawnAllVisuals(player: Player)
	local entries = activeVisual[player]
	if not entries then return end
	activeVisual[player] = nil
	for _, v in pairs(entries) do
		if v.model and v.model.Parent then v.model:Destroy() end
	end
end

-- Despawn JEDEN pet visual po petId. Nie używamy w hot-path bardzo często.
local function despawnVisualOne(player: Player, petId: string)
	local entries = activeVisual[player]
	if not entries then return end
	local v = entries[petId]
	if not v then return end
	entries[petId] = nil
	if v.model and v.model.Parent then v.model:Destroy() end
	if next(entries) == nil then activeVisual[player] = nil end
end

local function spawnVisual(player: Player, pet, slotIdx: number)
	-- Idempotent: jeśli już mamy tego peta visual'em — nic
	local entries = activeVisual[player]
	if entries and entries[pet.id] and entries[pet.id].model and entries[pet.id].model.Parent then
		entries[pet.id].slotIdx = slotIdx
		return
	end
	local template = petModelTemplate(pet.rarity, pet.gold == true)
	if not template then
		local fp = (pet.gold and cfg.GoldModelsFolderPath) or cfg.ModelsFolderPath
		warn(string.format("[PetService] Brak modelu peta dla rzadkości '%s' (ReplicatedStorage.%s.%s%s)",
			pet.rarity, table.concat(fp, "."), cfg.ModelNamePrefix or "Pet", pet.rarity))
		return
	end

	local clone
	if template:IsA("Model") or template:IsA("BasePart") then
		clone = template:Clone()
	else
		warn("[PetService] Pet template musi być Model albo BasePart, jest:", template.ClassName)
		return
	end
	clone.Name = "Pet_" .. player.Name

	-- Anchored + bezkolizyjne, żeby nie blokowało gracza
	local primary: BasePart?
	if clone:IsA("Model") then
		primary = clone.PrimaryPart
		if not primary then
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then primary = d :: BasePart; break end
			end
			if primary then clone.PrimaryPart = primary end
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored   = true
				d.CanCollide = false
				d.Massless   = true
				d.CanQuery   = false
				d.CanTouch   = false
			end
		end
	else
		primary = clone :: BasePart
		primary.Anchored   = true
		primary.CanCollide = false
		primary.Massless   = true
		primary.CanQuery   = false
		primary.CanTouch   = false
	end

	if not primary then
		warn("[PetService] Pet template nie ma BasePart")
		clone:Destroy()
		return
	end

	-- Pozycja startowa od razu za graczem (żeby się nie pojawił daleko i nie "doganiał")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if hrp then
		local startPos = hrp.Position - hrp.CFrame.LookVector * PET_FOLLOW_DIST + Vector3.new(0, PET_HEIGHT_OFFSET, 0)
		if clone:IsA("Model") then
			clone:PivotTo(CFrame.new(startPos, hrp.Position))
		else
			primary.CFrame = CFrame.new(startPos, hrp.Position)
		end
	end

	clone.Parent = getActivePetsFolder()
	activeVisual[player] = activeVisual[player] or {}
	activeVisual[player][pet.id] = { model = clone, primary = primary, slotIdx = slotIdx }
end

-- Sync wszystkich wizualnych petów do stanu data.EquippedPets.
-- Usuwa visuals nieobecnych w liście, spawnuje brakujących.
local function syncVisual(player: Player)
	local data = PlayerDataService.GetData(player)
	local equippedList = getEquippedPets(data)

	local entries = activeVisual[player] or {}
	local wanted: { [string]: boolean } = {}
	for i, p in ipairs(equippedList) do
		wanted[p.id] = true
		if not (entries[p.id] and entries[p.id].model and entries[p.id].model.Parent) then
			spawnVisual(player, p, i)
		else
			entries[p.id].slotIdx = i
		end
	end
	-- Despawn tych których już nie ma na liście
	for petId in pairs(entries) do
		if not wanted[petId] then despawnVisualOne(player, petId) end
	end
end
PetService.SyncVisual = syncVisual

-- Heartbeat follow — dla każdego gracza iterujemy WSZYSTKIE jego pety.
-- Pety rozłożone po obwodzie kątowym za graczem (slot 1 = lewo, slot 2 = prawo).
local PET_SIDE_SPREAD = 1.6  -- studs ofset lateralny dla 2+ petów

RunService.Heartbeat:Connect(function(dt)
	for player, entries in pairs(activeVisual) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not hrp then continue end
		for _, v in pairs(entries) do
			if not v.primary or not v.primary.Parent then continue end
			local lookFlat = hrp.CFrame.LookVector
			lookFlat = Vector3.new(lookFlat.X, 0, lookFlat.Z)
			if lookFlat.Magnitude < 0.01 then lookFlat = Vector3.new(0, 0, -1) end
			lookFlat = lookFlat.Unit
			-- Lateral offset: slot 1 → -spread, slot 2 → +spread (jeśli max=1, lateral=0)
			local rightVec = Vector3.new(-lookFlat.Z, 0, lookFlat.X)  -- 90° CCW od look (planar)
			local slot = v.slotIdx or 1
			local lateral = 0
			-- Liczba petów u tego gracza (potrzebne do równomiernego rozłożenia)
			local n = 0
			for _ in pairs(entries) do n += 1 end
			if n > 1 then
				-- Slot 1 → lewo (-), slot 2 → prawo (+), slot 3 → 2× lewo, slot 4 → 2× prawo, ...
				local sign = (slot % 2 == 1) and -1 or 1
				local mag  = math.ceil(slot / 2)
				lateral = sign * PET_SIDE_SPREAD * mag
			end
			local bob = math.sin(os.clock() * PET_BOB_FREQ + slot * 0.7) * PET_BOB_AMP
			local targetPos = hrp.Position - lookFlat * PET_FOLLOW_DIST
				+ rightVec * lateral
				+ Vector3.new(0, PET_HEIGHT_OFFSET + bob, 0)

			local alpha = math.min(1, PET_LERP_SPEED * dt)
			local curPos = v.primary.Position
			local newPos = curPos:Lerp(targetPos, alpha)
			local newCFrame = CFrame.new(newPos, hrp.Position)

			if v.model:IsA("Model") then
				v.model:PivotTo(newCFrame)
			else
				v.primary.CFrame = newCFrame
			end
		end
	end
end)

-- ── Apply pet effects on character (HP) ─────────────────────────────────────
-- HP boost wymaga zmiany MaxHealth — wywoływane na każdym CharacterAdded.
-- Speed/Money rezolwują się dynamicznie w hot pathach (Sprint/EmptyBackpack).
local function applyPetEffects(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Base 100 (Roblox default) + bonus z czapki + bonus z peta TANK
	local hatBonus = (Config.HatShop and Config.HatShop.HpBonus) or 0
	local data = PlayerDataService.GetData(player)
	local petHp = 0
	if data.HatOwned then hum.MaxHealth = 100 + hatBonus else hum.MaxHealth = 100 end
	petHp = PetService.GetHpBonus(player)
	hum.MaxHealth = hum.MaxHealth + petHp
	-- Heal up jeśli pet dodał bufor (tak żeby gracz odczuł nowy max)
	if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
end
PetService.ApplyPetEffects = applyPetEffects

-- ── Status broadcast (klient renderuje EQ/HUD/Sprint na podstawie tego) ─────
function PetService.PushStatus(player: Player)
	if not player or not player.Parent then return end
	local data = PlayerDataService.GetData(player)
	PetStatusUpdate:FireClient(player, {
		pets        = data.Pets or {},
		equippedId  = data.EquippedPet or "",          -- legacy: pierwszy z listy
		equippedIds = data.EquippedPets or {},          -- nowe pole: lista wyposażonych
		maxEquipped = data.MaxEquippedPets or 1,        -- ile slotów (1 albo 2)
		bankPets    = data.BankPets or {},
		hasGamepass = gamepassCache[player] == true,
		bonuses     = {
			moneyMul = PetService.GetMoneyMul(player),
			speed    = PetService.GetSpeedBonus(player),
			hp       = PetService.GetHpBonus(player),
		},
	})
end

-- ── HUD sync (capacity zmienia się gdy dodaje/usuwa peta) ─────────────────
local function pushHud(player: Player)
	local data = PlayerDataService.GetData(player)
	local cap  = getCapacity(data)
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = cap,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
		magnetCount      = data.MagnetCount or 0,
	})
end
PetService.PushHud = pushHud

-- ── Gamepass check ─────────────────────────────────────────────────────────
local function checkGamepass(player: Player): boolean
	if gamepassCache[player] ~= nil then return gamepassCache[player] end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, cfg.TripleEggGamepassId)
	end)
	local res = ok and owns == true
	gamepassCache[player] = res
	return res
end

-- Public: reset gamepass cache w obrębie sesji (admin override do testów).
-- UWAGA: Roblox-side gamepass NIE jest revokowany — przy następnym join `checkGamepass`
-- znowu wykryje. To tylko dla testów flow zakupu w bieżącej sesji.
function PetService.SetGamepassCache(player: Player, value: boolean)
	gamepassCache[player] = value
	PetService.PushStatus(player)
end

-- Listen for live purchase (gdy gracz kupi gamepass w trakcie sesji)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gpId: number, purchased: boolean)
	if gpId ~= cfg.TripleEggGamepassId then return end
	if purchased then
		gamepassCache[player] = true
		PetService.PushStatus(player)
	end
end)

-- ── OpenEgg (główna mechanika) ─────────────────────────────────────────────
-- Walidacje:
--   1. count == 1 albo (count == 3 AND gamepass)
--   2. anty-spam cooldown OpenCooldownSec
--   3. starcza kasa (count * SingleEggCost lub TripleEggCost)
--   4. wolne sloty w plecaku (carried + count <= capacity)
-- Drop: dla każdego jajka — rollRarity + rollClass → nowy pet z UUID → push do data.Pets.
function PetService.OpenEgg(player: Player, count: number): { any }?
	if not player or not player.Parent then return nil end
	if count ~= 1 and count ~= 3 then return nil end

	-- Anty-spam
	local now = os.clock()
	if (lastOpenAt[player] or 0) + (cfg.OpenCooldownSec or 1) > now then
		return nil
	end

	-- Dystans od Gabloty (anti-exploit: gracz musi stać przy gablocie)
	if not isNearGablota(player) then
		PetRouletteResult:FireClient(player, { success = false, reason = "tooFar" })
		return nil
	end

	-- 3-jajka wymaga gamepassa
	if count == 3 and not checkGamepass(player) then
		PromptPetGamepassBuy:FireClient(player, { gamepassId = cfg.TripleEggGamepassId })
		return nil
	end

	local data = PlayerDataService.GetData(player)
	local cost = (count == 3) and cfg.TripleEggCost or (cfg.SingleEggCost * count)

	if (data.Zlotowki or 0) < cost then
		PetRouletteResult:FireClient(player, { success = false, reason = "broke" })
		return nil
	end

	-- Limit per-kategoria: pety mogą zająć max 20% pojemności plecaka.
	local capacity = getCapacity(data)
	local caps     = Util.getCategoryCaps(capacity, Config.BackpackCategorySplit)
	if Util.getPetCount(data) + count > caps.pets then
		PetRouletteResult:FireClient(player, { success = false, reason = "full" })
		return nil
	end

	-- Wszystko OK — deductuj, dropuj, push.
	lastOpenAt[player] = now
	data.Zlotowki -= cost
	data.StatEggsOpened = (data.StatEggsOpened or 0) + count  -- panel STATS
	PlayerDataService.UpdateLeaderstats(player)
	data.Pets = data.Pets or {}

	local drops = {}
	for _ = 1, count do
		local pet = newPet(rollRarity(), rollClass())
		table.insert(data.Pets, pet)
		table.insert(drops, pet)
	end

	-- NIE SaveData w hot path — yielduje 1-2s. Auto-save 60s + PlayerRemoving wystarczy.
	pushHud(player)
	PetService.PushStatus(player)
	PetRouletteResult:FireClient(player, { success = true, pets = drops })

	-- Story quest hooki: kupno jajka + wylosowanie peta danej rzadkości
	pcall(function()
		local sqs = require(script.Parent.StoryQuestService)
		sqs.AddProgress(player, "buy_egg", count)
		for _, pet in ipairs(drops) do
			sqs.AddProgress(player, "pet_rarity", 1, { rarity = pet.rarity })
		end
	end)
	return drops
end

BuyEggOpen.OnServerEvent:Connect(function(player: Player, payload)
	if type(payload) ~= "table" then return end
	local count = tonumber(payload.count) or 0
	PetService.OpenEgg(player, count)
end)

-- ── Equip / Unequip / Discard ──────────────────────────────────────────────
local function petIndex(pets, id: string): number?
	for i, p in ipairs(pets) do if p.id == id then return i end end
	return nil
end

EquipPet.OnServerEvent:Connect(function(player: Player, petId: any)
	if type(petId) ~= "string" then return end
	local now = os.clock()
	if lastPetActionAt[player] and now - lastPetActionAt[player] < PET_ACTION_THROTTLE then return end
	lastPetActionAt[player] = now
	local data = PlayerDataService.GetData(player)
	if not petIndex(data.Pets or {}, petId) then return end
	-- Toggle: jeśli już wyposażony → zdejmij. Inaczej dodaj jeśli jest slot.
	if isEquipped(data, petId) then
		unequipById(data, petId)
	else
		if not equipById(data, petId) then return end  -- max reached
	end
	PetService.PushStatus(player)
	applyPetEffects(player)
	syncVisual(player)
	pcall(function()
		require(script.Parent.StoryQuestService).AddProgress(player, "equip_pet", 1)
	end)
end)

UnequipPet.OnServerEvent:Connect(function(player: Player, petId: any)
	local now = os.clock()
	if lastPetActionAt[player] and now - lastPetActionAt[player] < PET_ACTION_THROTTLE then return end
	lastPetActionAt[player] = now
	local data = PlayerDataService.GetData(player)
	-- Z petId: zdejmij konkretnego. Bez petId (legacy/zdejmij-wszystko): wyczyść listę.
	if type(petId) == "string" and petId ~= "" then
		unequipById(data, petId)
	else
		data.EquippedPets = {}
		data.EquippedPet = ""
	end
	PetService.PushStatus(player)
	applyPetEffects(player)
	syncVisual(player)
end)

DiscardPet.OnServerEvent:Connect(function(player: Player, petId: any)
	if type(petId) ~= "string" then return end
	if player:GetAttribute("InPvPZone") == true then return end
	local now = os.clock()
	if lastPetActionAt[player] and now - lastPetActionAt[player] < PET_ACTION_THROTTLE then return end
	lastPetActionAt[player] = now
	local data = PlayerDataService.GetData(player)
	local idx = petIndex(data.Pets or {}, petId)
	if not idx then return end
	unequipById(data, petId)
	table.remove(data.Pets, idx)
	pushHud(player)
	PetService.PushStatus(player)
	applyPetEffects(player)
	syncVisual(player)
end)

-- ── Gablota: ProximityPrompt na workspace.Pets.GablotyPetow.Gablota ────────
local findAnchor = Util.findAnchor

task.spawn(function()
	print("[PetService] === diagnostyka gabloty ===")
	local petsFolder = workspace:WaitForChild("Pets", 30)
	if not petsFolder then warn("[PetService] Brak workspace.Pets") return end

	local gabloty = petsFolder:WaitForChild("GablotyPetow", 10)
	if not gabloty then warn("[PetService] Brak workspace.Pets.GablotyPetow") return end

	local gablota = gabloty:WaitForChild("Gablota", 10)
	if not gablota then warn("[PetService] Brak workspace.Pets.GablotyPetow.Gablota") return end

	-- Anchor: priorytetowo Part nazwany "Proximity" (case-insensitive) wewnątrz Gabloty.
	-- Fallback: standardowy findAnchor (Head/HRP/PrimaryPart/dowolny BasePart).
	local anchor: BasePart? = nil
	if gablota:IsA("Model") then
		for _, d in ipairs(gablota:GetDescendants()) do
			if d:IsA("BasePart") and string.lower(d.Name) == "proximity" then
				anchor = d :: BasePart
				break
			end
		end
	end
	if not anchor then anchor = findAnchor(gablota) end
	if not anchor then warn("[PetService] Gablota nie ma żadnego BasePart (ani Part 'Proximity')") return end
	petGablotaAnchor = anchor  -- cache do walidacji dystansu w BuyEggOpen

	for _, c in ipairs(gablota:GetDescendants()) do
		if c:IsA("ProximityPrompt") then c:Destroy() end
	end
	local existing = anchor:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	-- DWA prompty na gablocie: E = 1 jajko, T = 3 jajka. Custom Style — klient renderuje UI.
	-- Tag attribute `PetGablotaPrompt` z metadata żeby klient wiedział co stylizować.
	local promptSingle = Instance.new("ProximityPrompt")
	promptSingle.ActionText            = "Otwórz 1 jajko"
	promptSingle.ObjectText            = string.format("%d zł", cfg.SingleEggCost)
	promptSingle.KeyboardKeyCode       = Enum.KeyCode.E
	promptSingle.GamepadKeyCode        = Enum.KeyCode.ButtonX
	promptSingle.MaxActivationDistance = 10
	promptSingle.HoldDuration          = 0
	promptSingle.RequiresLineOfSight   = false
	promptSingle.Style                 = Enum.ProximityPromptStyle.Custom  -- klient buduje UI
	promptSingle.UIOffset              = Vector2.new(0, -60)
	promptSingle:SetAttribute("PetGablotaPrompt", "single")
	promptSingle:SetAttribute("Cost", cfg.SingleEggCost)
	promptSingle.Parent                = anchor

	promptSingle.Triggered:Connect(function(player: Player)
		PetService.OpenEgg(player, 1)
	end)

	local promptTriple = Instance.new("ProximityPrompt")
	promptTriple.ActionText            = "Otwórz 3 jajka"
	promptTriple.ObjectText            = string.format("%d zł (Gamepass)", cfg.TripleEggCost)
	promptTriple.KeyboardKeyCode       = Enum.KeyCode.T
	promptTriple.GamepadKeyCode        = Enum.KeyCode.ButtonY
	promptTriple.MaxActivationDistance = 10
	promptTriple.HoldDuration          = 0
	promptTriple.RequiresLineOfSight   = false
	promptTriple.Style                 = Enum.ProximityPromptStyle.Custom
	promptTriple.UIOffset              = Vector2.new(0, 60)
	promptTriple:SetAttribute("PetGablotaPrompt", "triple")
	promptTriple:SetAttribute("Cost", cfg.TripleEggCost)
	promptTriple.Parent                = anchor

	promptTriple.Triggered:Connect(function(player: Player)
		PetService.OpenEgg(player, 3)
	end)

	print(string.format("[PetService] Gablota gotowa → %s (anchor=%s) — E: 1 jajko, T: 3 jajka",
		gablota:GetFullName(), anchor.Name))
end)

-- ── Lifecycle ──────────────────────────────────────────────────────────────
local function onCharacter(player: Player, character: Model)
	character:WaitForChild("Humanoid", 5)
	task.wait(0.2)
	applyPetEffects(player)
	-- Po respawnie wskrzeszamy wizualnego peta
	syncVisual(player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		PlayerDataService.GetData(player)
		-- Sprawdź gamepass raz w tle
		checkGamepass(player)
		task.wait(2)
		if player.Parent then
			PetService.PushStatus(player)
			if player.Character then onCharacter(player, player.Character) end
			syncVisual(player)  -- jeśli gracz miał equipped peta przy join
		end
	end)
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
end)

Players.PlayerRemoving:Connect(function(p)
	despawnAllVisuals(p)
	gamepassCache[p]   = nil
	lastOpenAt[p]      = nil
	lastPetActionAt[p] = nil
end)

-- ── BindableEvent ForceDespawnPet (PvPService fire'uje gdy gracz wejdzie w PVPZone/SAFEZONE) ──
-- Sam tworzymy event jeśli nie istnieje. Tylko despawn wizualnego — efekty (HP/speed/money) trwają.
local forceDespawnPetEvent = ServerScriptService:FindFirstChild("ForceDespawnPetEvent")
if not forceDespawnPetEvent then
	forceDespawnPetEvent = Instance.new("BindableEvent")
	forceDespawnPetEvent.Name = "ForceDespawnPetEvent"
	forceDespawnPetEvent.Parent = ServerScriptService
end
forceDespawnPetEvent.Event:Connect(function(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	despawnAllVisuals(player)  -- idempotentne
end)

-- Po wyjściu z PVP/SAFEZONE pet wraca — sprawdzamy w Heartbeat (co 0.5s żeby nie spamować).
-- Inaczej trzeba by trzymać "exited PVP" event w PvPService.
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Parent then
				local data = PlayerDataService.GetData(player)
				if (data.EquippedPets and #data.EquippedPets > 0) and not activeVisual[player] then
					-- Sprawdź czy gracz NIE jest w strefie (raycast/bbox check w prostym wykonaniu)
					local char = player.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
					if hrp then
						local pos = hrp.Position
						local inZone = false
						for _, name in ipairs({ "PVPZone", "SAFEZONE" }) do
							local zone = workspace:FindFirstChild(name, true)
							if zone and zone:IsA("BasePart") then
								local local_ = zone.CFrame:PointToObjectSpace(pos)
								local half = zone.Size / 2
								if  math.abs(local_.X) <= half.X
								and math.abs(local_.Y) <= half.Y
								and math.abs(local_.Z) <= half.Z then
									inZone = true; break
								end
							end
						end
						if not inZone then
							syncVisual(player)  -- respawn wizualny
						end
					end
				end
			end
		end
	end
end)

for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
	if p.Character then task.spawn(onCharacter, p, p.Character) end
end

print("[PetService] gotowy — rarities:", table.concat(listRaritiesOrdered(), ", "))

return PetService
