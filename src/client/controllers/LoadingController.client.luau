-- LoadingController.luau
-- Loading screen z realnym preloadem assetów:
-- 1) ContentProvider:PreloadAsync — modele butelek + automat + sklep + kosze
-- 2) WaitForChild na leaderstats — gwarancja że PlayerDataService załadował dane
-- 3) Po wszystkim: pokazuje "TAP TO CONTINUE", input nie działa wcześniej

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider  = game:GetService("ContentProvider")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local FONT       = Enum.Font.GothamBlack
local TITLE_FONT = Enum.Font.LuckiestGuy   -- chunky cartoon style — fajny do collector simulatora
local C_BLACK    = Color3.new(0, 0, 0)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIM      = Color3.fromRGB(175, 175, 175)
local C_TITLE    = Color3.fromRGB(170, 221, 102)  -- matowy leśny zielony (ten sam co C_BASE_ACC w skill tree)

-- Flag dla IntroController
_G["__loadingDone"] = false

local gui = Instance.new("ScreenGui")
gui.Name           = "Loading"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 200
gui.Parent         = playerGui

-- Czarne tło (TextButton — click w dowolnym miejscu)
local bg = Instance.new("TextButton")
bg.Size                   = UDim2.fromScale(1, 1)
bg.BackgroundColor3       = C_BLACK
bg.BackgroundTransparency = 0
bg.BorderSizePixel        = 0
bg.Text                   = ""
bg.AutoButtonColor        = false
bg.ZIndex                 = 1
bg.Parent                 = gui

-- Tytuł
local title = Instance.new("TextLabel")
title.AnchorPoint            = Vector2.new(0.5, 0.5)
title.Position               = UDim2.new(0.5, 0, 0.4, 0)
title.Size                   = UDim2.new(0, 900, 0, 120)
title.BackgroundTransparency = 1
title.Text                   = "KAUCJA SIMULATOR"
title.TextSize               = 96
title.Font                   = TITLE_FONT
title.TextColor3             = C_TITLE
title.TextStrokeColor3       = C_BLACK
title.TextStrokeTransparency = 0
title.ZIndex                 = 2
title.Parent                 = gui

-- Podtytuł (zmienia się: ładowanie… → slogan)
local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint            = Vector2.new(0.5, 0.5)
subtitle.Position               = UDim2.new(0.5, 0, 0.4, 70)
subtitle.Size                   = UDim2.new(0, 700, 0, 40)
subtitle.BackgroundTransparency = 1
subtitle.Text                   = "ŁADOWANIE"
subtitle.TextSize               = 24
subtitle.Font                   = FONT
subtitle.TextColor3             = C_DIM
subtitle.ZIndex                 = 2
subtitle.Parent                 = gui

-- TAP TO CONTINUE (ukryte do końca loadingu)
local tapLbl = Instance.new("TextLabel")
tapLbl.AnchorPoint            = Vector2.new(0.5, 1)
tapLbl.Position               = UDim2.new(0.5, 0, 1, -80)
tapLbl.Size                   = UDim2.new(0, 600, 0, 50)
tapLbl.BackgroundTransparency = 1
tapLbl.Text                   = "KLIKNIJ BY KONTYNUOWAĆ"
tapLbl.TextSize               = 28
tapLbl.Font                   = FONT
tapLbl.TextColor3             = C_WHITE
tapLbl.TextTransparency       = 1   -- ukryte na start
tapLbl.ZIndex                 = 2
tapLbl.Parent                 = gui

-- Status loadu (małe pod tytułem) — pokazuje co aktualnie się ładuje
local statusLbl = Instance.new("TextLabel")
statusLbl.AnchorPoint            = Vector2.new(0.5, 0)
statusLbl.Position               = UDim2.new(0.5, 0, 1, -150)
statusLbl.Size                   = UDim2.new(0, 600, 0, 24)
statusLbl.BackgroundTransparency = 1
statusLbl.Text                   = ""
statusLbl.TextSize               = 14
statusLbl.Font                   = FONT
statusLbl.TextColor3             = C_DIM
statusLbl.TextTransparency       = 0.5
statusLbl.ZIndex                 = 2
statusLbl.Parent                 = gui

-- ── Animacja kropek "ŁADOWANIE..." ───────────────────────────────────────

local loadingReady = false   -- true gdy preload skończony — wtedy click aktywny

local dotsConn: RBXScriptConnection? = nil
local function startDotsAnim()
	local startTick = tick()
	dotsConn = RunService.Heartbeat:Connect(function()
		if loadingReady then return end
		local n = math.floor(((tick() - startTick) * 2) % 4)
		subtitle.Text = "ŁADOWANIE" .. string.rep(".", n)
	end)
end

local function stopDotsAnim()
	if dotsConn then dotsConn:Disconnect(); dotsConn = nil end
end

startDotsAnim()

-- Puls TAP TO CONTINUE
local pulseConn: RBXScriptConnection? = nil
local function startTapPulse()
	pulseConn = RunService.Heartbeat:Connect(function()
		local t = tick()
		tapLbl.TextTransparency = 0.3 + 0.4 * (math.sin(t * 3) * 0.5 + 0.5)
	end)
end

-- ── Loading sequence ────────────────────────────────────────────────────

local MIN_LOAD_TIME = 1.0  -- minimum żeby UI się nie miknął — wymaga przynajmniej 1s

local function setStatus(text: string)
	statusLbl.Text = text
end

task.spawn(function()
	local startedAt = tick()

	-- 1) Czekaj na leaderstats — proxy że dane gracza załadowane na serwerze
	setStatus("dane gracza…")
	localPlayer:WaitForChild("leaderstats", 15)

	-- 2) Zbierz assety do preloadu
	setStatus("modele butelek…")
	local assets = {}

	local bottleModels = ReplicatedStorage:FindFirstChild("BottleModels")
	if bottleModels then
		for _, m in ipairs(bottleModels:GetChildren()) do
			table.insert(assets, m)
		end
	end

	-- Workspace prefaby
	for _, name in ipairs({ "AutomatKaucyjny", "Sklep" }) do
		local m = workspace:FindFirstChild(name)
		if m then table.insert(assets, m) end
	end

	-- Kosze
	local kosze = workspace:FindFirstChild("Kosze")
	if kosze then
		for _, k in ipairs(kosze:GetChildren()) do
			table.insert(assets, k)
		end
	end

	-- Tekstury petów (obrazki w slotach EQ) — preload by uniknąć pop-in
	local petsCfg = Config.Pets and Config.Pets.Rarities
	if petsCfg then
		for _, rcfg in pairs(petsCfg) do
			if type(rcfg) == "table" and rcfg.image then table.insert(assets, rcfg.image) end
		end
	end

	-- 3) Preload (yielding — zwraca gdy wszystko gotowe)
	setStatus("preload assetów (" .. #assets .. ")…")
	if #assets > 0 then
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
		if not ok then
			warn("[Loading] PreloadAsync failed:", err)
		end
	end

	-- 4) Minimum load time żeby flash nie irytował
	local elapsed = tick() - startedAt
	if elapsed < MIN_LOAD_TIME then
		task.wait(MIN_LOAD_TIME - elapsed)
	end

	-- 5) Gotowe — UI przechodzi w tryb "KLIKNIJ BY KONTYNUOWAĆ"
	setStatus("")
	loadingReady = true
	stopDotsAnim()
	-- Fade subtitle "ŁADOWANIE..." out
	TweenService:Create(subtitle,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad),
		{ TextTransparency = 1 }):Play()

	-- Fade-in tap label
	TweenService:Create(tapLbl,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad),
		{ TextTransparency = 0 }):Play()

	-- Włącz pulsowanie TAP TO CONTINUE
	startTapPulse()
end)

-- ── Tap handler ──────────────────────────────────────────────────────────

local dismissed = false

local function dismiss()
	if dismissed then return end
	if not loadingReady then return end  -- nie pozwól tapnać przed preloadem
	dismissed = true

	if pulseConn then pulseConn:Disconnect(); pulseConn = nil end

	-- Fade out wszystko
	local fadeTi = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	TweenService:Create(bg,       fadeTi, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title,    fadeTi, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subtitle, fadeTi, { TextTransparency = 1 }):Play()
	TweenService:Create(tapLbl,   fadeTi, { TextTransparency = 1 }):Play()

	-- Signal że loading skończony — IntroController może odpalić autoplay
	_G["__loadingDone"] = true
	if _G["__introTryAutoplay"] then
		_G["__introTryAutoplay"]()
	end

	-- Usuń GUI po fade
	task.delay(0.75, function() gui:Destroy() end)
end

bg.MouseButton1Click:Connect(dismiss)
UserInputService.InputBegan:Connect(function(input, processed)
	if dismissed or processed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard
		or input.UserInputType == Enum.UserInputType.Touch then
		dismiss()
	end
end)
