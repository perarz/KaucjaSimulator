-- GrandpaService.luau
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config            = require(ReplicatedStorage.Config)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local SyrupService      = require(ServerScriptService.SyrupService)

local GrandpaService = {}

local Events         = ReplicatedStorage:WaitForChild("Events")
local GrandpaTalk    = Events:WaitForChild("GrandpaTalk")
local GrandpaDialog  = Events:WaitForChild("GrandpaDialog")
local GrandpaAccept  = Events:WaitForChild("GrandpaAccept")
local GrandpaTurnIn  = Events:WaitForChild("GrandpaTurnIn")
local GrandpaState   = Events:WaitForChild("GrandpaState")

local cfg = Config.GrandpaQuest

-- Wysyła aktualny stan questa do klienta (UI questów + cokolwiek innego co słucha)
local function pushState(player: Player)
	local data = PlayerDataService.GetData(player)
	GrandpaState:FireClient(player, {
		state    = data.Grandpa.state,
		hasSyrup = data.Grandpa.hasSyrup,
		desc     = cfg.QuestDesc,
		reward   = cfg.Reward,
	})
end

-- Public — wywoływane przez SyrupService po pickup
function GrandpaService.PushStateTo(player: Player)
	pushState(player)
end

-- Stan dialogu: jaki tekst + jakie opcje pokazać dla danego stanu gracza
local function getDialogPayload(data: { [string]: any })
	local grandpa = data.Grandpa
	if grandpa.state == "none" then
		return {
			state   = "none",
			text    = cfg.Dialogs.none,
			options = { "accept", "close" },
		}
	elseif grandpa.state == "active" then
		if grandpa.hasSyrup then
			return {
				state   = "ready",
				text    = cfg.Dialogs.ready,
				options = { "turnin", "close" },
				reward  = cfg.Reward,
			}
		else
			return {
				state   = "active",
				text    = cfg.Dialogs.active,
				options = { "close" },
			}
		end
	else  -- done
		return {
			state   = "done",
			text    = cfg.Dialogs.done,
			options = { "close" },
		}
	end
end

-- Setup ProximityPrompt na dziadku
local function setupGrandpa()
	local model = workspace:FindFirstChild("Grandpa")
	if not model then
		warn("[GrandpaService] Brak workspace.Grandpa")
		return
	end

	local hrp = (model :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		hrp = (model :: Model).PrimaryPart
	end
	if not hrp then
		warn("[GrandpaService] Grandpa nie ma HumanoidRootPart ani PrimaryPart")
		return
	end

	if not hrp:FindFirstChildOfClass("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText            = "Porozmawiaj"
		prompt.ObjectText            = "Dziadek"
		prompt.MaxActivationDistance = cfg.PromptDist
		prompt.HoldDuration          = 0
		prompt.RequiresLineOfSight   = false
		prompt.Parent                = hrp

		prompt.Triggered:Connect(function(player)
			local data = PlayerDataService.GetData(player)
			GrandpaDialog:FireClient(player, getDialogPayload(data))
		end)
	end

	print("[GrandpaService] Dziadek gotowy →", hrp:GetFullName())
end

-- Klient prosi o aktualny dialog (np. po wejściu w panel)
GrandpaTalk.OnServerEvent:Connect(function(player)
	local data = PlayerDataService.GetData(player)
	GrandpaDialog:FireClient(player, getDialogPayload(data))
end)

-- Gracz przyjmuje questa
GrandpaAccept.OnServerEvent:Connect(function(player)
	local data = PlayerDataService.GetData(player)
	if data.Grandpa.state ~= "none" then return end  -- już w trakcie / skończony

	data.Grandpa.state         = "active"
	data.Grandpa.syrupLocation = math.random(1, 3)
	data.Grandpa.hasSyrup      = false
	PlayerDataService.SaveData(player)

	-- Spawn syropu w wylosowanej lokacji (per-player)
	SyrupService.OnQuestAccepted(player)

	-- Specjalny dialog tylko po akcepcie — "Dobrze, czekam".
	-- Następnym razem gdy gracz zagada → getDialogPayload zwróci standardowe "Szukaj dalej".
	GrandpaDialog:FireClient(player, {
		state   = "active",
		text    = cfg.Dialogs.justAccepted,
		options = { "close" },
	})
	pushState(player)
end)

-- Gracz oddaje syrop dziadkowi
GrandpaTurnIn.OnServerEvent:Connect(function(player)
	local data = PlayerDataService.GetData(player)
	if data.Grandpa.state ~= "active" then return end
	if not data.Grandpa.hasSyrup then return end

	-- Reward + state przejście
	data.Zlotowki    += cfg.Reward
	data.TotalEarned += cfg.Reward
	data.Grandpa.state         = "done"
	data.Grandpa.hasSyrup      = false
	data.Grandpa.syrupLocation = 0
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	-- Sync HUD: syrop zniknął z plecaka
	local UpdateHUD = ReplicatedStorage.Events.UpdateHUD
	local capacity  = Config.BackpackUpgrades[data.BackpackLevel].Capacity
	local carried = 0
	for _, c in pairs(data.BackpackContents) do carried += c end
	UpdateHUD:FireClient(player, {
		backpackContents = data.BackpackContents,
		backpackCapacity = capacity,
		hasSyrup         = false,
		bottlesCarried   = carried,
	})

	GrandpaDialog:FireClient(player, getDialogPayload(data))
	pushState(player)
end)

-- Public API — używane przez SyrupService w Kroku 2
function GrandpaService.SetHasSyrup(player: Player, value: boolean)
	local data = PlayerDataService.GetData(player)
	data.Grandpa.hasSyrup = value
end

function GrandpaService.GetState(player: Player)
	local data = PlayerDataService.GetData(player)
	return data.Grandpa
end

setupGrandpa()

-- Initial state sync dla wracających graczy
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		PlayerDataService.GetData(player)  -- czeka na load DataStore
		task.wait(2)  -- buffer na pełny load + character spawn (jak w SyrupService)
		if player.Parent then
			pushState(player)
		end
	end)
end)

return GrandpaService
