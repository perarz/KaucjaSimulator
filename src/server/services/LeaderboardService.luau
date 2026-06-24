-- LeaderboardService.luau
-- Ranking aktualnego salda (Zlotowki) — top 10, SurfaceGui na workspace.LeaderboardTablica

local Players             = game:GetService("Players")
local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage.Config)
local PlayerDataService = require(ServerScriptService.PlayerDataService)

local LEADERBOARD_KEY = "Leaderboard_Zlotowki_v1"
local store           = DataStoreService:GetOrderedDataStore(LEADERBOARD_KEY)

local LeaderboardService = {}

-- ── Helpery ───────────────────────────────────────────────────────────────

local nameCache: { [number]: string } = {}

local function getNameFromUserId(uid: number): string
	if nameCache[uid] then return nameCache[uid] end
	-- Spróbuj najpierw po Players (online)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == uid then
			nameCache[uid] = p.DisplayName ~= "" and p.DisplayName or p.Name
			return nameCache[uid]
		end
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(uid)
	end)
	if ok and name then
		nameCache[uid] = name
		return name
	end
	return "User" .. tostring(uid)
end

local function formatAmount(amount: number): string
	local rounded = math.floor(amount * 100 + 0.5) / 100
	if math.abs(rounded - math.floor(rounded)) < 0.005 then
		return tostring(math.floor(rounded))
	end
	return string.format("%.2f", rounded)
end

-- ── Zapis do OrderedDataStore ─────────────────────────────────────────────
-- OrderedDataStore akceptuje tylko integery → trzymamy grosze (×100).

local function savePlayer(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then return end
	local grosze = math.floor((data.Zlotowki or 0) * 100)
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), grosze)
	end)
	if not ok then
		warn("[LeaderboardService] SetAsync failed for", player.Name, ":", err)
	end
end

local function saveAllOnline()
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(savePlayer, p)
	end
end

-- ── SurfaceGui na tablicy ─────────────────────────────────────────────────

local FONT       = Enum.Font.GothamBlack
local C_PANEL    = Color3.fromRGB(60, 60, 60)
local C_BG       = Color3.fromRGB(52, 52, 52)
local C_HEADER   = Color3.fromRGB(42, 42, 42)
local C_BORDER   = Color3.fromRGB(15, 15, 15)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT  = Color3.fromRGB(175, 175, 175)
local C_GREEN    = Color3.fromRGB(80, 220, 100)
local C_GOLD     = Color3.fromRGB(255, 195, 70)
local C_SILVER   = Color3.fromRGB(200, 200, 220)
local C_BRONZE   = Color3.fromRGB(205, 130, 70)

type RowHandle = {
	rankLbl:   TextLabel,
	nameLbl:   TextLabel,
	amountLbl: TextLabel,
}

local rowFrames: { [number]: RowHandle } = {}

-- Cache top-listy (uid+value) — czytane przez PodiumService (podium top-3).
local topCache: { { uid: number, value: number } } = {}
function LeaderboardService.GetTop(): { { uid: number, value: number } }
	return topCache
end

local CANVAS_W = 800
local CANVAS_H = 1100
local HEADER_H = 140
local ROW_H    = (CANVAS_H - HEADER_H - 20) / Config.LeaderboardMaxEntries  -- ~95

local function rankColor(i: number): Color3
	if i == 1 then return C_GOLD end
	if i == 2 then return C_SILVER end
	if i == 3 then return C_BRONZE end
	return C_DIMTEXT
end

local function buildSurfaceGui(part: BasePart)
	-- Wyczyść istniejący
	local existing = part:FindFirstChild("LeaderboardGui")
	if existing then existing:Destroy() end

	local sg = Instance.new("SurfaceGui")
	sg.Name           = "LeaderboardGui"
	sg.Face           = Enum.NormalId.Front
	sg.SizingMode     = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize     = Vector2.new(CANVAS_W, CANVAS_H)
	sg.LightInfluence = 0
	sg.AlwaysOnTop    = false
	sg.Parent         = part

	-- Tło panel
	local bg = Instance.new("Frame")
	bg.Size            = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C_PANEL
	bg.BorderSizePixel = 0
	bg.Parent          = sg

	-- Header
	local header = Instance.new("Frame")
	header.Size            = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundColor3 = C_HEADER
	header.BorderSizePixel = 0
	header.Parent          = bg

	local headerLbl = Instance.new("TextLabel")
	headerLbl.Size                   = UDim2.fromScale(1, 1)
	headerLbl.BackgroundTransparency = 1
	headerLbl.Text                   = "RANKING KAUCYJNY — TOP " .. Config.LeaderboardMaxEntries
	headerLbl.TextSize               = 48
	headerLbl.Font                   = FONT
	headerLbl.TextColor3             = C_WHITE
	headerLbl.Parent                 = header

	-- Separator pod headerem
	local sep = Instance.new("Frame")
	sep.Size            = UDim2.new(1, 0, 0, 4)
	sep.Position        = UDim2.fromOffset(0, HEADER_H)
	sep.BackgroundColor3 = C_BORDER
	sep.BorderSizePixel = 0
	sep.Parent          = bg

	-- Wiersze
	rowFrames = {}
	local startY = HEADER_H + 12
	for i = 1, Config.LeaderboardMaxEntries do
		local row = Instance.new("Frame")
		row.Size                  = UDim2.new(1, -20, 0, ROW_H - 8)
		row.Position              = UDim2.fromOffset(10, startY + (i - 1) * ROW_H)
		row.BackgroundColor3      = (i % 2 == 1) and C_BG or C_PANEL
		row.BackgroundTransparency = 0.05
		row.BorderSizePixel       = 0
		row.Parent                = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent       = row

		local rankLbl = Instance.new("TextLabel")
		rankLbl.Size                   = UDim2.fromOffset(110, ROW_H - 8)
		rankLbl.Position               = UDim2.fromOffset(14, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Text                   = "#" .. i
		rankLbl.TextSize               = 42
		rankLbl.Font                   = FONT
		rankLbl.TextColor3             = rankColor(i)
		rankLbl.TextXAlignment         = Enum.TextXAlignment.Left
		rankLbl.Parent                 = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size                   = UDim2.new(0.55, -130, 0, ROW_H - 8)
		nameLbl.Position               = UDim2.fromOffset(130, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text                   = "—"
		nameLbl.TextSize               = 36
		nameLbl.Font                   = FONT
		nameLbl.TextColor3             = C_WHITE
		nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
		nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
		nameLbl.Parent                 = row

		local amountLbl = Instance.new("TextLabel")
		amountLbl.Size                   = UDim2.new(0.45, -20, 0, ROW_H - 8)
		amountLbl.Position               = UDim2.new(0.55, 0, 0, 0)
		amountLbl.BackgroundTransparency = 1
		amountLbl.Text                   = ""
		amountLbl.TextSize               = 36
		amountLbl.Font                   = FONT
		amountLbl.TextColor3             = C_GREEN
		amountLbl.TextXAlignment         = Enum.TextXAlignment.Right
		amountLbl.Parent                 = row

		rowFrames[i] = { rankLbl = rankLbl, nameLbl = nameLbl, amountLbl = amountLbl }
	end
end

-- ── Aktualizacja widoku ──────────────────────────────────────────────────

local function updateDisplay()
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.LeaderboardMaxEntries)
	end)
	if not ok or not pages then
		warn("[LeaderboardService] GetSortedAsync failed:", pages)
		return
	end
	local top = pages:GetCurrentPage()

	-- Odśwież cache top-listy (dla PodiumService)
	topCache = {}
	for _, entry in ipairs(top) do
		local uid = tonumber(entry.key)
		if uid then table.insert(topCache, { uid = uid, value = entry.value }) end
	end

	for i = 1, Config.LeaderboardMaxEntries do
		local row = rowFrames[i]
		if not row then break end
		local entry = top[i]
		if entry then
			local uid    = tonumber(entry.key)
			local grosze = entry.value
			local zl     = grosze / 100
			row.nameLbl.Text   = uid and getNameFromUserId(uid) or "—"
			row.amountLbl.Text = formatAmount(zl) .. " ZŁ"
			row.rankLbl.TextColor3 = rankColor(i)
		else
			row.nameLbl.Text   = "—"
			row.amountLbl.Text = ""
			row.rankLbl.TextColor3 = C_DIMTEXT
		end
	end
end

-- ── Setup ────────────────────────────────────────────────────────────────

-- Osobne pętle: save i refresh działają niezależnie, oba co LeaderboardUpdateInterval (60s)
local function startSaveLoop()
	task.spawn(function()
		while true do
			task.wait(Config.LeaderboardUpdateInterval)
			saveAllOnline()
		end
	end)
end

local function startRefreshLoop()
	task.spawn(function()
		-- Initial refresh przy starcie — pobierz istniejący ranking
		updateDisplay()
		while true do
			task.wait(Config.LeaderboardUpdateInterval)
			updateDisplay()
		end
	end)
end

local function setupLeaderboard()
	-- Znajdź tablicę
	local part = workspace:FindFirstChild("LeaderboardTablica")
	if not part or not part:IsA("BasePart") then
		warn("[LeaderboardService] Brak BasePart 'LeaderboardTablica' w workspace — tablica nie zostanie utworzona")
		return
	end
	buildSurfaceGui(part :: BasePart)

	startSaveLoop()
	startRefreshLoop()

	print("[LeaderboardService] Tablica gotowa →", part:GetFullName(),
		"— refresh co", Config.LeaderboardUpdateInterval, "s")
end

-- Save przy wyjściu (żeby ostatnia kwota gracza była utrwalona)
Players.PlayerRemoving:Connect(savePlayer)

-- Initial save gracza zaraz po dołączeniu (żeby pojawił się w rankingu bez czekania na pętlę)
Players.PlayerAdded:Connect(function(player)
	task.wait(3)  -- dajemy czas PlayerDataService na załadowanie danych z DataStore
	if player.Parent then  -- nie zniknął w trakcie
		savePlayer(player)
	end
end)

task.spawn(setupLeaderboard)

return LeaderboardService
