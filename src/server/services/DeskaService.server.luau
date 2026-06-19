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

local function mountPlayer(player: Player, deckKey: string)
	if mountedData[player] then return end

	local deck = getDeckByKey(deckKey)
	if not deck then return end

	local data = PlayerDataService.GetData(player)
	if not (data.OwnedDecks and data.OwnedDecks[deckKey]) then return end  -- anti-cheat: musi posiadać

	local char     = player.Character
	local hrp      = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not hrp or not humanoid then return end

	-- Znajdź szablon w workspace.Deski (fallback ReplicatedStorage.Deski)
	local deskiFolder = workspace:FindFirstChild("Deski") or ReplicatedStorage:FindFirstChild("Deski")
	local template = deskiFolder and deskiFolder:FindFirstChild(deck.model)
	if not template or not template:IsA("Model") then
		warn("[DeskaService] Brak modelu deski:", deck.model, "(workspace.Deski)")
		return
	end

	local board = template:Clone()
	board.Name = "ActiveDeck_" .. player.Name
	board.Parent = getActiveFolder()

	local primary = getPrimaryPart(board)
	if not primary then
		warn("[DeskaService] Model deski nie ma BasePart:", deck.model)
		board:Destroy()
		return
	end

	for _, part in board:GetDescendants() do
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

	humanoid.WalkSpeed  = deck.Speed
	humanoid.JumpHeight = 0

	mountedData[player] = { weld = weld, board = board, deckKey = deckKey }
	DeskMountResult:FireClient(player, true, board)
	print(string.format("[DeskaService] %s jeździ na %s (speed %d)", player.Name, deck.name, deck.Speed))
end

-- ── Granting (zakup zł / Robux / kod) ──────────────────────────────────────────
local function grantDeckInternal(player: Player, key: string, autoEquip: boolean)
	local data = PlayerDataService.GetData(player)
	data.OwnedDecks = data.OwnedDecks or {}
	data.OwnedDecks[key] = true
	if autoEquip and (not data.EquippedDeck or data.EquippedDeck == "") then
		data.EquippedDeck = key
	end
	pushStatus(player)
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

	if deck.CostType == "Robux" then
		local id = deck.RobuxProductId
		if not id or id == 0 then
			warn("[DeskaService] Brak RobuxProductId dla deski", key, "— wpisz Developer Product ID w Config.Decks")
			BuyDeckResult:FireClient(player, { success = false, reason = "noproduct", deckKey = key })
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)  -- grant w ProcessReceipt
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
	print(string.format("[DeskaService] Gablota %d → %s (prompt na %s)", num, deck.key, anchor:GetFullName()))
end

local function setupGabloty()
	-- Najpierw folder "Gabloty" bezpośrednio, potem rekurencyjnie (gdy zagnieżdżony w mapie)
	local folder = workspace:FindFirstChild("Gabloty") or workspace:FindFirstChild("Gabloty", true)
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
	local data = PlayerDataService.GetData(player)
	if not (data.OwnedDecks and data.OwnedDecks[key]) then return end
	data.EquippedDeck = key
	PlayerDataService.SaveData(player)
	-- Natychmiast wsiada na wybraną deskę
	if mountedData[player] then dismountPlayer(player) end
	mountPlayer(player, key)
	pushStatus(player)
end)

BuyDeck.OnServerEvent:Connect(function(player: Player, key: string)
	if type(key) ~= "string" then return end
	tryBuyDeck(player, key)
end)

-- ── Lifecycle ──────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		PlayerDataService.GetData(player)  -- upewnij się że dane wczytane
		task.wait(1)
		pushStatus(player)
	end)
	player.CharacterAdded:Connect(function()
		-- po respawnie nie jeździmy — posprzątaj osierocony klon deski (weld zginął z postacią)
		local prev = mountedData[player]
		if prev and prev.board and prev.board.Parent then prev.board:Destroy() end
		mountedData[player] = nil
		task.wait(0.5)
		pushStatus(player)
	end)
end)

Players.PlayerRemoving:Connect(dismountPlayer)

setupGabloty()

print("[DeskaService] Gotowy —", #Config.Decks, "desek (standalone Script)")
