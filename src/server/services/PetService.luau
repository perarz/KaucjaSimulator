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
-- Aktywne wizualne pety (server spawnuje, wszyscy widzą)
local activeVisual: { [Player]: { model: Model, primary: BasePart, equippedId: string } } = {}

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

local function findEquippedPet(data)
	local id = data.EquippedPet
	if not id or id == "" then return nil end
	for _, p in ipairs(data.Pets or {}) do
		if p.id == id then return p end
	end
	return nil
end

function PetService.GetMoneyMul(player: Player): number
	if not player or not player.Parent then return 1 end
	local data = PlayerDataService.GetData(player)
	local p = findEquippedPet(data)
	if not p then return 1 end
	local rcfg = rarityCfg(p.rarity)
	return (rcfg and rcfg.moneyMul) or 1
end

function PetService.GetSpeedBonus(player: Player): number
	if not player or not player.Parent then return 0 end
	local data = PlayerDataService.GetData(player)
	local p = findEquippedPet(data)
	if not p then return 0 end
	local ccfg = classCfg(p.class)
	if not ccfg or ccfg.effect ~= "speed" then return 0 end
	return (ccfg.bonuses[p.rarity]) or 0
end

function PetService.GetHpBonus(player: Player): number
	if not player or not player.Parent then return 0 end
	local data = PlayerDataService.GetData(player)
	local p = findEquippedPet(data)
	if not p then return 0 end
	local ccfg = classCfg(p.class)
	if not ccfg or ccfg.effect ~= "hp" then return 0 end
	return (ccfg.bonuses[p.rarity]) or 0
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

local function petModelTemplate(rarity: string): Instance?
	local folder: Instance = ReplicatedStorage
	for _, segment in ipairs(cfg.ModelsFolderPath) do
		folder = folder:FindFirstChild(segment)
		if not folder then return nil end
	end
	return folder:FindFirstChild((cfg.ModelNamePrefix or "Pet") .. rarity)
end

local function despawnVisual(player: Player)
	local v = activeVisual[player]
	if not v then return end
	activeVisual[player] = nil
	if v.model and v.model.Parent then v.model:Destroy() end
end

local function spawnVisual(player: Player, pet)
	despawnVisual(player)  -- na wszelki wypadek
	local template = petModelTemplate(pet.rarity)
	if not template then
		warn(string.format("[PetService] Brak modelu peta dla rzadkości '%s' (ReplicatedStorage.%s.%s%s)",
			pet.rarity, table.concat(cfg.ModelsFolderPath, "."), cfg.ModelNamePrefix or "Pet", pet.rarity))
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
	activeVisual[player] = { model = clone, primary = primary, equippedId = pet.id }
end

-- Sync wizualnego peta ze stanem (called po każdej zmianie equipped)
local function syncVisual(player: Player)
	local data = PlayerDataService.GetData(player)
	local equipped = findEquippedPet(data)
	local cur = activeVisual[player]

	if not equipped then
		despawnVisual(player)
		return
	end
	-- Jeśli już wyświetlamy tego samego peta — nic
	if cur and cur.equippedId == equipped.id and cur.model and cur.model.Parent then
		return
	end
	-- Inaczej spawn (despawn old jest w spawnVisual)
	spawnVisual(player, equipped)
end
PetService.SyncVisual = syncVisual

-- Heartbeat follow — wszyscy gracze, lerp pozycji do za graczem + bobbing.
RunService.Heartbeat:Connect(function(dt)
	for player, v in pairs(activeVisual) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not hrp or not v.primary or not v.primary.Parent then
			continue
		end
		local lookFlat = hrp.CFrame.LookVector
		lookFlat = Vector3.new(lookFlat.X, 0, lookFlat.Z)
		if lookFlat.Magnitude < 0.01 then lookFlat = Vector3.new(0, 0, -1) end
		lookFlat = lookFlat.Unit
		local bob = math.sin(os.clock() * PET_BOB_FREQ) * PET_BOB_AMP
		local targetPos = hrp.Position - lookFlat * PET_FOLLOW_DIST
			+ Vector3.new(0, PET_HEIGHT_OFFSET + bob, 0)

		-- Lerp z dt (frame-rate independent)
		local alpha = math.min(1, PET_LERP_SPEED * dt)
		local curPos = v.primary.Position
		local newPos = curPos:Lerp(targetPos, alpha)
		-- Patrz na gracza
		local newCFrame = CFrame.new(newPos, hrp.Position)

		if v.model:IsA("Model") then
			v.model:PivotTo(newCFrame)
		else
			v.primary.CFrame = newCFrame
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
		equippedId  = data.EquippedPet or "",
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

	local capacity = getCapacity(data)
	if countCarried(data) + count > capacity then
		PetRouletteResult:FireClient(player, { success = false, reason = "full" })
		return nil
	end

	-- Wszystko OK — deductuj, dropuj, push.
	lastOpenAt[player] = now
	data.Zlotowki -= cost
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
	local data = PlayerDataService.GetData(player)
	if not petIndex(data.Pets or {}, petId) then return end
	data.EquippedPet = petId
	PetService.PushStatus(player)
	applyPetEffects(player)
	syncVisual(player)
	-- Story quest hook: założenie peta
	pcall(function()
		require(script.Parent.StoryQuestService).AddProgress(player, "equip_pet", 1)
	end)
end)

UnequipPet.OnServerEvent:Connect(function(player: Player)
	local data = PlayerDataService.GetData(player)
	data.EquippedPet = ""
	PetService.PushStatus(player)
	applyPetEffects(player)
	syncVisual(player)
end)

DiscardPet.OnServerEvent:Connect(function(player: Player, petId: any)
	if type(petId) ~= "string" then return end
	-- Zakaz wyrzucania itemów (petów) w strefie PvP
	if player:GetAttribute("InPvPZone") == true then return end
	local data = PlayerDataService.GetData(player)
	local idx = petIndex(data.Pets or {}, petId)
	if not idx then return end
	if data.EquippedPet == petId then
		data.EquippedPet = ""
	end
	table.remove(data.Pets, idx)
	pushHud(player)
	PetService.PushStatus(player)
	applyPetEffects(player)
	syncVisual(player)
end)

-- ── Gablota: ProximityPrompt na workspace.Pets.GablotyPetow.Gablota ────────
local function findAnchor(model: Instance): BasePart?
	if model:IsA("BasePart") then return model :: BasePart end
	if not model:IsA("Model") then return nil end
	for _, name in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "Torso" }) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p :: BasePart end
	end
	if (model :: Model).PrimaryPart then return (model :: Model).PrimaryPart end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

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
	despawnVisual(p)
	gamepassCache[p] = nil
	lastOpenAt[p]    = nil
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
	despawnVisual(player)  -- idempotentne
end)

-- Po wyjściu z PVP/SAFEZONE pet wraca — sprawdzamy w Heartbeat (co 0.5s żeby nie spamować).
-- Inaczej trzeba by trzymać "exited PVP" event w PvPService.
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Parent then
				local data = PlayerDataService.GetData(player)
				if data.EquippedPet ~= "" and not activeVisual[player] then
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
