-- KoszController.luau
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local Config     = require(ReplicatedStorage:WaitForChild("Config"))
local Events     = ReplicatedStorage:WaitForChild("Events")
local KoszResult = Events:WaitForChild("KoszResult")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── SFX ───────────────────────────────────────────────────────────────────
local SFX_FOLDER = workspace:WaitForChild("SFX")

local function getOrCreateSfxGroup(): SoundGroup
	local existing = SoundService:FindFirstChild("SfxGroup")
	if existing and existing:IsA("SoundGroup") then return existing :: SoundGroup end
	local g = Instance.new("SoundGroup")
	g.Name   = "SfxGroup"
	g.Volume = 1
	g.Parent = SoundService
	return g
end
local SFX_GROUP = getOrCreateSfxGroup()

-- opts: { trimEnd: number? } — utnij ostatnie X sekund (np. Win)
local function playSfx(name: string, opts: { trimEnd: number? }?)
	local template = SFX_FOLDER:FindFirstChild(name)
	if not template or not template:IsA("Sound") then return end
	local s = template:Clone()
	s.SoundGroup = SFX_GROUP
	s.Parent = SoundService
	s:Play()
	local trim = opts and opts.trimEnd
	if trim and trim > 0 then
		local playStart = os.clock()
		task.spawn(function()
			if not s.IsLoaded then s.Loaded:Wait() end
			local stopAt = s.TimeLength - trim
			local remaining = stopAt - (os.clock() - playStart)
			if remaining > 0 then task.wait(remaining) end
			if s.Parent then s:Stop(); s:Destroy() end
		end)
	else
		s.Ended:Connect(function() s:Destroy() end)
	end
end

-- ── Paleta ────────────────────────────────────────────────────────────────

local FONT      = Enum.Font.GothamBlack
local C_BG      = Color3.fromRGB(18, 91, 73)
local C_PANEL   = Color3.fromRGB(24, 110, 90)
local C_HEADER  = Color3.fromRGB(0, 53, 39)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_WHITE   = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT = Color3.fromRGB(175, 175, 175)
local C_GREEN   = Color3.fromRGB(170, 221, 102)
local C_RED     = Color3.fromRGB(220, 80, 80)

local RARITY_COLORS = Config.BottleColors
local RARITY_ORDER  = { "Zwykla", "Rzadka", "Epicka", "Legendarna", "Mityczny" }

-- ── Helpery koloru ───────────────────────────────────────────────────────

local function darken(c: Color3, mix: number): Color3
	return Color3.new(c.R * (1 - mix), c.G * (1 - mix), c.B * (1 - mix))
end

-- ── ScreenGui ────────────────────────────────────────────────────────────

local PANEL_W  = 480
local PANEL_H  = 540
local HEADER_H = 56
local WINDOW_W = PANEL_W - 64
local WINDOW_H = 312    -- pokazuje ~3 itemy (czyli 3 × 104)
local ITEM_H   = 104

local gui = Instance.new("ScreenGui")
gui.Name           = "Kosz"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("Frame")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.ZIndex                 = 1
overlay.Parent                 = gui

-- Panel: transparentny kontener pozycyjny (tylko anchor/position, brak chrome)
local panel = Instance.new("Frame")
panel.Size                  = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint           = Vector2.new(0.5, 0.5)
panel.Position              = UDim2.new(0.5, 0, 0.55, 0)
panel.BackgroundTransparency = 1
panel.BorderSizePixel       = 0
panel.ZIndex                = 2
panel.Parent                = gui

-- Window (okienko z lecącymi itemami) — transparentne tło, fade na krawędziach
local window = Instance.new("Frame")
window.Size                   = UDim2.fromOffset(WINDOW_W, WINDOW_H)
window.AnchorPoint            = Vector2.new(0.5, 0)
window.Position               = UDim2.new(0.5, 0, 0, 12)
window.BackgroundTransparency = 1
window.BorderSizePixel        = 0
window.ClipsDescendants       = true
window.ZIndex                 = 3
window.Parent                 = panel

-- Gradient transparency: fade w górze i dole okna, opaque w środku
do
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90  -- pionowy
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1.00),
		NumberSequenceKeypoint.new(0.22, 0.00),
		NumberSequenceKeypoint.new(0.78, 0.00),
		NumberSequenceKeypoint.new(1.00, 1.00),
	})
	grad.Parent = window
end

-- Strip — kontener z itemami
local strip = Instance.new("Frame")
strip.Size                   = UDim2.new(1, 0, 0, 0)  -- wysokość ustawiana per losowanie
strip.Position               = UDim2.fromOffset(0, 0)
strip.BackgroundTransparency = 1
strip.BorderSizePixel        = 0
strip.ZIndex                 = 4
strip.Parent                 = window

-- Wskaźnik środka (jedyna widoczna "ramka" — ramka po środku)
-- Renderowany NA panelu (nie na oknie), bo gradient w oknie by go też wyfadeował
local indicator = Instance.new("Frame")
indicator.Size                   = UDim2.fromOffset(WINDOW_W - 4, ITEM_H + 4)
indicator.AnchorPoint            = Vector2.new(0.5, 0.5)
indicator.Position               = UDim2.new(0.5, 0, 0, 12 + WINDOW_H / 2)
indicator.BackgroundTransparency = 1
indicator.BorderSizePixel        = 0
indicator.ZIndex                 = 10
indicator.Parent                 = panel
do
	local s = Instance.new("UIStroke")
	s.Color = C_WHITE; s.Thickness = 4; s.Transparency = 0.05
	s.Parent = indicator
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = indicator
end

-- Etykieta rezultatu (pod oknem) — pojawia się i znika szybko
local resultLbl = Instance.new("TextLabel")
resultLbl.Size                   = UDim2.new(1, -32, 0, 36)
resultLbl.AnchorPoint            = Vector2.new(0.5, 0)
resultLbl.Position               = UDim2.new(0.5, 0, 0, 12 + WINDOW_H + 10)
resultLbl.BackgroundTransparency = 1
resultLbl.Text                   = ""
resultLbl.TextSize               = 24
resultLbl.Font                   = FONT
resultLbl.TextColor3             = C_WHITE
resultLbl.TextStrokeColor3       = Color3.new(0, 0, 0)
resultLbl.TextStrokeTransparency = 0.4
resultLbl.TextTransparency       = 1
resultLbl.ZIndex                 = 4
resultLbl.Parent                 = panel

-- ── Budowa stripu ────────────────────────────────────────────────────────

local legendaryHeartbeatConns: { RBXScriptConnection } = {}

local function randomCountFor(rarity: string): number
	local pool = Config.KoszDropQuantity and Config.KoszDropQuantity[rarity]
	if not pool or #pool == 0 then return 1 end
	local total = 0
	for _, e in ipairs(pool) do total = total + (e[2] or 0) end
	local r = math.random() * total
	local acc = 0
	for _, e in ipairs(pool) do
		acc = acc + (e[2] or 0)
		if r <= acc then return e[1] end
	end
	return pool[1][1]
end

local function makeItemFrame(rarity: string, index: number, count: number): Frame
	local item = Instance.new("Frame")
	item.Size                   = UDim2.new(1, -16, 0, ITEM_H - 8)
	item.Position               = UDim2.fromOffset(8, index * ITEM_H + 4)
	item.BackgroundColor3       = darken(RARITY_COLORS[rarity], 0.55)
	item.BackgroundTransparency = 0
	item.BorderSizePixel        = 0
	item.ClipsDescendants       = true
	item.ZIndex                 = 5
	item.Parent                 = strip
	local stroke
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = item
		stroke = Instance.new("UIStroke")
		stroke.Color = RARITY_COLORS[rarity]; stroke.Thickness = 3
		stroke.Parent = item
	end

	-- VFX Legendarnej — rotujący gradient + pulsujący stroke (jak w ekwipunku)
	if rarity == "Legendarna" then
		local glow = Instance.new("Frame")
		glow.Size                   = UDim2.fromScale(1, 1)
		glow.BackgroundColor3       = Color3.fromRGB(255, 230, 100)
		glow.BackgroundTransparency = 0.4
		glow.BorderSizePixel        = 0
		glow.ZIndex                 = 5  -- pod tekstem
		glow.Parent                 = item

		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 235, 130)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 40)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 235, 130)),
		})
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   0.15),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1,   0.15),
		})
		grad.Rotation = math.random() * 360  -- random start
		grad.Parent = glow

		local conn = RunService.Heartbeat:Connect(function(dt)
			if not item.Parent then return end
			local t = tick()
			local pulse = (math.sin(t * 4.5) + 1) * 0.5  -- 0..1
			-- Stroke pulsuje gold ↔ white, grubość 3 → 5.5
			stroke.Color = Color3.fromRGB(
				255,
				200 + math.floor(pulse * 55),
				60  + math.floor(pulse * 195))
			stroke.Thickness = 3 + pulse * 2.5
			-- Rotacja gradientu
			grad.Rotation = (grad.Rotation + 80 * dt) % 360
		end)
		table.insert(legendaryHeartbeatConns, conn)
	end

	-- VFX Mityczna — gradient fiolet ↔ czarny
	if rarity == "Mityczny" then
		local glow = Instance.new("Frame")
		glow.Size                   = UDim2.fromScale(1, 1)
		glow.BackgroundColor3       = Color3.fromRGB(80, 30, 140)
		glow.BackgroundTransparency = 0.35
		glow.BorderSizePixel        = 0
		glow.ZIndex                 = 5
		glow.Parent                 = item

		local mgrad = Instance.new("UIGradient")
		mgrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(150, 50, 220)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10,  0,  20)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(150, 50, 220)),
		})
		mgrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   0.15),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1,   0.15),
		})
		mgrad.Rotation = math.random() * 360
		mgrad.Parent = glow

		local conn = RunService.Heartbeat:Connect(function(dt)
			if not item.Parent then return end
			local t = tick()
			local pulse = (math.sin(t * 4.0) + 1) * 0.5
			stroke.Color = Color3.fromRGB(
				80  + math.floor(pulse * 100),
				20  + math.floor(pulse * 60),
				140 + math.floor(pulse * 100))
			stroke.Thickness = 3 + pulse * 2.5
			mgrad.Rotation = (mgrad.Rotation + 60 * dt) % 360
		end)
		table.insert(legendaryHeartbeatConns, conn)
	end

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = "+" .. tostring(count) .. " " .. string.upper(rarity)
	lbl.TextSize               = 28
	lbl.Font                   = FONT
	lbl.TextColor3             = C_WHITE
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.ZIndex                 = 6
	lbl.Parent                 = item

	return item
end

local function randomRarity(): string
	-- Random z weight (te same wagi co spawn). Bo to dekoracja, mogę używać prostszego.
	return RARITY_ORDER[math.random(#RARITY_ORDER)]
end

local function clearStrip()
	for _, conn in ipairs(legendaryHeartbeatConns) do conn:Disconnect() end
	legendaryHeartbeatConns = {}
	for _, child in ipairs(strip:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local STRIP_LEN     = 36
local WINNER_OFFSET = 5   -- itemów po winnerze (żeby strip nie wyglądał na kończący się)
local WINNER_IDX    = STRIP_LEN - 1 - WINNER_OFFSET

local function buildStrip(winnerRarity: string, winnerCount: number)
	clearStrip()
	for i = 0, STRIP_LEN - 1 do
		local isWinner = (i == WINNER_IDX)
		local r = isWinner and winnerRarity or randomRarity()
		local c = isWinner and winnerCount or randomCountFor(r)
		makeItemFrame(r, i, c)
	end
	strip.Size = UDim2.new(1, 0, 0, STRIP_LEN * ITEM_H)
end

-- ── Animacja ─────────────────────────────────────────────────────────────

local POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)

local function showPanel()
	gui.Enabled = true
	panel.Position = POS_HIDE
	overlay.BackgroundTransparency = 1
	TweenService:Create(panel,
		TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = POS_SHOW }):Play()
	TweenService:Create(overlay,
		TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.55 }):Play()
end

local function hidePanel()
	TweenService:Create(panel,
		TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Position = POS_HIDE }):Play()
	local tw = TweenService:Create(overlay,
		TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 })
	tw.Completed:Connect(function() gui.Enabled = false end)
	tw:Play()
end

local SPIN_DURATION = 3.5

local function showRoulette(winnerRarity: string, winnerCount: number)
	buildStrip(winnerRarity, winnerCount)
	resultLbl.Text             = ""
	resultLbl.TextTransparency = 1

	-- Pozycja startowa: pierwszy item na górze okna
	strip.Position = UDim2.fromOffset(0, 0)

	-- Cel: winner item (WINNER_IDX) wycentrowany w oknie
	local winnerOffsetY = WINNER_IDX * ITEM_H + 4
	local targetY       = -(winnerOffsetY) + (WINDOW_H / 2) - (ITEM_H / 2)

	showPanel()
	if _G["__lockMovement"] then _G["__lockMovement"]() end

	task.delay(0.25, function()
		local spin = TweenService:Create(strip,
			TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, targetY) })
		spin:Play()

		-- Tick przy każdym itemie przejeżdżającym przez wskaźnik (środek okna)
		local lastIdx = -1
		local tickConn: RBXScriptConnection? = nil
		tickConn = RunService.RenderStepped:Connect(function()
			local stripY = strip.Position.Y.Offset
			local idx = math.floor((WINDOW_H / 2 - ITEM_H / 2 - stripY) / ITEM_H + 0.5)
			if idx ~= lastIdx then
				lastIdx = idx
				playSfx("RouletteTick")
			end
		end)

		spin.Completed:Connect(function()
			if tickConn then tickConn:Disconnect() end
			playSfx("Win", { trimEnd = 0.6 })

			-- Krótki flash tekstu: fade in szybko → trzymaj → fade out szybko
			resultLbl.Text       = "+" .. tostring(winnerCount) .. " " .. string.upper(winnerRarity)
			resultLbl.TextColor3 = RARITY_COLORS[winnerRarity]
			TweenService:Create(resultLbl,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0 }):Play()
			task.delay(0.55, function()
				TweenService:Create(resultLbl,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ TextTransparency = 1 }):Play()
			end)
			task.delay(0.85, function()
				hidePanel()
				if _G["__unlockMovement"] then _G["__unlockMovement"]() end
			end)
		end)
	end)
end

local function showFailMessage(reason: string, ctx: any?)
	local msg
	if reason == "full" then
		msg = "PLECAK PEŁNY!"
	elseif reason == "noSpace" then
		-- ctx ma rarity, count, freeSpace
		if ctx and ctx.count and ctx.freeSpace then
			msg = string.format("ZA MAŁO MIEJSCA (%d/%d) — ODDAJ DO BUTELKOMATU!",
				ctx.freeSpace, ctx.count)
		else
			msg = "MASZ ZA MAŁO MIEJSCA — ODDAJ DO BUTELKOMATU!"
		end
	elseif reason == "cooldown" then
		msg = "PUSTY KOSZ"
	else
		msg = "BŁĄD"
	end

	clearStrip()
	resultLbl.Text             = msg
	resultLbl.TextColor3       = C_RED
	resultLbl.TextTransparency = 1
	resultLbl.TextSize         = (reason == "noSpace") and 18 or 24
	showPanel()
	TweenService:Create(resultLbl,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0 }):Play()
	task.delay(0.7, function()
		TweenService:Create(resultLbl,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }):Play()
	end)
	task.delay(1.0, hidePanel)
end

-- ── Listener ──────────────────────────────────────────────────────────────

KoszResult.OnClientEvent:Connect(function(result)
	if result.success then
		showRoulette(result.rarity, result.count or 1)
	else
		showFailMessage(result.reason or "unknown", result)
	end
end)
