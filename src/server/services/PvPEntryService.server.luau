-- PvPEntryService.server.luau
-- Wrzuć do: ServerScriptService (Rojo mapuje automatycznie)
-- Opłata 300 PLN ZA KAŻDYM RAZEM za wstęp do strefy PvP.
-- KasjerPVP (rig) dostaje ProximityPrompt → klient pokazuje GUI → BuyPvPEntry.
-- Po udanej płatności odpala BindableEvent PvPGateEvent → skrypt bramy (brama_pvp) otwiera bramę.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local COST = Config.PvPEntry.Cost

-- BindableEvent — most do skryptu bramy (brama_pvp nasłuchuje przez WaitForChild)
local gateEvent  = Instance.new("BindableEvent")
gateEvent.Name   = "PvPGateEvent"
gateEvent.Parent = ServerScriptService

local Events         = ReplicatedStorage:WaitForChild("Events")
local OpenPvPEntry   = Events:WaitForChild("OpenPvPEntry")
local BuyPvPEntry    = Events:WaitForChild("BuyPvPEntry")
local PvPEntryResult = Events:WaitForChild("PvPEntryResult")

-- Throttle anty-spam (0.5s na gracza)
local lastAction: { [Player]: number } = {}

-- ── Płatność ────────────────────────────────────────────────────────────────
BuyPvPEntry.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.5 then return end
	lastAction[player] = now

	local data = PlayerDataService.GetData(player)
	if data.Zlotowki < COST then
		PvPEntryResult:FireClient(player, { success = false, reason = "broke" })
		return
	end

	data.Zlotowki -= COST
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	-- Otwórz bramę (skrypt bramy resetuje licznik przejść Sensora)
	gateEvent:Fire(player.UserId)

	PvPEntryResult:FireClient(player, { success = true })
	print(string.format("[PvPEntryService] %s zapłacił %d PLN za wstęp — pozostało %s",
		player.Name, COST, tostring(data.Zlotowki)))
end)

-- ── ProximityPrompt na KasjerPVP ──────────────────────────────────────────────
local function pickAnchor(rig: Instance): BasePart?
	if rig:IsA("BasePart") then return rig :: BasePart end
	if rig:IsA("Model") then
		return rig:FindFirstChild("Head") :: BasePart?
			or rig:FindFirstChild("HumanoidRootPart") :: BasePart?
			or rig.PrimaryPart
			or rig:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Dopasowanie odporne na spacje/wielkość liter: nazwa po lower + usunięte spacje
local function normalize(s: string): string
	return string.gsub(string.lower(s), "%s", "")
end

local function findKasjer(name: string): Instance?
	-- 1) dokładne dopasowanie
	local exact = workspace:FindFirstChild(name, true)
	if exact then return exact end
	-- 2) fuzzy: nazwa zawiera "kasjer" i "pvp" (po normalizacji), preferuj Model/BasePart
	local target = normalize(name)
	for _, d in workspace:GetDescendants() do
		local n = normalize(d.Name)
		if n == target or (string.find(n, "kasjer") and string.find(n, "pvp")) then
			if d:IsA("Model") or d:IsA("BasePart") then
				return d
			end
		end
	end
	return nil
end

local function setupKasjer()
	local name = Config.PvPEntry.KasjerName
	local rig
	for _ = 1, 30 do
		rig = findKasjer(name)
		if rig then break end
		task.wait(1)
	end
	if not rig then
		warn("[PvPEntryService] Nie znaleziono '" .. name .. "' w workspace. Kandydaci z 'kasjer' w nazwie:")
		local any = false
		for _, d in workspace:GetDescendants() do
			if string.find(string.lower(d.Name), "kasjer") then
				print("   • '" .. d.Name .. "' (" .. d.ClassName .. ") @ " .. d:GetFullName())
				any = true
			end
		end
		if not any then print("   (żadnych — rig nie istnieje pod tą nazwą)") end
		return
	end
	print("[PvPEntryService] Znaleziono riga →", rig:GetFullName(), "(", rig.ClassName, ")")

	local anchor = pickAnchor(rig)
	if not anchor then
		warn("[PvPEntryService] '" .. name .. "' nie ma BasePart (Head/HRP/PrimaryPart) na prompt")
		return
	end

	local prompt = anchor:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = anchor
	end
	prompt.ActionText            = Config.PvPEntry.PromptText
	prompt.ObjectText            = Config.PvPEntry.PromptObject
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Enabled               = true

	prompt.Triggered:Connect(function(player: Player)
		OpenPvPEntry:FireClient(player)
	end)

	print("[PvPEntryService] Kasjer gotowy → prompt na", anchor:GetFullName())
end

-- Nie blokuj reszty skryptu — szukanie riga w osobnym wątku
task.spawn(setupKasjer)

Players.PlayerRemoving:Connect(function(p) lastAction[p] = nil end)

print("[PvPEntryService] Gotowy — wstęp:", COST, "PLN (za każdym razem)")
