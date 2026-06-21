-- AdminController.client.luau
-- Panel admina: F2 toggle (tylko jeśli serwer potwierdził isAdmin).
-- Broadcast tekstu, daj sobie zł/butelki. Wszyscy gracze widzą broadcast jako duży napis na ekranie.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local Config         = require(ReplicatedStorage:WaitForChild("Config"))
local Events         = ReplicatedStorage:WaitForChild("Events")
local AdminInit      = Events:WaitForChild("AdminInit")
local AdminAction    = Events:WaitForChild("AdminAction")
local AdminBroadcast = Events:WaitForChild("AdminBroadcast")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local isAdmin = false

-- ── Broadcast HUD (widoczny dla WSZYSTKICH graczy) ──────────────────────────
local bcGui = Instance.new("ScreenGui")
bcGui.Name           = "AdminBroadcastHUD"
bcGui.IgnoreGuiInset = true
bcGui.ResetOnSpawn   = false
bcGui.DisplayOrder   = 1000
bcGui.Parent         = playerGui

local bcLabel = Instance.new("TextLabel")
bcLabel.Size                   = UDim2.new(0.9, 0, 0, 120)
bcLabel.AnchorPoint            = Vector2.new(0.5, 0)
bcLabel.Position               = UDim2.new(0.5, 0, 0, 80)
bcLabel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
bcLabel.BackgroundTransparency = 0.15            -- ciemniejsze tło dla kontrastu
bcLabel.BorderSizePixel        = 0
bcLabel.Text                   = ""
bcLabel.TextSize               = 36
bcLabel.Font                   = Enum.Font.GothamBold
bcLabel.TextColor3             = Color3.fromRGB(255, 255, 255)  -- BIAŁY zamiast gold — wyraźny kontrast z czarnym tłem
bcLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
bcLabel.TextStrokeTransparency = 0               -- czarny kontur wokół liter zawsze widoczny
bcLabel.TextWrapped            = true
bcLabel.Visible                = false
bcLabel.Parent                 = bcGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = bcLabel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 220, 100); s.Thickness = 3; s.Parent = bcLabel
end

local bcTask: thread? = nil
AdminBroadcast.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local msg = tostring(payload.message or "")
	if #msg == 0 then return end
	if bcTask then task.cancel(bcTask); bcTask = nil end

	bcLabel.Text = msg
	bcLabel.Visible = true
	bcLabel.TextTransparency = 1
	bcLabel.BackgroundTransparency = 1
	TweenService:Create(bcLabel, TweenInfo.new(0.3), {
		TextTransparency = 0,
		BackgroundTransparency = 0.3,
	}):Play()

	bcTask = task.delay(5, function()
		local tw = TweenService:Create(bcLabel, TweenInfo.new(0.6), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tw:Play()
		tw.Completed:Wait()
		bcLabel.Visible = false
	end)
end)

-- ── Panel admina (tylko dla adminów, F2 toggle) ─────────────────────────────
local PANEL_W = 460
local PANEL_H = 510  -- powiększony żeby pomieścić sekcję DODAJ KOD + MAGNES

local gui = Instance.new("ScreenGui")
gui.Name           = "AdminPanel"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 999
gui.Enabled        = false
gui.Parent         = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 91, 73)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(5, 25, 20); s.Thickness = 4; s.Parent = panel
end

local function mkLabel(parent, size, pos, text, ts, color, xAlign)
	local l = Instance.new("TextLabel")
	l.Size = size; l.Position = pos; l.BackgroundTransparency = 1
	l.Text = text; l.TextSize = ts; l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.Parent = parent; return l
end

local function mkBtn(parent, size, pos, text, bg)
	local b = Instance.new("TextButton")
	b.Size = size; b.Position = pos
	b.BackgroundColor3 = bg or Color3.fromRGB(170, 221, 102)
	b.BorderSizePixel = 0
	b.Text = text; b.TextSize = 16; b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.fromRGB(0, 0, 0); b.AutoButtonColor = false
	b.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
	-- UIStroke usunięty — obramówka zlewała się z czarnym tekstem
	return b
end

local function mkInput(parent, size, pos, placeholder)
	local t = Instance.new("TextBox")
	t.Size = size; t.Position = pos
	t.BackgroundColor3 = Color3.fromRGB(8, 60, 48); t.BorderSizePixel = 0
	t.Text = ""; t.PlaceholderText = placeholder
	t.PlaceholderColor3 = Color3.fromRGB(175, 175, 175)
	t.TextSize = 16; t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(255, 255, 255); t.ClearTextOnFocus = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = t
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(5, 25, 20); s.Thickness = 2; s.Parent = t
	return t
end

-- Header
local header = mkLabel(panel, UDim2.new(1, -16, 0, 36), UDim2.fromOffset(16, 12),
	"PANEL ADMINA — F2 zamyka", 20, Color3.fromRGB(255, 220, 100), Enum.TextXAlignment.Left)

-- Broadcast section
mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 56), "BROADCAST", 14, Color3.fromRGB(175, 175, 175))
local bcInput = mkInput(panel, UDim2.new(1, -130, 0, 36), UDim2.fromOffset(16, 80), "Wpisz wiadomość…")
local bcBtn = mkBtn(panel, UDim2.fromOffset(96, 36), UDim2.new(1, -112, 0, 80), "WYŚLIJ")

-- Give zł section
mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 130), "DAJ SOBIE ZŁOTÓWKI", 14, Color3.fromRGB(175, 175, 175))
local zlInput = mkInput(panel, UDim2.new(1, -130, 0, 36), UDim2.fromOffset(16, 154), "Ilość (np. 10000)")
local zlBtn = mkBtn(panel, UDim2.fromOffset(96, 36), UDim2.new(1, -112, 0, 154), "DODAJ", Color3.fromRGB(88, 166, 255))

-- Give butelki section
mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 204), "DAJ SOBIE BUTELKI", 14, Color3.fromRGB(175, 175, 175))
local bottleInput = mkInput(panel, UDim2.fromOffset(140, 36), UDim2.fromOffset(16, 228), "Rzadkość")
bottleInput.Text = "Mityczny"
local countInput = mkInput(panel, UDim2.fromOffset(90, 36), UDim2.fromOffset(160, 228), "Ile")
countInput.Text = "10"
local bottleBtn = mkBtn(panel, UDim2.fromOffset(96, 36), UDim2.new(1, -112, 0, 228), "DODAJ", Color3.fromRGB(88, 166, 255))

-- Dodaj kod promocyjny section
mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 278), "DODAJ KOD PROMOCYJNY", 14, Color3.fromRGB(175, 175, 175))
local codeInput = mkInput(panel, UDim2.fromOffset(140, 36), UDim2.fromOffset(16, 302), "KOD (np. NOWY2026)")
local rewardInput = mkInput(panel, UDim2.fromOffset(90, 36), UDim2.fromOffset(160, 302), "Nagroda zł")
rewardInput.Text = "500"
local codeBtn = mkBtn(panel, UDim2.fromOffset(96, 36), UDim2.new(1, -112, 0, 302), "DODAJ", Color3.fromRGB(255, 220, 100))
local codeStatus = mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 342),
	"", 12, Color3.fromRGB(170, 221, 102))

-- Give magnes section
mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 372), "DAJ SOBIE MAGNESY", 14, Color3.fromRGB(175, 175, 175))
local magnetInput = mkInput(panel, UDim2.fromOffset(140, 36), UDim2.fromOffset(16, 396), "Ile sztuk")
magnetInput.Text = "1"
local magnetBtn = mkBtn(panel, UDim2.fromOffset(96, 36), UDim2.new(1, -112, 0, 396), "DODAJ", Color3.fromRGB(220, 90, 90))

magnetBtn.MouseButton1Click:Connect(function()
	local n = tonumber(magnetInput.Text) or 0
	if n <= 0 then return end
	AdminAction:FireServer({ action = "giveMagnet", count = n })
end)

-- Hint
mkLabel(panel, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, PANEL_H - 30),
	"Skróty: F2 = otwórz/zamknij. Kody żyją do restartu serwera.", 12, Color3.fromRGB(175, 175, 175))

-- Actions
bcBtn.MouseButton1Click:Connect(function()
	local msg = bcInput.Text
	if #msg == 0 then return end
	AdminAction:FireServer({ action = "broadcast", message = msg })
	bcInput.Text = ""
end)
zlBtn.MouseButton1Click:Connect(function()
	local n = tonumber(zlInput.Text) or 0
	if n <= 0 then return end
	AdminAction:FireServer({ action = "giveZl", amount = n })
	zlInput.Text = ""
end)
codeBtn.MouseButton1Click:Connect(function()
	local code = string.upper(codeInput.Text)
	local reward = tonumber(rewardInput.Text) or 0
	if #code == 0 or reward <= 0 then return end
	AdminAction:FireServer({ action = "addCode", code = code, reward = reward })
	codeStatus.Text = string.format("Dodano: %s = %d zł", code, reward)
	codeStatus.TextColor3 = Color3.fromRGB(170, 221, 102)
	codeInput.Text = ""
end)

bottleBtn.MouseButton1Click:Connect(function()
	local r = bottleInput.Text
	local n = tonumber(countInput.Text) or 0
	if #r == 0 or n <= 0 then return end
	AdminAction:FireServer({ action = "giveBottles", rarity = r, count = n })
end)

-- F2 toggle
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F2 and isAdmin then
		gui.Enabled = not gui.Enabled
	end
end)

-- Receive admin status
AdminInit.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.isAdmin then
		isAdmin = true
		print("[AdminController] Jesteś adminem! F2 = panel.")
	end
end)
