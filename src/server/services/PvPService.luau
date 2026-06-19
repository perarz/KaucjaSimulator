-- PvPService.luau
-- Strefa PvP: gdy gracz wejdzie do workspace.StrefaPVP.PVPZone, dostaje ReplicatedStorage.Sword
-- i traci ForceField (może zadawać/przyjmować obrażenia). Wyjście → miecz usunięty.
-- Detekcja: server-side poll co POLL_INTERVAL — niezawodne, niewrażliwe na overlap z innymi partami w strefie.
-- Damage: ClassicSword z toolboxa ma własne skrypty, działa na Humanoid:TakeDamage. Roblox FF chroni nie-PvP graczy.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local POLL_INTERVAL = 0.25
local SWORD_TAG     = "__PvPSword"

local function getZone(): BasePart?
	-- Akceptujemy: workspace.PVPZone (bezpośrednio) ALBO głębiej w dowolnym folderze
	local zone = workspace:FindFirstChild("PVPZone", true)
	if zone and zone:IsA("BasePart") then return zone :: BasePart end
	return nil
end

local function getSwordTemplate(): Tool?
	local t = ReplicatedStorage:FindFirstChild("Sword")
	return (t and t:IsA("Tool")) and (t :: Tool) or nil
end

local function isInZone(player: Player, zone: BasePart): boolean
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return false end
	local localPos = zone.CFrame:PointToObjectSpace((hrp :: BasePart).Position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function hasSword(player: Player): boolean
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:GetAttribute(SWORD_TAG) then return true end
		end
	end
	local char = player.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute(SWORD_TAG) then return true end
		end
	end
	return false
end

local function giveSword(player: Player)
	print("[PvPService] giveSword →", player.Name)
	local template = getSwordTemplate()
	if not template then
		warn("[PvPService] Brak ReplicatedStorage.Sword (Tool) — nie mogę dać miecza")
		return
	end
	local char = player.Character
	if not char then
		warn("[PvPService] Brak Character dla", player.Name)
		return
	end

	-- Zdejmij ForceField (Roblox dodaje na spawn) — żeby gracz w strefie mógł przyjmować obrażenia
	local ffCount = 0
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("ForceField") then c:Destroy(); ffCount += 1 end
	end
	print(string.format("[PvPService] %s: usunięto ForceField=%d", player.Name, ffCount))

	if hasSword(player) then
		print("[PvPService]", player.Name, "już ma miecz — pomijam clone")
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		warn("[PvPService] Brak Backpack dla", player.Name)
		return
	end

	local clone = template:Clone()
	clone:SetAttribute(SWORD_TAG, true)
	clone.Parent = backpack
	print("[PvPService]", player.Name, "→ miecz dodany do Backpack")
end

local function removeSword(player: Player)
	print("[PvPService] removeSword →", player.Name)
	local count = 0
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:GetAttribute(SWORD_TAG) then t:Destroy(); count += 1 end
		end
	end
	local char = player.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute(SWORD_TAG) then t:Destroy(); count += 1 end
		end
	end
	print(string.format("[PvPService] %s: zniszczono %d miecz(y)", player.Name, count))
end

local inZone: { [Player]: boolean } = {}

-- ── Hitbox normalization: w strefie wszyscy mają scale=1 (mali skinowie nie wygrywają przewagą) ──
local SCALE_NAMES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale", "BodyTypeScale", "BodyProportionScale" }
local originalScales: { [Player]: { [string]: number } } = {}

local function normalizeScales(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R15 then return end  -- R6 nie ma scales

	local saved = {}
	for _, name in ipairs(SCALE_NAMES) do
		local v = hum:FindFirstChild(name)
		if v and v:IsA("NumberValue") then
			saved[name] = v.Value
			v.Value = 1
		end
	end
	originalScales[player] = saved
end

local function restoreScales(player: Player)
	local saved = originalScales[player]
	if not saved then return end
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			for name, val in pairs(saved) do
				local v = hum:FindFirstChild(name)
				if v and v:IsA("NumberValue") then v.Value = val end
			end
		end
	end
	originalScales[player] = nil
end

-- ── Startup diagnostics ────────────────────────────────────────────────────
task.spawn(function()
	task.wait(2)
	print("[PvPService] === diagnostyka startowa ===")
	local zone = workspace:FindFirstChild("PVPZone", true)
	print("[PvPService] PVPZone:", zone and zone:GetFullName() or "BRAK",
		zone and ("isBasePart=" .. tostring(zone:IsA("BasePart"))) or "")
	if zone and zone:IsA("BasePart") then
		print(string.format("[PvPService] PVPZone size=%s pos=%s anchored=%s cancollide=%s",
			tostring(zone.Size), tostring(zone.Position),
			tostring(zone.Anchored), tostring(zone.CanCollide)))
	end
	local sword = ReplicatedStorage:FindFirstChild("Sword")
	print("[PvPService] ReplicatedStorage.Sword:", sword and sword:GetFullName() or "BRAK",
		sword and ("class=" .. sword.ClassName) or "")
	print("[PvPService] === koniec diagnostyki ===")
end)

-- Polling loop
task.spawn(function()
	-- Czekaj na strefę
	local waited = 0
	while not getZone() do
		task.wait(1); waited += 1
		if waited == 5 then
			warn("[PvPService] Nadal brak PVPZone po 5s — sprawdź strukturę workspace")
		end
	end
	print("[PvPService] PVPZone gotowa →", getZone():GetFullName(), "— start poll co", POLL_INTERVAL, "s")

	local tickCount = 0
	while true do
		task.wait(POLL_INTERVAL)
		tickCount += 1
		local zone = getZone()
		if zone then
			for _, p in ipairs(Players:GetPlayers()) do
				local should = isInZone(p, zone)
				local was = inZone[p] == true
				-- Co ~5s wypisz status każdego gracza dla diagnostyki (na początku)
				if tickCount % 20 == 0 then
					local char = p.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					print(string.format("[PvPService] tick %d: %s hrp=%s inZone=%s was=%s",
						tickCount, p.Name,
						hrp and tostring((hrp :: BasePart).Position) or "nil",
						tostring(should), tostring(was)))
				end
				if should and not was then
					print("[PvPService] WEJŚCIE do strefy:", p.Name)
					inZone[p] = true
					giveSword(p)
					normalizeScales(p)
				elseif not should and was then
					print("[PvPService] WYJŚCIE ze strefy:", p.Name)
					inZone[p] = nil
					removeSword(p)
					restoreScales(p)
				end
			end
		end
	end
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(p) inZone[p] = nil; originalScales[p] = nil end)

-- Reset flagi na respawn — nowy character zawsze wchodzi z ForceField, nasz poll wykryje wejście do strefy ponownie
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function() inZone[player] = nil end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function() inZone[p] = nil end)
end

return {}
