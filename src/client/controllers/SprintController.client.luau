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
local PetStatusUpdate  = Events:WaitForChild("PetStatusUpdate")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

print("[SprintController] start — czeka na SkillTreeInit")

-- Shift Lock wyłączony przez StarterPlayer.EnableMouseLockOption=false w default.project.json

-- ── Tuning ─────────────────────────────────────────────────────────────────
local SPRINT_BONUS   = 12   -- było 5 — różnica chodzenie/sprint za mało zauważalna
local STAMINA_MAX_BASE = 100
local DRAIN_PER_SEC  = 25   -- 4 sekundy pełnego sprintu
local REGEN_PER_SEC  = 18
local SPRINT_KEY     = Enum.KeyCode.LeftShift
local DEFAULT_SPEED  = 16
local BAR_HEIGHT     = 5

-- ── Stan ───────────────────────────────────────────────────────────────────
local baseLevel       = 0
local speedLevel      = 0
local staminaLevel    = 0  -- odnoga skill tree: +Config.StaminaUpgrade.StaminaBonus do max
local hatOwned        = false
local hatSpeedBonus   = 0
local hatStaminaBonus = 0
local petSpeedBonus   = 0  -- z PetService (klasa Sprinter, addytywne do baseSpeed)
local function getStaminaMax(): number
	local n = STAMINA_MAX_BASE
	if hatOwned then n += hatStaminaBonus end
	if staminaLevel >= 1 and Config.StaminaUpgrade then
		n += (Config.StaminaUpgrade.StaminaBonus or 0)
	end
	return n
end
local stamina      = STAMINA_MAX_BASE
local sprinting    = false
local shiftHeld    = false
local exhausted    = false  -- po zejściu staminy do 0 blokuje sprint dopóki Shift nie zostanie puszczony
local wasMounted   = false  -- do wykrycia zejścia z deski → przywrócenie prędkości pieszej

local function getBaseSpeed(): number
	local s = DEFAULT_SPEED
	if speedLevel > 0 and Config.SpeedUpgrades and Config.SpeedUpgrades[speedLevel] then
		s = Config.SpeedUpgrades[speedLevel].Speed
	end
	if hatOwned then s += hatSpeedBonus end
	s += petSpeedBonus  -- Sprinter pet — addytywnie
	return s
end

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function applySpeed()
	-- Gdy jeździsz na desce — NIE dotykamy WalkSpeed (deska/DeskaService nim zarządza).
	-- Inaczej event-driven calle (PetStatusUpdate przy otwarciu jajka, HatStatus,
	-- SkillTreeUpdate) nadpisywały prędkość deski na pieszą → "poruszasz się wolno".
	if _G["__deskaMounted"] == true then return end
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

-- API dla MobileControlsController (przycisk SPRINT na ekranie)
_G["__sprintStart"] = function() shiftHeld = true end
_G["__sprintEnd"]   = function() shiftHeld = false end

-- ── Update loop ────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	-- Gate: jeździsz na desce — sprint NIE działa, nie dotykamy WalkSpeed
	-- (deska sama ustawia swoją prędkość; sprint by ją nadpisywał lub kasował)
	if _G["__deskaMounted"] == true then
		if sprinting then sprinting = false end
		shiftHeld = false
		container.Visible = false
		wasMounted = true
		return
	end
	-- Tuż po zejściu z deski — przywróć prędkość pieszą (applySpeed był gate'owany)
	if wasMounted then
		wasMounted = false
		applySpeed()
	end

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

	-- exhausted: gdy stamina spadła do 0, blokujemy sprint dopóki Shift nie zostanie puszczony.
	-- Inaczej `shiftHeld and stamina>0` oscylowało drain ↔ regen przy stamina=0 i Shift dawał
	-- praktycznie nieskończony sprint (regen 18/s wpadał między drain ticki).
	if shiftHeld and stamina > 0 and not exhausted then
		if not sprinting then
			sprinting = true
			applySpeed()
		end
		stamina = math.max(0, stamina - DRAIN_PER_SEC * dt)
		if stamina <= 0 then
			sprinting = false
			exhausted = true
			applySpeed()
		end
	else
		if sprinting then
			sprinting = false
			applySpeed()
		end
		-- Reset exhausted gdy Shift puszczony — można znowu sprintować dopiero po puszczeniu.
		if not shiftHeld then exhausted = false end
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
	baseLevel    = data.baseLevel    or 0
	speedLevel   = data.speedLevel   or 0
	staminaLevel = data.staminaLevel or 0
	print(string.format("[SprintController] SkillTreeInit → baseLevel=%d speedLevel=%d staminaLevel=%d",
		baseLevel, speedLevel, staminaLevel))
	-- Cap stamina do nowego max (gdyby był niższy niż obecny — bezpieczeństwo)
	if stamina > getStaminaMax() then stamina = getStaminaMax() end
	applySpeed()
end)

SkillTreeUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or not data.success then return end
	if data.upgradeType == "Base"    then baseLevel    = data.newLevel or baseLevel end
	if data.upgradeType == "Speed"   then speedLevel   = data.newLevel or speedLevel end
	if data.upgradeType == "Stamina" then staminaLevel = data.newLevel or staminaLevel end
	applySpeed()
end)

HatStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	hatOwned        = data.owned == true
	hatSpeedBonus   = tonumber(data.speedBonus) or 0
	hatStaminaBonus = tonumber(data.staminaBonus) or 0
	print(string.format("[SprintController] HatStatus → owned=%s speedBonus=%d staminaBonus=%d",
		tostring(hatOwned), hatSpeedBonus, hatStaminaBonus))
	if stamina > getStaminaMax() then stamina = getStaminaMax() end
	applySpeed()
end)

PetStatusUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local b = data.bonuses
	petSpeedBonus = (b and tonumber(b.speed)) or 0
	-- applySpeed jest no-op gdy jeździsz na desce (gate w applySpeed) — nie nadpisze
	-- prędkości deski przy otwieraniu jajka / equipowaniu peta.
	applySpeed()
end)

localPlayer.CharacterAdded:Connect(function()
	stamina   = getStaminaMax()
	sprinting = false
	shiftHeld = false
	task.wait(0.3)
	applySpeed()
end)
