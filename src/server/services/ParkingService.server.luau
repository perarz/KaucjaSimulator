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

-- Per-sesja: czy gracz już kupił bilet (nie wymaga DataStore — po rejoinie płaci ponownie)
local ticketOwners: { [number]: boolean } = {}

BuyParkingTicket.OnServerEvent:Connect(function(player: Player)
	if ticketOwners[player.UserId] then
		ParkingTicketResult:FireClient(player, { success = false, reason = "already" })
		return
	end

	local data = PlayerDataService.GetData(player)
	if data.Zlotowki < TICKET_COST then
		ParkingTicketResult:FireClient(player, { success = false, reason = "broke" })
		return
	end

	data.Zlotowki -= TICKET_COST
	PlayerDataService.UpdateLeaderstats(player)
	ticketOwners[player.UserId] = true

	-- Poinformuj bramę — wrzuc_do_bramy doda userId do paidPlayers i otworzy
	gateEvent:Fire(player.UserId)

	ParkingTicketResult:FireClient(player, { success = true })
	print("[ParkingService]", player.Name, "kupił bilet — pozostało", data.Zlotowki, "PLN")
end)

Players.PlayerRemoving:Connect(function(player)
	ticketOwners[player.UserId] = nil
end)

print("[ParkingService] Gotowy — bilet:", TICKET_COST, "PLN")
