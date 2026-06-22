-- ShopService.luau
-- Sklep z plecakami (BackpackUpgrades). ProximityPrompt na blacie sklepu otwiera UI.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage.Config)
local Util              = require(ReplicatedStorage:WaitForChild("Util"))
local PlayerDataService = require(ServerScriptService.PlayerDataService)

local Events         = ReplicatedStorage:WaitForChild("Events")
local OpenShop       = Events:WaitForChild("OpenShop")
local BuyBackpack    = Events:WaitForChild("BuyBackpack")
local BackpackResult = Events:WaitForChild("BackpackResult")
local UpdateHUD      = Events:WaitForChild("UpdateHUD")

local ShopService = {}

-- Anchor + throttle do walidacji BuyBackpack (anti-exploit)
local shopAnchor: BasePart? = nil
local SHOP_MAX_DIST = 15
local lastBuyAt: { [Player]: number } = {}
local BUY_THROTTLE = 0.5
local function isNearShop(player: Player): boolean
	if not shopAnchor then return false end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	return ((hrp :: BasePart).Position - shopAnchor.Position).Magnitude <= SHOP_MAX_DIST
end
Players.PlayerRemoving:Connect(function(p) lastBuyAt[p] = nil end)

-- ── Setup ProximityPrompt na blacie ───────────────────────────────────────

local findAnchor = Util.findAnchor

local function setupShop()
	local sklep = workspace:WaitForChild("BUTELKOMANIACY", 30)
	if not sklep then
		warn("[ShopService] Brak workspace.BUTELKOMANIACY — sklep nie będzie aktywny")
		return
	end

	local kasjer = sklep:WaitForChild("Kasjer", 15)
	if not kasjer then
		warn("[ShopService] Brak BUTELKOMANIACY.Kasjer — sklep nie będzie aktywny")
		return
	end

	local counter = findAnchor(kasjer)
	if not counter then
		warn("[ShopService] Kasjer nie ma żadnego BasePart — sklep nie będzie aktywny")
		return
	end
	shopAnchor = counter  -- cache do walidacji dystansu w BuyBackpack

	-- Prompt
	local existing = counter:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Sklep z plecakami"
	prompt.ObjectText            = "Kasjer"
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration          = 0
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = counter

	prompt.Triggered:Connect(function(player: Player)
		OpenShop:FireClient(player)
	end)

	print("[ShopService] Sklep gotowy →", counter:GetFullName())
end

-- ── Logika zakupu plecaków ────────────────────────────────────────────────

local function tryBuyBackpack(player: Player, targetLevel: number)
	-- Throttle + dystans od Kasjera
	local now = os.clock()
	if lastBuyAt[player] and now - lastBuyAt[player] < BUY_THROTTLE then return end
	lastBuyAt[player] = now
	if not isNearShop(player) then
		BackpackResult:FireClient(player, { success = false, reason = "tooFar" })
		return
	end

	local data = PlayerDataService.GetData(player)
	local current = data.BackpackLevel or 1

	-- Walidacje
	if type(targetLevel) ~= "number" then
		BackpackResult:FireClient(player, { success = false, reason = "bad" })
		return
	end
	if targetLevel <= current then
		BackpackResult:FireClient(player, { success = false, reason = "already" })
		return
	end
	if targetLevel ~= current + 1 then
		BackpackResult:FireClient(player, { success = false, reason = "sequential" })
		return
	end
	local upgrades = Config.BackpackUpgrades
	if targetLevel > #upgrades then
		BackpackResult:FireClient(player, { success = false, reason = "max" })
		return
	end

	local upgrade = upgrades[targetLevel]
	if upgrade.CostType ~= "Zlotowki" then
		BackpackResult:FireClient(player, { success = false, reason = "bad" })
		return
	end
	if data.Zlotowki < upgrade.Cost then
		BackpackResult:FireClient(player, { success = false, reason = "broke" })
		return
	end

	-- Zakup
	data.Zlotowki     -= upgrade.Cost
	data.BackpackLevel = targetLevel
	PlayerDataService.UpdateLeaderstats(player)

	-- Klient potrzebuje nowej pojemności w HUD/inventory
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = upgrade.Capacity,
	})

	BackpackResult:FireClient(player, {
		success     = true,
		newLevel    = targetLevel,
		newCapacity = upgrade.Capacity,
	})

	pcall(function()
		local sqs = require(script.Parent.StoryQuestService)
		sqs.AddProgress(player, "buy_backpack", 1)
	end)

	-- Przełóż model plecaka na postaci na nowy poziom
	local ok, BackpackEquipService = pcall(function()
		return require(ServerScriptService:WaitForChild("BackpackEquipService"))
	end)
	if ok and BackpackEquipService then
		pcall(function() BackpackEquipService.Refresh(player) end)
	end
end

BuyBackpack.OnServerEvent:Connect(tryBuyBackpack)

-- ── Start ────────────────────────────────────────────────────────────────

task.spawn(setupShop)

return ShopService
