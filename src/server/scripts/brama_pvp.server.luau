-- brama_pvp.server.luau
-- Wrzuć do: workspace...bramawejsciowa (jako Script — zastąp treść istniejącego 'Script')
-- Brama wstępu do PvP:
--   • otwiera się po zapłaceniu 300 PLN (PvPEntryService → PvPGateEvent)
--   • Sensor (part przed bramą): PIERWSZE przejście gracza ignorowane, DRUGIE zamyka bramę
-- Wymaga dzieci w script.Parent: Gate_2A, Gate_2B (każde z MeshPart1..4), Sensor

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local parent = script.Parent
local gateA  = parent:WaitForChild("Gate_2A")
local gateB  = parent:WaitForChild("Gate_2B")
local sensor = parent:WaitForChild("Sensor")

-- ── Strojenie ───────────────────────────────────────────────────────────────
local ANIM_TIME       = 0.45
local EASING_STYLE    = Enum.EasingStyle.Sine
local EASING_DIR      = Enum.EasingDirection.InOut
local CROSS_COOLDOWN  = 1.5   -- s — jedno przejście liczone raz (anti-double-count)
local PASSES_TO_CLOSE = 2     -- 1. przejście ignorowane, 2. zamyka

-- Sensor: gracz ma przez niego PRZEJŚĆ, więc bez kolizji, ale z detekcją dotyku
if sensor:IsA("BasePart") then
	sensor.CanCollide = false
	sensor.CanTouch   = true
end

-- ── Waypointy zapamiętane RAZ (zanim cokolwiek się ruszy) ─────────────────────
-- Dzięki temu open i close używają tych samych punktów i działają w nieskończoność.
local function capture(gate)
	return {
		gate.MeshPart1.CFrame,
		gate.MeshPart2.CFrame,
		gate.MeshPart3.CFrame,
		gate.MeshPart4.CFrame,
	}
end
local waypointsA = capture(gateA)
local waypointsB = capture(gateB)

-- ── Animacja ruchu wzdłuż ścieżki CFrame ──────────────────────────────────────
local function tweenAlongPath(part, cframes, totalTime, easingStyle, easingDirection)
	local n = #cframes - 1
	if n <= 0 then return end
	local segLengths, totalLength = {}, 0
	for i = 1, n do
		local dist = (cframes[i + 1].Position - cframes[i].Position).Magnitude
		segLengths[i] = math.max(dist, 0.001)
		totalLength += segLengths[i]
	end
	local startTime = os.clock()
	while true do
		local elapsed = os.clock() - startTime
		local alpha   = math.clamp(elapsed / totalTime, 0, 1)
		local eased   = TweenService:GetValue(alpha, easingStyle, easingDirection)
		local target  = eased * totalLength
		local accum   = 0
		for i = 1, n do
			if target <= accum + segLengths[i] or i == n then
				local segAlpha = math.clamp((target - accum) / segLengths[i], 0, 1)
				part.CFrame = cframes[i]:Lerp(cframes[i + 1], segAlpha)
				break
			end
			accum += segLengths[i]
		end
		if alpha >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	part.CFrame = cframes[n + 1]
end

-- reverse=false → otwieranie (1→4), reverse=true → zamykanie (4→1)
local function moveGate(gate, waypoints, reverse)
	local path = {}
	if reverse then
		for i = #waypoints, 1, -1 do path[#path + 1] = waypoints[i] end
	else
		for i = 1, #waypoints do path[#path + 1] = waypoints[i] end
	end
	tweenAlongPath(gate.MeshPart1, path, ANIM_TIME, EASING_STYLE, EASING_DIR)
end

local function moveBoth(reverse)
	local doneA, doneB = false, false
	task.spawn(function() moveGate(gateA, waypointsA, reverse); doneA = true end)
	task.spawn(function() moveGate(gateB, waypointsB, reverse); doneB = true end)
	while not (doneA and doneB) do RunService.Heartbeat:Wait() end
end

-- ── Stan bramy ────────────────────────────────────────────────────────────────
local isOpen        = false
local animating     = false
local passes        = 0
local crossDebounce: { [Player]: boolean } = {}

local function openGate()
	if isOpen or animating then return end
	animating = true
	passes = 0                       -- reset licznika przejść na nową sesję
	parent:SetAttribute("DoorOpen", true)
	moveBoth(false)
	animating = false
	isOpen = true
	print("[brama_pvp] Brama OTWARTA")
end

local function closeGate()
	if not isOpen or animating then return end
	animating = true
	moveBoth(true)
	animating = false
	isOpen = false
	passes = 0
	parent:SetAttribute("DoorOpen", false)
	print("[brama_pvp] Brama ZAMKNIĘTA")
end

-- ── Sensor: licz przejścia gracza ────────────────────────────────────────────
sensor.Touched:Connect(function(hit)
	if not isOpen or animating then return end           -- działa tylko gdy brama otwarta
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if not player then return end
	if crossDebounce[player] then return end             -- jedno przejście = jeden licznik
	crossDebounce[player] = true
	task.delay(CROSS_COOLDOWN, function() crossDebounce[player] = nil end)

	passes += 1
	print(string.format("[brama_pvp] przejście %d/%d (%s)", passes, PASSES_TO_CLOSE, player.Name))
	if passes >= PASSES_TO_CLOSE then
		closeGate()
	end
end)

-- ── Otwarcie na sygnał z PvPEntryService ──────────────────────────────────────
local gateEvent = ServerScriptService:WaitForChild("PvPGateEvent", 30)
if not gateEvent then
	warn("[brama_pvp] Brak PvPGateEvent — upewnij się że PvPEntryService jest w ServerScriptService")
else
	gateEvent.Event:Connect(function()
		openGate()
	end)
	print("[brama_pvp] Gotowy — czekam na opłatę wstępu")
end
