-- BottleService.luau
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local Config              = require(ReplicatedStorage.Config)
local Util                = require(ReplicatedStorage:WaitForChild("Util"))
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataService   = require(ServerScriptService.PlayerDataService)
local QuestService        = require(ServerScriptService.QuestService)

local BUTELKOMAT_TAG = "Butelkomat"

local BottleService = {}

-- RemoteEvents
local Events              = ReplicatedStorage:WaitForChild("Events")
local CollectBottle       = Events:WaitForChild("CollectBottle")
local CollectBottleResult = Events:WaitForChild("CollectBottleResult")
local DropBottle          = Events:WaitForChild("DropBottle")
local EmptyBackpack       = Events:WaitForChild("EmptyBackpack")
local EmptyBackpackResult = Events:WaitForChild("EmptyBackpackResult")
local LegendaryEventStart = Events:WaitForChild("LegendaryEventStart")
local LegendaryEventEnd   = Events:WaitForChild("LegendaryEventEnd")

-- Flaga eventu — pętla respawn i jednorazowe spawny ją respektują
local legendaryEventActive = false

-- ── Rate limit (per-player) + dystans do butelkomatu ──────────────────────────
local lastCollectAt: { [Player]: number } = {}
local lastEmptyAt:   { [Player]: number } = {}
local lastDropAt:    { [Player]: number } = {}
local COLLECT_THROTTLE = 0.05  -- 20 Hz max — chroni przed spamem, nie blokuje magnesu/normalnego pickup
local EMPTY_THROTTLE   = 0.5
local DROP_THROTTLE    = 0.2
local BUTELKOMAT_MAX_DIST = 15  -- studs, ile od najbliższego tagged Butelkomat
local function isNearButelkomat(hrp: BasePart): boolean
	for _, part in ipairs(CollectionService:GetTagged(BUTELKOMAT_TAG)) do
		if part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= BUTELKOMAT_MAX_DIST then
			return true
		end
	end
	return false
end

Players.PlayerRemoving:Connect(function(p: Player)
	lastCollectAt[p] = nil
	lastEmptyAt[p]   = nil
	lastDropAt[p]    = nil
end)

-- Workspace foldery
local bottlesFolder:      Folder
local spawnPointsFolder:  Folder
local spawnAreasFolder:   Folder?    -- opcjonalne: BottleSpawnAreas (Partsy = obszary)

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

local function setupSpawnPoints()
	spawnPointsFolder = workspace:FindFirstChild("BottleSpawnPoints") :: Folder
end

-- Dodaje ProximityPrompt i tag CollectionService do danej części.
-- MaxActivationDistance 14 (było 8) + UIOffset.Y = -100 — żeby przy crowdzie 40+ graczy
-- nie trzeba było wciskać się w tłum i prompt UI nie ginął za głowami innych.
local function tagAsButelkomat(part: BasePart, objectText: string)
	if not part:FindFirstChildOfClass("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText            = "Oddaj butelki"
		prompt.ObjectText            = objectText
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration          = 0
		prompt.RequiresLineOfSight   = false
		prompt.UIOffset              = Vector2.new(0, -100)
		prompt.Parent                = part
	end
	CollectionService:AddTag(part, BUTELKOMAT_TAG)
end

local function setupButelkomaty()
	local butelkomatyFolder = workspace:FindFirstChild("Butelkomaty")
	if not butelkomatyFolder then return end
	for _, child in ipairs(butelkomatyFolder:GetChildren()) do
		if child:IsA("BasePart") then
			tagAsButelkomat(child :: BasePart, "Butelkomat")
		end
	end
end

-- Taguje BlackPanel (lub PrimaryPart/dowolny BasePart fallback) w jednym modelu AutomatKaucyjny.
local function setupOneAutomat(model: Instance)
	if not model:IsA("Model") then return end
	-- Preferowany target: model.BlackPanel (oryginalny design — prompt siedzi na czarnym panelu).
	-- Fallback: PrimaryPart, potem dowolny BasePart — żeby duplikaty zachowane bez BlackPanel
	-- nadal dostały prompt.
	local target: BasePart? = nil
	local bp = model:FindFirstChild("BlackPanel")
	if bp and bp:IsA("BasePart") then
		target = bp :: BasePart
	else
		target = (model :: Model).PrimaryPart
		if not target then
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then target = desc :: BasePart; break end
			end
		end
	end
	if not target then
		warn("[BottleService] AutomatKaucyjny", model:GetFullName(), "nie ma żadnego BasePart — pominięty")
		return
	end
	tagAsButelkomat(target, "Automat Kaucyjny")
	print("[BottleService] AutomatKaucyjny gotowy →", target:GetFullName())
end

-- Obsługuje DOWOLNĄ liczbę modeli AutomatKaucyjny w workspace (zarówno duplikaty o tej
-- samej nazwie jak i z suffix'em "AutomatKaucyjny2", "AutomatKaucyjny_3"). ChildAdded
-- pokrywa dynamiczne klonowanie podczas runtime.
local automatHooked = false
local function setupAutomatKaucyjny()
	if automatHooked then return end
	automatHooked = true
	local function matches(name: string): boolean
		return string.match(name, "^AutomatKaucyjny") ~= nil
	end
	local found = 0
	for _, child in ipairs(workspace:GetChildren()) do
		if matches(child.Name) then
			setupOneAutomat(child)
			found += 1
		end
	end
	if found == 0 then
		warn("[BottleService] Nie znaleziono żadnego AutomatKaucyjny w workspace")
	else
		print(string.format("[BottleService] Zarejestrowano %d automat(ów) kaucyjnych", found))
	end
	-- Późne dodawanie (np. clone w Studio podczas play, procedural spawn) — przechwytuj.
	workspace.ChildAdded:Connect(function(child)
		if matches(child.Name) then
			task.wait(0.1)  -- daj klatkę żeby BlackPanel/PrimaryPart się dociągnęły
			setupOneAutomat(child)
		end
	end)
end

-- Weighted random rzadkość
local rarityOrder = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }

-- Wyciąga tier z nazwy Partu — pierwszy "T<liczba>" jako osobny token (case-insensitive).
-- "T1_centrum" → 1, "Las_T2" → 2, "Centrum" → 1 (default).
local function parseTier(name: string): number
	local n = string.match(name, "[Tt](%d+)")
	if n then
		local v = tonumber(n)
		if v and v >= 1 then return v end
	end
	return 1
end

local function pickRarity(tier: number?): string
	local chanceTable = (tier and Config.BottleSpawnChanceByTier and Config.BottleSpawnChanceByTier[tier])
		or Config.BottleSpawnChance
	local roll = math.random()
	local cumulative = 0
	for _, rarity in ipairs(rarityOrder) do
		cumulative += (chanceTable[rarity] or 0)
		if roll <= cumulative then
			return rarity
		end
	end
	return "Zwykla"
end

-- Folder z modelami butelek (opcjonalny — jeśli brak, fallback na cylinder)
local bottleModelsFolder = ReplicatedStorage:FindFirstChild("BottleModels")

-- Pozycja butelki (Model używa pivota, Part używa Position)
local function getBottlePos(bottle: Instance): Vector3
	if bottle:IsA("Model") then return (bottle :: Model):GetPivot().Position end
	return (bottle :: BasePart).Position
end

local function anchorPartFromBottle(bottle: Instance): BasePart?
	if bottle:IsA("BasePart") then return bottle :: BasePart end
	if bottle:IsA("Model") then
		local pp = (bottle :: Model).PrimaryPart
		if pp then return pp end
		for _, d in ipairs(bottle:GetDescendants()) do
			if d:IsA("BasePart") then return d :: BasePart end
		end
	end
	return nil
end

-- Losowa pozycja na górnej powierzchni dowolnego obszaru (Part z BottleSpawnAreas)
local function getRandomPositionInArea(area: BasePart): Vector3
	local sz = area.Size
	local localX = (math.random() - 0.5) * sz.X
	local localZ = (math.random() - 0.5) * sz.Z
	-- Uwzględnia rotację Partu (CFrame)
	local worldOffset = area.CFrame:VectorToWorldSpace(Vector3.new(localX, sz.Y / 2 + 1, localZ))
	return area.Position + worldOffset
end

-- Czy pozycja jest wystarczająco daleko od istniejących butelek
local MIN_BOTTLE_DIST = 3
local function isPositionFree(pos: Vector3): boolean
	for _, b in ipairs(bottlesFolder:GetChildren()) do
		if (getBottlePos(b) - pos).Magnitude < MIN_BOTTLE_DIST then
			return false
		end
	end
	return true
end

-- ── Per-area density targets ─────────────────────────────────────────────
-- Każdy obszar dostaje cel = round(powierzchnia_XZ * Config.BottleDensity).
-- Suma celów = dynamiczne MaxBottlesOnMap (cap-owane przez MaxBottlesHardCap).
local areaTargets: {[BasePart]: number} = {}
local dynamicMaxBottles = 0

local function recomputeAreaTargets()
	areaTargets = {}
	dynamicMaxBottles = 0
	if not spawnAreasFolder then return end
	for _, c in ipairs(spawnAreasFolder:GetChildren()) do
		if c:IsA("BasePart") then
			local surf   = c.Size.X * c.Size.Z
			local raw    = math.floor(surf * Config.BottleDensity + 0.5)
			local target = math.max(Config.MinBottlesPerArea, raw)
			areaTargets[c] = target
			dynamicMaxBottles += target
		end
	end
	if dynamicMaxBottles > Config.MaxBottlesHardCap then
		-- Skaluj proporcjonalnie wszystkie cele żeby suma = hard cap
		local scale = Config.MaxBottlesHardCap / dynamicMaxBottles
		dynamicMaxBottles = 0
		for area, target in pairs(areaTargets) do
			local scaled = math.max(Config.MinBottlesPerArea, math.floor(target * scale + 0.5))
			areaTargets[area] = scaled
			dynamicMaxBottles += scaled
		end
	end
	print(string.format("[BottleService] Density: %d obszarów, target = %d butelek",
		(function() local n=0; for _ in pairs(areaTargets) do n+=1 end; return n end)(),
		dynamicMaxBottles))
end

-- Czy pozycja należy do obszaru (XZ wewnątrz prostokąta po object-space)
local function isPositionInArea(pos: Vector3, area: BasePart): boolean
	local local_ = area.CFrame:PointToObjectSpace(pos)
	return math.abs(local_.X) <= area.Size.X / 2
		and math.abs(local_.Z) <= area.Size.Z / 2
end

local function countBottlesInArea(area: BasePart): number
	local n = 0
	for _, b in ipairs(bottlesFolder:GetChildren()) do
		if isPositionInArea(getBottlePos(b), area) then
			n += 1
		end
	end
	return n
end

-- Wybiera obszar z deficytem (waga = deficyt), albo nil jeśli wszystkie pełne
local function pickAreaNeedingFill(): BasePart?
	local candidates = {}
	local totalDeficit = 0
	for area, target in pairs(areaTargets) do
		if area.Parent then
			local deficit = target - countBottlesInArea(area)
			if deficit > 0 then
				table.insert(candidates, { area = area, deficit = deficit })
				totalDeficit += deficit
			end
		end
	end
	if #candidates == 0 then return nil end
	local roll, cum = math.random() * totalDeficit, 0
	for _, c in ipairs(candidates) do
		cum += c.deficit
		if roll <= cum then return c.area :: BasePart end
	end
	return candidates[#candidates].area :: BasePart
end

-- Czy tier obszaru pozwala spawnować daną rzadkość (chance > 0).
-- Używane przez EnsureRareBottles żeby nie wymuszać Legendarki w T1.
local function tierAllowsRarity(tier: number, rarity: string): boolean
	local tbl = Config.BottleSpawnChanceByTier and Config.BottleSpawnChanceByTier[tier]
	if not tbl then return true end  -- brak tabeli = fallback, dopuść wszystko
	return (tbl[rarity] or 0) > 0
end

-- Próbkuje losową pozycję — najpierw w obszarze z deficytem, potem dowolnym.
-- Zwraca też tier wybranego obszaru (do ważenia rzadkości).
-- Jeśli `requireRarity` podane, filtruje obszary do tych których tier dopuszcza tę rzadkość.
local function pickPositionFromAreas(requireRarity: string?): (Vector3?, number?)
	if not spawnAreasFolder then return nil, nil end
	local preferred = pickAreaNeedingFill()
	if preferred and (not requireRarity or tierAllowsRarity(parseTier(preferred.Name), requireRarity)) then
		for _ = 1, 12 do
			local pos = getRandomPositionInArea(preferred)
			if isPositionFree(pos) then return pos, parseTier(preferred.Name) end
		end
	end
	-- Fallback: losowy obszar (filtrowany po rzadkości jeśli wymagana)
	local areas = {}
	for _, c in ipairs(spawnAreasFolder:GetChildren()) do
		if c:IsA("BasePart") then
			if not requireRarity or tierAllowsRarity(parseTier(c.Name), requireRarity) then
				table.insert(areas, c)
			end
		end
	end
	if #areas == 0 then return nil, nil end
	for _ = 1, 12 do
		local area = areas[math.random(#areas)] :: BasePart
		local pos = getRandomPositionInArea(area)
		if isPositionFree(pos) then return pos, parseTier(area.Name) end
	end
	return nil, nil
end

local function getFreeSpawnPoint(): BasePart?
	if not spawnPointsFolder then return nil end
	local points = spawnPointsFolder:GetChildren()
	local occupied: { [BasePart]: boolean } = {}

	for _, bottle in ipairs(bottlesFolder:GetChildren()) do
		local bPos = getBottlePos(bottle)
		local closest: BasePart? = nil
		local bestDist = math.huge
		for _, sp in ipairs(points) do
			local dist = (bPos - (sp :: BasePart).Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				closest = sp :: BasePart
			end
		end
		if closest and bestDist < 5 then
			occupied[closest] = true
		end
	end

	local free = {}
	for _, sp in ipairs(points) do
		if not occupied[sp :: BasePart] then
			table.insert(free, sp)
		end
	end

	if #free == 0 then return nil end
	return free[math.random(#free)] :: BasePart
end

function BottleService.SpawnBottle(position: Vector3, forcedRarity: string?, tier: number?, attributes: { [string]: any }?): Instance
	local rarity = forcedRarity or pickRarity(tier)
	-- Szuka modelu: najpierw w BottleModels/<rarity>, potem fallback bezpośrednio w ReplicatedStorage/<rarity>
	-- (Mityczny user wrzucił bezpośrednio w ReplicatedStorage, nie do folderu)
	local template = (bottleModelsFolder and bottleModelsFolder:FindFirstChild(rarity))
		or ReplicatedStorage:FindFirstChild(rarity)

	local bottle: Instance
	local anchorPart: BasePart?

	if template and template:IsA("Model") then
		if not (template :: Model).PrimaryPart then
			warn("[BottleService] Model '" .. rarity .. "' nie ma ustawionego PrimaryPart — pivot i prompt mogą być w złym miejscu")
		end

		-- Klonujemy model dostarczony przez gracza
		local model = template:Clone() :: Model
		model.Name = "Bottle_" .. rarity

		-- Ustaw pivot na podaną pozycję
		-- Losowa rotacja tylko w poziomie (oś Y) — butelka stoi prosto, ale zwrócona losowo
		local randomYaw = math.random() * math.pi * 2
		model:PivotTo(CFrame.new(position) * CFrame.Angles(0, randomYaw, 0))

		-- Anchor + no-collide na wszystkich częściach
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored   = true
				d.CanCollide = false
				d.CastShadow = false
			end
		end

		bottle     = model
		anchorPart = anchorPartFromBottle(model)
	else
		-- Fallback: cylinder z kolorem rzadkości (gdy brak modelu)
		local part = Instance.new("Part")
		part.Name        = "Bottle_" .. rarity
		part.Shape       = Enum.PartType.Cylinder
		part.Size        = Vector3.new(1, 2, 1)
		part.Anchored    = true
		part.CanCollide  = false
		part.Color       = Config.BottleColors[rarity]
		part.CastShadow  = false
		part.CFrame      = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
		bottle           = part
		anchorPart       = part
	end

	-- Metadata na rodzicu (Model lub Part)
	local rarityValue = Instance.new("StringValue")
	rarityValue.Name  = "Rarity"
	rarityValue.Value = rarity
	rarityValue.Parent = bottle

	local collectedValue = Instance.new("BoolValue")
	collectedValue.Name  = "Collected"
	collectedValue.Value = false
	collectedValue.Parent = bottle

	-- ProximityPrompt na głównej części
	if anchorPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText            = "Zbierz"
		prompt.ObjectText            = rarity
		prompt.MaxActivationDistance = 5
		prompt.HoldDuration          = 0
		prompt.RequiresLineOfSight   = false   -- ważne dla modeli butelek: nie chowa się gdy bryła zasłania
		prompt.Parent                = anchorPart

		-- Light dla Epicka/Legendarna/Mityczny
		if rarity == "Epicka" or rarity == "Legendarna" or rarity == "Mityczny" then
			local light = Instance.new("PointLight")
			light.Brightness = 2
			light.Range      = 12
			light.Color      = Config.BottleColors[rarity]
			light.Parent     = anchorPart
		end
	end

	-- Atrybuty ustawione PRZED parent — żeby nie było okna w którym CollectBottle mógłby
	-- chwycić butelkę bez np. DeathDropOwner (race condition)
	if attributes then
		for k, v in pairs(attributes) do bottle:SetAttribute(k, v) end
	end

	bottle.Parent = bottlesFolder
	return bottle
end

local function countRarityOnMap(rarity: string): number
	local count = 0
	for _, bottle in ipairs(bottlesFolder:GetChildren()) do
		local rv = bottle:FindFirstChild("Rarity")
		local cv = bottle:FindFirstChild("Collected")
		if rv and rv.Value == rarity and cv and not cv.Value then
			count += 1
		end
	end
	return count
end

-- Wybór pozycji spawn: najpierw obszary (BottleSpawnAreas), potem punkty (BottleSpawnPoints).
-- Zwraca też tier (z nazwy obszaru) — nil gdy fallback na stare spawn points.
-- `requireRarity` — gdy podane, spawn tylko w obszarach których tier dopuszcza tę rzadkość.
local function pickSpawnPosition(requireRarity: string?): (Vector3?, number?)
	local areaPos, tier = pickPositionFromAreas(requireRarity)
	if areaPos then return areaPos, tier end
	local sp = getFreeSpawnPoint()
	if sp then return sp.Position + Vector3.new(0, 1, 0), nil end
	return nil, nil
end

function BottleService.EnsureRareBottles()
	local legendaryNeeded = Config.MinLegendarnaOnMap - countRarityOnMap("Legendarna")
	local epicNeeded      = Config.MinEpickaOnMap     - countRarityOnMap("Epicka")

	for _ = 1, legendaryNeeded do
		local pos, tier = pickSpawnPosition("Legendarna")
		if pos then BottleService.SpawnBottle(pos, "Legendarna", tier) end
	end

	for _ = 1, epicNeeded do
		local pos, tier = pickSpawnPosition("Epicka")
		if pos then BottleService.SpawnBottle(pos, "Epicka", tier) end
	end
end

local function scheduleRespawn()
	task.delay(Config.BottleRespawnTime, function()
		local currentCount = #bottlesFolder:GetChildren()
		if currentCount < dynamicMaxBottles then
			local pos, tier = pickSpawnPosition()
			if pos then
				BottleService.SpawnBottle(pos, legendaryEventActive and "Legendarna" or nil, tier)
			end
		end
		if not legendaryEventActive then
			BottleService.EnsureRareBottles()
		end
	end)
end

-- ── Event: Deszcz Legendarek ──────────────────────────────────────────────

local function clearAllBottles()
	if not bottlesFolder then return end
	for _, b in ipairs(bottlesFolder:GetChildren()) do
		b:Destroy()
	end
end

local function floodLegendaryBottles(target: number)
	for _ = 1, target do
		local pos, tier = pickSpawnPosition()
		if pos then
			BottleService.SpawnBottle(pos, "Legendarna", tier)
		else
			break
		end
	end
end

local function startLegendaryEvent()
	if legendaryEventActive then return end
	legendaryEventActive = true
	local cfg = Config.LegendaryEvent

	clearAllBottles()
	floodLegendaryBottles(cfg.BottleCount)

	LegendaryEventStart:FireAllClients({ duration = cfg.DurationSec })
	print("[BottleService] EVENT: Deszcz Legendarek — start (", cfg.DurationSec, "s )")

	task.delay(cfg.DurationSec, function()
		legendaryEventActive = false
		clearAllBottles()
		LegendaryEventEnd:FireAllClients()

		-- Przywróć normalny spawn pełnej puli
		for _ = 1, dynamicMaxBottles do
			local pos, tier = pickSpawnPosition()
			if pos then BottleService.SpawnBottle(pos, nil, tier) else break end
		end
		BottleService.EnsureRareBottles()
		print("[BottleService] EVENT: koniec, mapa zresetowana do normy")
	end)
end

local function startLegendaryEventLoop()
	task.spawn(function()
		local cfg = Config.LegendaryEvent
		while true do
			local wait = math.random(cfg.MinIntervalSec, cfg.MaxIntervalSec)
			task.wait(wait)
			local ok, err = pcall(startLegendaryEvent)
			if not ok then
				warn("[BottleService] Błąd startu eventu:", err)
			end
			-- Poczekaj aż event się skończy zanim wejdziemy w kolejny interval
			task.wait(cfg.DurationSec + 2)
		end
	end)
end

local function initBottles()
	setupSpawnPoints()
	setupButelkomaty()
	setupAutomatKaucyjny()
	bottlesFolder    = getOrCreateFolder(workspace, "Bottles")
	spawnAreasFolder = workspace:FindFirstChild("BottleSpawnAreas") :: Folder?

	-- Auto-fix area parts: bez tego są niezakotwiczone, spadają i Roblox je destroyuje
	if spawnAreasFolder then
		local function fixAreaPart(part: Instance)
			if part:IsA("BasePart") then
				part.Anchored   = true
				part.CanCollide = false
			end
		end
		for _, child in ipairs(spawnAreasFolder:GetChildren()) do
			fixAreaPart(child)
		end
		spawnAreasFolder.ChildAdded:Connect(function(child)
			fixAreaPart(child)
			recomputeAreaTargets()
		end)
		spawnAreasFolder.ChildRemoved:Connect(function()
			recomputeAreaTargets()
		end)
		print("[BottleService] Obszary spawnu:", #spawnAreasFolder:GetChildren(),
			"— wszystkie zakotwiczone i bez kolizji")
		recomputeAreaTargets()
	end

	if spawnAreasFolder then
		-- Mamy obszary — spawn po pełnej puli
		for _ = 1, dynamicMaxBottles do
			local pos, tier = pickSpawnPosition()
			if pos then BottleService.SpawnBottle(pos, nil, tier) else break end
		end
	elseif spawnPointsFolder then
		-- Fallback: stary system spawn points (1 butelka per point, hard cap 30)
		local spawnPoints = spawnPointsFolder:GetChildren()
		local toSpawn = math.min(30, #spawnPoints)
		for i = 1, toSpawn do
			local sp = spawnPoints[i] :: BasePart
			BottleService.SpawnBottle(sp.Position + Vector3.new(0, 1, 0))
		end
		dynamicMaxBottles = toSpawn  -- żeby respawn loop też respektował
	else
		warn("[BottleService] Brak folderu BottleSpawnAreas ani BottleSpawnPoints — butelki się nie pojawią")
	end

	BottleService.EnsureRareBottles()
end

-- Cykliczna pętla respawn: co `BottleRespawnTime` sekund próbuje dolosować
-- butelki jeśli mapa jest poniżej `MaxBottlesOnMap`. Działa niezależnie
-- od zbierania — utrzymuje rotację butelek nawet gdy nikt nic nie zbiera.
local SPAWNS_PER_TICK_CAP = 15  -- max butelek dolosowanych w jednej iteracji pętli

local function startRespawnLoop()
	task.spawn(function()
		while true do
			task.wait(Config.BottleRespawnTime)
			local ok, err = pcall(function()
				if not bottlesFolder then return end
				local count = #bottlesFolder:GetChildren()
				local need  = dynamicMaxBottles - count
				if need > 0 then
					local spawned = 0
					local forced  = legendaryEventActive and "Legendarna" or nil
					-- W trakcie eventu zalewamy mapę bez cap-a — chcemy 30 sztuk od razu
					local cap = legendaryEventActive and need or math.min(need, SPAWNS_PER_TICK_CAP)
					for _ = 1, cap do
						local pos, tier = pickSpawnPosition()
						if pos then
							BottleService.SpawnBottle(pos, forced, tier)
							spawned += 1
						else
							break  -- brak miejsca w obszarach — nie ma sensu próbować dalej
						end
					end
					if spawned > 0 then
						print("[BottleService] Respawn tick: dolosowano", spawned,
							"butelek (było", count, "/", dynamicMaxBottles, ")")
					end
				end
				if not legendaryEventActive then
					BottleService.EnsureRareBottles()
				end
			end)
			if not ok then
				warn("[BottleService] Błąd w pętli respawn:", err)
			end
		end
	end)
end

-- Handler zbierania butelki
-- Handler upuszczania butelki z ekwipunku (przycisk "UPUŚĆ" w inventory)
local DROP_FORWARD_DIST = 3   -- studs przed graczem

DropBottle.OnServerEvent:Connect(function(player: Player, rarity: any)
	if type(rarity) ~= "string" then return end
	if not Config.BottleValues[rarity] then return end
	-- Zakaz wyrzucania itemów w strefie PvP (anti-exploit + porządek na arenie)
	if player:GetAttribute("InPvPZone") == true then return end
	-- Throttle anty-spam
	local now = os.clock()
	if lastDropAt[player] and now - lastDropAt[player] < DROP_THROTTLE then return end
	lastDropAt[player] = now

	local data = PlayerDataService.GetData(player)
	if not data.BackpackContents then return end
	if (data.BackpackContents[rarity] or 0) <= 0 then return end

	-- Wymagana postać + pozycja przed graczem
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	local fwd = hrp.CFrame.LookVector
	local dropPos = hrp.Position + fwd * DROP_FORWARD_DIST + Vector3.new(0, -1, 0)

	-- Zdjemij z plecaka, zespawnuj butelkę (bez cooldownu — ręczny drop, możesz od razu podnieść)
	data.BackpackContents[rarity] -= 1
	pcall(function()
		BottleService.SpawnBottle(dropPos, rarity, nil)
	end)

	-- Sync HUD klienta
	local cap = Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity
	local UpdateHUDEvt = Events:WaitForChild("UpdateHUD")
	UpdateHUDEvt:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = cap,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
		magnetCount      = data.MagnetCount or 0,
	})
end)

-- Wspólna logika zbierania — używana przez CollectBottle handler (klient klika prompt)
-- ORAZ MagnetService sweep (auto-pickup w promieniu).
-- opts.skipDistanceCheck — pomija sanity 12-stud check (magnes ma własny radius)
-- opts.silent — nie wysyła CollectBottleResult przy "full" (magnes nie spamuje błędami)
-- Zwraca: success (bool), reason (string?), rarity (string?)
function BottleService.TryCollectBottle(player: Player, bottlePart: Instance, opts: {skipDistanceCheck: boolean?, silent: boolean?}?): (boolean, string?, string?)
	opts = opts or {}
	if not bottlePart then return false, "invalid", nil end
	if not (bottlePart:IsA("BasePart") or bottlePart:IsA("Model")) then return false, "invalid", nil end
	if bottlePart.Parent ~= bottlesFolder then return false, "invalid", nil end

	local collectedValue = bottlePart:FindFirstChild("Collected") :: BoolValue
	local rarityValue    = bottlePart:FindFirstChild("Rarity")    :: StringValue
	if not collectedValue or collectedValue.Value then return false, "alreadyCollected", nil end
	if not rarityValue then return false, "invalid", nil end

	-- Cooldown na własny drop po śmierci — dotyczy obu trybów (ręczny pickup + magnes)
	local dropOwner   = bottlePart:GetAttribute("DeathDropOwner")
	local dropExpires = bottlePart:GetAttribute("DeathDropExpires")
	if dropOwner and dropOwner == player.UserId and dropExpires and os.clock() < dropExpires then
		if not opts.silent then
			CollectBottleResult:FireClient(player, { success = false, reason = "ownDropCooldown" })
		end
		return false, "ownDropCooldown", nil
	end

	local character = player.Character
	if not character then return false, "noChar", nil end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hrp then return false, "noChar", nil end
	if not opts.skipDistanceCheck then
		if (hrp.Position - getBottlePos(bottlePart)).Magnitude > 12 then return false, "tooFar", nil end
	end

	local data = PlayerDataService.GetData(player)
	local capacity = Config.BackpackUpgrades[data.BackpackLevel].Capacity
	local carried  = Util.getCarriedCount(data)

	-- Limit per-kategoria: butelki mogą zająć max 70% pojemności plecaka (reszta dla petów/akcesoriów).
	local caps        = Util.getCategoryCaps(capacity, Config.BackpackCategorySplit)
	local bottleCount = Util.getBottleCount(data)
	if bottleCount >= caps.bottles then
		if not opts.silent then
			CollectBottleResult:FireClient(player, { success = false, reason = "full" })
		end
		return false, "full", nil
	end

	local rarity = rarityValue.Value
	collectedValue.Value = true
	bottlePart:Destroy()

	data.BackpackContents[rarity] += 1
	data.TotalBottles             += 1

	QuestService.AddProgress(player, "collect", { rarity = rarity, amount = 1 })
	pcall(function()
		local sqs = require(script.Parent.StoryQuestService)
		sqs.AddProgress(player, "collect", 1, { rarity = rarity })
	end)

	CollectBottleResult:FireClient(player, {
		success        = true,
		rarity         = rarity,
		bottlesCarried = carried + 1,
		capacity       = capacity,
	})

	scheduleRespawn()
	return true, nil, rarity
end

CollectBottle.OnServerEvent:Connect(function(player: Player, bottlePart: Instance)
	-- Throttle 20Hz — exploit-spam guard. Normalny pickup nigdy nie przekracza tego.
	local now = os.clock()
	if lastCollectAt[player] and now - lastCollectAt[player] < COLLECT_THROTTLE then return end
	lastCollectAt[player] = now
	BottleService.TryCollectBottle(player, bottlePart)
end)

-- Handler opróżnienia plecaka (butelkomat)
EmptyBackpack.OnServerEvent:Connect(function(player: Player)
	-- Throttle
	local now = os.clock()
	if lastEmptyAt[player] and now - lastEmptyAt[player] < EMPTY_THROTTLE then return end
	lastEmptyAt[player] = now

	-- Dystans: gracz MUSI być blisko któregoś tagged Butelkomat
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end
	if not isNearButelkomat(hrp :: BasePart) then
		EmptyBackpackResult:FireClient(player, { success = false, reason = "tooFar" })
		return
	end

	local data = PlayerDataService.GetData(player)

	local totalBottles = 0
	for _, count in pairs(data.BackpackContents) do totalBottles += count end

	if totalBottles == 0 then
		EmptyBackpackResult:FireClient(player, { success = false, reason = "empty" })
		return
	end

	local multLevel  = (data.MultiplierLevel or 0) > 0 and data.MultiplierLevel or nil
	local multiplier = multLevel and Config.MultiplierUpgrades[multLevel].Multiplier or 1.0

	-- Boost x2 (Developer Product) — multiplikatywny, sumuje się z mnożnikiem ze skill tree
	local ok, BoostShopService = pcall(function() return require(script.Parent.BoostShopService) end)
	if ok and BoostShopService then
		multiplier *= BoostShopService.GetEarnMultiplier(player)
	end

	-- Pet equipped (rzadkość → moneyMul) — multiplikatywnie z resztą.
	-- Stack: base × skillMul × boostMul × petMul.
	local okP, PetService = pcall(function() return require(script.Parent.PetService) end)
	if okP and PetService then
		multiplier *= PetService.GetMoneyMul(player)
	end

	local earned = 0
	local breakdown = {}
	for rarity, count in pairs(data.BackpackContents) do
		if count > 0 then
			local rarityEarned = Config.BottleValues[rarity] * count * multiplier
			breakdown[rarity] = rarityEarned
			earned += rarityEarned
		end
	end

	data.Zlotowki    += earned
	data.TotalEarned += earned
	data.BackpackContents = { Zwykla = 0, Rzadka = 0, Epicka = 0, Legendarna = 0, Mityczny = 0 }
	PlayerDataService.UpdateLeaderstats(player)

	-- Quest progress: zarobione zł + 1 opróżnienie plecaka
	QuestService.AddProgress(player, "earn", { amount = math.floor(earned) })
	QuestService.AddProgress(player, "empty_backpack", { amount = 1 })
	pcall(function()
		local sqs = require(script.Parent.StoryQuestService)
		sqs.AddProgress(player, "deposit", 1)
	end)

	EmptyBackpackResult:FireClient(player, {
		success         = true,
		bottlesReturned = totalBottles,
		earned          = earned,
		newTotal        = data.Zlotowki,
		breakdown       = breakdown,
	})
end)

initBottles()
startRespawnLoop()
startLegendaryEventLoop()

return BottleService
