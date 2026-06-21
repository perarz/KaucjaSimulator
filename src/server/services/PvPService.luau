-- PvPService.luau
-- Strefa PvP: gdy gracz wejdzie do workspace.StrefaPVP.PVPZone, dostaje ReplicatedStorage.Sword
-- i traci ForceField (może zadawać/przyjmować obrażenia). Wyjście → miecz usunięty.
-- Detekcja: server-side poll co POLL_INTERVAL — niezawodne, niewrażliwe na overlap z innymi partami w strefie.
-- Damage: ClassicSword z toolboxa ma własne skrypty, działa na Humanoid:TakeDamage. Roblox FF chroni nie-PvP graczy.
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events         = ReplicatedStorage:WaitForChild("Events")
local OpenPvPEntry   = Events:WaitForChild("OpenPvPEntry")
local ClosePvPEntry  = Events:WaitForChild("ClosePvPEntry")

-- BindableEvent na force dismount deski — tworzony przez DeskaService.
-- Może jeszcze nie istnieć przy require'cie PvPService, więc szukamy lazy.
local function fireForceDismount(player: Player)
	local ev = ServerScriptService:FindFirstChild("ForceDeskDismountEvent")
	if ev and ev:IsA("BindableEvent") then ev:Fire(player) end
end

-- Analogicznie pet — chowamy wizualnego peta gdy gracz wejdzie w PVPZone/SAFEZONE.
-- Efekty (HP/speed/money) nie znikają — tylko model.
local function fireForceDespawnPet(player: Player)
	local ev = ServerScriptService:FindFirstChild("ForceDespawnPetEvent")
	if ev and ev:IsA("BindableEvent") then ev:Fire(player) end
end

local POLL_INTERVAL  = 0.25
local SWORD_TAG      = "__PvPSword"
local GRACE_SECONDS  = 3   -- po wejściu: ForceField + sword.Enabled=false przez 3s

local function getZone(): BasePart?
	-- Akceptujemy: workspace.PVPZone (bezpośrednio) ALBO głębiej w dowolnym folderze
	local zone = workspace:FindFirstChild("PVPZone", true)
	if zone and zone:IsA("BasePart") then return zone :: BasePart end
	return nil
end

local function getSafeZone(): BasePart?
	-- workspace.SAFEZONE — bufor wokół wejścia do PvP. Gracz wewnątrz dostaje ForceField,
	-- żeby nie zginął w 0.25s okienku zanim PvPService go wypchnie ze strefy bez biletu.
	local sz = workspace:FindFirstChild("SAFEZONE", true)
	if sz and sz:IsA("BasePart") then return sz :: BasePart end
	return nil
end

local function isInBox(player: Player, box: BasePart): boolean
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return false end
	local localPos = box.CFrame:PointToObjectSpace((hrp :: BasePart).Position)
	local half = box.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
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

local function giveSwordWithGrace(player: Player)
	print("[PvPService] giveSwordWithGrace →", player.Name)
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

	-- Grace period: ZAMIAST od razu zdjąć ForceField, dodajemy nowy widoczny FF na GRACE_SECONDS.
	-- Wcześniejsze FFy (Roblox spawn) usuwamy żeby start gracji był deterministyczny.
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("ForceField") then c:Destroy() end
	end
	local graceFF = Instance.new("ForceField")
	graceFF.Visible = true
	graceFF.Name    = "PvPGraceFF"
	graceFF.Parent  = char

	-- Daj miecz (jeśli jeszcze nie ma), DISABLED przez czas gracji
	local sword: Tool? = nil
	if hasSword(player) then
		local bp = player:FindFirstChild("Backpack")
		if bp then
			for _, t in ipairs(bp:GetChildren()) do
				if t:GetAttribute(SWORD_TAG) and t:IsA("Tool") then sword = t :: Tool; break end
			end
		end
	else
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			local clone = template:Clone()
			clone:SetAttribute(SWORD_TAG, true)
			clone.Parent = backpack
			sword = clone
			print("[PvPService]", player.Name, "→ miecz dodany do Backpack")
		end
	end
	if sword then sword.Enabled = false end

	print(string.format("[PvPService] %s: grace %ds start (FF + sword disabled)", player.Name, GRACE_SECONDS))

	-- Po 3s: usuń graceFF, włącz miecz (jeśli gracz wciąż w grze)
	task.delay(GRACE_SECONDS, function()
		local ch = player.Character
		if ch then
			local ff = ch:FindFirstChild("PvPGraceFF")
			if ff then ff:Destroy() end
		end
		if sword and sword.Parent then sword.Enabled = true end
		print(string.format("[PvPService] %s: grace KONIEC", player.Name))
	end)
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

local inZone:        { [Player]: boolean } = {}
local guiShownFor:   { [Player]: boolean } = {}  -- czy GUI płatności jest aktualnie otwarte u gracza
local lastPushAt:    { [Player]: number  } = {}  -- timestamp ostatniego wypchnięcia (anti-spam)
local inSafeZone:    { [Player]: boolean } = {}  -- gracz w SAFEZONE → ma SafeZoneFF

local SAFE_FF_NAME = "SafeZoneFF"

local function addSafeZoneFF(player: Player)
	local char = player.Character
	if not char then return end
	if char:FindFirstChild(SAFE_FF_NAME) then return end  -- już ma
	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Name    = SAFE_FF_NAME
	ff.Parent  = char
	print("[PvPService] SAFEZONE +FF:", player.Name)
end

local function removeSafeZoneFF(player: Player)
	local char = player.Character
	if not char then return end
	local ff = char:FindFirstChild(SAFE_FF_NAME)
	if ff then ff:Destroy(); print("[PvPService] SAFEZONE -FF:", player.Name) end
end

-- Wypchnij gracza poza strefę PvP — radialnie od środka strefy w płaszczyźnie XZ,
-- na odległość większą niż największy wymiar strefy + bufor, żeby na pewno wyszedł.
-- Y zachowane, więc nie spadnie pod mapę ani nie wbije się w sufit.
local PUSH_COOLDOWN = 0.4  -- żeby nie teleportować co frame (poll co 0.25s i tak)
local function pushOutOfZone(player: Player, zone: BasePart)
	local now = os.clock()
	if lastPushAt[player] and now - lastPushAt[player] < PUSH_COOLDOWN then return end
	lastPushAt[player] = now

	local char = player.Character
	if not char then return end
	local hrpRaw = char:FindFirstChild("HumanoidRootPart")
	if not (hrpRaw and hrpRaw:IsA("BasePart")) then return end
	local hrp: BasePart = hrpRaw :: BasePart

	local zonePos = zone.Position
	local hrpPos  = hrp.Position
	local dx, dz  = hrpPos.X - zonePos.X, hrpPos.Z - zonePos.Z
	local mag     = math.sqrt(dx * dx + dz * dz)
	if mag < 0.1 then dx, dz, mag = 1, 0, 1 end  -- safety gdy stoisz w środku
	local nx, nz  = dx / mag, dz / mag

	local half      = zone.Size / 2
	-- Diagonalna przekątna XZ + bufor — gwarantuje wyjście niezależnie od rotacji strefy
	local pushDist  = math.sqrt(half.X * half.X + half.Z * half.Z) + 1
	local target    = Vector3.new(zonePos.X + nx * pushDist, hrpPos.Y, zonePos.Z + nz * pushDist)

	hrp.CFrame = CFrame.new(target)
end

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
		local zone     = getZone()
		local safeZone = getSafeZone()
		if zone then
			for _, p in ipairs(Players:GetPlayers()) do
				local should = isInZone(p, zone)
				local was = inZone[p] == true

				-- ── SAFEZONE check (osobno od PvP zone) ──
				if safeZone then
					local inSafe    = isInBox(p, safeZone)
					local wasInSafe = inSafeZone[p] == true
					if inSafe and not wasInSafe then
						inSafeZone[p] = true
						addSafeZoneFF(p)
						fireForceDismount(p)  -- zakaz deski w SAFEZONE
						fireForceDespawnPet(p)  -- pet znika w strefie
					elseif not inSafe and wasInSafe then
						inSafeZone[p] = nil
						removeSafeZoneFF(p)
					end
				end
				-- Co ~5s wypisz status każdego gracza dla diagnostyki (na początku)
				if tickCount % 20 == 0 then
					local char = p.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					print(string.format("[PvPService] tick %d: %s hrp=%s inZone=%s was=%s",
						tickCount, p.Name,
						hrp and tostring((hrp :: BasePart).Position) or "nil",
						tostring(should), tostring(was)))
				end
				if should then
					-- Gracz fizycznie w strefie — w PvPZone deska zabroniona w obu przypadkach
					fireForceDismount(p)
					fireForceDespawnPet(p)  -- pet znika w PVP arenie
					if was then
						-- Już wewnątrz z mieczem — nic nie robimy (nie sprawdzamy biletu,
						-- bo został skonsumowany przy wejściu i PvPAccess teraz=false)
					else
						-- Pierwsze wykrycie wejścia — sprawdź bilet
						if p:GetAttribute("PvPAccess") == true then
							p:SetAttribute("PvPAccess", false)
							print("[PvPService] WEJŚCIE (bilet skonsumowany):", p.Name)
							inZone[p] = true
							giveSwordWithGrace(p)
							normalizeScales(p)
							if guiShownFor[p] then
								ClosePvPEntry:FireClient(p)
								guiShownFor[p] = nil
							end
						else
							-- Brak biletu — wypychamy każdy tick + pokazujemy GUI (raz)
							pushOutOfZone(p, zone)
							if not guiShownFor[p] then
								print("[PvPService] WEJŚCIE bez biletu — wypycham + GUI:", p.Name)
								OpenPvPEntry:FireClient(p)
								guiShownFor[p] = true
							end
						end
					end
				else
					-- Gracz poza strefą
					if was then
						print("[PvPService] WYJŚCIE ze strefy:", p.Name)
						inZone[p] = nil
						removeSword(p)
						restoreScales(p)
					end
					-- guiShownFor NIE resetowane tutaj — żeby nie spamować GUI
					-- za każdym razem gdy gracz wyleci ze strefy (push i tak będzie pokazywał).
					-- Reset gdy gracz oddali się daleko (>20 studs od krawędzi strefy):
					local char = p.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					if guiShownFor[p] and hrp and hrp:IsA("BasePart") then
						local zPos = zone.Position
						local pos  = (hrp :: BasePart).Position
						local dx, dz = pos.X - zPos.X, pos.Z - zPos.Z
						local distFromCenter = math.sqrt(dx * dx + dz * dz)
						local half = zone.Size / 2
						local diag = math.sqrt(half.X * half.X + half.Z * half.Z)
						if distFromCenter > diag + 20 then
							-- Daleko od strefy — gracz odszedł, można zresetować flagę
							guiShownFor[p] = nil
							ClosePvPEntry:FireClient(p)
						end
					end
				end
			end
		end
	end
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(p)
	inZone[p] = nil
	originalScales[p] = nil
	guiShownFor[p] = nil
	lastPushAt[p] = nil
	inSafeZone[p] = nil
end)

-- Reset flagi na respawn — nowy character zawsze wchodzi z ForceField, poll wykryje wejście ponownie.
-- Wskazówka: bilet (PvPAccess) NIE jest resetowany przy respawnie — jeśli gracz zapłacił i zginął
-- zanim wszedł, to po respawnie wciąż ma bilet i wejdzie bez ponownej opłaty.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		inZone[player] = nil
		guiShownFor[player] = nil
		inSafeZone[player] = nil
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function()
		inZone[p] = nil
		guiShownFor[p] = nil
		inSafeZone[p] = nil
	end)
end

return {}
