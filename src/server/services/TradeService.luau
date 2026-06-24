-- TradeService.luau
-- Wymiana gracz ↔ gracz: pety (z EQ, włącznie z założonym) + pieniądze. Serwer autorytatywny.
--
-- Flow:
--   1) Zapraszający → TradeInvite(targetUserId). Zaproszony dostaje TradeInvited(popup).
--   2) Zaproszony → TradeRespond{accept}. Odmowa → TradeInviteResult(accepted=false) do zapraszającego.
--      Akceptacja → tworzymy sesję, TradeStart do obu (otwiera okno wymiany).
--   3) Każda strona buduje ofertę (TradeOffer{pets,money}). KAŻDA zmiana resetuje obie akceptacje
--      i przerywa ewentualne odliczanie (anti-scam).
--   4) TradeAccept od obu → 3s odliczanie. Anuluj (TradeCancel) przerywa w każdym momencie.
--   5) Po 3s walidacja (własność petów, kasa, wolne sloty 20% plecaka). Brak miejsca/kasy →
--      cała wymiana anulowana z komunikatem. OK → atomowy swap + SaveData obu + TradeEnd(completed).
--
-- Bezpieczeństwo:
--   • Lista petów weryfikowana po stronie serwera (PetService.FindPet z data.Pets).
--   • Walidacja i mutacja bez yieldów pomiędzy (atomowość). SaveData dopiero po swapie.
--   • Pet logic (remove/add/unequip/refresh) zostaje w PetService (single source of truth).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PetService        = require(script.Parent:WaitForChild("PetService"))

local Events            = ReplicatedStorage:WaitForChild("Events")
local TradeInvite       = Events:WaitForChild("TradeInvite")
local TradeInvited      = Events:WaitForChild("TradeInvited")
local TradeRespond      = Events:WaitForChild("TradeRespond")
local TradeInviteResult = Events:WaitForChild("TradeInviteResult")
local TradeStart        = Events:WaitForChild("TradeStart")
local TradeOffer        = Events:WaitForChild("TradeOffer")
local TradeSync         = Events:WaitForChild("TradeSync")
local TradeAccept       = Events:WaitForChild("TradeAccept")
local TradeCancel       = Events:WaitForChild("TradeCancel")
local TradeEnd          = Events:WaitForChild("TradeEnd")

local cfg = Config.Trade or {}
local COUNTDOWN_SEC = cfg.CountdownSec or 3
local INVITE_TIMEOUT = cfg.InviteTimeout or 30
local THROTTLE = cfg.Throttle or 0.5
local MAX_MONEY = cfg.MaxMoney or 1e9

local TradeService = {}

-- ── Stan ────────────────────────────────────────────────────────────────────
-- Aktywne zaproszenia: { [toPlayer] = { from = Player, at = clock } } — 1 aktywne na odbiorcę.
local invites: { [Player]: { from: Player, at: number } } = {}
-- Aktywne sesje: playerSession[player] = session (oba gracze wskazują tę samą tabelę).
local playerSession: { [Player]: any } = {}
-- Anty-spam akcji invite/respond/accept/cancel.
local lastActionAt: { [Player]: number } = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	if (lastActionAt[player] or 0) + THROTTLE > now then return true end
	lastActionAt[player] = now
	return false
end

local function isBusy(player: Player): boolean
	return playerSession[player] ~= nil
end

local function otherOf(session, player: Player): Player
	return (session.a == player) and session.b or session.a
end

-- ── Resolve petów ────────────────────────────────────────────────────────────
-- Pety gracza możliwe do wystawienia = wszystkie z EQ (data.Pets), włącznie z założonym.
local function tradeablePets(player: Player): { any }
	local data = PlayerDataService.GetData(player)
	local out = {}
	for _, p in ipairs((data and data.Pets) or {}) do
		table.insert(out, { id = p.id, rarity = p.rarity, class = p.class, gold = p.gold == true })
	end
	return out
end

-- Z listy id → lista info {id,rarity,class,gold} (rozwiązane z data.Pets danego gracza).
local function offerPetInfo(player: Player, ids: { string }): { any }
	local data = PlayerDataService.GetData(player)
	local out = {}
	for _, id in ipairs(ids) do
		local p = PetService.FindPet(data, id)
		if p then table.insert(out, { id = p.id, rarity = p.rarity, class = p.class, gold = p.gold == true }) end
	end
	return out
end

-- ── TradeSync (personalizowany snapshot do obu) ──────────────────────────────
local function syncSession(session)
	if not session then return end
	local a, b = session.a, session.b
	local function pushTo(me: Player, other: Player)
		if not (me and me.Parent) then return end
		local myOffer    = session.offer[me]    or { pets = {}, money = 0 }
		local theirOffer = session.offer[other] or { pets = {}, money = 0 }
		TradeSync:FireClient(me, {
			your = {
				pets     = offerPetInfo(me, myOffer.pets),
				money    = myOffer.money,
				accepted = session.accepted[me] == true,
			},
			their = {
				pets     = offerPetInfo(other, theirOffer.pets),
				money    = theirOffer.money,
				accepted = session.accepted[other] == true,
				name     = (other.DisplayName ~= "" and other.DisplayName) or other.Name,
			},
			counting     = session.counting == true,
			countdownSec = COUNTDOWN_SEC,
		})
	end
	pushTo(a, b)
	pushTo(b, a)
end

-- ── Reset akceptacji (anti-scam) ─────────────────────────────────────────────
local function resetAcceptance(session)
	session.accepted[session.a] = false
	session.accepted[session.b] = false
	session.counting = false
	session.countdownToken += 1  -- unieważnia trwające odliczanie
end

-- ── Koniec sesji ─────────────────────────────────────────────────────────────
-- received: { [player] = { pets = {...}, money = n } } opcjonalnie (przy completed).
local function endSession(session, reason: string, message: string?, received)
	if not session or session.ended then return end
	session.ended = true
	session.counting = false
	session.countdownToken += 1
	local a, b = session.a, session.b
	if playerSession[a] == session then playerSession[a] = nil end
	if playerSession[b] == session then playerSession[b] = nil end
	local function tell(p: Player)
		if not (p and p.Parent) then return end
		TradeEnd:FireClient(p, {
			reason   = reason,
			message  = message,
			received = received and received[p] or nil,
		})
	end
	tell(a); tell(b)
end

-- ── Wykonanie wymiany (po 3s, walidacja + atomowy swap) ──────────────────────
local function executeTrade(session)
	if session.ended then return end
	local a, b = session.a, session.b
	if not (a and a.Parent and b and b.Parent) then
		endSession(session, "cancelled", "Drugi gracz wyszedł")
		return
	end
	local dataA = PlayerDataService.GetData(a)
	local dataB = PlayerDataService.GetData(b)
	if not (dataA and dataB) then
		endSession(session, "cancelled", "Błąd danych")
		return
	end
	local offerA = session.offer[a] or { pets = {}, money = 0 }
	local offerB = session.offer[b] or { pets = {}, money = 0 }

	-- 1) Własność petów (oba kierunki) — UWAGA: od tego miejsca BEZ yieldów aż do swapu.
	for _, id in ipairs(offerA.pets) do
		if not PetService.FindPet(dataA, id) then endSession(session, "failed", "Pet zniknął z ekwipunku") return end
	end
	for _, id in ipairs(offerB.pets) do
		if not PetService.FindPet(dataB, id) then endSession(session, "failed", "Pet zniknął z ekwipunku") return end
	end
	-- 2) Kasa
	if (dataA.Zlotowki or 0) < offerA.money then endSession(session, "failed", "Brak wystarczających środków") return end
	if (dataB.Zlotowki or 0) < offerB.money then endSession(session, "failed", "Brak wystarczających środków") return end
	-- 3) Wolne sloty na pety (limit 20% plecaka) po wymianie
	local newA = PetService.CountPets(dataA) - #offerA.pets + #offerB.pets
	local newB = PetService.CountPets(dataB) - #offerB.pets + #offerA.pets
	if newA > PetService.GetPetCap(dataA) then endSession(session, "failed", "Nie masz miejsca na pety") return end
	if newB > PetService.GetPetCap(dataB) then endSession(session, "failed", "Drugi gracz nie ma miejsca na pety") return end

	-- Walidacja OK — atomowy swap (PetService.RemovePets/AddPets nie yielduje).
	local removedA = PetService.RemovePets(a, offerA.pets)
	local removedB = PetService.RemovePets(b, offerB.pets)
	PetService.AddPets(a, removedB)
	PetService.AddPets(b, removedA)

	dataA.Zlotowki = (dataA.Zlotowki or 0) - offerA.money + offerB.money
	dataB.Zlotowki = (dataB.Zlotowki or 0) - offerB.money + offerA.money

	PlayerDataService.UpdateLeaderstats(a)
	PlayerDataService.UpdateLeaderstats(b)
	PetService.RefreshAfterTrade(a)
	PetService.RefreshAfterTrade(b)

	local function summary(pets)
		local out = {}
		for _, p in ipairs(pets) do table.insert(out, { rarity = p.rarity, class = p.class, gold = p.gold == true }) end
		return out
	end
	local received = {
		[a] = { pets = summary(removedB), money = offerB.money },
		[b] = { pets = summary(removedA), money = offerA.money },
	}
	endSession(session, "completed", nil, received)

	-- Persystencja transferu (anti-dupe/rollback) — POZA atomowym blokiem (SetAsync yielduje).
	task.spawn(PlayerDataService.SaveData, a)
	task.spawn(PlayerDataService.SaveData, b)
end

-- ── TradeInvite (zapraszający) ───────────────────────────────────────────────
TradeInvite.OnServerEvent:Connect(function(player: Player, targetUserId: any)
	if throttled(player) then return end
	if type(targetUserId) ~= "number" then return end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then return end
	if isBusy(player) or isBusy(target) then
		TradeInviteResult:FireClient(player, { accepted = false, name = target.DisplayName, message = "Gracz jest zajęty" })
		return
	end
	-- Odbiorca ma już wiszące zaproszenie → zajęty
	if invites[target] then
		TradeInviteResult:FireClient(player, { accepted = false, name = target.DisplayName, message = "Gracz ma inne zaproszenie" })
		return
	end
	invites[target] = { from = player, at = os.clock() }
	TradeInvited:FireClient(target, {
		fromUserId = player.UserId,
		fromName   = (player.DisplayName ~= "" and player.DisplayName) or player.Name,
	})
	-- Wygaszanie po timeout
	task.delay(INVITE_TIMEOUT, function()
		local inv = invites[target]
		if inv and inv.from == player then invites[target] = nil end
	end)
end)

-- ── TradeRespond (zaproszony) ────────────────────────────────────────────────
TradeRespond.OnServerEvent:Connect(function(player: Player, payload: any)
	if throttled(player) then return end
	if type(payload) ~= "table" then return end
	local inv = invites[player]
	if not inv then return end
	if type(payload.fromUserId) == "number" and inv.from.UserId ~= payload.fromUserId then return end
	local inviter = inv.from
	invites[player] = nil
	if not (inviter and inviter.Parent) then return end

	if payload.accept ~= true then
		TradeInviteResult:FireClient(inviter, { accepted = false, name = (player.DisplayName ~= "" and player.DisplayName) or player.Name })
		return
	end
	if isBusy(inviter) or isBusy(player) then
		TradeInviteResult:FireClient(player, { accepted = false, name = inviter.DisplayName, message = "Nie można rozpocząć wymiany" })
		return
	end
	-- Twórz sesję
	local session = {
		a = inviter, b = player,
		offer = { [inviter] = { pets = {}, money = 0 }, [player] = { pets = {}, money = 0 } },
		accepted = { [inviter] = false, [player] = false },
		counting = false,
		countdownToken = 0,
		ended = false,
	}
	playerSession[inviter] = session
	playerSession[player]  = session

	TradeStart:FireClient(inviter, {
		otherUserId = player.UserId,
		otherName   = (player.DisplayName ~= "" and player.DisplayName) or player.Name,
		yourPets    = tradeablePets(inviter),
	})
	TradeStart:FireClient(player, {
		otherUserId = inviter.UserId,
		otherName   = (inviter.DisplayName ~= "" and inviter.DisplayName) or inviter.Name,
		yourPets    = tradeablePets(player),
	})
	syncSession(session)
end)

-- ── TradeOffer (zmiana oferty) ───────────────────────────────────────────────
-- Bez throttlingu (zmiany rzadkie: toggle peta / debounce kwoty) — żeby nie gubić ostatniej.
TradeOffer.OnServerEvent:Connect(function(player: Player, payload: any)
	local session = playerSession[player]
	if not session or session.ended then return end
	if type(payload) ~= "table" then return end
	local data = PlayerDataService.GetData(player)
	if not data then return end

	-- Filtruj pety do faktycznie posiadanych (dedup po id)
	local seen: { [string]: boolean } = {}
	local pets = {}
	if type(payload.pets) == "table" then
		for _, id in ipairs(payload.pets) do
			if type(id) == "string" and not seen[id] and PetService.FindPet(data, id) then
				seen[id] = true
				table.insert(pets, id)
			end
		end
	end
	-- Kwota: liczba całkowita w [0, MAX_MONEY]
	local money = tonumber(payload.money) or 0
	money = math.floor(math.clamp(money, 0, MAX_MONEY))

	session.offer[player] = { pets = pets, money = money }
	resetAcceptance(session)  -- każda zmiana resetuje obie akceptacje + przerywa odliczanie
	syncSession(session)
end)

-- ── TradeAccept ──────────────────────────────────────────────────────────────
TradeAccept.OnServerEvent:Connect(function(player: Player)
	local session = playerSession[player]
	if not session or session.ended then return end
	if throttled(player) then return end
	if session.accepted[player] then return end
	session.accepted[player] = true

	local a, b = session.a, session.b
	if session.accepted[a] and session.accepted[b] then
		-- Obaj zaakceptowali → odliczanie
		session.counting = true
		session.countdownToken += 1
		local myToken = session.countdownToken
		syncSession(session)
		task.delay(COUNTDOWN_SEC, function()
			if session.ended then return end
			if session.countdownToken ~= myToken then return end  -- przerwane (anuluj/zmiana)
			if not (session.accepted[a] and session.accepted[b]) then return end
			executeTrade(session)
		end)
	else
		syncSession(session)
	end
end)

-- ── TradeCancel (anuluj — w każdym momencie, też podczas odliczania) ─────────
TradeCancel.OnServerEvent:Connect(function(player: Player)
	local session = playerSession[player]
	if not session or session.ended then return end
	endSession(session, "cancelled", "Wymiana anulowana")
end)

-- ── Cleanup ──────────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	-- Zaproszenia w obie strony
	if invites[player] then invites[player] = nil end
	for to, inv in pairs(invites) do
		if inv.from == player then invites[to] = nil end
	end
	-- Aktywna sesja → przerwij, powiadom drugiego
	local session = playerSession[player]
	if session and not session.ended then
		endSession(session, "cancelled", "Drugi gracz wyszedł")
	end
	lastActionAt[player] = nil
end)

print("[TradeService] gotowy")

return TradeService
