-- ParkingService.server.luau
-- Wrzuć do: ServerScriptService
-- Obsługuje zakup biletów parkingowych (500 PLN jednorazowo).
-- Po zakupie odpala BindableEvent ParkingGateEvent → wrzuc_do_bramy otwiera bramę.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local TICKET_COST = 500

-- BindableEvent do komunikacji z bramą (wrzuc_do_bramy nasłuchuje przez WaitForChild)
local gateEvent      = Instance.new("BindableEvent")
gateEvent.Name       = "ParkingGateEvent"
gateEvent.Parent     = ServerScriptService

local Events              = ReplicatedStorage:WaitForChild("Events")
local BuyParkingTicket    = Events:WaitForChild("BuyParkingTicket")
local ParkingTicketResult = Events:WaitForChild("ParkingTicketResult")

-- Persystencja: data.ParkingTicket (bool) w PlayerData. Kto raz kupił — brama otwarta na zawsze.
BuyParkingTicket.OnServerEvent:Connect(function(player: Player)
	local data = PlayerDataService.GetData(player)

	if data.ParkingTicket then
		-- Już kupiony (trwale) — upewnij się że brama otwarta i nie pobieraj ponownie
		gateEvent:Fire(player.UserId)
		ParkingTicketResult:FireClient(player, { success = false, reason = "already" })
		return
	end

	if data.Zlotowki < TICKET_COST then
		ParkingTicketResult:FireClient(player, { success = false, reason = "broke" })
		return
	end

	data.Zlotowki -= TICKET_COST
	data.ParkingTicket = true
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	-- Poinformuj bramę — wrzuc_do_bramy otwiera ją
	gateEvent:Fire(player.UserId)

	ParkingTicketResult:FireClient(player, { success = true })
	print("[ParkingService]", player.Name, "kupił bilet — pozostało", data.Zlotowki, "PLN")
end)

-- Przy dołączeniu: jeśli gracz ma już bilet (trwale), otwórz dla niego bramę
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local data = PlayerDataService.GetData(player)
		task.wait(1)
		if data.ParkingTicket then
			gateEvent:Fire(player.UserId)
		end
	end)
end)

print("[ParkingService] Gotowy — bilet:", TICKET_COST, "PLN")
