-- PvPEntryService.server.luau
-- Płatność 300 PLN za wstęp do strefy PvP. Wstęp jednorazowy (per session) — po skonsumowaniu
-- przez PvPService trzeba znowu zapłacić następnym razem.
--
-- Flow:
--   1. Gracz wchodzi do strefy PVPZone (detekcja w PvPService)
--   2. PvPService sprawdza `player:GetAttribute("PvPAccess")`:
--      - true → konsumuje (= false), daje miecz + 3s grace (ForceField + tool disabled)
--      - false → fire OpenPvPEntry → klient pokazuje GUI płatności
--   3. Gracz klika ZAPŁAĆ → BuyPvPEntry → server ten serwis:
--      - pobiera 300 zł
--      - ustawia `player:SetAttribute("PvPAccess", true)`
--      - PvPService na następnym poll tickcie (≤0.25s) wpuści gracza
--   4. Gracz wychodzi ze strefy → PvPService usuwa miecz, gracz musi zapłacić znów

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Util              = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local COST = Config.PvPEntry.Cost

local Events         = ReplicatedStorage:WaitForChild("Events")
local BuyPvPEntry    = Events:WaitForChild("BuyPvPEntry")
local PvPEntryResult = Events:WaitForChild("PvPEntryResult")
local OpenPvPEntry   = Events:WaitForChild("OpenPvPEntry")

-- Throttle anty-spam (0.5s na gracza)
local lastAction: { [Player]: number } = {}

BuyPvPEntry.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.5 then return end
	lastAction[player] = now

	-- Już opłacony (nie skonsumował jeszcze) — odrzuć, żeby nie wziąć podwójnie kasy
	if player:GetAttribute("PvPAccess") == true then
		PvPEntryResult:FireClient(player, { success = false, reason = "already" })
		return
	end

	local data = PlayerDataService.GetData(player)
	if data.Zlotowki < COST then
		PvPEntryResult:FireClient(player, { success = false, reason = "broke" })
		return
	end

	data.Zlotowki -= COST
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	-- Ustaw flagę dostępu. PvPService na poll tickcie zobaczy i wpuści gracza
	-- (jeśli jest jeszcze w strefie) z mieczem + 3s grace.
	player:SetAttribute("PvPAccess", true)

	PvPEntryResult:FireClient(player, { success = true })
	print(string.format("[PvPEntryService] %s zapłacił %d PLN za wstęp — pozostało %s",
		player.Name, COST, tostring(data.Zlotowki)))
end)

Players.PlayerRemoving:Connect(function(p) lastAction[p] = nil end)

-- ── Opcjonalny ProximityPrompt na KasjerPVP (alternative entry punkt) ────────
-- Gracz może kupić bilet u NPC przed wejściem do strefy, nie musi wpaść by zobaczyć GUI.
local pickAnchor = Util.findAnchor

local kasjerHooked = false
local function attachKasjer(rig: Instance)
	if kasjerHooked then return end
	local anchor = pickAnchor(rig)
	if not anchor then return end
	local prompt = anchor:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = anchor
	end
	prompt.ActionText            = Config.PvPEntry.PromptText or "Zapłać za wstęp"
	prompt.ObjectText            = Config.PvPEntry.PromptObject or "Wstęp do PvP"
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Enabled               = true
	prompt.Triggered:Connect(function(player: Player)
		OpenPvPEntry:FireClient(player)
	end)
	kasjerHooked = true
	print("[PvPEntryService] KasjerPVP gotowy → prompt na", anchor:GetFullName())
end

local function findRig(name: string): Instance?
	local direct = workspace:FindFirstChild(name)
	if direct then return direct end
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == name and (inst:IsA("Model") or inst:IsA("BasePart")) then
			return inst
		end
	end
	return nil
end

task.spawn(function()
	local name = (Config.PvPEntry.KasjerName or "")
	if name == "" then return end
	-- Cyclical retry — bez warningu jeśli rig nie istnieje (jest opcjonalny)
	while not kasjerHooked do
		local rig = findRig(name)
		if rig then attachKasjer(rig); return end
		task.wait(3)
	end
end)
workspace.DescendantAdded:Connect(function(inst: Instance)
	if kasjerHooked then return end
	local name = Config.PvPEntry.KasjerName
	if name and inst.Name == name and (inst:IsA("Model") or inst:IsA("BasePart")) then
		attachKasjer(inst)
	end
end)

print("[PvPEntryService] Gotowy — wstęp:", COST, "PLN (jednorazowy, konsumowany przy wejściu do strefy)")
