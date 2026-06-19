-- SyrupService.luau
-- Spawnuje syrop dziadka per gracz w jednej z 3 lokacji (workspace.SyrupSpawnPoints).
-- Każdy model ma attribute "OwnerUserId" — klient filtruje LocalTransparencyModifier,
-- serwer gate'uje pickup do właściciela (defense in depth).
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config              = require(ReplicatedStorage.Config)
local PlayerDataService   = require(ServerScriptService.PlayerDataService)

local SyrupService = {}

local Events             = ReplicatedStorage:WaitForChild("Events")
local SyrupPickupResult  = Events:WaitForChild("SyrupPickupResult")
local UpdateHUD          = Events:WaitForChild("UpdateHUD")

local cfg = Config.GrandpaQuest

-- Workspace setup
local activeFolder: Folder
local spawnPoints:  Folder?

-- Per-player live model
local activeModels: { [Player]: Instance } = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name   = name
		f.Parent = parent
	end
	return f :: Folder
end

local function getSpawnPart(index: number): BasePart?
	if not spawnPoints then return nil end
	local part = spawnPoints:FindFirstChild("SyrupSpawn" .. index)
	if part and part:IsA("BasePart") then return part :: BasePart end
	return nil
end

local function getCarriedCount(data): number
	local carried = 0
	for _, count in pairs(data.BackpackContents) do carried += count end
	if data.Grandpa and data.Grandpa.hasSyrup then carried += 1 end
	return carried
end

-- Tworzy fizyczny model syropu w workspace.SyrupActive z attribute OwnerUserId
local function buildSyrupModel(position: Vector3, ownerUserId: number): Model
	-- Fallback: cylinder w kolorze syropu (gdy brak ReplicatedStorage.SyrupModel)
	local template = ReplicatedStorage:FindFirstChild("SyrupModel")
	local model: Model

	if template and template:IsA("Model") then
		model = template:Clone()
		model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored   = true
				d.CanCollide = false
				d.CastShadow = false
			end
		end
	else
		model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name        = "SyrupBottle"
		part.Shape       = Enum.PartType.Cylinder
		part.Size        = Vector3.new(2, 1.2, 1.2)
		part.Anchored    = true
		part.CanCollide  = false
		part.Color       = cfg.SyrupColor
		part.Material    = Enum.Material.Glass
		part.CastShadow  = false
		part.CFrame      = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		part.Parent      = model
		model.PrimaryPart = part
	end

	model.Name = "Syrup_" .. ownerUserId
	model:SetAttribute("OwnerUserId", ownerUserId)

	-- Anchor part dla prompt + światła
	local anchorPart = model.PrimaryPart
	if not anchorPart then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then anchorPart = d :: BasePart; break end
		end
	end

	if anchorPart then
		-- Brązowo-złote światło żeby było widać z daleka
		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range      = 14
		light.Color      = cfg.SyrupLight
		light.Parent     = anchorPart

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText            = "Podnieś"
		prompt.ObjectText            = "Syrop Dziadka"
		prompt.MaxActivationDistance = 6
		prompt.HoldDuration          = 0
		prompt.RequiresLineOfSight   = false
		prompt.Parent                = anchorPart

		prompt.Triggered:Connect(function(player)
			-- Server gate: tylko właściciel (defense in depth — client też filtruje)
			if player.UserId ~= ownerUserId then return end
			SyrupService.HandlePickup(player)
		end)
	end

	return model
end

function SyrupService.SpawnFor(player: Player)
	-- Cleanup poprzedniego modelu jeśli istnieje
	local existing = activeModels[player]
	if existing then existing:Destroy(); activeModels[player] = nil end

	local data = PlayerDataService.GetData(player)
	if not data.Grandpa or data.Grandpa.state ~= "active" then return end
	if data.Grandpa.hasSyrup then return end  -- już w plecaku
	local idx = data.Grandpa.syrupLocation
	if idx < 1 or idx > 3 then return end

	local spawnPart = getSpawnPart(idx)
	if not spawnPart then
		warn("[SyrupService] Brak SyrupSpawn" .. idx .. " w workspace.SyrupSpawnPoints")
		return
	end

	-- Spawn lekko nad pivotem żeby nie tonął w podłodze
	local pos = spawnPart.Position + Vector3.new(0, 1.5, 0)
	local model = buildSyrupModel(pos, player.UserId)
	model.Parent = activeFolder
	activeModels[player] = model
end

function SyrupService.DespawnFor(player: Player)
	local m = activeModels[player]
	if m then m:Destroy() end
	activeModels[player] = nil
end

function SyrupService.HandlePickup(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data.Grandpa or data.Grandpa.state ~= "active" then return end
	if data.Grandpa.hasSyrup then return end  -- już ma — ignoruj

	-- Pojemność: syrop zajmuje 1 slot
	local capacity = Config.BackpackUpgrades[data.BackpackLevel].Capacity
	local carried  = getCarriedCount(data)
	if carried >= capacity then
		SyrupPickupResult:FireClient(player, { success = false, reason = "full" })
		return
	end

	-- Podnoszenie
	data.Grandpa.hasSyrup = true
	SyrupService.DespawnFor(player)
	PlayerDataService.SaveData(player)

	-- Sync HUD (carried count + hasSyrup flag dla inventory)
	local newCarried = getCarriedCount(data)
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = capacity,
		hasSyrup         = true,
		bottlesCarried   = newCarried,
	})

	SyrupPickupResult:FireClient(player, { success = true })

	-- Push state do UI questów — karta dziadka zmieni status na "ODDAJ DZIADKOWI"
	local ok, GrandpaService = pcall(function()
		return require(script.Parent.GrandpaService)
	end)
	if ok and GrandpaService then
		pcall(function() GrandpaService.PushStateTo(player) end)
	end
end

-- Public: hook do GrandpaService gdy gracz przyjmuje quest
function SyrupService.OnQuestAccepted(player: Player)
	SyrupService.SpawnFor(player)
end

-- Public: hook do GrandpaService gdy gracz oddaje syrop (lub reset)
function SyrupService.OnQuestCleared(player: Player)
	SyrupService.DespawnFor(player)
end

-- Bootstrap: folder + spawn dla graczy z aktywnym questem (po dołączeniu)
local function initWorkspace()
	activeFolder = getOrCreateFolder(workspace, "SyrupActive")
	spawnPoints  = workspace:FindFirstChild("SyrupSpawnPoints") :: Folder?
	if not spawnPoints then
		warn("[SyrupService] Brak workspace.SyrupSpawnPoints — quest dziadka nie spawnuje syropu")
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- Czekaj aż PlayerDataService wczyta dane
		local _ = PlayerDataService.GetData(player)
		task.wait(2)  -- buffer na pełny load + character spawn
		if player.Parent then
			SyrupService.SpawnFor(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	SyrupService.DespawnFor(player)
end)

initWorkspace()

return SyrupService
