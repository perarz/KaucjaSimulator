-- MagnetController.client.luau
-- HUD countdown timer + most do CollectController (eksporty _G).
-- Aktualny stan magnesu i count trzymamy w `magnetState` — CollectController
-- czyta to przez _G["__magnetState"] żeby rysować slot + detail panel.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local cfg    = Config.Magnet

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local Events             = ReplicatedStorage:WaitForChild("Events")
local UseMagnet          = Events:WaitForChild("UseMagnet")
local MagnetStatusUpdate = Events:WaitForChild("MagnetStatusUpdate")

local FONT       = Enum.Font.GothamBlack
local C_BG       = Color3.fromRGB(18, 91, 73)
local C_HEADER   = Color3.fromRGB(0, 53, 39)
local C_BORDER   = Color3.fromRGB(5, 25, 20)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_MAGNET   = cfg.Color or Color3.fromRGB(220, 90, 90)

-- ── Stan ──────────────────────────────────────────────────────────────────
local magnetState = {
	count       = 0,
	secondsLeft = 0,
	active      = false,
	endsAt      = 0,  -- os.clock() — używane do gładkiego countdown'a
}
_G["__magnetState"] = magnetState

-- Listeners które CollectController rejestruje żeby odświeżyć slot/detail
local listeners: { () -> () } = {}
_G["__magnetAddListener"] = function(fn: () -> ())
	table.insert(listeners, fn)
end

local function fireListeners()
	for _, fn in ipairs(listeners) do
		pcall(fn)
	end
end

-- Public — używane przez CollectController (przycisk UŻYJ w detail panelu)
_G["__magnetTryUse"] = function()
	if magnetState.active then return false, "active" end
	if magnetState.count <= 0 then return false, "empty" end
	UseMagnet:FireServer()
	return true, nil
end

-- ── HUD timer ─────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "MagnetHUD"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 60
gui.Parent         = playerGui

-- Pozycja: prawy górny róg (pod ewentualnym boost badgem — z marginesem)
local box = Instance.new("Frame")
box.Name             = "MagnetTimer"
box.AnchorPoint      = Vector2.new(1, 0)
box.Position         = UDim2.new(1, -16, 0, 200)  -- pod BoostShop badgem (Y=110, ~72 wys)
box.Size             = UDim2.fromOffset(220, 72)
box.BackgroundColor3 = C_BG
box.BackgroundTransparency = 0.05
box.BorderSizePixel  = 0
box.Visible          = false
box.Parent           = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent       = box

local stroke = Instance.new("UIStroke")
stroke.Color     = C_MAGNET
stroke.Thickness = 3
stroke.Parent    = box

-- Ikona / etykieta "MAGNES"
local titleLbl = Instance.new("TextLabel")
titleLbl.Size                   = UDim2.new(1, -16, 0, 24)
titleLbl.Position               = UDim2.fromOffset(8, 6)
titleLbl.BackgroundTransparency = 1
titleLbl.Text                   = "🧲 MAGNES"
titleLbl.Font                   = FONT
titleLbl.TextSize               = 18
titleLbl.TextColor3             = C_MAGNET
titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
titleLbl.Parent                 = box

-- Countdown "M:SS"
local timeLbl = Instance.new("TextLabel")
timeLbl.Size                   = UDim2.new(1, -16, 0, 30)
timeLbl.Position               = UDim2.fromOffset(8, 32)
timeLbl.BackgroundTransparency = 1
timeLbl.Text                   = "2:00"
timeLbl.Font                   = FONT
timeLbl.TextSize               = 26
timeLbl.TextColor3             = C_WHITE
timeLbl.TextXAlignment         = Enum.TextXAlignment.Right
timeLbl.Parent                 = box

-- Progress bar pod całym boxem (cienki pasek na dole)
local barBg = Instance.new("Frame")
barBg.Size               = UDim2.new(1, -16, 0, 4)
barBg.Position           = UDim2.new(0, 8, 1, -8)
barBg.BackgroundColor3   = C_HEADER
barBg.BorderSizePixel    = 0
barBg.Parent             = box
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = barBg
end

local barFill = Instance.new("Frame")
barFill.Size               = UDim2.fromScale(1, 1)
barFill.BackgroundColor3   = C_MAGNET
barFill.BorderSizePixel    = 0
barFill.Parent             = barBg
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = barFill
end

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

-- ── Update countdown HUD (Heartbeat) ──────────────────────────────────────
RunService.Heartbeat:Connect(function()
	if not magnetState.active then return end
	local remaining = math.max(0, magnetState.endsAt - os.clock())
	magnetState.secondsLeft = remaining
	timeLbl.Text = fmtTime(remaining)
	local ratio = math.clamp(remaining / cfg.DurationSec, 0, 1)
	barFill.Size = UDim2.fromScale(ratio, 1)

	if remaining <= 0 then
		magnetState.active = false
		box.Visible = false
		fireListeners()
	end
end)

-- ── Server status ─────────────────────────────────────────────────────────
MagnetStatusUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local prevActive = magnetState.active
	magnetState.count       = tonumber(payload.count) or 0
	magnetState.secondsLeft = tonumber(payload.secondsLeft) or 0
	magnetState.active      = payload.active == true and magnetState.secondsLeft > 0
	magnetState.endsAt      = os.clock() + magnetState.secondsLeft

	if magnetState.active then
		box.Visible = true
		timeLbl.Text = fmtTime(magnetState.secondsLeft)
		local ratio = math.clamp(magnetState.secondsLeft / cfg.DurationSec, 0, 1)
		barFill.Size = UDim2.fromScale(ratio, 1)
		if not prevActive then
			-- Animacja pop przy aktywacji
			box.Size = UDim2.fromOffset(0, 72)
			TweenService:Create(box, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(220, 72) }):Play()
		end
	else
		box.Visible = false
	end

	fireListeners()
end)
