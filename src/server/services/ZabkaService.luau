-- ZabkaService.luau
-- Sklep "Żabka" — sprzedaje magnesy za zł. ProximityPrompt na workspace.blok_zabki.KasjerZabka.
-- Walidacja: gracz ma zł + miejsce w plecaku (magnes zajmuje 1 slot pojemności).
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)
local MagnetService     = require(script.Parent.MagnetService)

local Events               = ReplicatedStorage:WaitForChild("Events")
local OpenZabka            = Events:WaitForChild("OpenZabka")
local BuyZabkaMagnet       = Events:WaitForChild("BuyZabkaMagnet")
local BuyZabkaMagnetResult = Events:WaitForChild("BuyZabkaMagnetResult")
local UpdateHUD            = Events:WaitForChild("UpdateHUD")

local cfg = Config.Zabka

-- Priorytet anchor'a: Head > HRP > UpperTorso/Torso > PrimaryPart > dowolny BasePart
local function findAnchor(model: Instance): BasePart?
	if model:IsA("BasePart") then return model :: BasePart end
	if not model:IsA("Model") then return nil end
	for _, name in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "Torso" }) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p :: BasePart end
	end
	local pp = (model :: Model).PrimaryPart
	if pp then return pp end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

-- ── ProximityPrompt na workspace.KasjerZabka ───────────────────────────────
task.spawn(function()
	print("[ZabkaService] === diagnostyka startowa ===")

	-- Listujemy dzieci workspace zawierające "kasjer" lub "zabka" w nazwie (case-insensitive)
	-- — pomaga gdy nazwa się różni od oczekiwanej
	print("[ZabkaService] Skanuję workspace dla 'kasjer'/'zabka':")
	local hits = 0
	for _, c in ipairs(workspace:GetDescendants()) do
		local n = string.lower(c.Name)
		if string.find(n, "kasjer") or string.find(n, "zabka") or string.find(n, "żabk") then
			print(string.format("   • %s (%s) → %s", c.Name, c.ClassName, c:GetFullName()))
			hits += 1
		end
	end
	if hits == 0 then
		warn("[ZabkaService] BRAK obiektów z 'kasjer/zabka' w nazwie — nazwa instancji nie pasuje. Sprawdź pisownię w Studio.")
	end

	local kasjer = workspace:WaitForChild("KasjerZabka", 30)
	if not kasjer then
		warn("[ZabkaService] Brak workspace.KasjerZabka po 30s — przerwa.")
		return
	end
	print(string.format("[ZabkaService] KasjerZabka znaleziony: %s (class=%s)",
		kasjer:GetFullName(), kasjer.ClassName))

	-- Lista dzieci jeśli to Model — pomoga gdy brak BasePart
	if kasjer:IsA("Model") then
		print("[ZabkaService] Dzieci KasjerZabka:")
		for _, c in ipairs(kasjer:GetChildren()) do
			print("   -", c.Name, "(" .. c.ClassName .. ")")
		end
	end

	local anchor = findAnchor(kasjer)
	if not anchor then
		warn("[ZabkaService] KasjerZabka nie ma żadnego BasePart — nie da się podłączyć ProximityPrompt.")
		return
	end
	print(string.format("[ZabkaService] Anchor wybrany: %s (size=%s, pos=%s)",
		anchor:GetFullName(), tostring(anchor.Size), tostring(anchor.Position)))

	-- Usuń stary prompt jeśli był (np. po hot-reload)
	local removedCount = 0
	for _, c in ipairs(kasjer:GetDescendants()) do
		if c:IsA("ProximityPrompt") then
			print(string.format("[ZabkaService] Usuwam stary ProximityPrompt: parent=%s actionText='%s'",
				c.Parent and c.Parent.Name or "?", c.ActionText))
			c:Destroy()
			removedCount += 1
		end
	end
	if removedCount > 0 then
		print(string.format("[ZabkaService] Usunięto %d starych promptów", removedCount))
	end
	local existing = anchor:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = cfg.PromptText
	prompt.ObjectText            = cfg.PromptObject
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Enabled               = true
	prompt.Parent                = anchor

	prompt.Triggered:Connect(function(player: Player)
		print(string.format("[ZabkaService] %s triggered prompt → fire OpenZabka", player.Name))
		OpenZabka:FireClient(player)
	end)

	print(string.format("[ZabkaService] ✓ ProximityPrompt dodany do %s (actionText='%s', dist=%d)",
		anchor:GetFullName(), prompt.ActionText, prompt.MaxActivationDistance))
end)

-- ── Pojemność: magnes/syrop zajmuje 1 slot ──────────────────────────────────
local function getCarried(data): number
	local n = 0
	for _, c in pairs(data.BackpackContents) do n += c end
	if data.Grandpa and data.Grandpa.hasSyrup then n += 1 end
	n += data.MagnetCount or 0
	n += #(data.Pets or {})       -- pet = 1 slot
	return n
end

-- ── Zakup magnesu ───────────────────────────────────────────────────────────
BuyZabkaMagnet.OnServerEvent:Connect(function(player: Player)
	if not player or not player.Parent then return end
	local data = PlayerDataService.GetData(player)

	local cost = cfg.MagnetCost or 1000
	if (data.Zlotowki or 0) < cost then
		BuyZabkaMagnetResult:FireClient(player, { success = false, reason = "broke" })
		return
	end

	local capacity = Config.BackpackUpgrades[data.BackpackLevel or 1].Capacity
	if getCarried(data) >= capacity then
		BuyZabkaMagnetResult:FireClient(player, { success = false, reason = "full" })
		return
	end

	-- Atomowo: zł najpierw, potem grant. Grant zwraca 0 jeśli (z jakiegoś
	-- powodu race) nie ma miejsca — wtedy zwracamy zł.
	data.Zlotowki -= cost
	PlayerDataService.UpdateLeaderstats(player)

	local granted = MagnetService.Grant(player, 1)  -- woła PushStatus + SaveData
	if granted < 1 then
		-- Refund (na wszelki wypadek)
		data.Zlotowki += cost
		PlayerDataService.UpdateLeaderstats(player)
		BuyZabkaMagnetResult:FireClient(player, { success = false, reason = "full" })
		return
	end

	-- Sync HUD (nowy magnetCount + saldo)
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = capacity,
		hasSyrup         = (data.Grandpa and data.Grandpa.hasSyrup) or false,
		magnetCount      = data.MagnetCount or 0,
	})

	BuyZabkaMagnetResult:FireClient(player, { success = true, cost = cost })
end)

return {}
