-- SettingsController.luau
-- Panel ustawień z opcją odtworzenia tutorialu od nowa.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")

local ResetProgress     = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ResetProgress")
local RedeemCode        = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RedeemCode")
local RedeemCodeResult  = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RedeemCodeResult")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── SFX group (współdzielona z innymi kontrolerami) ──────────────────────
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

-- ── Paleta ────────────────────────────────────────────────────────────────

local FONT      = Enum.Font.GothamBlack
local C_BG      = Color3.fromRGB(18, 91, 73)
local C_PANEL   = Color3.fromRGB(24, 110, 90)
local C_HEADER  = Color3.fromRGB(0, 53, 39)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_WHITE   = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT = Color3.fromRGB(175, 175, 175)
local C_ACCENT  = Color3.fromRGB(88, 166, 255)
local X_RED        = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER  = Color3.fromRGB(255, 110, 110)

-- ── ScreenGui ─────────────────────────────────────────────────────────────

local PANEL_W  = 480
local PANEL_H  = 600
-- HEADER_H = 0 — panel mieszka w zakładce MenuController, własny header schowany.
-- Wszystkie pozycje children w tym pliku liczą się od HEADER_H + PAD,
-- więc samo wyzerowanie tego stałej shifuje content do góry.
local HEADER_H = 0
local PAD      = 22

local gui = Instance.new("ScreenGui")
gui.Name           = "Settings"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = gui

local panel = Instance.new("Frame")
panel.Size                  = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint           = Vector2.new(0.5, 0.5)
panel.Position              = UDim2.new(0.5, 0, 0.55, 0)
-- Bez własnej ramki/tła — content siedzi w zakładce MenuController który
-- zapewnia ramę. Jeśli kiedyś będzie używany solo, można zmienić tu transparency.
panel.BackgroundTransparency = 1
panel.BorderSizePixel       = 0
panel.ClipsDescendants      = false
panel.ZIndex                = 2
panel.Parent                = gui

-- Header (wzór CLAUDE.md) — niewidoczny w nowym UI (zakładka menu ma swój pasek)
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Visible          = false
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(1, 0, 0, 10)
	fill.Position         = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3 = C_HEADER
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 3
	fill.Parent           = header
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, 0, 0, 2)
	sep.Position         = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER
	sep.BorderSizePixel  = 0
	sep.ZIndex           = 5
	sep.Parent           = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -70, 1, 0)
title.Position               = UDim2.fromOffset(22, 0)
title.BackgroundTransparency = 1
title.Text                   = "USTAWIENIA"
title.TextSize               = 16
title.Font                   = FONT
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

-- Close X
local closeBtn = Instance.new("TextButton")
closeBtn.Size                   = UDim2.fromOffset(36, 36)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "X"
closeBtn.TextSize               = 24
closeBtn.Font                   = FONT
closeBtn.TextColor3             = X_RED
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 5
closeBtn.Parent                 = header
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
		closeBtn.TextColor3 = X_RED_HOVER
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		closeBtn.TextColor3 = X_RED
	end)
end

-- ── Sekcja Tutorial ─────────────────────────────────────────────────────

local sectionLbl = Instance.new("TextLabel")
sectionLbl.Size                   = UDim2.new(1, -PAD * 2, 0, 24)
sectionLbl.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD)
sectionLbl.BackgroundTransparency = 1
sectionLbl.Text                   = "TUTORIAL"
sectionLbl.TextSize               = 14
sectionLbl.Font                   = FONT
sectionLbl.TextColor3             = C_DIMTEXT
sectionLbl.TextXAlignment         = Enum.TextXAlignment.Left
sectionLbl.ZIndex                 = 3
sectionLbl.Parent                 = panel

local desc = Instance.new("TextLabel")
desc.Size                   = UDim2.new(1, -PAD * 2, 0, 36)
desc.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD + 28)
desc.BackgroundTransparency = 1
desc.Text                   = "Odtwórz cutscenę intro od nowa — pokazuje jak zbierać, oddawać i ulepszać."
desc.TextSize               = 13
desc.Font                   = FONT
desc.TextColor3             = C_DIMTEXT
desc.TextXAlignment         = Enum.TextXAlignment.Left
desc.TextWrapped            = true
desc.ZIndex                 = 3
desc.Parent                 = panel

local replayBtn = Instance.new("TextButton")
replayBtn.Size                 = UDim2.new(1, -PAD * 2, 0, 56)
replayBtn.Position             = UDim2.fromOffset(PAD, HEADER_H + PAD + 80)
replayBtn.BackgroundColor3     = C_ACCENT
replayBtn.BackgroundTransparency = 0
replayBtn.BorderSizePixel      = 0
replayBtn.Text                 = "ZOBACZ INTRO PONOWNIE"
replayBtn.TextSize             = 18
replayBtn.Font                 = FONT
replayBtn.TextColor3           = C_WHITE
replayBtn.AutoButtonColor      = false
replayBtn.ZIndex               = 3
replayBtn.Parent               = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = replayBtn
	local s = Instance.new("UIStroke")
	s.Color = C_BORDER; s.Thickness = 3; s.Parent = replayBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = replayBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	replayBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	replayBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

-- ── Sekcja Dźwięk ───────────────────────────────────────────────────────

local SFX_Y      = HEADER_H + PAD + 80 + 56 + PAD + 8   -- pod replayBtn
local SLIDER_W   = PANEL_W - PAD * 2
local TRACK_H    = 10
local KNOB_SIZE  = 26

local sfxLbl = Instance.new("TextLabel")
sfxLbl.Size                   = UDim2.new(1, -PAD * 2, 0, 24)
sfxLbl.Position               = UDim2.fromOffset(PAD, SFX_Y)
sfxLbl.BackgroundTransparency = 1
sfxLbl.Text                   = "DŹWIĘK"
sfxLbl.TextSize               = 14
sfxLbl.Font                   = FONT
sfxLbl.TextColor3             = C_DIMTEXT
sfxLbl.TextXAlignment         = Enum.TextXAlignment.Left
sfxLbl.ZIndex                 = 3
sfxLbl.Parent                 = panel

local sfxRow = Instance.new("TextLabel")
sfxRow.Size                   = UDim2.new(1, -PAD * 2, 0, 24)
sfxRow.Position               = UDim2.fromOffset(PAD, SFX_Y + 26)
sfxRow.BackgroundTransparency = 1
sfxRow.Text                   = "Głośność SFX"
sfxRow.TextSize               = 16
sfxRow.Font                   = FONT
sfxRow.TextColor3             = C_WHITE
sfxRow.TextXAlignment         = Enum.TextXAlignment.Left
sfxRow.ZIndex                 = 3
sfxRow.Parent                 = panel

local valueLbl = Instance.new("TextLabel")
valueLbl.Size                   = UDim2.new(0, 70, 0, 24)
valueLbl.AnchorPoint            = Vector2.new(1, 0)
valueLbl.Position               = UDim2.new(1, -PAD, 0, SFX_Y + 26)
valueLbl.BackgroundTransparency = 1
valueLbl.Text                   = "100%"
valueLbl.TextSize               = 16
valueLbl.Font                   = FONT
valueLbl.TextColor3             = Color3.fromRGB(170, 221, 102)
valueLbl.TextXAlignment         = Enum.TextXAlignment.Right
valueLbl.ZIndex                 = 3
valueLbl.Parent                 = panel

-- Track (klikalny obszar 40px wysoki — łatwo trafić palcem)
local trackHit = Instance.new("TextButton")
trackHit.Size                   = UDim2.new(1, -PAD * 2, 0, 40)
trackHit.Position               = UDim2.fromOffset(PAD, SFX_Y + 60)
trackHit.BackgroundTransparency = 1
trackHit.Text                   = ""
trackHit.AutoButtonColor        = false
trackHit.ZIndex                 = 3
trackHit.Parent                 = panel

local track = Instance.new("Frame")
track.Size                   = UDim2.new(1, 0, 0, TRACK_H)
track.AnchorPoint            = Vector2.new(0, 0.5)
track.Position               = UDim2.new(0, 0, 0.5, 0)
track.BackgroundColor3       = C_HEADER
track.BackgroundTransparency = 0
track.BorderSizePixel        = 0
track.ZIndex                 = 3
track.Parent                 = trackHit
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = track
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = track
end

local fill = Instance.new("Frame")
fill.Size                   = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3       = Color3.fromRGB(170, 221, 102)
fill.BorderSizePixel        = 0
fill.ZIndex                 = 4
fill.Parent                 = track
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = fill
end

local knob = Instance.new("Frame")
knob.Size                   = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
knob.AnchorPoint            = Vector2.new(0.5, 0.5)
knob.Position               = UDim2.new(1, 0, 0.5, 0)
knob.BackgroundColor3       = C_WHITE
knob.BorderSizePixel        = 0
knob.ZIndex                 = 5
knob.Parent                 = track
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = knob
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = knob
end

local function setVolume(v: number)
	if v < 0 then v = 0 elseif v > 1 then v = 1 end
	SFX_GROUP.Volume = v
	fill.Size      = UDim2.new(v, 0, 1, 0)
	knob.Position  = UDim2.new(v, 0, 0.5, 0)
	valueLbl.Text  = tostring(math.floor(v * 100 + 0.5)) .. "%"
end

setVolume(SFX_GROUP.Volume)

local dragging = false
local function updateFromX(absX: number)
	local rel = (absX - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
	setVolume(rel)
end

trackHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		updateFromX(input.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		updateFromX(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

-- ── Sekcja Kody promocyjne ──────────────────────────────────────────────

local CODES_Y      = SFX_Y + 60 + 40 + PAD
local C_OK_GREEN   = Color3.fromRGB(170, 221, 102)
local C_ERR_RED    = Color3.fromRGB(255, 90, 90)
local C_INPUT_BG   = Color3.fromRGB(8, 60, 48)

local codesLbl = Instance.new("TextLabel")
codesLbl.Size                   = UDim2.new(1, -PAD * 2, 0, 24)
codesLbl.Position               = UDim2.fromOffset(PAD, CODES_Y)
codesLbl.BackgroundTransparency = 1
codesLbl.Text                   = "KODY"
codesLbl.TextSize               = 14
codesLbl.Font                   = FONT
codesLbl.TextColor3             = C_DIMTEXT
codesLbl.TextXAlignment         = Enum.TextXAlignment.Left
codesLbl.ZIndex                 = 3
codesLbl.Parent                 = panel

local CODE_INPUT_H = 48
local CODE_BTN_W   = 140

local codeBox = Instance.new("TextBox")
codeBox.Size                   = UDim2.new(1, -PAD * 2 - CODE_BTN_W - 10, 0, CODE_INPUT_H)
codeBox.Position               = UDim2.fromOffset(PAD, CODES_Y + 28)
codeBox.BackgroundColor3       = C_INPUT_BG
codeBox.BackgroundTransparency = 0
codeBox.BorderSizePixel        = 0
codeBox.Text                   = ""
codeBox.PlaceholderText        = "Wpisz kod…"
codeBox.PlaceholderColor3      = C_DIMTEXT
codeBox.TextSize               = 18
codeBox.Font                   = FONT
codeBox.TextColor3             = C_WHITE
codeBox.ClearTextOnFocus       = false
codeBox.TextXAlignment         = Enum.TextXAlignment.Center
codeBox.ZIndex                 = 3
codeBox.Parent                 = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = codeBox
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = codeBox
end

local codeBtn = Instance.new("TextButton")
codeBtn.Size                   = UDim2.fromOffset(CODE_BTN_W, CODE_INPUT_H)
codeBtn.AnchorPoint            = Vector2.new(1, 0)
codeBtn.Position               = UDim2.new(1, -PAD, 0, CODES_Y + 28)
codeBtn.BackgroundColor3       = C_OK_GREEN
codeBtn.BorderSizePixel        = 0
codeBtn.Text                   = "AKTYWUJ"
codeBtn.TextSize               = 18
codeBtn.Font                   = FONT
codeBtn.TextColor3             = Color3.fromRGB(0, 0, 0)
codeBtn.AutoButtonColor        = false
codeBtn.ZIndex                 = 3
codeBtn.Parent                 = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = codeBtn
	-- UIStroke usunięty — czarny tekst na zielonym tle wystarczy do czytelności, obramówka się zlewała z tekstem
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = codeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	codeBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
	codeBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
end

local codeStatus = Instance.new("TextLabel")
codeStatus.Size                   = UDim2.new(1, -PAD * 2, 0, 20)
codeStatus.Position               = UDim2.fromOffset(PAD, CODES_Y + 28 + CODE_INPUT_H + 6)
codeStatus.BackgroundTransparency = 1
codeStatus.Text                   = ""
codeStatus.TextSize               = 14
codeStatus.Font                   = FONT
codeStatus.TextColor3             = C_DIMTEXT
codeStatus.TextXAlignment         = Enum.TextXAlignment.Left
codeStatus.ZIndex                 = 3
codeStatus.Parent                 = panel

local function showStatus(text: string, color: Color3)
	codeStatus.Text       = text
	codeStatus.TextColor3 = color
end

local function trySubmitCode()
	local raw = codeBox.Text
	if not raw or #raw == 0 then return end
	codeBtn.Active = false
	codeBtn.Text   = "..."
	showStatus("Sprawdzam…", C_DIMTEXT)
	RedeemCode:FireServer(raw)
end

codeBtn.MouseButton1Click:Connect(trySubmitCode)
codeBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then trySubmitCode() end
end)

RedeemCodeResult.OnClientEvent:Connect(function(result)
	codeBtn.Active = true
	codeBtn.Text   = "AKTYWUJ"
	if type(result) ~= "table" then return end
	if result.success then
		showStatus(string.format("+%d PLN za kod %s ✓", result.reward or 0, result.code or ""), C_OK_GREEN)
		codeBox.Text = ""
	else
		local msg = "Nieprawidłowy kod."
		if result.reason == "alreadyUsed" then msg = "Kod już wykorzystany."
		elseif result.reason == "unknown" then msg = "Nieznany kod."
		elseif result.reason == "throttle" then msg = "Spróbuj za chwilę…"
		elseif result.reason == "invalid"  then msg = "Nieprawidłowy kod."
		end
		showStatus(msg, C_ERR_RED)
	end
end)

-- ── Sekcja Reset progresu ───────────────────────────────────────────────

local C_DANGER       = Color3.fromRGB(180, 60, 60)
local C_DANGER_HOVER = Color3.fromRGB(220, 80, 80)
local RESET_Y        = CODES_Y + 28 + CODE_INPUT_H + 6 + 20 + PAD

local resetLbl = Instance.new("TextLabel")
resetLbl.Size                   = UDim2.new(1, -PAD * 2, 0, 24)
resetLbl.Position               = UDim2.fromOffset(PAD, RESET_Y)
resetLbl.BackgroundTransparency = 1
resetLbl.Text                   = "POSTĘP"
resetLbl.TextSize               = 14
resetLbl.Font                   = FONT
resetLbl.TextColor3             = C_DIMTEXT
resetLbl.TextXAlignment         = Enum.TextXAlignment.Left
resetLbl.ZIndex                 = 3
resetLbl.Parent                 = panel

local resetBtn = Instance.new("TextButton")
resetBtn.Size                   = UDim2.new(1, -PAD * 2, 0, 48)
resetBtn.Position               = UDim2.fromOffset(PAD, RESET_Y + 28)
resetBtn.BackgroundColor3       = C_DANGER
resetBtn.BorderSizePixel        = 0
resetBtn.Text                   = "RESETUJ POSTĘP"
resetBtn.TextSize               = 18
resetBtn.Font                   = FONT
resetBtn.TextColor3             = C_WHITE
resetBtn.AutoButtonColor        = false
resetBtn.ZIndex                 = 3
resetBtn.Parent                 = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = resetBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = resetBtn
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = resetBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	resetBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.04 }):Play()
		resetBtn.BackgroundColor3 = C_DANGER_HOVER
	end)
	resetBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		resetBtn.BackgroundColor3 = C_DANGER
	end)
end

-- ── Confirm dialog ──────────────────────────────────────────────────────

local confirmGui = Instance.new("ScreenGui")
confirmGui.Name           = "SettingsConfirmReset"
confirmGui.ResetOnSpawn   = false
confirmGui.IgnoreGuiInset = true
confirmGui.DisplayOrder   = 250
confirmGui.Enabled        = false
confirmGui.Parent         = playerGui

local confirmDim = Instance.new("TextButton")
confirmDim.Size                   = UDim2.fromScale(1, 1)
confirmDim.BackgroundColor3       = Color3.new(0, 0, 0)
confirmDim.BackgroundTransparency = 0.4
confirmDim.BorderSizePixel        = 0
confirmDim.Text                   = ""
confirmDim.AutoButtonColor        = false
confirmDim.ZIndex                 = 1
confirmDim.Parent                 = confirmGui

local confirmPanel = Instance.new("Frame")
confirmPanel.Size                  = UDim2.fromOffset(440, 220)
confirmPanel.AnchorPoint           = Vector2.new(0.5, 0.5)
confirmPanel.Position              = UDim2.new(0.5, 0, 0.5, 0)
confirmPanel.BackgroundColor3      = C_PANEL
confirmPanel.BackgroundTransparency = 0.05
confirmPanel.BorderSizePixel       = 0
confirmPanel.ZIndex                = 2
confirmPanel.Parent                = confirmGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = confirmPanel
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 4; s.Parent = confirmPanel
end

local confirmTitle = Instance.new("TextLabel")
confirmTitle.Size                   = UDim2.new(1, -32, 0, 32)
confirmTitle.Position               = UDim2.fromOffset(16, 18)
confirmTitle.BackgroundTransparency = 1
confirmTitle.Text                   = "NA PEWNO RESETOWAĆ?"
confirmTitle.TextSize               = 22
confirmTitle.Font                   = FONT
confirmTitle.TextColor3             = C_DANGER_HOVER
confirmTitle.ZIndex                 = 3
confirmTitle.Parent                 = confirmPanel

local confirmDesc = Instance.new("TextLabel")
confirmDesc.Size                   = UDim2.new(1, -32, 0, 64)
confirmDesc.Position               = UDim2.fromOffset(16, 58)
confirmDesc.BackgroundTransparency = 1
confirmDesc.Text                   = "Stracisz złotówki, plecak, ulepszenia i questy. Tej operacji nie da się cofnąć."
confirmDesc.TextSize               = 14
confirmDesc.Font                   = FONT
confirmDesc.TextColor3             = C_WHITE
confirmDesc.TextWrapped            = true
confirmDesc.ZIndex                 = 3
confirmDesc.Parent                 = confirmPanel

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size                   = UDim2.new(0.5, -24, 0, 48)
cancelBtn.Position               = UDim2.new(0, 16, 1, -64)
cancelBtn.BackgroundColor3       = C_HEADER
cancelBtn.BorderSizePixel        = 0
cancelBtn.Text                   = "ANULUJ"
cancelBtn.TextSize               = 18
cancelBtn.Font                   = FONT
cancelBtn.TextColor3             = C_WHITE
cancelBtn.AutoButtonColor        = false
cancelBtn.ZIndex                 = 3
cancelBtn.Parent                 = confirmPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = cancelBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = cancelBtn
end

local confirmBtn = Instance.new("TextButton")
confirmBtn.Size                   = UDim2.new(0.5, -24, 0, 48)
confirmBtn.Position               = UDim2.new(0.5, 8, 1, -64)
confirmBtn.BackgroundColor3       = C_DANGER
confirmBtn.BorderSizePixel        = 0
confirmBtn.Text                   = "RESETUJ"
confirmBtn.TextSize               = 18
confirmBtn.Font                   = FONT
confirmBtn.TextColor3             = C_WHITE
confirmBtn.AutoButtonColor        = false
confirmBtn.ZIndex                 = 3
confirmBtn.Parent                 = confirmPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = confirmBtn
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = confirmBtn
end

local function showConfirm(show: boolean)
	confirmGui.Enabled = show
end

cancelBtn.MouseButton1Click:Connect(function() showConfirm(false) end)
confirmDim.MouseButton1Click:Connect(function() showConfirm(false) end)
-- Ekran "trwa resetowanie" — blokuje wszystko, daje jasny komunikat aż serwer teleportuje/kickuje
local resettingGui = Instance.new("ScreenGui")
resettingGui.Name           = "SettingsResetting"
resettingGui.ResetOnSpawn   = false
resettingGui.IgnoreGuiInset = true
resettingGui.DisplayOrder   = 500
resettingGui.Enabled        = false
resettingGui.Parent         = playerGui

local resettingBg = Instance.new("Frame")
resettingBg.Size                  = UDim2.fromScale(1, 1)
resettingBg.BackgroundColor3      = Color3.new(0, 0, 0)
resettingBg.BackgroundTransparency = 0.05
resettingBg.BorderSizePixel       = 0
resettingBg.ZIndex                = 1
resettingBg.Parent                = resettingGui

local resettingTitle = Instance.new("TextLabel")
resettingTitle.Size                   = UDim2.new(1, -80, 0, 60)
resettingTitle.AnchorPoint            = Vector2.new(0.5, 1)
resettingTitle.Position               = UDim2.new(0.5, 0, 0.5, -12)
resettingTitle.BackgroundTransparency = 1
resettingTitle.Text                   = "RESETOWANIE POSTĘPU…"
resettingTitle.TextSize               = 36
resettingTitle.Font                   = FONT
resettingTitle.TextColor3             = Color3.fromRGB(220, 80, 80)
resettingTitle.TextStrokeColor3       = Color3.new(0, 0, 0)
resettingTitle.TextStrokeTransparency = 0.3
resettingTitle.ZIndex                 = 2
resettingTitle.Parent                 = resettingGui

local resettingSub = Instance.new("TextLabel")
resettingSub.Size                   = UDim2.new(1, -80, 0, 80)
resettingSub.AnchorPoint            = Vector2.new(0.5, 0)
resettingSub.Position               = UDim2.new(0.5, 0, 0.5, 12)
resettingSub.BackgroundTransparency = 1
resettingSub.Text                   = "Za chwilę gra uruchomi się ponownie.\nNie zamykaj okna."
resettingSub.TextSize               = 20
resettingSub.Font                   = FONT
resettingSub.TextColor3             = C_WHITE
resettingSub.TextWrapped            = true
resettingSub.ZIndex                 = 2
resettingSub.Parent                 = resettingGui

confirmBtn.MouseButton1Click:Connect(function()
	confirmBtn.Active = false
	confirmGui.Enabled = false
	resettingGui.Enabled = true
	ResetProgress:FireServer()
end)

resetBtn.MouseButton1Click:Connect(function()
	showConfirm(true)
end)

-- ── Toggle ──────────────────────────────────────────────────────────────

local isOpen = false
local POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local TI_OPEN  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function setOpen(open: boolean)
	isOpen = open
	if open then
		gui.Enabled                    = true
		panel.Position                 = POS_HIDE
		overlay.BackgroundTransparency = 1
		TweenService:Create(panel,   TI_OPEN, { Position = POS_SHOW }):Play()
		TweenService:Create(overlay, TI_OPEN, { BackgroundTransparency = 0.30 }):Play()
	else
		TweenService:Create(panel, TI_CLOSE, { Position = POS_HIDE }):Play()
		local tw = TweenService:Create(overlay, TI_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not isOpen then gui.Enabled = false end
		end)
		tw:Play()
	end
end

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

replayBtn.MouseButton1Click:Connect(function()
	if _G["__playIntroTest"] then
		-- Zamknij MENU (nie setOpen, który tweenuje panel.Position i przesuwa content)
		if _G["__menuClose"] then _G["__menuClose"]() end
		task.wait(0.25)
		_G["__playIntroTest"]()
	end
end)

-- Eksport panelu dla MenuController — przeniesie go do zakładki 4 (USTAWIENIA)
_G["__settingsPanel"] = panel
_G["__settingsReady"] = true

-- Toggle kieruje do MenuController na zakładkę 4 (USTAWIENIA)
_G["__settingsToggle"] = function()
	if _G["__menuSetActiveTab"] then
		_G["__menuOpen"]()
		_G["__menuSetActiveTab"](5)
	else
		setOpen(not isOpen)  -- fallback
	end
end
