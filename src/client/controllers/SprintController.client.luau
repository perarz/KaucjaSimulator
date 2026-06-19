-- SprintController.client.luau
-- Shift = sprint (+5 do WalkSpeed). Wymaga BaseLevel >= 1 (Fundament w drzewku).
-- Cienki biały pasek staminy na dole ekranu — widoczny tylko podczas sprintu / regeneracji.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config           = require(ReplicatedStorage:WaitForChild("Config"))
local Events           = ReplicatedStorage:WaitForChild("Events")
local SkillTreeInit    = Events:WaitForChild("SkillTreeInit")
local SkillTreeUpdate  = Events:WaitForChild("SkillTreeUpdate")
local HatStatusUpdate  = Events:WaitForChild("HatStatusUpdate")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

print("[SprintController] start — czeka na SkillTreeInit")

-- Shift Lock wyłączony przez StarterPlayer.EnableMouseLockOption=false w default.project.json

-- ── Tuning ─────────────────────────────────────────────────────────────────
local SPRINT_BONUS   = 5
local STAMINA_MAX_BASE = 100
local DRAIN_PER_SEC  = 25   -- 4 sekundy pełnego sprintu
local REGEN_PER_SEC  = 18
local SPRINT_KEY     = Enum.KeyCode.LeftShift
local DEFAULT_SPEED  = 16
local BAR_HEIGHT     = 5

-- ── Stan ───────────────────────────────────────────────────────────────────
local baseLevel       = 0
local speedLevel      = 0
local hatOwned        = false
local hatSpeedBonus   = 0
local hatStaminaBonus = 0
local function getStaminaMax(): number return STAMINA_MAX_BASE + (hatOwned and hatStaminaBonus or 0) end
local stamina      = STAMINA_MAX_BASE
local sprinting    = false
local shiftHeld    = false

local function getBaseSpeed(): number
	local s = DEFAULT_SPEED
	if speedLevel > 0 and Config.SpeedUpgrades and Config.SpeedUpgrades[speedLevel] then
		s = Config.SpeedUpgrades[speedLevel].Speed
	end
	if hatOwned then s += hatSpeedBonus end
	return s
end

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function applySpeed()
	local hum = getHumanoid()
	if not hum then return end
	local base = getBaseSpeed()
	hum.WalkSpeed = sprinting and (base + SPRINT_BONUS) or base
end

-- ── UI: cienki biały pasek na dole ekranu ──────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "SprintHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 60
gui.Parent         = playerGui

local container = Instance.new("Frame")
container.AnchorPoint            = Vector2.new(0.5, 1)
container.Position               = UDim2.new(0.5, 0, 1, 0)
container.Size                   = UDim2.new(1, 0, 0, BAR_HEIGHT)
container.BackgroundColor3       = Color3.fromRGB(30, 30, 30)
container.BackgroundTransparency = 0.5
container.BorderSizePixel        = 0
container.Visible                = false
container.Parent                 = gui

local fill = Instance.new("Frame")
fill.Position         = UDim2.fromScale(0, 0)
fill.Size             = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
fill.BorderSizePixel  = 0
fill.Parent           = container

-- ── Input ──────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == SPRINT_KEY then
		print(string.format("[SprintController] Shift wciśnięty (processed=%s baseLevel=%d stamina=%d)",
			tostring(processed), baseLevel, math.floor(stamina)))
		if processed then return end
		shiftHeld = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == SPRINT_KEY then
		shiftHeld = false
	end
end)

-- ── Update loop ────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	-- Gate: brak Fundamentu → sprint wyłączony, pasek schowany
	if baseLevel < 1 then
		if sprinting then
			sprinting = false
			applySpeed()
		end
		shiftHeld = false
		container.Visible = false
		return
	end

	if shiftHeld and stamina > 0 then
		if not sprinting then
			sprinting = true
			applySpeed()
		end
		stamina = math.max(0, stamina - DRAIN_PER_SEC * dt)
		if stamina <= 0 then
			sprinting = false
			applySpeed()
		end
	else
		if sprinting then
			sprinting = false
			applySpeed()
		end
		if stamina < getStaminaMax() then
			stamina = math.min(getStaminaMax(), stamina + REGEN_PER_SEC * dt)
		end
	end

	fill.Size = UDim2.fromScale(stamina / getStaminaMax(), 1)
	container.Visible = sprinting or (stamina < getStaminaMax())
end)

-- ── Sync z drzewkiem umiejętności ──────────────────────────────────────────
SkillTreeInit.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	baseLevel  = data.baseLevel  or 0
	speedLevel = data.speedLevel or 0
	print(string.format("[SprintController] SkillTreeInit → baseLevel=%d speedLevel=%d", baseLevel, speedLevel))
	applySpeed()
end)

SkillTreeUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or not data.success then return end
	if data.upgradeType == "Base"  then baseLevel  = data.newLevel or baseLevel end
	if data.upgradeType == "Speed" then speedLevel = data.newLevel or speedLevel end
	applySpeed()
end)

HatStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	hatOwned        = data.owned == true
	hatSpeedBonus   = tonumber(data.speedBonus) or 0
	hatStaminaBonus = tonumber(data.staminaBonus) or 0
	print(string.format("[SprintController] HatStatus → owned=%s speedBonus=%d staminaBonus=%d",
		tostring(hatOwned), hatSpeedBonus, hatStaminaBonus))
	-- Po założeniu czapki stamina powinna móc rosnąć do nowego maxa
	if stamina > getStaminaMax() then stamina = getStaminaMax() end
	applySpeed()
end)

localPlayer.CharacterAdded:Connect(function()
	stamina   = getStaminaMax()
	sprinting = false
	shiftHeld = false
	task.wait(0.3)
	applySpeed()
end)
