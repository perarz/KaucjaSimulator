-- TradeController.client.luau
-- Wymiana gracz↔gracz. Przycisk WYMIANA w HUD (lewa strona, pod deską+teleportem) →
-- lista aktywnych graczy z przyciskiem INVITE. Zaproszenie → popup u odbiorcy (akceptuj/anuluj).
-- Po akceptacji → okno wymiany dwustronne: po lewej Twoja oferta (pety + kwota), po prawej
-- oferta drugiego gracza. Zaznaczanie peta = checkmark (jak przy gold upgrade). Obaj 'Akceptuj'
-- → 3s odliczanie → transfer. 'Anuluj' przerywa w każdym momencie.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

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

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local cfg          = Config.Trade or {}
local BTN_ICON     = cfg.ButtonIconId or "rbxassetid://102471495116579"
local ACCEPT_ICON  = cfg.AcceptIconId or "rbxassetid://77598935140150"
local CANCEL_ICON  = cfg.CancelIconId or "rbxassetid://124962493500922"
local COUNTDOWN_SEC = cfg.CountdownSec or 3
local PET_RARITIES = (Config.Pets and Config.Pets.Rarities) or {}

-- ── SFX ──────────────────────────────────────────────────────────────────────
local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl   = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

-- ── Paleta ─────────────────────────────────────────────────────────────────
local FONT      = Enum.Font.GothamBold
local C_PANEL   = Color3.fromRGB(24, 110, 90)
local C_HEADER  = Color3.fromRGB(0, 53, 39)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_CARD    = Color3.fromRGB(17, 60, 48)
local C_BTN     = Color3.fromRGB(18, 91, 73)
local C_WHITE   = Color3.fromRGB(245, 250, 247)
local C_ACC     = Color3.fromRGB(170, 221, 102)
local C_DIM     = Color3.fromRGB(150, 185, 170)
local C_GREEN   = Color3.fromRGB(120, 235, 150)
local X_RED     = Color3.fromRGB(225, 80, 80)

local function thumbUrl(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

-- Ustawia awatar: natychmiast rbxthumb, potem (async) pewniejszy GetUserThumbnailAsync.
local function setAvatar(img: ImageLabel, userId: number)
	img.Image = thumbUrl(userId)
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and content and content ~= "" and img and img.Parent then
			img.Image = content
		end
	end)
end

-- ── Movement lock (ref-counted, balansowany per-gui) ─────────────────────────
local lockedGuis: { [string]: boolean } = {}
local function lockMove(tag: string)
	if lockedGuis[tag] then return end
	lockedGuis[tag] = true
	if _G["__lockMovement"] then _G["__lockMovement"]() end
end
local function unlockMove(tag: string)
	if not lockedGuis[tag] then return end
	lockedGuis[tag] = nil
	if _G["__unlockMovement"] then _G["__unlockMovement"]() end
end

-- ════════════════════════════════════════════════════════════════════════════
--  1) HUD BUTTON
-- ════════════════════════════════════════════════════════════════════════════
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "TradeHud"
hudGui.ResetOnSpawn   = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder   = 10
hudGui.Parent         = playerGui

local tradeBtn = Instance.new("ImageButton")
tradeBtn.Name                   = "TradeButton"
tradeBtn.AnchorPoint            = Vector2.new(0, 0.5)
tradeBtn.Position               = UDim2.new(0, 16, 0.5, 190)  -- pod deską+teleportem
tradeBtn.Size                   = UDim2.fromOffset(156, 156)
tradeBtn.BackgroundTransparency = 1
tradeBtn.BorderSizePixel        = 0
tradeBtn.Image                  = BTN_ICON
tradeBtn.ScaleType              = Enum.ScaleType.Fit
tradeBtn.AutoButtonColor        = false
tradeBtn.Parent                 = hudGui
do
	local ti = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
	local baseSize  = UDim2.fromOffset(156, 156)
	local hoverSize = UDim2.fromOffset(175, 175)
	tradeBtn.MouseEnter:Connect(function() TweenService:Create(tradeBtn, ti, { Size = hoverSize, Rotation = -6 }):Play() end)
	tradeBtn.MouseLeave:Connect(function() TweenService:Create(tradeBtn, ti, { Size = baseSize, Rotation = 0 }):Play() end)
end

_G["__hudBtnRegistry"] = _G["__hudBtnRegistry"] or {}
_G["__hudBtnRegistry"]["TRADE"] = tradeBtn
if _G["__hudRegisterBtn"] then _G["__hudRegisterBtn"]("TRADE", tradeBtn) end

-- ── Header helper (UICorner + bottom-fill mask) ──────────────────────────────
local function buildHeader(parent: Frame, h: number, titleText: string): (Frame, ImageButton)
	local header = Instance.new("Frame")
	header.Size             = UDim2.new(1, 0, 0, h)
	header.BackgroundColor3 = C_HEADER
	header.BorderSizePixel  = 0
	header.ZIndex           = 3
	header.Parent           = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 12); fill.Position = UDim2.new(0, 0, 1, -12)
	fill.BackgroundColor3 = C_HEADER; fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = header

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, -64, 1, 0)
	title.Position               = UDim2.fromOffset(20, 0)
	title.BackgroundTransparency = 1
	title.Text                   = titleText
	title.TextSize               = 24
	title.Font                   = FONT
	title.TextColor3             = C_ACC
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.TextTruncate           = Enum.TextTruncate.AtEnd
	title.ZIndex                 = 4
	title.Name                   = "Title"
	title.Parent                 = header

	local x = Instance.new("ImageButton")
	x.Size                   = UDim2.fromOffset(46, 46)
	x.AnchorPoint            = Vector2.new(1, 0.5)
	x.Position               = UDim2.new(1, -12, 0.5, 0)
	x.BackgroundTransparency = 1
	x.BorderSizePixel        = 0
	x.Image                  = CANCEL_ICON
	x.ScaleType              = Enum.ScaleType.Fit
	x.AutoButtonColor        = false
	x.ZIndex                 = 5
	x.Parent                 = header
	local sc = Instance.new("UIScale"); sc.Parent = x
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	x.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.15 }):Play() end)
	x.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
	return header, x
end

-- Wspólny przycisk akcji (pill)
local function makeButton(parent: Instance, text: string, w: number, h: number, fill: Color3, txtColor: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size              = UDim2.fromOffset(w, h)
	b.BackgroundColor3  = fill
	b.BorderSizePixel   = 0
	b.AutoButtonColor   = false
	b.Text              = text
	b.TextSize          = 22
	b.Font              = FONT
	b.TextColor3        = txtColor
	b.Parent            = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = b
	local sc = Instance.new("UIScale"); sc.Parent = b
	local ti = TweenInfo.new(0.1)
	b.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
	return b
end

-- ════════════════════════════════════════════════════════════════════════════
--  2) PANEL LISTY GRACZY
-- ════════════════════════════════════════════════════════════════════════════
local listGui = Instance.new("ScreenGui")
listGui.Name           = "TradeListGui"
listGui.ResetOnSpawn   = false
listGui.IgnoreGuiInset = true
listGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
listGui.DisplayOrder   = 61
listGui.Enabled        = false
listGui.Parent         = playerGui

local listOverlay = Instance.new("TextButton")
listOverlay.Size = UDim2.fromScale(1, 1); listOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
listOverlay.BackgroundTransparency = 0.5; listOverlay.BorderSizePixel = 0
listOverlay.Text = ""; listOverlay.AutoButtonColor = false; listOverlay.ZIndex = 1; listOverlay.Parent = listGui

local LIST_W, LIST_H = 540, 620
local listPanel = Instance.new("Frame")
listPanel.Size             = UDim2.fromOffset(LIST_W, LIST_H)
listPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
listPanel.Position         = UDim2.fromScale(0.5, 0.5)
listPanel.BackgroundColor3 = C_PANEL
listPanel.BorderSizePixel  = 0
listPanel.ZIndex           = 2
listPanel.Parent           = listGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = listPanel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = listPanel
end
local _, listClose = buildHeader(listPanel, 56, "WYMIANA")

local rows = Instance.new("ScrollingFrame")
rows.Size                  = UDim2.new(1, -24, 1, -80)
rows.Position              = UDim2.fromOffset(12, 68)
rows.BackgroundTransparency = 1
rows.BorderSizePixel       = 0
rows.ScrollBarThickness    = 6
rows.CanvasSize            = UDim2.new()
rows.AutomaticCanvasSize   = Enum.AutomaticSize.Y
rows.ZIndex                = 3
rows.Parent                = listPanel
do
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 8); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = rows
	local p = Instance.new("UIPadding"); p.PaddingRight = UDim.new(0, 6); p.Parent = rows
end

local emptyLbl = Instance.new("TextLabel")
emptyLbl.Size = UDim2.new(1, 0, 0, 60); emptyLbl.BackgroundTransparency = 1
emptyLbl.Text = "Brak innych graczy na serwerze"; emptyLbl.Font = FONT; emptyLbl.TextSize = 18
emptyLbl.TextColor3 = C_DIM; emptyLbl.ZIndex = 3; emptyLbl.Visible = false; emptyLbl.Parent = listPanel
emptyLbl.AnchorPoint = Vector2.new(0.5, 0); emptyLbl.Position = UDim2.new(0.5, 0, 0, 120)

local inTrade = false  -- czy okno wymiany aktywne (blokuje wysłanie kolejnego zaproszenia)

local function rebuildList()
	for _, c in ipairs(rows:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local others = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then table.insert(others, p) end
	end
	emptyLbl.Visible = #others == 0
	for i, p in ipairs(others) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64); row.BackgroundColor3 = C_CARD
		row.BorderSizePixel = 0; row.LayoutOrder = i; row.ZIndex = 4; row.Parent = rows
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row
		local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = row

		local av = Instance.new("ImageLabel")
		av.Size = UDim2.fromOffset(48, 48); av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, 10, 0.5, 0); av.BackgroundColor3 = C_HEADER
		av.BorderSizePixel = 0; av.ScaleType = Enum.ScaleType.Fit
		av.ZIndex = 5; av.Parent = row
		local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1, 0); ac.Parent = av
		setAvatar(av, p.UserId)

		local nick = Instance.new("TextLabel")
		nick.Size = UDim2.new(1, -200, 1, 0); nick.Position = UDim2.fromOffset(68, 0)
		nick.BackgroundTransparency = 1; nick.Text = (p.DisplayName ~= "" and p.DisplayName) or p.Name
		nick.TextSize = 19; nick.Font = FONT; nick.TextColor3 = C_WHITE
		nick.TextXAlignment = Enum.TextXAlignment.Left; nick.TextTruncate = Enum.TextTruncate.AtEnd
		nick.ZIndex = 5; nick.Parent = row

		local invite = makeButton(row, "INVITE", 110, 44, C_ACC, C_HEADER)
		invite.AnchorPoint = Vector2.new(1, 0.5)
		invite.Position    = UDim2.new(1, -12, 0.5, 0)
		invite.ZIndex      = 6
		local targetId = p.UserId
		invite.MouseButton1Click:Connect(function()
			playSfx("Click")
			if inTrade then return end
			TradeInvite:FireServer(targetId)
			invite.Text = "WYSŁANO"
			task.delay(1.5, function() if invite and invite.Parent then invite.Text = "INVITE" end end)
		end)
	end
end

local function openList()
	if inTrade then return end
	rebuildList()
	listGui.Enabled = true
	lockMove("list")
	if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("TRADE") end
	listPanel.Size = UDim2.fromOffset(LIST_W * 0.85, LIST_H * 0.85)
	TweenService:Create(listPanel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(LIST_W, LIST_H) }):Play()
end
local function closeList()
	listGui.Enabled = false
	unlockMove("list")
	if _G["__hudPanelClose"] then _G["__hudPanelClose"]("TRADE") end
end

tradeBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	if listGui.Enabled then closeList() else openList() end
end)
listClose.MouseButton1Click:Connect(function() playSfx("Click"); closeList() end)

-- Odśwież listę gdy ktoś dołączy/wyjdzie (jeśli otwarta)
Players.PlayerAdded:Connect(function() if listGui.Enabled then rebuildList() end end)
Players.PlayerRemoving:Connect(function() if listGui.Enabled then rebuildList() end end)

-- ════════════════════════════════════════════════════════════════════════════
--  3) POPUPY (zaproszenie + powiadomienia)
-- ════════════════════════════════════════════════════════════════════════════
local popupGui = Instance.new("ScreenGui")
popupGui.Name           = "TradePopupGui"
popupGui.ResetOnSpawn   = false
popupGui.IgnoreGuiInset = true
popupGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
popupGui.DisplayOrder   = 80  -- nad oknem wymiany
popupGui.Parent         = playerGui

-- 3a) Zaproszenie przychodzące (akceptuj / anuluj), trochę wyżej niż środek
local invitePopup = Instance.new("Frame")
invitePopup.Size             = UDim2.fromOffset(560, 150)
invitePopup.AnchorPoint      = Vector2.new(0.5, 0.5)
invitePopup.Position         = UDim2.fromScale(0.5, 0.38)
invitePopup.BackgroundColor3 = C_PANEL
invitePopup.BorderSizePixel  = 0
invitePopup.Visible          = false
invitePopup.Parent           = popupGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = invitePopup
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = invitePopup
end
local inviteText = Instance.new("TextLabel")
inviteText.Size = UDim2.new(1, -32, 0, 60); inviteText.Position = UDim2.fromOffset(16, 16)
inviteText.BackgroundTransparency = 1; inviteText.Text = ""; inviteText.TextWrapped = true
inviteText.TextSize = 22; inviteText.Font = FONT; inviteText.TextColor3 = C_WHITE
inviteText.Parent = invitePopup

local inviteAccept = Instance.new("ImageButton")
inviteAccept.Size = UDim2.fromOffset(64, 64); inviteAccept.AnchorPoint = Vector2.new(0.5, 1)
inviteAccept.Position = UDim2.new(0.5, -70, 1, -14); inviteAccept.BackgroundTransparency = 1
inviteAccept.Image = ACCEPT_ICON; inviteAccept.ScaleType = Enum.ScaleType.Fit
inviteAccept.AutoButtonColor = false; inviteAccept.Parent = invitePopup
do
	local sc = Instance.new("UIScale"); sc.Parent = inviteAccept
	local ti = TweenInfo.new(0.1)
	inviteAccept.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.12 }):Play() end)
	inviteAccept.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
end
local inviteDecline = Instance.new("ImageButton")
inviteDecline.Size = UDim2.fromOffset(64, 64); inviteDecline.AnchorPoint = Vector2.new(0.5, 1)
inviteDecline.Position = UDim2.new(0.5, 70, 1, -14); inviteDecline.BackgroundTransparency = 1
inviteDecline.Image = CANCEL_ICON; inviteDecline.ScaleType = Enum.ScaleType.Fit
inviteDecline.AutoButtonColor = false; inviteDecline.Parent = invitePopup
do
	local sc = Instance.new("UIScale"); sc.Parent = inviteDecline
	local ti = TweenInfo.new(0.1)
	inviteDecline.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.12 }):Play() end)
	inviteDecline.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end)
end

local pendingInviteFrom: number? = nil
local function hideInvitePopup()
	invitePopup.Visible = false
	pendingInviteFrom = nil
	unlockMove("invite")
end
inviteAccept.MouseButton1Click:Connect(function()
	playSfx("Click")
	if pendingInviteFrom then TradeRespond:FireServer({ fromUserId = pendingInviteFrom, accept = true }) end
	hideInvitePopup()
end)
inviteDecline.MouseButton1Click:Connect(function()
	playSfx("Click")
	if pendingInviteFrom then TradeRespond:FireServer({ fromUserId = pendingInviteFrom, accept = false }) end
	hideInvitePopup()
end)

-- 3b) Powiadomienie (auto-dismiss) — odmowa / zajęty / wynik
local notif = Instance.new("TextLabel")
notif.Size = UDim2.fromOffset(560, 64); notif.AnchorPoint = Vector2.new(0.5, 0.5)
notif.Position = UDim2.fromScale(0.5, 0.34); notif.BackgroundColor3 = C_PANEL
notif.BorderSizePixel = 0; notif.Text = ""; notif.TextWrapped = true
notif.TextSize = 22; notif.Font = FONT; notif.TextColor3 = C_WHITE
notif.Visible = false; notif.Parent = popupGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = notif
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = notif
end
local notifToken = 0
local function showNotif(msg: string, color: Color3?)
	notif.Text = msg
	notif.TextColor3 = color or C_WHITE
	notif.Visible = true
	notifToken += 1
	local my = notifToken
	task.delay(3, function() if notifToken == my then notif.Visible = false end end)
end

-- ════════════════════════════════════════════════════════════════════════════
--  4) OKNO WYMIANY
-- ════════════════════════════════════════════════════════════════════════════
local tradeGui = Instance.new("ScreenGui")
tradeGui.Name           = "TradeWindowGui"
tradeGui.ResetOnSpawn   = false
tradeGui.IgnoreGuiInset = true
tradeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
tradeGui.DisplayOrder   = 62
tradeGui.Enabled        = false
tradeGui.Parent         = playerGui

local tOverlay = Instance.new("TextButton")
tOverlay.Size = UDim2.fromScale(1, 1); tOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
tOverlay.BackgroundTransparency = 0.5; tOverlay.BorderSizePixel = 0
tOverlay.Text = ""; tOverlay.AutoButtonColor = false; tOverlay.ZIndex = 1; tOverlay.Parent = tradeGui

local TW_W, TW_H = 1080, 660
local tPanel = Instance.new("Frame")
tPanel.Size             = UDim2.fromOffset(TW_W, TW_H)
tPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
tPanel.Position         = UDim2.fromScale(0.5, 0.5)
tPanel.BackgroundColor3 = C_PANEL
tPanel.BorderSizePixel  = 0
tPanel.ZIndex           = 2
tPanel.Parent           = tradeGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 18); c.Parent = tPanel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = tPanel
end
local _, tClose = buildHeader(tPanel, 56, "WYMIANA")
local tTitle = tPanel:FindFirstChild("Title", true) :: TextLabel

-- Buduje jedną stronę (kolumna): tytuł, siatka petów, wiersz kwoty, znacznik akceptacji.
-- editable = true → moja strona (klikalne pety + edytowalna kwota).
local function buildSide(x: number, w: number, editable: boolean)
	local col = Instance.new("Frame")
	col.Size = UDim2.fromOffset(w, TW_H - 56 - 24 - 80)
	col.Position = UDim2.fromOffset(x, 56 + 12)
	col.BackgroundColor3 = C_CARD; col.BackgroundTransparency = 0.15
	col.BorderSizePixel = 0; col.ZIndex = 3; col.Parent = tPanel
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = col
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Transparency = 0.4; s.Parent = col

	local head = Instance.new("TextLabel")
	head.Size = UDim2.new(1, -24, 0, 34); head.Position = UDim2.fromOffset(14, 10)
	head.BackgroundTransparency = 1; head.Text = editable and "TWOJA OFERTA" or "OFERTA"
	head.TextSize = 18; head.Font = FONT; head.TextColor3 = editable and C_ACC or Color3.fromRGB(239, 199, 95)
	head.TextXAlignment = Enum.TextXAlignment.Left; head.TextTruncate = Enum.TextTruncate.AtEnd
	head.ZIndex = 4; head.Name = "Head"; head.Parent = col

	local grid = Instance.new("ScrollingFrame")
	grid.Size = UDim2.new(1, -24, 1, -110); grid.Position = UDim2.fromOffset(12, 50)
	grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 6
	grid.CanvasSize = UDim2.new(); grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ZIndex = 4; grid.Name = "Grid"; grid.Parent = col
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(92, 92); gl.CellPadding = UDim2.fromOffset(10, 10)
	gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = grid

	-- Wiersz kwoty (na dole kolumny)
	local moneyRow = Instance.new("Frame")
	moneyRow.Size = UDim2.new(1, -24, 0, 44); moneyRow.AnchorPoint = Vector2.new(0, 1)
	moneyRow.Position = UDim2.new(0, 12, 1, -12); moneyRow.BackgroundColor3 = C_HEADER
	moneyRow.BorderSizePixel = 0; moneyRow.ZIndex = 4; moneyRow.Name = "MoneyRow"; moneyRow.Parent = col
	local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = moneyRow

	if editable then
		local box = Instance.new("TextBox")
		box.Size = UDim2.fromScale(1, 1); box.BackgroundTransparency = 1
		box.Text = ""; box.PlaceholderText = "Kwota PLN (0)"; box.ClearTextOnFocus = false
		box.TextSize = 20; box.Font = FONT; box.TextColor3 = C_GREEN; box.PlaceholderColor3 = C_DIM
		box.ZIndex = 5; box.Name = "MoneyBox"; box.Parent = moneyRow
	else
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
		lbl.Text = "0 PLN"; lbl.TextSize = 20; lbl.Font = FONT; lbl.TextColor3 = C_GREEN
		lbl.ZIndex = 5; lbl.Name = "MoneyLbl"; lbl.Parent = moneyRow
	end
	return col, grid
end

local GAP = 16
local SIDE_W = (TW_W - 24 - GAP) / 2
local leftCol,  leftGrid  = buildSide(12, SIDE_W, true)
local rightCol, rightGrid = buildSide(12 + SIDE_W + GAP, SIDE_W, false)
local leftMoneyBox  = leftCol:FindFirstChild("MoneyBox", true) :: TextBox
local rightMoneyLbl = rightCol:FindFirstChild("MoneyLbl", true) :: TextLabel
local rightHead     = rightCol:FindFirstChild("Head", true) :: TextLabel

-- Dolny pasek akcji
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 80); bar.AnchorPoint = Vector2.new(0, 1)
bar.Position = UDim2.new(0, 0, 1, 0); bar.BackgroundTransparency = 1
bar.ZIndex = 4; bar.Parent = tPanel

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(0, 360, 0, 30); statusLbl.AnchorPoint = Vector2.new(0.5, 0.5)
statusLbl.Position = UDim2.new(0.5, 0, 0.5, -18); statusLbl.BackgroundTransparency = 1
statusLbl.Text = ""; statusLbl.TextSize = 18; statusLbl.Font = FONT; statusLbl.TextColor3 = C_DIM
statusLbl.ZIndex = 5; statusLbl.Parent = bar

local acceptBtn = makeButton(bar, "Akceptuj", 220, 50, C_ACC, C_HEADER)
acceptBtn.AnchorPoint = Vector2.new(0.5, 0.5); acceptBtn.Position = UDim2.new(0.5, -130, 0.5, 14); acceptBtn.ZIndex = 5
local cancelBtn = makeButton(bar, "Anuluj", 220, 50, X_RED, C_WHITE)
cancelBtn.AnchorPoint = Vector2.new(0.5, 0.5); cancelBtn.Position = UDim2.new(0.5, 130, 0.5, 14); cancelBtn.ZIndex = 5

-- ── Stan okna ────────────────────────────────────────────────────────────────
local myPets: { any } = {}
local mySelected: { string } = {}
local mySelectedSet: { [string]: boolean } = {}
local myMoney = 0
local youAccepted = false
local tileByPet: { [string]: { check: Frame } } = {}
local countdownThread: thread? = nil

local function rarityColor(r: string): Color3
	local rc = PET_RARITIES[r]
	return (rc and rc.color) or Color3.fromRGB(150, 150, 150)
end
local function rarityImage(r: string): string?
	local rc = PET_RARITIES[r]
	return rc and rc.image or nil
end

local function sendOffer()
	TradeOffer:FireServer({ pets = mySelected, money = myMoney })
end

-- Render kafelka peta (lewa = klikalny z checkmarkiem; prawa = read-only)
local function makePetTile(parent: Instance, pet, idx: number, clickable: boolean): Frame
	local tile = Instance.new("Frame")
	tile.Size = UDim2.fromOffset(92, 92); tile.BackgroundColor3 = Color3.fromRGB(12, 44, 35)
	tile.BorderSizePixel = 0; tile.LayoutOrder = idx; tile.ZIndex = 5; tile.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = tile
	local s = Instance.new("UIStroke"); s.Color = rarityColor(pet.rarity); s.Thickness = 3; s.Parent = tile

	local img = rarityImage(pet.rarity)
	if img then
		local il = Instance.new("ImageLabel")
		il.Size = UDim2.fromScale(0.78, 0.78); il.AnchorPoint = Vector2.new(0.5, 0.5)
		il.Position = UDim2.fromScale(0.5, 0.46); il.BackgroundTransparency = 1
		il.Image = img; il.ScaleType = Enum.ScaleType.Fit; il.ZIndex = 6; il.Parent = tile
	end
	local cl = Instance.new("TextLabel")
	cl.Size = UDim2.new(1, -6, 0, 18); cl.AnchorPoint = Vector2.new(0.5, 1)
	cl.Position = UDim2.new(0.5, 0, 1, -3); cl.BackgroundTransparency = 1
	cl.Text = pet.class or ""; cl.TextSize = 13; cl.Font = FONT
	cl.TextColor3 = C_WHITE; cl.TextTruncate = Enum.TextTruncate.AtEnd; cl.ZIndex = 7; cl.Parent = tile
	if pet.gold then
		cl.TextColor3 = Color3.fromRGB(255, 215, 90)
	end

	if clickable then
		-- checkmark overlay (jak przy gold upgrade)
		local check = Instance.new("Frame")
		check.Size = UDim2.fromScale(1, 1); check.BackgroundColor3 = Color3.new(0, 0, 0)
		check.BackgroundTransparency = 0.45; check.BorderSizePixel = 0
		check.Visible = mySelectedSet[pet.id] == true; check.ZIndex = 8; check.Parent = tile
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = check
		local mark = Instance.new("TextLabel")
		mark.Size = UDim2.fromScale(1, 1); mark.BackgroundTransparency = 1
		mark.Text = "✓"; mark.Font = FONT; mark.TextSize = 36; mark.TextColor3 = C_GREEN
		mark.ZIndex = 9; mark.Parent = check
		tileByPet[pet.id] = { check = check }

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromScale(1, 1); btn.BackgroundTransparency = 1; btn.Text = ""
		btn.AutoButtonColor = false; btn.ZIndex = 10; btn.Parent = tile
		btn.MouseButton1Click:Connect(function()
			if youAccepted then return end  -- oferta zablokowana po akceptacji (zmiana = reset na serwerze)
			playSfx("Click")
			if mySelectedSet[pet.id] then
				mySelectedSet[pet.id] = nil
				for i, id in ipairs(mySelected) do if id == pet.id then table.remove(mySelected, i); break end end
				check.Visible = false
			else
				mySelectedSet[pet.id] = true
				table.insert(mySelected, pet.id)
				check.Visible = true
			end
			sendOffer()
		end)
	end
	return tile
end

local function renderMyPets()
	for _, ch in ipairs(leftGrid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	tileByPet = {}
	for i, pet in ipairs(myPets) do
		makePetTile(leftGrid, pet, i, true)
	end
end

local function renderTheirPets(pets)
	for _, ch in ipairs(rightGrid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	for i, pet in ipairs(pets or {}) do
		makePetTile(rightGrid, pet, i, false)
	end
end

local function stopCountdown()
	if countdownThread then pcall(task.cancel, countdownThread); countdownThread = nil end
end

local function setAcceptedVisual()
	if youAccepted then
		acceptBtn.Text = "ZAAKCEPTOWANO"
		acceptBtn.BackgroundColor3 = C_GREEN
		leftMoneyBox.TextEditable = false
	else
		acceptBtn.Text = "Akceptuj"
		acceptBtn.BackgroundColor3 = C_ACC
		leftMoneyBox.TextEditable = true
	end
end

-- Układ dolnego paska: Anuluj pojawia się dopiero po akceptacji (lub w trakcie odliczania).
local function updateBar(counting: boolean)
	cancelBtn.Visible = youAccepted or counting
	acceptBtn.Visible = not counting
	if acceptBtn.Visible and cancelBtn.Visible then
		acceptBtn.Position = UDim2.new(0.5, -130, 0.5, 14)
		cancelBtn.Position = UDim2.new(0.5, 130, 0.5, 14)
	elseif acceptBtn.Visible then
		acceptBtn.Position = UDim2.new(0.5, 0, 0.5, 14)
	else
		cancelBtn.Position = UDim2.new(0.5, 0, 0.5, 14)
	end
end

local function startCountdown()
	stopCountdown()
	countdownThread = task.spawn(function()
		for t = COUNTDOWN_SEC, 1, -1 do
			statusLbl.Text = string.format("Wymiana za %d...", t)
			statusLbl.TextColor3 = C_GREEN
			task.wait(1)
		end
		statusLbl.Text = "Finalizowanie..."
	end)
end

-- ── Apply TradeSync ──────────────────────────────────────────────────────────
local function applySync(s)
	if type(s) ~= "table" then return end
	local your, their = s.your or {}, s.their or {}
	youAccepted = your.accepted == true

	-- Moja kwota — nie nadpisuj gdy aktywnie piszę
	if not leftMoneyBox:IsFocused() then
		myMoney = tonumber(your.money) or 0
		leftMoneyBox.Text = myMoney > 0 and tostring(myMoney) or ""
	end

	-- Prawa strona (read-only): pety + kwota + nazwa + akceptacja
	if their.name then rightHead.Text = "OFERTA " .. string.upper(their.name) end
	renderTheirPets(their.pets)
	rightMoneyLbl.Text = string.format("%d PLN", math.floor(tonumber(their.money) or 0))

	setAcceptedVisual()

	-- Status + countdown
	updateBar(s.counting == true)
	if s.counting then
		startCountdown()
	else
		stopCountdown()
		if youAccepted and not their.accepted then
			statusLbl.Text = "Czekam na drugiego gracza..."
			statusLbl.TextColor3 = C_DIM
		elseif their.accepted and not youAccepted then
			statusLbl.Text = "Drugi gracz zaakceptował"
			statusLbl.TextColor3 = C_ACC
		else
			statusLbl.Text = ""
		end
	end
end

local function openTradeWindow(payload)
	inTrade = true
	closeList()
	myPets = payload.yourPets or {}
	mySelected = {}; mySelectedSet = {}; myMoney = 0; youAccepted = false
	leftMoneyBox.Text = ""; leftMoneyBox.TextEditable = true
	rightMoneyLbl.Text = "0 PLN"
	statusLbl.Text = ""
	tTitle.Text = "WYMIANA — " .. tostring(payload.otherName or "")
	rightHead.Text = "OFERTA " .. string.upper(tostring(payload.otherName or ""))
	renderMyPets()
	renderTheirPets({})
	setAcceptedVisual()
	updateBar(false)

	tradeGui.Enabled = true
	lockMove("trade")
	if _G["__hudPanelOpen"] then _G["__hudPanelOpen"]("TRADE") end
	tPanel.Size = UDim2.fromOffset(TW_W * 0.9, TW_H * 0.9)
	TweenService:Create(tPanel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(TW_W, TW_H) }):Play()
end

local function closeTradeWindow()
	stopCountdown()
	tradeGui.Enabled = false
	inTrade = false
	unlockMove("trade")
	if _G["__hudPanelClose"] then _G["__hudPanelClose"]("TRADE") end
end

-- Kwota: na zatwierdzeniu (FocusLost) waliduj i wyślij
leftMoneyBox.FocusLost:Connect(function()
	if youAccepted then leftMoneyBox.Text = myMoney > 0 and tostring(myMoney) or ""; return end
	local n = math.max(0, math.floor(tonumber(leftMoneyBox.Text) or 0))
	myMoney = n
	leftMoneyBox.Text = n > 0 and tostring(n) or ""
	sendOffer()
end)

acceptBtn.MouseButton1Click:Connect(function()
	if youAccepted then return end
	playSfx("Click")
	TradeAccept:FireServer()
end)
cancelBtn.MouseButton1Click:Connect(function()
	playSfx("Click")
	TradeCancel:FireServer()
	-- okno zamknie się po TradeEnd; nie zamykamy lokalnie żeby uniknąć desyncu
end)
tClose.MouseButton1Click:Connect(function()
	playSfx("Click")
	TradeCancel:FireServer()
end)

-- ════════════════════════════════════════════════════════════════════════════
--  WIRING — eventy serwera
-- ════════════════════════════════════════════════════════════════════════════
TradeInvited.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if inTrade then return end  -- jesteśmy już w wymianie — ignoruj (serwer i tak odrzuci)
	-- BEZ blokady ruchu — niezamówione zaproszenie nie powinno zamrażać gracza (anti-grief).
	pendingInviteFrom = payload.fromUserId
	inviteText.Text = string.format("%s zaprosił cię do wymiany", tostring(payload.fromName or "Gracz"))
	invitePopup.Visible = true
	playSfx("Click")
	-- Auto-ukrycie po wygaśnięciu zaproszenia po stronie serwera
	local my = payload.fromUserId
	task.delay((cfg.InviteTimeout or 30) + 1, function()
		if invitePopup.Visible and pendingInviteFrom == my then hideInvitePopup() end
	end)
end)

TradeInviteResult.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.message then
		showNotif(payload.message, X_RED)
	elseif payload.accepted == false then
		showNotif(string.format("%s odmówił wymiany", tostring(payload.name or "Gracz")), X_RED)
	end
end)

TradeStart.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	hideInvitePopup()
	openTradeWindow(payload)
end)

TradeSync.OnClientEvent:Connect(function(s)
	if not tradeGui.Enabled then return end
	applySync(s)
end)

TradeEnd.OnClientEvent:Connect(function(payload)
	payload = type(payload) == "table" and payload or {}
	local reason = payload.reason
	if reason == "completed" then
		local rec = payload.received or {}
		local petN = rec.pets and #rec.pets or 0
		local money = math.floor(tonumber(rec.money) or 0)
		local parts = {}
		if petN > 0 then table.insert(parts, string.format("%d pet%s", petN, petN == 1 and "" or "y")) end
		if money > 0 then table.insert(parts, string.format("%d PLN", money)) end
		local got = #parts > 0 and ("Otrzymałeś: " .. table.concat(parts, " + ")) or "Wymiana zakończona"
		showNotif(got, C_GREEN)
		playSfx("Money")
	elseif reason == "failed" then
		showNotif(payload.message or "Wymiana nieudana", X_RED)
	else  -- cancelled / left
		showNotif(payload.message or "Wymiana anulowana", X_RED)
	end
	closeTradeWindow()
end)

-- ESC zamyka listę / anuluje wymianę / odrzuca zaproszenie
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode ~= Enum.KeyCode.Escape then return end
	if invitePopup.Visible then
		if pendingInviteFrom then TradeRespond:FireServer({ fromUserId = pendingInviteFrom, accept = false }) end
		hideInvitePopup()
	elseif tradeGui.Enabled then
		TradeCancel:FireServer()
	elseif listGui.Enabled then
		closeList()
	end
end)

print("[TradeController] gotowy")
