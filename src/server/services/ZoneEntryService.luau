-- ZoneEntryService.luau
-- Bramki do stref (Config.Zones). Każda strefa ma w workspace folder z modelem
-- "entry" — przy nim ProximityPrompt "Kup wstęp". Po zakupie:
--   1) -Cost z portfela
--   2) data.OwnedZones[zoneKey] = true (persystencja)
--   3) ZoneOwnedUpdate:FireClient(player, owned) → klient ukrywa entry lokalnie
-- Na CharacterAdded/PlayerAdded → wysyłamy snapshot OwnedZones do klienta.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local Events            = ReplicatedStorage:WaitForChild("Events")
local ZoneOwnedUpdate   = Events:WaitForChild("ZoneOwnedUpdate")

local ZoneEntryService = {}

-- ── Helper: znajdź pierwszy BasePart w modelu (do attachowania ProximityPrompt) ─
local function findAnchor(model: Instance): BasePart?
	if model:IsA("BasePart") then return model end
	if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

-- ── Mapa: zoneKey → entryModel (do dystansu walidacji) ──────────────────────
local zoneAnchors: { [string]: BasePart } = {}

-- ── Snapshot dla klienta ────────────────────────────────────────────────────
local function sendSnapshot(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then return end
	ZoneOwnedUpdate:FireClient(player, data.OwnedZones or {})
end

-- ── Setup bramki w workspace ────────────────────────────────────────────────
local function setupZone(zoneKey: string, cfg)
	local folder = workspace:FindFirstChild(cfg.FolderName)
	if not folder then
		warn(string.format("[ZoneEntryService] Brak folderu workspace.%s (strefa %s pomijana)", cfg.FolderName, zoneKey))
		return
	end
	local entry = folder:FindFirstChild(cfg.EntryModelName)
	if not entry then
		warn(string.format("[ZoneEntryService] Brak modelu %s w workspace.%s", cfg.EntryModelName, cfg.FolderName))
		return
	end
	local anchor = findAnchor(entry)
	if not anchor then
		warn(string.format("[ZoneEntryService] Model entry strefy %s nie ma BasePart", zoneKey))
		return
	end

	-- Tag dla klienta — żeby znalazł entry niezależnie od ścieżki
	CollectionService:AddTag(entry, "ZoneEntry_" .. zoneKey)
	zoneAnchors[zoneKey] = anchor

	-- Usuń istniejące prompty (jeśli skrypt restartuje się — Studio reload)
	for _, c in ipairs(anchor:GetChildren()) do
		if c:IsA("ProximityPrompt") then c:Destroy() end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = cfg.PromptText or ("Kup wstęp do " .. (cfg.DisplayName or zoneKey))
	prompt.ObjectText            = string.format("%d zł", cfg.Cost)
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = anchor

	local lastBuyAt: { [Player]: number } = {}
	prompt.Triggered:Connect(function(player: Player)
		-- Anty-spam throttle (1s)
		local now = os.clock()
		if (lastBuyAt[player] or 0) + 1 > now then return end
		lastBuyAt[player] = now

		-- Dystans (anti-exploit) — gracz musi stać przy bramie
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then return end
		if (hrp.Position - anchor.Position).Magnitude > 15 then return end

		local data = PlayerDataService.GetData(player)
		if not data then return end
		data.OwnedZones = data.OwnedZones or {}
		if data.OwnedZones[zoneKey] then
			-- Już ma — tylko sync klienta (na wypadek desynchronizacji)
			sendSnapshot(player)
			return
		end
		if (data.Zlotowki or 0) < cfg.Cost then return end

		-- OK — deduktuj, zapisz, ogłoś
		data.Zlotowki = data.Zlotowki - cfg.Cost
		data.OwnedZones[zoneKey] = true
		PlayerDataService.UpdateLeaderstats(player)
		PlayerDataService.SaveData(player)
		sendSnapshot(player)
		pcall(function() require(script.Parent.StoryQuestService).AddProgress(player, "unlock_zone", 1, { zone = zoneKey }) end)  -- linia fabularna
	end)

	print(string.format("[ZoneEntryService] Strefa %s gotowa (entry=%s, koszt=%d zł)",
		zoneKey, entry:GetFullName(), cfg.Cost))
end

-- ── Init ────────────────────────────────────────────────────────────────────
for zoneKey, cfg in pairs(Config.Zones or {}) do
	setupZone(zoneKey, cfg)
end

Players.PlayerAdded:Connect(function(player)
	-- Czekamy aż dane się załadują przed pierwszym snapshotem
	task.defer(function()
		for _ = 1, 20 do
			if PlayerDataService.GetData(player) then break end
			task.wait(0.25)
		end
		sendSnapshot(player)
	end)
end)

-- Snapshot przy każdym respawnie (klient mógł zresetować transparency)
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		sendSnapshot(player)
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	task.defer(sendSnapshot, p)
end

return ZoneEntryService
