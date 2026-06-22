-- MobileControlsController.client.luau
-- Touch-only:
--   1) Wymusza statyczny joystick (Thumbstick) w lewym dolnym — domyślnie Roblox używa
--      DynamicThumbstick który spawnuje się wszędzie po lewej stronie i blokuje kliknięcia
--      w przyciski MENU/deska.
--   2) Dodaje 2 przyciski po prawej stronie: SPRINT (Shift) i DESKA (R) — wywołują te same
--      akcje co klawiatura (przez _G API z SprintController/DeskaController).

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

-- Detekcja touch — w Studio mobile emulator KeyboardEnabled JEST true (bo Studio chodzi
-- na desktopie z klawiaturą), więc nie można excludować KeyboardEnabled. Sam TouchEnabled wystarczy.
if not UserInputService.TouchEnabled then return end

print("[MobileControlsController] Touch wykryty — uruchamiam mobile UI")

-- ── Przesunięcie pozycji joysticka ──────────────────────────────────────────
-- Typ joysticka (Thumbstick — statyczny) ustawiony w StarterPlayer.DevTouchMovementMode
-- w default.project.json. Tutaj tylko przesuwamy go w lewy dolny róg żeby nie zachodził na MENU.
local THUMBSTICK_POS = UDim2.new(0, 110, 1, -90)  -- bliżej lewego dolnego rogu

local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Przesuwa ThumbstickFrame i lockuje pozycję (Roblox PlayerModule nadpisuje co frame).
local lockedFrame: GuiObject? = nil
local lockedAnchor = Vector2.new(0, 1)
local applying = false  -- chroni przed rekursją w listenerze

local function forcePos(frame: GuiObject)
	applying = true
	frame.AnchorPoint = lockedAnchor
	frame.Position    = THUMBSTICK_POS
	applying = false
end

local function lockThumbstick()
	if lockedFrame and lockedFrame.Parent then return end  -- już zlockowane
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then return end
	local touchFrame = touchGui:FindFirstChild("TouchControlFrame")
	if not touchFrame then return end
	local thumb = touchFrame:FindFirstChild("ThumbstickFrame")
	if not (thumb and thumb:IsA("GuiObject")) then return end

	lockedFrame = thumb :: GuiObject
	forcePos(lockedFrame)

	-- Roblox PlayerModule może nadpisywać Position — pilnujemy przez PropertyChangedSignal
	lockedFrame:GetPropertyChangedSignal("Position"):Connect(function()
		if applying then return end
		if lockedFrame and lockedFrame.Position ~= THUMBSTICK_POS then
			forcePos(lockedFrame)
		end
	end)
	lockedFrame:GetPropertyChangedSignal("AnchorPoint"):Connect(function()
		if applying then return end
		if lockedFrame and lockedFrame.AnchorPoint ~= lockedAnchor then
			forcePos(lockedFrame)
		end
	end)

	print("[MobileControlsController] ThumbstickFrame zlockowane →", lockedFrame:GetFullName(),
		"na", tostring(THUMBSTICK_POS))
end

-- ── Lock pozycji domyślnego JumpButton (Roblox) w prawym dolnym rogu ────────
-- Bez locka JumpButton siedzi w okolicach centrum-prawej i zachodzi na SPRINT/DESKA.
-- Wymuszamy go w prawym dolnym rogu, a SPRINT/DESKA siedzą NA LEWO od niego.
local JUMP_SIZE = 90  -- typowa wielkość domyślnego JumpButton
local JUMP_POS  = UDim2.new(1, -30, 1, -30)
local JUMP_ANCHOR = Vector2.new(1, 1)
local lockedJump: GuiObject? = nil
local applyingJump = false

local function forceJumpPos(btn: GuiObject)
	applyingJump = true
	btn.AnchorPoint = JUMP_ANCHOR
	btn.Position    = JUMP_POS
	applyingJump = false
end

local function lockJumpButton()
	if lockedJump and lockedJump.Parent then return end
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then return end
	local touchFrame = touchGui:FindFirstChild("TouchControlFrame")
	if not touchFrame then return end
	local jump = touchFrame:FindFirstChild("JumpButton")
	if not (jump and jump:IsA("GuiObject")) then return end

	lockedJump = jump :: GuiObject
	forceJumpPos(lockedJump)

	lockedJump:GetPropertyChangedSignal("Position"):Connect(function()
		if applyingJump then return end
		if lockedJump and lockedJump.Position ~= JUMP_POS then forceJumpPos(lockedJump) end
	end)
	lockedJump:GetPropertyChangedSignal("AnchorPoint"):Connect(function()
		if applyingJump then return end
		if lockedJump and lockedJump.AnchorPoint ~= JUMP_ANCHOR then forceJumpPos(lockedJump) end
	end)

	print("[MobileControlsController] JumpButton zlockowany →", lockedJump:GetFullName())
end

-- Polling do skutku — TouchGui pojawia się asynchronicznie po pierwszym dotknięciu w niektórych edge cases.
task.spawn(function()
	for _ = 1, 60 do  -- 60 × 0.2s = 12s
		lockThumbstick()
		lockJumpButton()
		if lockedFrame and lockedJump then break end
		task.wait(0.2)
	end
end)

-- Reset gdy gracz respawnuje (CharacterAdded może zresetować TouchGui)
localPlayer.CharacterAdded:Connect(function()
	lockedFrame = nil
	lockedJump  = nil
	task.wait(0.3)
	task.spawn(function()
		for _ = 1, 30 do
			lockThumbstick()
			lockJumpButton()
			if lockedFrame and lockedJump then break end
			task.wait(0.2)
		end
	end)
end)

-- Reset gdy TouchGui jest na nowo tworzone
playerGui.ChildAdded:Connect(function(c)
	if c.Name == "TouchGui" then
		lockedFrame = nil
		lockedJump  = nil
		task.wait(0.2)
		lockThumbstick()
		lockJumpButton()
	end
end)

-- ── UI ──────────────────────────────────────────────────────────────────────
local FONT_MAIN = Enum.Font.GothamBlack
local C_BG      = Color3.fromRGB(18, 91, 73)
local C_BORDER  = Color3.fromRGB(5, 25, 20)
local C_WHITE   = Color3.new(1, 1, 1)

local gui = Instance.new("ScreenGui")
gui.Name           = "MobileControls"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 5  -- pod menu (30) i HUD (10), nad joystickiem
gui.Parent         = playerGui

local BTN_SIZE = 110
local PAD      = 18
-- SPRINT/DESKA siedzą NA LEWO od JumpButton (który jest w prawym dolnym rogu, ~90px szer).
-- Margines = JUMP_SIZE + odstęp jumpa od krawędzi + gap. Bez tego palec na sprint trafiał w jump.
local RIGHT_OFFSET = 30 + JUMP_SIZE + 16  -- = 136

local function makeMobileBtn(label: string, anchorY: number, posYOffset: number): TextButton
	local btn = Instance.new("TextButton")
	btn.AnchorPoint            = Vector2.new(1, anchorY)
	btn.Position               = UDim2.new(1, -RIGHT_OFFSET, anchorY, posYOffset)
	btn.Size                   = UDim2.fromOffset(BTN_SIZE, BTN_SIZE)
	btn.BackgroundColor3       = C_BG
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel        = 0
	btn.Text                   = label
	btn.Font                   = FONT_MAIN
	btn.TextSize               = 24
	btn.TextColor3             = C_WHITE
	btn.AutoButtonColor        = false
	btn.Parent                 = gui

	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = btn
	local stroke = Instance.new("UIStroke"); stroke.Color = C_BORDER; stroke.Thickness = 3; stroke.Parent = btn

	-- Touch feedback: scale na press
	local sc = Instance.new("UIScale"); sc.Parent = btn
	local pressTI   = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local releaseTI = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	btn.MouseButton1Down:Connect(function() TweenService:Create(sc, pressTI,   { Scale = 0.90 }):Play() end)
	btn.MouseButton1Up:Connect(  function() TweenService:Create(sc, releaseTI, { Scale = 1.00 }):Play() end)
	return btn
end

-- ── SPRINT (Shift) — trzymanie = sprint ────────────────────────────────────
local sprintBtn = makeMobileBtn("SPRINT", 1, -PAD - BTN_SIZE - 16)  -- prawy dolny, wyżej
sprintBtn.MouseButton1Down:Connect(function()
	local fn = _G["__sprintStart"]; if type(fn) == "function" then fn() end
end)
sprintBtn.MouseButton1Up:Connect(function()
	local fn = _G["__sprintEnd"]; if type(fn) == "function" then fn() end
end)
-- Failsafe: gdy gracz "ślizgnie" palcem poza przycisk, też zwolnij sprint
sprintBtn.MouseLeave:Connect(function()
	local fn = _G["__sprintEnd"]; if type(fn) == "function" then fn() end
end)

-- ── DESKA (R) — kliknięcie = wsiada / wysiada ──────────────────────────────
local deskaBtn = makeMobileBtn("DESKA", 1, -PAD)  -- prawy dolny, najniżej
deskaBtn.MouseButton1Click:Connect(function()
	local fn = _G["__deskaToggle"]; if type(fn) == "function" then fn() end
end)

print("[MobileControlsController] Gotowy — touch joystick=Thumbstick + 2 przyciski po prawej")
