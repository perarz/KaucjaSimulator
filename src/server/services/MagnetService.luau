-- MagnetService.luau
-- Magnes — używany item z ekwipunku. Aktywacja na Config.Magnet.DurationSec (2 min):
-- serwer co Config.Magnet.TickInterval iteruje workspace.Bottles i zbiera te w promieniu
-- BaseRadius * RadiusMultiplier. Każda butelka przechodzi przez BottleService.TryCollectBottle
-- — czyli respektuje plecak/cooldown drop'a/atrybuty.
--
-- MagnetCount NIE stackuje się w slotach EQ (1 magnes = 1 slot) — to logika klienta.
-- Tu trzymamy tylko liczbę sztuk + state aktywnego efektu per gracz.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))
local BottleService     = require(ServerScriptService:WaitForChild("BottleService"))

local Events             = ReplicatedStorage:WaitForChild("Events")
local UseMagnet          = Events:WaitForChild("UseMagnet")
local MagnetStatusUpdate = Events:WaitForChild("MagnetStatusUpdate")

local MagnetService = {}

local cfg = Config.Magnet

-- Stan per gracz: kiedy efekt się kończy (os.clock) + wątek sweep
type ActiveMagnet = { endsAt: number, thread: thread }
local active: { [Player]: ActiveMagnet } = {}

local function getRadius(): number
	return cfg.BaseRadius * cfg.RadiusMultiplier
end

local function getBottlePos(bottle: Instance): Vector3?
	if bottle:IsA("BasePart") then return (bottle :: BasePart).Position end
	if bottle:IsA("Model") then return (bottle :: Model):GetPivot().Position end
	return nil
end

-- Wysyła aktualny status do klienta (count + ile sekund zostało, 0 gdy nieaktywny)
function MagnetService.PushStatus(player: Player)
	if not player or not player.Parent then return end
	local data = PlayerDataService.GetData(player)
	local secondsLeft = 0
	local a = active[player]
	if a then
		secondsLeft = math.max(0, a.endsAt - os.clock())
	end
	MagnetStatusUpdate:FireClient(player, {
		count        = data.MagnetCount or 0,
		secondsLeft  = secondsLeft,
		durationSec  = cfg.DurationSec,
		active       = secondsLeft > 0,
	})
end

local function getCarriedCount(data): number
	local carried = 0
	for _, c in pairs(data.BackpackContents) do carried += c end
	if data.Grandpa and data.Grandpa.hasSyrup then carried += 1 end
	carried += data.MagnetCount or 0
	carried += #(data.Pets or {})       -- pet = 1 slot
	return carried
end

-- Public API — używane przez AdminService / CodeService / questy.
-- Respektuje pojemność plecaka (każdy magnes = 1 slot). Zwraca liczbę faktycznie przyznanych.
function MagnetService.Grant(player: Player, amount: number?): number
	if not player or not player.Parent then return 0 end
	local n = math.max(1, math.floor(amount or 1))
	local data = PlayerDataService.GetData(player)
	local capacity = Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity
	local carried  = getCarriedCount(data)
	local space    = math.max(0, capacity - carried)
	local granted  = math.min(n, space)
	if granted <= 0 then
		MagnetService.PushStatus(player)
		return 0
	end
	data.MagnetCount = (data.MagnetCount or 0) + granted
	PlayerDataService.SaveData(player)
	MagnetService.PushStatus(player)
	return granted
end

local function deactivate(player: Player)
	local a = active[player]
	if not a then return end
	active[player] = nil
	MagnetService.PushStatus(player)
end

local function sweepOnce(player: Player)
	if not player.Parent then return end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hrp then return end

	local bottlesFolder = workspace:FindFirstChild("Bottles")
	if not bottlesFolder then return end

	local radius   = getRadius()
	local rSquared = radius * radius
	local hrpPos   = hrp.Position

	-- Snapshot childów — TryCollectBottle destroyuje, więc i tak iterujemy bezpiecznie
	for _, bottle in ipairs(bottlesFolder:GetChildren()) do
		local pos = getBottlePos(bottle)
		if pos and (pos - hrpPos).Magnitude <= radius then
			-- silent=true: nie spamuj klienta "full" przy każdym ticku z pełnym plecakiem
			-- skipDistanceCheck=true: magnes nie podlega 12-stud sanity (jesteśmy w jego radius)
			BottleService.TryCollectBottle(player, bottle, { silent = true, skipDistanceCheck = true })
		end
	end
end

local function activate(player: Player)
	local existing = active[player]
	if existing then return end  -- już aktywny — nie restartuj

	local endsAt = os.clock() + cfg.DurationSec
	local state: ActiveMagnet = { endsAt = endsAt, thread = nil :: any }
	active[player] = state

	state.thread = task.spawn(function()
		while active[player] == state and os.clock() < state.endsAt do
			local ok, err = pcall(sweepOnce, player)
			if not ok then warn("[MagnetService] sweep error:", err) end
			task.wait(cfg.TickInterval)
		end
		-- Wygaśnięcie efektu
		if active[player] == state then
			deactivate(player)
		end
	end)

	MagnetService.PushStatus(player)
end

UseMagnet.OnServerEvent:Connect(function(player: Player)
	if not player or not player.Parent then return end
	if active[player] then return end  -- już aktywny — ignoruj
	local data = PlayerDataService.GetData(player)
	if (data.MagnetCount or 0) <= 0 then return end

	data.MagnetCount -= 1
	-- NIE SaveData w hot path — DataStore yielduje 1-2s i opóźnia zniknięcie z EQ.
	-- Persystencja przez auto-save co 60s + PlayerRemoving. Ryzyko utraty zużycia <60s akceptowalne.
	activate(player)  -- już woła PushStatus z secondsLeft + nowym count
end)

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(function()
		PlayerDataService.GetData(player)
		task.wait(2)
		if player.Parent then MagnetService.PushStatus(player) end
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local a = active[player]
	if a then
		a.endsAt = 0  -- pętla sama wyjdzie przy następnym sprawdzeniu
		active[player] = nil
	end
end)

-- Tick co sekundę: odśwież klientowi countdown HUD'a
task.spawn(function()
	while true do
		task.wait(1)
		for player, a in pairs(active) do
			if player.Parent then
				MagnetService.PushStatus(player)
			end
			-- Cleanup dla zawisłych state'ów (na wszelki wypadek)
			if os.clock() >= a.endsAt + 0.5 then
				active[player] = nil
				if player.Parent then MagnetService.PushStatus(player) end
			end
		end
	end
end)

print("[MagnetService] Gotowy — radius =", getRadius(), "studs, czas =", cfg.DurationSec, "s")

return MagnetService
