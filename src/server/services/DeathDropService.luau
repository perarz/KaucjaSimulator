-- DeathDropService.luau
-- Gdy gracz umrze:
--   1. Wszystkie butelki z plecaka spadają wokół ciała, rozsiane w promieniu 5 stoodów
--   2. Butelki są ANCHORED + CanCollide=false → nie kolidują z graczami ani niczym, nie da się ich poturlać
--   3. Każda butelka jest cała (tak jak normalny spawn — BottleService.SpawnBottle robi anchored model w jednym kawałku)
--   4. Inni gracze mogą podnieść (ProximityPrompt aktywny). Sam zmarły gracz nie może (DeathDropOwner attribute → block w BottleService.CollectBottle)
--   5. Gracz natychmiast respawnuje (LoadCharacter po 0.5s)
-- Syrop dziadka NIE drop'uje się (quest item).
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace           = game:GetService("Workspace")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))
local BottleService     = require(ServerScriptService:WaitForChild("BottleService"))

local UpdateHUD = ReplicatedStorage:WaitForChild("Events"):WaitForChild("UpdateHUD")

local SCATTER_RADIUS = 5    -- studs — promień rozsypania wokół ciała
local DROP_HEIGHT    = 2    -- studs nad ziemią (od powierzchni której dotyka raycast)
local RESPAWN_DELAY  = 0    -- instant respawn po śmierci
local OWN_DROP_COOLDOWN_SEC = 5  -- przez tyle sekund właściciel nie może podnieść własnego dropu (anty-spam)

-- ── Raycast w dół: znajdź wysokość ziemi pod podaną pozycją XZ ──
-- Iteracyjnie pomija invisible trigger parts (PVPZone, BottleSpawnAreas itp.) — wszystko o Transparency >= 0.9.
local function findGroundY(x: number, z: number, fallbackY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(exclude, p.Character) end
	end
	local bottlesFolder = Workspace:FindFirstChild("Bottles")
	if bottlesFolder then table.insert(exclude, bottlesFolder) end
	params.FilterDescendantsInstances = exclude

	local origin    = Vector3.new(x, fallbackY + 50, z)
	local direction = Vector3.new(0, -500, 0)

	-- Pętla: jeśli trafimy invisible trigger (np. PVPZone), dorzucamy do exclude i strzelamy ponownie
	for _ = 1, 10 do
		local result = Workspace:Raycast(origin, direction, params)
		if not result then break end
		if result.Instance.Transparency >= 0.9 then
			table.insert(exclude, result.Instance)
			params.FilterDescendantsInstances = exclude
		else
			return result.Position.Y + DROP_HEIGHT
		end
	end
	return fallbackY  -- fallback: poziom ciała
end

-- ── Znajdź główny BasePart postaci (HRP/Torso/Head/cokolwiek) ──
local function findBodyAnchor(character: Model): BasePart?
	for _, name in ipairs({ "HumanoidRootPart", "Torso", "UpperTorso", "Head" }) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p :: BasePart end
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

-- ── Główna logika: zrzuć butelki + wyzeruj plecak + sync HUD ──
local function dropBottlesOnDeath(player: Player, character: Model)
	local data = PlayerDataService.GetData(player)
	if not data or not data.BackpackContents then return end

	-- Policz łączną liczbę butelek
	local total = 0
	for _, count in pairs(data.BackpackContents) do
		if type(count) == "number" then total += count end
	end
	if total == 0 then return end

	-- Pozycja ciała
	local bodyAnchor = findBodyAnchor(character)
	if not bodyAnchor then return end
	local center = bodyAnchor.Position

	print(string.format("[DeathDropService] %s zginął — drop %d butelek wokół (%d, %d, %d)",
		player.Name, total, math.floor(center.X), math.floor(center.Y), math.floor(center.Z)))

	-- Spawn każdej butelki w losowym miejscu w promieniu SCATTER_RADIUS,
	-- na wysokości znalezionej raycastem (na ziemi, nie lewitującej)
	for rarity, count in pairs(data.BackpackContents) do
		if type(count) == "number" and count > 0 then
			for _ = 1, count do
				local angle = math.random() * math.pi * 2
				local dist  = math.random() * SCATTER_RADIUS
				local x     = center.X + math.cos(angle) * dist
				local z     = center.Z + math.sin(angle) * dist
				local y     = findGroundY(x, z, center.Y)
				pcall(function()
					BottleService.SpawnBottle(Vector3.new(x, y, z), rarity, nil, {
						DeathDropOwner    = player.UserId,
						DeathDropExpires  = os.clock() + OWN_DROP_COOLDOWN_SEC,
					})
				end)
			end
		end
	end

	-- Wyzeruj plecak
	for rarity in pairs(data.BackpackContents) do
		data.BackpackContents[rarity] = 0
	end

	-- Sync HUD klienta (saldo zł / upgrady nie ruszane)
	local cap = Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = cap,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
	})

	PlayerDataService.SaveData(player)
end

-- ── Hook na śmierć: drop + natychmiastowy respawn ──
local function onCharacter(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then return end

	local diedHandled = false
	hum.Died:Connect(function()
		if diedHandled then return end
		diedHandled = true
		dropBottlesOnDeath(player, character)
		if RESPAWN_DELAY > 0 then
			task.delay(RESPAWN_DELAY, function()
				if player and player.Parent then player:LoadCharacter() end
			end)
		else
			task.spawn(function()
				if player and player.Parent then player:LoadCharacter() end
			end)
		end
	end)
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
	if p.Character then task.spawn(onCharacter, p, p.Character) end
end

return {}
