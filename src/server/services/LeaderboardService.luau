-- LeaderboardService.luau
-- Dwa rankingi (SurfaceGui + cache top-listy dla podium):
--   • PIENIĄDZE — aktualne Zlotowki, workspace.LeaderboardTablica
--   • ELIMINACJE — StatPvpKills, workspace.LeaderboardTablicaKilli
-- Oba zbudowane z tego samego "Board" factory — identyczny wygląd, inna wartość.

local Players             = game:GetService("Players")
local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config            = require(ReplicatedStorage.Config)
local PlayerDataService = require(ServerScriptService.PlayerDataService)

local LeaderboardService = {}

-- ── Helpery ───────────────────────────────────────────────────────────────
local nameCache: { [number]: string } = {}

local function getNameFromUserId(uid: number): string
	if nameCache[uid] then return nameCache[uid] end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == uid then
			nameCache[uid] = p.DisplayName ~= "" and p.DisplayName or p.Name
			return nameCache[uid]
		end
	end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
	if ok and name then nameCache[uid] = name; return name end
	return "User" .. tostring(uid)
end

local function formatAmount(amount: number): string
	local rounded = math.floor(amount * 100 + 0.5) / 100
	if math.abs(rounded - math.floor(rounded)) < 0.005 then
		return tostring(math.floor(rounded))
	end
	return string.format("%.2f", rounded)
end

-- ── Stałe wyglądu (wspólne dla obu tablic) ─────────────────────────────────
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

type RowHandle = { rankLbl: TextLabel, nameLbl: TextLabel, amountLbl: TextLabel }

local CANVAS_W = 800
local CANVAS_H = 1100
local HEADER_H = 140
local ROW_H    = (CANVAS_H - HEADER_H - 20) / Config.LeaderboardMaxEntries

local function rankColor(i: number): Color3
	if i == 1 then return C_GOLD end
	if i == 2 then return C_SILVER end
	if i == 3 then return C_BRONZE end
	return C_DIMTEXT
end

local function buildSurfaceGui(part: BasePart, titleText: string): { [number]: RowHandle }
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

	local bg = Instance.new("Frame")
	bg.Size            = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C_PANEL
	bg.BorderSizePixel = 0
	bg.Parent          = sg

	local header = Instance.new("Frame")
	header.Size            = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundColor3 = C_HEADER
	header.BorderSizePixel = 0
	header.Parent          = bg

	local headerLbl = Instance.new("TextLabel")
	headerLbl.Size                   = UDim2.fromScale(1, 1)
	headerLbl.BackgroundTransparency = 1
	headerLbl.Text                   = titleText
	headerLbl.TextSize               = 48
	headerLbl.Font                   = FONT
	headerLbl.TextColor3             = C_WHITE
	headerLbl.Parent                 = header

	local sep = Instance.new("Frame")
	sep.Size            = UDim2.new(1, 0, 0, 4)
	sep.Position        = UDim2.fromOffset(0, HEADER_H)
	sep.BackgroundColor3 = C_BORDER
	sep.BorderSizePixel = 0
	sep.Parent          = bg

	local rowFrames: { [number]: RowHandle } = {}
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
	return rowFrames
end

-- ── Board factory ───────────────────────────────────────────────────────────
-- opts: { storeKey, partName, title, suffix, getValue(data)->number, toInt(v)->int, fromInt(int)->v, format(v)->string }
local function makeBoard(opts)
	local board = {
		store     = DataStoreService:GetOrderedDataStore(opts.storeKey),
		rowFrames = nil :: any,
		topCache  = {} :: { { uid: number, value: number } },
		opts      = opts,
	}

	function board.save(player: Player)
		local data = PlayerDataService.GetData(player)
		if not data then return end
		local v = opts.toInt(opts.getValue(data))
		local ok, err = pcall(function()
			board.store:SetAsync(tostring(player.UserId), v)
		end)
		if not ok then warn("[Leaderboard:" .. opts.storeKey .. "] SetAsync failed for", player.Name, ":", err) end
	end

	function board.build()
		local part = workspace:FindFirstChild(opts.partName)
		if not part or not part:IsA("BasePart") then
			warn("[Leaderboard] Brak BasePart '" .. opts.partName .. "' w workspace — tablica pominięta")
			return false
		end
		board.rowFrames = buildSurfaceGui(part :: BasePart, opts.title)
		return true
	end

	function board.update()
		local ok, pages = pcall(function()
			return board.store:GetSortedAsync(false, Config.LeaderboardMaxEntries)
		end)
		if not ok or not pages then
			warn("[Leaderboard:" .. opts.storeKey .. "] GetSortedAsync failed:", pages)
			return
		end
		local top = pages:GetCurrentPage()

		board.topCache = {}
		for _, entry in ipairs(top) do
			local uid = tonumber(entry.key)
			if uid then table.insert(board.topCache, { uid = uid, value = entry.value }) end
		end

		if not board.rowFrames then return end
		for i = 1, Config.LeaderboardMaxEntries do
			local row = board.rowFrames[i]
			if not row then break end
			local entry = top[i]
			if entry then
				local uid = tonumber(entry.key)
				local v   = opts.fromInt(entry.value)
				row.nameLbl.Text       = uid and getNameFromUserId(uid) or "—"
				row.amountLbl.Text     = opts.format(v) .. opts.suffix
				row.rankLbl.TextColor3 = rankColor(i)
			else
				row.nameLbl.Text       = "—"
				row.amountLbl.Text     = ""
				row.rankLbl.TextColor3 = C_DIMTEXT
			end
		end
	end

	return board
end

-- ── Definicje tablic ────────────────────────────────────────────────────────
local moneyBoard = makeBoard({
	storeKey = "Leaderboard_Zlotowki_v1",
	partName = "LeaderboardTablica",
	title    = "RANKING KAUCYJNY — TOP " .. Config.LeaderboardMaxEntries,
	suffix   = " ZŁ",
	getValue = function(data) return data.Zlotowki or 0 end,
	toInt    = function(v) return math.floor(v * 100) end,   -- grosze
	fromInt  = function(i) return i / 100 end,
	format   = formatAmount,
})

local killsBoard = makeBoard({
	storeKey = "Leaderboard_Kille_v1",
	partName = "LeaderboardTablicaKilli",
	title    = "RANKING ELIMINACJI — TOP " .. Config.LeaderboardMaxEntries,
	suffix   = "",
	getValue = function(data) return data.StatPvpKills or 0 end,
	toInt    = function(v) return math.floor(v) end,
	fromInt  = function(i) return i end,
	format   = function(v) return tostring(math.floor(v)) end,
})

local boards = { moneyBoard, killsBoard }

-- ── Public: top-listy dla podium ────────────────────────────────────────────
function LeaderboardService.GetTopMoney() return moneyBoard.topCache end
function LeaderboardService.GetTopKills() return killsBoard.topCache end
-- backward compat
function LeaderboardService.GetTop() return moneyBoard.topCache end

-- ── Pętle save/refresh ───────────────────────────────────────────────────────
local function saveAllOnline()
	for _, p in ipairs(Players:GetPlayers()) do
		for _, board in ipairs(boards) do
			task.spawn(board.save, p)
		end
	end
end

local function startLoops()
	task.spawn(function()
		while true do
			task.wait(Config.LeaderboardUpdateInterval)
			saveAllOnline()
		end
	end)
	task.spawn(function()
		for _, board in ipairs(boards) do board.update() end
		while true do
			task.wait(Config.LeaderboardUpdateInterval)
			for _, board in ipairs(boards) do board.update() end
		end
	end)
end

local function setup()
	for _, board in ipairs(boards) do board.build() end
	startLoops()
	print("[LeaderboardService] Tablice gotowe (pieniądze + eliminacje) — refresh co",
		Config.LeaderboardUpdateInterval, "s")
end

Players.PlayerRemoving:Connect(function(player)
	for _, board in ipairs(boards) do board.save(player) end
end)

Players.PlayerAdded:Connect(function(player)
	task.wait(3)
	if player.Parent then
		for _, board in ipairs(boards) do board.save(player) end
	end
end)

task.spawn(setup)

return LeaderboardService
