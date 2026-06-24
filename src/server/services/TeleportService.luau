-- TeleportService.luau
-- Teleportacja gracza do partów w workspace["strefy teleportu"]. Server weryfikuje klucz
-- (musi być w Config.Teleport.Locations) i przenosi postać na part o tej samej nazwie.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local Events     = ReplicatedStorage:WaitForChild("Events")
local TeleportTo = Events:WaitForChild("TeleportTo")

local cfg = Config.Teleport or {}

local TeleportService = {}

-- Dozwolone klucze (anti-exploit — tylko z configu) + wymagane strefy (requiresZone)
local allowed: { [string]: boolean } = {}
local requiresZone: { [string]: string } = {}
for _, loc in ipairs(cfg.Locations or {}) do
	allowed[loc.key] = true
	if loc.requiresZone then requiresZone[loc.key] = loc.requiresZone end
end

local lastTp: { [Player]: number } = {}

local function getFolder(): Instance?
	return workspace:FindFirstChild(cfg.FolderName or "strefymapy")
end

-- Pozycja docelowa partu (BasePart lub Model)
local function targetCFrame(key: string): CFrame?
	local folder = getFolder()
	if not folder then
		warn("[TeleportService] Brak katalogu '" .. (cfg.FolderName or "strefymapy") .. "' w workspace")
		return nil
	end
	local target = folder:FindFirstChild(key)
	if not target then
		warn("[TeleportService] Brak partu/locacji '" .. key .. "' w", folder:GetFullName())
		return nil
	end
	local pos: Vector3
	if target:IsA("BasePart") then
		pos = (target :: BasePart).Position
	elseif target:IsA("Model") then
		pos = target:GetPivot().Position
	else
		local bp = target:FindFirstChildWhichIsA("BasePart", true)
		if not bp then return nil end
		pos = bp.Position
	end
	return CFrame.new(pos + Vector3.new(0, cfg.HeightOffset or 5, 0))
end

TeleportTo.OnServerEvent:Connect(function(player: Player, key: any)
	if type(key) ~= "string" or not allowed[key] then return end
	local now = os.clock()
	if (lastTp[player] or 0) + (cfg.Throttle or 0.5) > now then return end
	lastTp[player] = now

	-- Gating strefowy (np. Pustynia) — gracz musi mieć kupioną strefę.
	local zone = requiresZone[key]
	if zone then
		local data = PlayerDataService.GetData(player)
		if not (data and data.OwnedZones and data.OwnedZones[zone]) then return end
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hrp) then return end

	local cf = targetCFrame(key)
	if not cf then return end
	-- Zachowaj orientację gracza (tylko pozycja się zmienia)
	char:PivotTo(CFrame.new(cf.Position) * (char:GetPivot() - char:GetPivot().Position))
end)

Players.PlayerRemoving:Connect(function(p) lastTp[p] = nil end)

print("[TeleportService] gotowy — lokalizacje:", #(cfg.Locations or {}))

return TeleportService
