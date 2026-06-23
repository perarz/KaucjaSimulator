-- DeskaService.server.luau
-- Deski (skateboardy): kupowanie przy gablotach, posiadanie/equip, jazda po R.
-- Mount klonuje szablon z workspace.Deski[model] i przyspawia go do gracza (clone-per-mount → multiplayer-safe).
-- Standalone Script (.server.luau) — NIE wymagany przez GameServer (uruchamia się sam).
-- VIP (Robux) grantowany przez BoostShopService.ProcessReceipt → BindableEvent GrantDeckEvent (poniżej).

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local Events          = ReplicatedStorage:WaitForChild("Events")
local DeskMount       = Events:WaitForChild("DeskMount")
local DeskDismount    = Events:WaitForChild("DeskDismount")
local DeskMountResult = Events:WaitForChild("DeskMountResult")
local QuickMount      = Events:WaitForChild("QuickMount")
local OpenDeckShop    = Events:WaitForChild("OpenDeckShop")
local BuyDeck         = Events:WaitForChild("BuyDeck")
local BuyDeckResult   = Events:WaitForChild("BuyDeckResult")
local EquipDeck       = Events:WaitForChild("EquipDeck")
local DeckStatus      = Events:WaitForChild("DeckStatus")

local BOARD_Y_OFFSET = -3.0

-- [Player] = { weld, board(clone), parts={[part]=savedState}, deckKey }
local mountedData: { [Player]: any } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function getDeckByKey(key: string)
	for _, deck in ipairs(Config.Decks) do
		if deck.key == key then return deck end
	end
	return nil
end

local function getDeckByGablota(num: number)
	for _, deck in ipairs(Config.Decks) do
		if deck.gablota == num then return deck end
	end
	return nil
end

-- Najlepsza (najszybsza) deska którą gracz posiada
local function getBestOwnedKey(player: Player): string?
	local data = PlayerDataService.GetData(player)
	local owned = data.OwnedDecks or {}
	local bestKey, bestSpeed = nil, -1
	for _, deck in ipairs(Config.Decks) do
		if owned[deck.key] and deck.Speed > bestSpeed then
			bestKey, bestSpeed = deck.key, deck.Speed
		end
	end
	return bestKey
end

-- Klucz deski do jazdy: wyposażona (jeśli posiadana) inaczej najlepsza posiadana
local function getRideKey(player: Player): string?
	local data = PlayerDataService.GetData(player)
	local owned = data.OwnedDecks or {}
	local eq = data.EquippedDeck
	if eq and eq ~= "" and owned[eq] then return eq end
	return getBestOwnedKey(player)
end

local function getPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then return model.PrimaryPart end
	for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then return v :: BasePart end
	end
	return nil
end

local function getActiveFolder(): Folder
	local f = workspace:FindFirstChild("ActiveDecks")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ActiveDecks"
		f.Parent = workspace
	end
	return f :: Folder
end

-- ── Status sync do klienta ─────────────────────────────────────────────────────
local function pushStatus(player: Player)
	local data = PlayerDataService.GetData(player)
	DeckStatus:FireClient(player, {
		owned    = data.OwnedDecks or {},
		equipped = data.EquippedDeck or "",
		riding   = mountedData[player] and mountedData[player].deckKey or nil,
	})
end

-- ── Mount / dismount ───────────────────────────────────────────────────────────
local function dismountPlayer(player: Player)
	local data = mountedData[player]
	if not data then return end
	mountedData[player] = nil

	if data.weld and data.weld.Parent then data.weld:Destroy() end
	if data.board and data.board.Parent then data.board:Destroy() end
	if data.seatedConn then data.seatedConn:Disconnect() end

	local char = player.Character
	if char then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed  = Config.DeckDismountWalkSpeed or 16
			humanoid.JumpHeight = Config.DeckDismountJumpHeight or 7.2
		end
	end

	DeskMountResult:FireClient(player, false, nil)
end

-- Sprawdza czy gracz jest aktualnie w workspace.PVPZone lub workspace.SAFEZONE.
-- Zakaz wsiadania na deskę w obu strefach.
local function isInBlockedZone(player: Player): boolean
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	local pos = (hrp :: BasePart).Position

	for _, name in ipairs({ "PVPZone", "SAFEZONE" }) do
		local zone = workspace:FindFirstChild(name, true)
		if zone and zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(pos)
			local half = zone.Size / 2
			if  math.abs(localPos.X) <= half.X
			and math.abs(localPos.Y) <= half.Y
			and math.abs(localPos.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function mountPlayer(player: Player, deckKey: string)
	if mountedData[player] then return end

	local deck = getDeckByKey(deckKey)
	if not deck then return end

	local data = PlayerDataService.GetData(player)
	if not (data.OwnedDecks and data.OwnedDecks[deckKey]) then return end  -- anti-cheat: musi posiadać

	-- Zakaz jazdy w strefie PvP i SAFEZONE
	if isInBlockedZone(player) then
		DeskMountResult:FireClient(player, false, nil)
		return
	end

	local char     = player.Character
	local hrp      = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not hrp or not humanoid then return end

	-- Wstajemy z siedzenia (huśtawka, krzesło, Seat/VehicleSeat) przed wsiadem na deskę.
	-- Bez tego welds bind do HRP konfliktują z SeatWeld → gracz wpada pod mapę.
	if humanoid.SeatPart then
		humanoid.Sit = false
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		task.wait(0.15)  -- daj klatkę na destruction SeatWeld i fizyczne odlepienie
		-- Re-fetch HRP — character mógł się zmienić w trakcie wait
		local refreshedChar = player.Character
		if not refreshedChar then return end
		local refreshedHrp = refreshedChar:FindFirstChild("HumanoidRootPart")
		if not (refreshedHrp and refreshedHrp:IsA("BasePart")) then return end
		hrp = refreshedHrp :: BasePart
	end

	-- Znajdź szablon w workspace.Deski (fallback ReplicatedStorage.Deski)
	-- Szablon może być Modelem (z PrimaryPart) ALBO pojedynczym BasePart/Union.
	local deskiFolder = workspace:FindFirstChild("Deski") or ReplicatedStorage:FindFirstChild("Deski")
	local template = deskiFolder and deskiFolder:FindFirstChild(deck.model)
	if not template or not (template:IsA("Model") or template:IsA("BasePart")) then
		warn("[DeskaService] Brak deski (Model/BasePart):", deck.model, "(workspace.Deski)")
		return
	end

	local board = template:Clone()
	board.Name = "ActiveDeck_" .. player.Name
	board.Parent = getActiveFolder()

	-- PrimaryPart dla Modelu, lub sam part gdy deska to BasePart/Union
	local primary: BasePart?
	if board:IsA("Model") then
		primary = getPrimaryPart(board)
	elseif board:IsA("BasePart") then
		primary = board :: BasePart
	end
	if not primary then
		warn("[DeskaService] Deska nie ma BasePart:", deck.model)
		board:Destroy()
		return
	end

	-- Ustaw fizyczne właściwości — działa dla Modelu (descendants) i samego BasePart
	local toSet = board:IsA("BasePart") and { board } or board:GetDescendants()
	for _, part in toSet do
		if part:IsA("BasePart") then
			part.Anchored     = false
			part.CanCollide   = false
			part.Massless     = true
		end
	end

	local _, yRot, _ = hrp.CFrame:ToEulerAnglesYXZ()
	primary.CFrame = CFrame.new(hrp.Position + Vector3.new(0, BOARD_Y_OFFSET, 0))
		* CFrame.Angles(0, yRot + math.rad(90), 0)
		* CFrame.Angles(0, 0, math.rad(90))

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = hrp
	weld.Part1  = primary
	weld.Parent = primary

	-- Sprinter pet — addytywny bonus do deck.Speed (np. Default 40 + Huge 25 = 65)
	local petSpeedBonus = 0
	local okP, PetService = pcall(function() return require(script.Parent.PetService) end)
	if okP and PetService then
		petSpeedBonus = PetService.GetSpeedBonus(player) or 0
	end
	humanoid.WalkSpeed  = deck.Speed + petSpeedBonus
	humanoid.JumpHeight = 0

	-- Blokuj siadanie na Seat/VehicleSeat podczas jazdy — SeatWeld konfliktuje z weldem deski (gracz pod mapą / desync).
	local seatedConn = humanoid.Seated:Connect(function(isSeated, seatPart)
		if isSeated and seatPart and mountedData[player] then
			humanoid.Sit = false
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)

	mountedData[player] = { weld = weld, board = board, deckKey = deckKey, seatedConn = seatedConn }
	DeskMountResult:FireClient(player, true, board)
	print(string.format("[DeskaService] %s jeździ na %s (speed %d)", player.Name, deck.name, deck.Speed))
end

-- ── Granting (zakup zł / Robux / kod) ──────────────────────────────────────────
local function grantDeckInternal(player: Player, key: string, autoEquip: boolean)
	local data = PlayerDataService.GetData(player)
	data.OwnedDecks = data.OwnedDecks or {}
	-- Liczymy progres tylko gdy to PIERWSZY zakup tej deski (nie podwójny grant)
	local wasNew = not data.OwnedDecks[key]
	data.OwnedDecks[key] = true
	if autoEquip and (not data.EquippedDeck or data.EquippedDeck == "") then
		data.EquippedDeck = key
	end
	pushStatus(player)
	if wasNew then
		pcall(function()
			local sqs = require(script.Parent:WaitForChild("StoryQuestService"))
			sqs.AddProgress(player, "buy_deck", 1, { deckKey = key })
		end)
	end
end

-- Wywoływane przez BoostShopService.ProcessReceipt (przez BindableEvent) dla VIP w Robux
local function grantDeck(player: Player, key: string)
	if not getDeckByKey(key) then return end
	grantDeckInternal(player, key, true)
	PlayerDataService.SaveData(player)
	BuyDeckResult:FireClient(player, { success = true, deckKey = key })
	print(string.format("[DeskaService] %s otrzymał %s (Robux)", player.Name, key))
end

local function tryBuyDeck(player: Player, key: string)
	local deck = getDeckByKey(key)
	if not deck then return end
	local data = PlayerDataService.GetData(player)
	data.OwnedDecks = data.OwnedDecks or {}

	if data.OwnedDecks[key] then
		BuyDeckResult:FireClient(player, { success = false, reason = "already", deckKey = key })
		return
	end

	if deck.CostType == "Gamepass" then
		local id = deck.GamepassId
		if not id or id == 0 then
			warn("[DeskaService] Brak GamepassId dla deski", key, "— wpisz Gamepass ID w Config.Decks")
			BuyDeckResult:FireClient(player, { success = false, reason = "noproduct", deckKey = key })
			return
		end
		-- Sprawdź czy gracz już posiada (np. kupił wcześniej a OwnedDecks się nie zsynchronizowało)
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if ok and owns then
			-- Posiada gamepass — grant od razu
			grantDeck(player, key)
			return
		end
		-- Inaczej prompt kupna — grant odbywa się w PromptGamePassPurchaseFinished niżej
		MarketplaceService:PromptGamePassPurchase(player, id)
		return
	end

	if deck.CostType == "Robux" then
		local id = deck.RobuxProductId
		if not id or id == 0 then
			warn("[DeskaService] Brak RobuxProductId dla deski", key, "— wpisz Developer Product ID w Config.Decks")
			BuyDeckResult:FireClient(player, { success = false, reason = "noproduct", deckKey = key })
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)
		return
	end

	-- Płatność w złotówkach
	if data.Zlotowki < deck.Cost then
		BuyDeckResult:FireClient(player, { success = false, reason = "broke", deckKey = key })
		return
	end
	data.Zlotowki -= deck.Cost
	PlayerDataService.UpdateLeaderstats(player)
	grantDeckInternal(player, key, true)
	PlayerDataService.SaveData(player)
	BuyDeckResult:FireClient(player, { success = true, deckKey = key })
	print(string.format("[DeskaService] %s kupił %s za %d zł", player.Name, deck.name, deck.Cost))
end

-- ── Gabloty: cache anchorów + throttle do walidacji BuyDeck/EquipDeck (anti-exploit) ──
local gablotyAnchors: { BasePart } = {}
local DECK_MAX_DIST = 18  -- gabloty są większe, dajemy luźniejszą tolerancję
local lastDeckActionAt: { [Player]: number } = {}
local DECK_ACTION_THROTTLE = 0.5
local function isNearAnyGablota(player: Player): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	local pos = (hrp :: BasePart).Position
	for _, a in ipairs(gablotyAnchors) do
		if a.Parent and (a.Position - pos).Magnitude <= DECK_MAX_DIST then return true end
	end
	return false
end
Players.PlayerRemoving:Connect(function(p) lastDeckActionAt[p] = nil end)

-- ── Gabloty (ProximityPrompt → OpenDeckShop) ───────────────────────────────────
local function setupGablota(model: Instance)
	local num = tonumber(string.match(model.Name, "(%d+)"))
	if not num then return end
	local deck = getDeckByGablota(num)
	if not deck then return end

	local anchor: BasePart? = nil
	if model:IsA("BasePart") then
		anchor = model
	elseif model:IsA("Model") then
		-- Preferuj Part nazwany "Proximity" (konwencja w gablotach) — tam ma być prompt
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and string.find(string.lower(d.Name), "proximity") then
				anchor = d :: BasePart
				break
			end
		end
		anchor = anchor or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not anchor then
		warn("[DeskaService] Gablota", model.Name, "— brak BasePart/Proximity na prompt")
		return
	end
	table.insert(gablotyAnchors, anchor)  -- cache do walidacji dystansu

	local prompt = anchor:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = anchor
	end
	-- Wymuś poprawne ustawienia (także na istniejącym prompcie — np. Gablota1 miała Enabled=false)
	prompt.ActionText            = "Kup deskę"
	prompt.ObjectText            = deck.name
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Enabled               = true

	prompt.Triggered:Connect(function(player: Player)
		OpenDeckShop:FireClient(player, deck.key)
	end)

	-- Diagnostyka: gdzie jest anchor względem modelu (wykrywa "Proximity" part odsunięty/na 0,0,0)
	local modelPos = model:IsA("Model") and model:GetPivot().Position or anchor.Position
	local dist = (anchor.Position - modelPos).Magnitude
	local promptCount, proxParts = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then promptCount += 1 end
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "proximity") then proxParts += 1 end
	end
	print(string.format(
		"[DeskaService] Gablota %d → %s | anchor=%s pos=(%.0f,%.0f,%.0f) size=(%.1f,%.1f,%.1f) distOdModelu=%.1f | promptów=%d proxParts=%d",
		num, deck.key, anchor.Name,
		anchor.Position.X, anchor.Position.Y, anchor.Position.Z,
		anchor.Size.X, anchor.Size.Y, anchor.Size.Z,
		dist, promptCount, proxParts))
end

local function setupGabloty()
	-- Lokalizacja: workspace.Parking.Gabloty (preferowane). Fallback: workspace.Gabloty albo rekurencyjnie.
	local parking = workspace:FindFirstChild("Parking")
	local folder = (parking and parking:FindFirstChild("Gabloty"))
		or workspace:FindFirstChild("Gabloty")
		or workspace:FindFirstChild("Gabloty", true)
	local searchRoot = folder or workspace

	if folder then
		print("[DeskaService] Folder Gabloty znaleziony →", folder:GetFullName())
		print("[DeskaService] Dzieci folderu Gabloty:")
		for _, child in folder:GetChildren() do
			print("   •", child.Name, "(", child.ClassName, ")")
		end
		folder.ChildAdded:Connect(setupGablota)
	else
		warn("[DeskaService] Brak folderu 'Gabloty' — skanuję cały workspace")
	end

	local seen = {}
	local found = 0
	local function tryAttach(d: Instance)
		if seen[d] then return end
		if not (d:IsA("Model") or d:IsA("BasePart")) then return end
		local num = tonumber(string.match(d.Name, "(%d+)"))
		if num and getDeckByGablota(num) then
			seen[d] = true
			setupGablota(d)
			found += 1
		end
	end

	-- 1) Bezpośrednie dzieci folderu (covers "1" / "Gablota1" / "Gablota 1")
	if folder then
		for _, child in folder:GetChildren() do
			tryAttach(child)
		end
	end

	-- 2) Dowolny zagnieżdżony obiekt z "gablota" w nazwie (gdy gabloty są opakowane głębiej)
	for _, d in searchRoot:GetDescendants() do
		if string.find(string.lower(d.Name), "gablota") then
			tryAttach(d)
		end
	end

	if found == 0 then
		warn("[DeskaService] Nie znaleziono żadnych Gablot — nazwy muszą zawierać numer 1-4 (np. 'Gablota1'). Patrz lista dzieci wyżej.")
	else
		print("[DeskaService] Podłączono", found, "gablot z promptami")
	end
end

-- ── BindableEvent grant (most z BoostShopService.ProcessReceipt dla VIP Robux) ──
local grantDeckEvent = ServerScriptService:FindFirstChild("GrantDeckEvent")
if not grantDeckEvent then
	grantDeckEvent = Instance.new("BindableEvent")
	grantDeckEvent.Name = "GrantDeckEvent"
	grantDeckEvent.Parent = ServerScriptService
end
grantDeckEvent.Event:Connect(function(player: Player, key: string)
	if typeof(player) ~= "Instance" or type(key) ~= "string" then return end
	grantDeck(player, key)
end)

-- ── BindableEvent force dismount (PvPService fire'uje gdy gracz wejdzie w PVPZone/SAFEZONE) ──
local forceDismountEvent = ServerScriptService:FindFirstChild("ForceDeskDismountEvent")
if not forceDismountEvent then
	forceDismountEvent = Instance.new("BindableEvent")
	forceDismountEvent.Name = "ForceDeskDismountEvent"
	forceDismountEvent.Parent = ServerScriptService
end
forceDismountEvent.Event:Connect(function(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	dismountPlayer(player)  -- idempotent: jeśli nie na desce, no-op
end)

-- ── Eventy ─────────────────────────────────────────────────────────────────────
DeskMount.OnServerEvent:Connect(function(player: Player, _board: Instance?)
	-- R: wsiada na wyposażoną (lub najlepszą posiadaną) deskę
	local key = getRideKey(player)
	if not key then
		DeskMountResult:FireClient(player, false, nil)
		return
	end
	mountPlayer(player, key)
end)

QuickMount.OnServerEvent:Connect(function(player: Player)
	local key = getRideKey(player)
	if key then mountPlayer(player, key) end
end)

DeskDismount.OnServerEvent:Connect(function(player: Player)
	dismountPlayer(player)
end)

EquipDeck.OnServerEvent:Connect(function(player: Player, key: string)
	if type(key) ~= "string" then return end
	local now = os.clock()
	if lastDeckActionAt[player] and now - lastDeckActionAt[player] < DECK_ACTION_THROTTLE then return end
	lastDeckActionAt[player] = now
	-- BUGFIX: usunięty wymóg isNearAnyGablota — EquipDeck jest wywoływany z hoverboard
	-- menu (otwieralne wszędzie), nie z gabloty. Posiadanie deski wystarcza za autoryzację.
	local data = PlayerDataService.GetData(player)
	if not (data.OwnedDecks and data.OwnedDecks[key]) then
		-- nie posiada — pchnij aktualny stan żeby UI się nie zacięło z "selecting…"
		pushStatus(player)
		return
	end
	if data.EquippedDeck == key then
		pushStatus(player)
		return
	end
	data.EquippedDeck = key
	PlayerDataService.SaveData(player)
	-- Auto-swap tylko gdy aktualnie jeździ — inaczej WYPOSAŻ z menu nieoczekiwanie sadzało
	-- gracza na deskę. Jeśli nie jedzie, samo ustawiamy equipped i pushujemy status.
	if mountedData[player] then
		dismountPlayer(player)
		mountPlayer(player, key)
	end
	pushStatus(player)
end)

BuyDeck.OnServerEvent:Connect(function(player: Player, key: string)
	if type(key) ~= "string" then return end
	local now = os.clock()
	if lastDeckActionAt[player] and now - lastDeckActionAt[player] < DECK_ACTION_THROTTLE then return end
	lastDeckActionAt[player] = now
	if not isNearAnyGablota(player) then
		BuyDeckResult:FireClient(player, { success = false, reason = "tooFar" })
		return
	end
	tryBuyDeck(player, key)
end)

-- ── Gamepass: nasłuch zakupów + check przy join ────────────────────────────────
-- Po zakupie gamepass'a w trakcie sesji — grant odpowiedniej deski.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gpId: number, purchased: boolean)
	if not purchased then return end
	for _, deck in ipairs(Config.Decks) do
		if deck.CostType == "Gamepass" and deck.GamepassId == gpId then
			grantDeck(player, deck.key)
			break
		end
	end
end)

-- Przy joinie sprawdź gamepassy — jeśli gracz posiada gamepass a deski nie ma → grant
local function checkGamepassDecksOnJoin(player: Player)
	local data = PlayerDataService.GetData(player)
	data.OwnedDecks = data.OwnedDecks or {}
	for _, deck in ipairs(Config.Decks) do
		if deck.CostType == "Gamepass" and deck.GamepassId and not data.OwnedDecks[deck.key] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, deck.GamepassId)
			end)
			if ok and owns then
				grantDeck(player, deck.key)
			end
		end
	end
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		PlayerDataService.GetData(player)
		checkGamepassDecksOnJoin(player)  -- po wczytaniu danych
		task.wait(1)
		pushStatus(player)
	end)
	player.CharacterAdded:Connect(function()
		-- po respawnie nie jeździmy — posprzątaj osierocony klon deski (weld zginął z postacią)
		local prev = mountedData[player]
		if prev and prev.board and prev.board.Parent then prev.board:Destroy() end
		mountedData[player] = nil
		-- BUGFIX: bez tego klient zostawał z `mounted = true` po śmierci na desce —
		-- press R → klient myślał że jeździ → wysyłał DeskDismount zamiast Mount →
		-- server (mountedData=nil) ignorował → gracz nie mógł wsiąść na deskę nigdy więcej.
		-- Szczególnie widoczne na VIP (Speed=100) gdzie ludzie częściej giną podczas jazdy.
		DeskMountResult:FireClient(player, false, nil)
		task.wait(0.5)
		pushStatus(player)
	end)
end)

Players.PlayerRemoving:Connect(dismountPlayer)

setupGabloty()

-- Diagnostyka: wypisz klasę każdego szablonu deski (rozstrzyga Model vs Union)
do
	local deskiFolder = workspace:FindFirstChild("Deski") or ReplicatedStorage:FindFirstChild("Deski")
	print("[DeskaService] Szablony desek w", deskiFolder and deskiFolder:GetFullName() or "(brak folderu Deski!)")
	for _, deck in ipairs(Config.Decks) do
		local t = deskiFolder and deskiFolder:FindFirstChild(deck.model)
		if t then
			print(string.format("   • %s → %s (%s) PrimaryPart=%s",
				deck.model, t.Name, t.ClassName,
				(t:IsA("Model") and t.PrimaryPart) and t.PrimaryPart.Name or "—"))
		else
			print(string.format("   • %s → BRAK w folderze!", deck.model))
		end
	end
end

print("[DeskaService] Gotowy —", #Config.Decks, "desek (standalone Script)")
