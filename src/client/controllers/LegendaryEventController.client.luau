-- LegendaryEventController.client.luau
-- Klient eventu "Deszcz Legendarek":
-- - złoty countdown u góry ekranu
-- - alert "DESZCZ LEGENDAREK!" przy starcie
-- - niebo lekko złote (ColorCorrectionEffect w Lighting)
-- - sfx (puste na razie, łatwo podpiąć)

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")

local Events                = ReplicatedStorage:WaitForChild("Events")
local LegendaryEventStart   = Events:WaitForChild("LegendaryEventStart")
local LegendaryEventEnd     = Events:WaitForChild("LegendaryEventEnd")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT_MAIN      = Enum.Font.GothamBlack
local GOLD           = Color3.fromRGB(255, 195, 70)
local GOLD_BRIGHT    = Color3.fromRGB(255, 230, 130)
local DARK_GOLD      = Color3.fromRGB(140, 90, 20)
local BG_DARK        = Color3.fromRGB(35, 28, 15)
local BORDER_DARK    = Color3.fromRGB(5, 25, 20)
local C_WHITE        = Color3.fromRGB(255, 255, 255)

-- ── GUI ───────────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "LegendaryEvent"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 150          -- pod loading (200), nad HUD
gui.Enabled        = true
gui.Parent         = playerGui

-- Pasek u góry z timerem (zawsze 0.5 X, AnchorPoint 0.5,0)
local timerHolder = Instance.new("Frame")
timerHolder.Name                   = "TimerHolder"
timerHolder.AnchorPoint            = Vector2.new(0.5, 0)
timerHolder.Position               = UDim2.new(0.5, 0, 0, -120)  -- start poza ekranem
timerHolder.Size                   = UDim2.fromOffset(320, 90)
timerHolder.BackgroundColor3       = BG_DARK
timerHolder.BackgroundTransparency = 0.1
timerHolder.BorderSizePixel        = 0
timerHolder.Visible                = false
timerHolder.Parent                 = gui

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(0, 12)
timerCorner.Parent       = timerHolder

local timerStroke = Instance.new("UIStroke")
timerStroke.Color     = GOLD
timerStroke.Thickness = 4
timerStroke.Parent    = timerHolder

local timerTitle = Instance.new("TextLabel")
timerTitle.BackgroundTransparency = 1
timerTitle.Size                   = UDim2.new(1, -16, 0, 30)
timerTitle.Position               = UDim2.fromOffset(8, 8)
timerTitle.Font                   = FONT_MAIN
timerTitle.Text                   = "DESZCZ LEGENDAREK"
timerTitle.TextColor3             = GOLD
timerTitle.TextStrokeColor3       = Color3.new(0, 0, 0)
timerTitle.TextStrokeTransparency = 0.4
timerTitle.TextSize               = 22
timerTitle.Parent                 = timerHolder

local timerNum = Instance.new("TextLabel")
timerNum.BackgroundTransparency = 1
timerNum.Size                   = UDim2.new(1, -16, 0, 44)
timerNum.Position               = UDim2.fromOffset(8, 38)
timerNum.Font                   = FONT_MAIN
timerNum.Text                   = "15"
timerNum.TextColor3             = GOLD_BRIGHT
timerNum.TextStrokeColor3       = DARK_GOLD
timerNum.TextStrokeTransparency = 0.2
timerNum.TextSize               = 44
timerNum.Parent                 = timerHolder

-- Alert na środku
local alert = Instance.new("TextLabel")
alert.Name                   = "Alert"
alert.AnchorPoint            = Vector2.new(0.5, 0.5)
alert.Position               = UDim2.new(0.5, 0, 0.7, 0)
alert.Size                   = UDim2.fromOffset(820, 120)
alert.BackgroundTransparency = 1
alert.Font                   = FONT_MAIN
alert.Text                   = "DESZCZ LEGENDAREK!"
alert.TextColor3             = GOLD_BRIGHT
alert.TextStrokeColor3       = DARK_GOLD
alert.TextStrokeTransparency = 0
alert.TextSize               = 80
alert.TextTransparency       = 1
alert.Visible                = false
alert.Parent                 = gui

-- ── Lighting efekty ──────────────────────────────────────────────────────

local function getOrCreateEffect(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild("__LegendaryEventCC")
	if existing and existing:IsA("ColorCorrectionEffect") then
		return existing :: ColorCorrectionEffect
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name        = "__LegendaryEventCC"
	cc.TintColor   = Color3.fromRGB(255, 255, 255)
	cc.Saturation  = 0
	cc.Brightness  = 0
	cc.Contrast    = 0
	cc.Enabled     = false
	cc.Parent      = Lighting
	return cc
end

local cc = getOrCreateEffect()

local function applyGoldenSky()
	cc.Enabled = true
	-- Tween do złotego tintu
	TweenService:Create(cc, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		TintColor  = Color3.fromRGB(255, 220, 160),
		Brightness = 0.05,
		Saturation = 0.15,
	}):Play()
end

local function clearGoldenSky()
	local t = TweenService:Create(cc, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		TintColor  = Color3.fromRGB(255, 255, 255),
		Brightness = 0,
		Saturation = 0,
	})
	t:Play()
	t.Completed:Connect(function()
		cc.Enabled = false
	end)
end

-- ── Animacje UI ──────────────────────────────────────────────────────────

local function slideTimerIn()
	timerHolder.Visible = true
	timerHolder.Position = UDim2.new(0.5, 0, 0, -120)
	TweenService:Create(timerHolder, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 110),
	}):Play()
end

local function slideTimerOut()
	local t = TweenService:Create(timerHolder, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, -120),
	})
	t:Play()
	t.Completed:Connect(function()
		timerHolder.Visible = false
	end)
end

local function showAlert()
	alert.Visible          = true
	alert.TextTransparency = 1
	alert.Size             = UDim2.fromOffset(820, 120)
	-- fade in + pop
	TweenService:Create(alert, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(900, 140),
	}):Play()
	TweenService:Create(alert, TweenInfo.new(0.35), {
		TextTransparency = 0,
	}):Play()

	task.delay(1.6, function()
		TweenService:Create(alert, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			TextTransparency = 1,
		}):Play()
		task.delay(0.5, function()
			alert.Visible = false
		end)
	end)
end

-- ── Stan eventu ──────────────────────────────────────────────────────────

local activeUntil: number? = nil
local renderConn: RBXScriptConnection? = nil

local function stopRender()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function startCountdown(duration: number)
	activeUntil = os.clock() + duration
	stopRender()
	renderConn = RunService.RenderStepped:Connect(function()
		if not activeUntil then return end
		local remaining = math.max(0, math.ceil(activeUntil - os.clock()))
		timerNum.Text = tostring(remaining)
		-- Pulsuj kolor cyfry w ostatnich 5s
		if remaining <= 5 then
			local t = os.clock() * 6
			local pulse = (math.sin(t) + 1) * 0.5
			timerNum.TextColor3 = Color3.fromRGB(
				255,
				math.floor(180 + 75 * pulse),
				math.floor(70  + 80 * pulse)
			)
		else
			timerNum.TextColor3 = GOLD_BRIGHT
		end
	end)
end

local function startEvent(duration: number)
	slideTimerIn()
	showAlert()
	applyGoldenSky()
	startCountdown(duration)
end

local function endEvent()
	activeUntil = nil
	stopRender()
	slideTimerOut()
	clearGoldenSky()
end

LegendaryEventStart.OnClientEvent:Connect(function(payload)
	local duration = (payload and payload.duration) or 15
	startEvent(duration)
end)

LegendaryEventEnd.OnClientEvent:Connect(function()
	endEvent()
end)
