-- GrandpaController.client.luau
-- Klasyczny visual-novel dialog box na dole ekranu:
-- avatar po lewej (kwadrat, no UICorner), tekst typewriter po prawej,
-- przyciski wyboru pojawiają się po skończeniu pisania.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local Config        = require(ReplicatedStorage:WaitForChild("Config"))
local cfg           = Config.GrandpaQuest

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events        = ReplicatedStorage:WaitForChild("Events")
local GrandpaDialog = Events:WaitForChild("GrandpaDialog")
local GrandpaAccept = Events:WaitForChild("GrandpaAccept")
local GrandpaTurnIn = Events:WaitForChild("GrandpaTurnIn")

local FONT_MAIN = Enum.Font.GothamBlack

-- Paleta (green theme — z CLAUDE.md)
local C_BG           = Color3.fromRGB(18, 91, 73)
local C_HEADER       = Color3.fromRGB(0, 53, 39)
local C_BORDER       = Color3.fromRGB(5, 25, 20)
local C_WHITE        = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT      = Color3.fromRGB(175, 175, 175)
local C_ACCENT_GREEN = Color3.fromRGB(170, 221, 102)
local C_ACC_BLUE     = Color3.fromRGB(70, 120, 180)
local X_RED          = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER    = Color3.fromRGB(255, 110, 110)

-- Wymiary dialog boxu
local BOX_W       = 960
local BOX_H       = 220
local AVATAR_SIZE = 180
local PAD         = 20
local BOTTOM_OFFSET = 80   -- ile pikseli od dolnej krawędzi

-- ── ScreenGui scaffold ──────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "Grandpa"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 50
gui.Enabled        = false
gui.Parent         = playerGui

-- Niewidoczny overlay tylko do łapania klików (skip typewriter).
-- BackgroundTransparency=1 cały czas — bez dimowania ekranu.
local overlay = Instance.new("TextButton")
overlay.Name             = "Overlay"
overlay.Size             = UDim2.fromScale(1, 1)
overlay.BackgroundTransparency = 1
overlay.AutoButtonColor  = false
overlay.Text             = ""
overlay.BorderSizePixel  = 0
overlay.Modal            = false
overlay.Parent           = gui

-- Główna ramka dialogu — prostokąt, NO UICorner (klasyczny dialog box)
local box = Instance.new("Frame")
box.AnchorPoint        = Vector2.new(0.5, 1)
box.Position           = UDim2.new(0.5, 0, 1, -BOTTOM_OFFSET)
box.Size               = UDim2.fromOffset(BOX_W, BOX_H)
box.BackgroundColor3   = C_BG
box.BackgroundTransparency = 0.05
box.BorderSizePixel    = 0
box.Parent             = gui

local boxStroke = Instance.new("UIStroke")
boxStroke.Color     = C_BORDER
boxStroke.Thickness = 5
boxStroke.Parent    = box

-- ── Avatar (kwadrat po lewej) ──────────────────────────────────────────────
local avatarFrame = Instance.new("Frame")
avatarFrame.Position           = UDim2.fromOffset(PAD, PAD)
avatarFrame.Size               = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
avatarFrame.BackgroundColor3   = cfg.AvatarBg or C_HEADER
avatarFrame.BorderSizePixel    = 0
avatarFrame.Parent             = box
-- ŻADNEGO UICorner — kwadratowe rogi celowo

local avatarStroke = Instance.new("UIStroke")
avatarStroke.Color     = C_BORDER
avatarStroke.Thickness = 4
avatarStroke.Parent    = avatarFrame

-- Zawartość avatara: 3 warianty, w kolejności priorytetów:
--   1. Jeśli AvatarImage podane w Config → ImageLabel (override custom grafiką)
--   2. Inaczej → ViewportFrame z klonem workspace.Grandpa (prawdziwa twarz z modelu)
--   3. Inaczej → placeholder emoji 👴

local hasCustomImage = (cfg.AvatarImage or "") ~= ""

local avatarImg = Instance.new("ImageLabel")
avatarImg.Size                   = UDim2.fromScale(1, 1)
avatarImg.BackgroundTransparency = 1
avatarImg.ScaleType              = Enum.ScaleType.Fit
avatarImg.Image                  = cfg.AvatarImage or ""
avatarImg.Visible                = hasCustomImage
avatarImg.Parent                 = avatarFrame

local avatarPlaceholder = Instance.new("TextLabel")
avatarPlaceholder.Size                   = UDim2.fromScale(1, 1)
avatarPlaceholder.BackgroundTransparency = 1
avatarPlaceholder.Text                   = "👴"
avatarPlaceholder.Font                   = Enum.Font.GothamBlack
avatarPlaceholder.TextSize               = 110
avatarPlaceholder.TextColor3             = C_WHITE
avatarPlaceholder.TextStrokeColor3       = Color3.new(0, 0, 0)
avatarPlaceholder.TextStrokeTransparency = 0.3
avatarPlaceholder.Visible                = false  -- ustawi się jeśli viewport setup zawiedzie
avatarPlaceholder.Parent                 = avatarFrame

-- ViewportFrame z prawdziwym modelem dziadka
local avatarViewport: ViewportFrame? = nil
if not hasCustomImage then
	avatarViewport = Instance.new("ViewportFrame")
	avatarViewport.Size                   = UDim2.fromScale(1, 1)
	avatarViewport.BackgroundTransparency = 1
	avatarViewport.Ambient                = Color3.fromRGB(160, 150, 140)
	avatarViewport.LightColor             = Color3.fromRGB(255, 245, 225)
	avatarViewport.LightDirection         = Vector3.new(-0.3, -1, -0.3)
	avatarViewport.Parent                 = avatarFrame
end

-- Setup viewport: klonuje workspace.Grandpa, pozycjonuje kamerę przed twarzą.
-- Jeśli model lub Head nie znalezione — fallback na emoji placeholder.
local function fail(reason: string)
	warn("[GrandpaController] Avatar viewport setup failed: " .. reason)
	avatarPlaceholder.Visible = true
	if avatarViewport then avatarViewport:Destroy() end
end

local function setupAvatarViewport()
	if not avatarViewport then return end

	local source = workspace:WaitForChild("Grandpa", 15)
	if not source then return fail("workspace.Grandpa not found after 15s") end

	-- Head replikuje się czasem osobno od modelu — czekaj na niego
	local sourceHead = source:WaitForChild("Head", 10)
	if not sourceHead then return fail("Grandpa.Head not found after 10s") end
	if not sourceHead:IsA("BasePart") then return fail("Grandpa.Head is " .. sourceHead.ClassName .. ", not BasePart") end

	local sourceHRP = source:FindFirstChild("HumanoidRootPart")

	-- Klon całego modelu (włącznie z accessories — czapki, włosy itd.)
	local clone = (source :: Model):Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored   = true
			d.CanCollide = false
		elseif d:IsA("Humanoid") then
			-- Humanoid w viewport może próbować animować/upaść — usuwamy
			d:Destroy()
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	clone.Parent = avatarViewport

	local headClone = (clone :: Model):FindFirstChild("Head") :: BasePart?
	if not headClone then return fail("Head missing in clone") end

	-- Camera framing — preferuj kierunek HRP (bardziej niezawodny niż Head.LookVector
	-- dla R15, bo Head może być rotowane animacją idle)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	cam.Parent      = avatarViewport
	avatarViewport.CurrentCamera = cam

	local hrpClone = (clone :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	local lookDir
	if hrpClone and sourceHRP then
		lookDir = hrpClone.CFrame.LookVector
	else
		lookDir = headClone.CFrame.LookVector
	end

	local headPos = headClone.Position
	local camPos  = headPos + lookDir * 3.2
	cam.CFrame    = CFrame.new(camPos, headPos)

	print("[GrandpaController] Avatar viewport ready — Head at", headPos)
end

task.spawn(function()
	local ok, err = pcall(setupAvatarViewport)
	if not ok then fail("exception: " .. tostring(err)) end
end)

-- Etykieta z imieniem POD avatarem (na ramce boxu, nie na avatarze)
local nameBar = Instance.new("Frame")
nameBar.Position           = UDim2.fromOffset(PAD, PAD + AVATAR_SIZE - 2)
nameBar.Size               = UDim2.fromOffset(AVATAR_SIZE, 0)  -- chowamy się w środku boxu (informacja w samym avatarze)
nameBar.BackgroundTransparency = 1
nameBar.BorderSizePixel    = 0
nameBar.Parent             = box

-- ── Tekst dialogu (typewriter) ──────────────────────────────────────────────
local TEXT_X        = PAD * 2 + AVATAR_SIZE
local TEXT_W        = BOX_W - TEXT_X - PAD
local NAME_H        = 28

-- Imię postaci nad tekstem
local nameLbl = Instance.new("TextLabel")
nameLbl.Position             = UDim2.fromOffset(TEXT_X, PAD)
nameLbl.Size                 = UDim2.fromOffset(TEXT_W, NAME_H)
nameLbl.BackgroundTransparency = 1
nameLbl.Text                 = "DZIADEK"
nameLbl.Font                 = FONT_MAIN
nameLbl.TextSize             = 22
nameLbl.TextColor3           = C_ACCENT_GREEN
nameLbl.TextXAlignment       = Enum.TextXAlignment.Left
nameLbl.TextYAlignment       = Enum.TextYAlignment.Top
nameLbl.Parent               = box

-- Tekst dialogu — z stopniowym pojawianiem
local dialogText = Instance.new("TextLabel")
dialogText.Position             = UDim2.fromOffset(TEXT_X, PAD + NAME_H + 6)
dialogText.Size                 = UDim2.fromOffset(TEXT_W, BOX_H - PAD * 2 - NAME_H - 80)  -- zostaw miejsce na przyciski
dialogText.BackgroundTransparency = 1
dialogText.Font                 = FONT_MAIN
dialogText.TextSize             = 22
dialogText.TextColor3           = C_WHITE
dialogText.TextWrapped          = true
dialogText.TextXAlignment       = Enum.TextXAlignment.Left
dialogText.TextYAlignment       = Enum.TextYAlignment.Top
dialogText.Text                 = ""
dialogText.Parent               = box

-- Container przycisków — na dole, po prawej
local btnHolder = Instance.new("Frame")
btnHolder.AnchorPoint        = Vector2.new(1, 1)
btnHolder.Position           = UDim2.new(1, -PAD, 1, -PAD)
btnHolder.Size               = UDim2.fromOffset(TEXT_W, 56)
btnHolder.BackgroundTransparency = 1
btnHolder.Parent             = box

local btnLayout = Instance.new("UIListLayout")
btnLayout.FillDirection       = Enum.FillDirection.Horizontal
btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
btnLayout.Padding             = UDim.new(0, 12)
btnLayout.SortOrder           = Enum.SortOrder.LayoutOrder
btnLayout.Parent              = btnHolder

-- Hint "kliknij by przyspieszyć" (znika gdy tekst skończony)
local hintLbl = Instance.new("TextLabel")
hintLbl.AnchorPoint            = Vector2.new(1, 1)
hintLbl.Position               = UDim2.new(1, -PAD, 1, -PAD)
hintLbl.Size                   = UDim2.fromOffset(280, 22)
hintLbl.BackgroundTransparency = 1
hintLbl.Text                   = "▼ kliknij by pominąć"
hintLbl.Font                   = FONT_MAIN
hintLbl.TextSize               = 14
hintLbl.TextColor3             = C_DIMTEXT
hintLbl.TextXAlignment         = Enum.TextXAlignment.Right
hintLbl.Visible                = false
hintLbl.Parent                 = box

-- ── Button helper ───────────────────────────────────────────────────────────
local function makeButton(text: string, color: Color3, textColor: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size               = UDim2.fromOffset(200, 56)
	b.BackgroundColor3   = color
	b.BorderSizePixel    = 0
	b.AutoButtonColor    = false
	b.Text               = text
	b.Font               = FONT_MAIN
	b.TextSize           = 20
	b.TextColor3         = textColor
	b.AnchorPoint        = Vector2.new(0.5, 0.5)
	-- Brak UICorner ani UIStroke — czysty kolor tła + tekst, bez "obramówki" wokół liter

	local sc = Instance.new("UIScale")
	sc.Parent = b

	b.MouseEnter:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.06 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.0 }):Play()
	end)
	b.MouseButton1Click:Connect(onClick)

	return b
end

-- ── Stan / opcje / typewriter ──────────────────────────────────────────────
local typewriterConn: RBXScriptConnection? = nil
local typing       = false
local currentText  = ""    -- pełny tekst aktualnie pisanego dialogu (do skip)
local pendingShow  = nil :: (() -> ())?  -- callback do uruchomienia po skończeniu tekstu

local function clearButtons()
	for _, c in ipairs(btnHolder:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
end

local function stopTypewriter()
	if typewriterConn then
		typewriterConn:Disconnect()
		typewriterConn = nil
	end
	typing = false
end

local function startTypewriter(fullText: string, onDone: () -> ())
	stopTypewriter()
	typing = true
	currentText     = fullText
	dialogText.Text = ""
	hintLbl.Visible = true

	local chars   = #fullText
	local cps     = cfg.TypeSpeed or 35
	local duration = chars / cps
	local startT  = tick()

	typewriterConn = RunService.Heartbeat:Connect(function()
		if not typing then return end
		local t       = tick() - startT
		local ratio   = math.min(1, t / duration)
		local visible = math.floor(ratio * chars)
		dialogText.Text = string.sub(fullText, 1, visible)
		if ratio >= 1 then
			stopTypewriter()
			dialogText.Text = fullText  -- pewność że pełen tekst widoczny
			hintLbl.Visible = false
			onDone()
		end
	end)
end

local function skipTypewriter()
	-- Wymuś pełny tekst od razu
	if not typing then return end
	stopTypewriter()
	dialogText.Text = currentText  -- ← TO brakowało: pokaż cały tekst od razu
	hintLbl.Visible = false
	if pendingShow then
		local cb = pendingShow
		pendingShow = nil
		cb()
	end
end

local function close()
	stopTypewriter()
	pendingShow = nil
	clearButtons()
	gui.Enabled = false
end

local function showOptions(options: {string}, reward: number?)
	clearButtons()
	local BLACK = Color3.new(0, 0, 0)
	for _, opt in ipairs(options) do
		if opt == "accept" then
			makeButton("PRZYJMIJ", C_ACCENT_GREEN, BLACK, function()
				GrandpaAccept:FireServer()
			end).Parent = btnHolder
		elseif opt == "turnin" then
			local label = reward and ("ODDAJ (+" .. tostring(reward) .. " zł)") or "ODDAJ"
			makeButton(label, C_ACCENT_GREEN, BLACK, function()
				GrandpaTurnIn:FireServer()
			end).Parent = btnHolder
		elseif opt == "close" then
			makeButton("ZAMKNIJ", C_ACC_BLUE, C_WHITE, close).Parent = btnHolder
		end
	end

	-- Pop-in animacja przycisków
	for _, c in ipairs(btnHolder:GetChildren()) do
		if c:IsA("TextButton") then
			local sc = c:FindFirstChildOfClass("UIScale")
			if sc then
				sc.Scale = 0.6
				TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1.0 }):Play()
			end
		end
	end
end

-- Klik w overlay = skip typewriter (jeśli pisze) → pokazuje przyciski od razu.
-- Nie zamyka dialogu — zamknięcie tylko przyciskiem ZAMKNIJ.
overlay.MouseButton1Click:Connect(skipTypewriter)
-- Również klik w sam dialog box przyspiesza
local boxClickCatcher = Instance.new("TextButton")
boxClickCatcher.Size                   = UDim2.fromScale(1, 1)
boxClickCatcher.BackgroundTransparency = 1
boxClickCatcher.AutoButtonColor        = false
boxClickCatcher.Text                   = ""
boxClickCatcher.ZIndex                 = 0
boxClickCatcher.Parent                 = box
boxClickCatcher.MouseButton1Click:Connect(skipTypewriter)

-- ── Otwieranie ──────────────────────────────────────────────────────────────
local function open(payload: { state: string, text: string, options: {string}, reward: number? })
	-- Kolor tekstu w zależności od stanu
	if payload.state == "ready" then
		dialogText.TextColor3 = C_ACCENT_GREEN
	elseif payload.state == "done" then
		dialogText.TextColor3 = C_DIMTEXT
	else
		dialogText.TextColor3 = C_WHITE
	end

	clearButtons()

	-- Slide-in dialog boxu od dołu (bez dimowania tła)
	box.Position = UDim2.new(0.5, 0, 1, 60)
	gui.Enabled = true
	TweenService:Create(box, TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_OFFSET),
	}):Play()

	-- Typewriter → przyciski pojawiają się po skończeniu
	pendingShow = function() showOptions(payload.options, payload.reward) end
	startTypewriter(payload.text, function()
		if pendingShow then
			local cb = pendingShow
			pendingShow = nil
			cb()
		end
	end)
end

-- Klawiatura: ESC zamyka, Space/Enter przyspiesza
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		close()
	elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
		skipTypewriter()
	end
end)

-- ── Listener serwera ───────────────────────────────────────────────────────
GrandpaDialog.OnClientEvent:Connect(function(payload)
	if not payload then return end
	open(payload)
end)

-- ── Per-player visibility syropu (z Kroku 2) ───────────────────────────────
local function applySyrupVisibility(model: Instance)
	if not model:IsA("Model") then return end
	local owner = model:GetAttribute("OwnerUserId")
	local isMine = (owner == player.UserId)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = isMine and 0 or 1
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = isMine
		elseif d:IsA("PointLight") then
			d.Enabled = isMine
		end
	end
end

local function watchSyrup(folder: Folder)
	for _, child in ipairs(folder:GetChildren()) do applySyrupVisibility(child) end
	folder.ChildAdded:Connect(function(child)
		task.defer(applySyrupVisibility, child)
	end)
end

task.spawn(function()
	local folder = workspace:WaitForChild("SyrupActive", 30)
	if folder then watchSyrup(folder :: Folder) end
end)
