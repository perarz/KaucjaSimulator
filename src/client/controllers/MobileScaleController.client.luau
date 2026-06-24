-- MobileScaleController.client.luau
-- Wariant 1: globalny UIScale per ScreenGui dla ekranów mobilnych/małych.
-- Wykrywa rozmiar viewportu i wstrzykuje UIScale do każdego ScreenGui w PlayerGui.
-- Skala = min(viewX/DESIGN_X, viewY/DESIGN_Y), clamp [MIN_SCALE, 1.0].

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Baza projektowa = 1920×1080 (referencja desktop). Na 1920×1080 skala = 1.0 (UI bez zmian).
-- Każdy mniejszy ekran → skala < 1.0 proporcjonalnie (telefony/tablety mieszczą całe UI).
local DESIGN_X  = 1920
local DESIGN_Y  = 1080
local MIN_SCALE = 0.30
local MAX_SCALE = 1.00
local TAG_NAME  = "__MobileUIScale"

-- ScreenGui, których NIE skalujemy (mają własne reguły fullscreen).
local SKIP_GUIS = {
    Loading = true,
    Splash  = true,
    Intro   = true,
}

local function computeScale()
    local cam = workspace.CurrentCamera
    if not cam then return 1 end
    local vp = cam.ViewportSize
    if vp.X <= 0 or vp.Y <= 0 then return 1 end
    local s = math.min(vp.X / DESIGN_X, vp.Y / DESIGN_Y)
    if s > MAX_SCALE then s = MAX_SCALE end
    if s < MIN_SCALE then s = MIN_SCALE end
    return s
end

local activeScales: {UIScale} = {}

local function ensureScaleFor(gui: GuiObject)
    local existing = gui:FindFirstChild(TAG_NAME)
    if existing and existing:IsA("UIScale") then
        return existing
    end
    local s = Instance.new("UIScale")
    s.Name  = TAG_NAME
    s.Scale = computeScale()
    s.Parent = gui
    return s
end

local function trackScale(s: UIScale)
    table.insert(activeScales, s)
    s.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            for i, v in ipairs(activeScales) do
                if v == s then
                    table.remove(activeScales, i)
                    break
                end
            end
        end
    end)
end

-- Top-level dzieci ScreenGui o rozmiarze CZYSTO scale'owym (np. overlay fromScale(1,1))
-- są już viewport-relative i NIE wolno ich skalować — UIScale mnoży AbsoluteSize parenta,
-- więc overlay 1×1 staje się np. 0.87×0.87 na małym ekranie → ciemne tło pokrywa tylko
-- lewy-górny róg ("ucięte pociemnienie"). Skipujemy je.
local function isViewportSized(child: GuiObject): boolean
    local sz = child.Size
    return sz.X.Offset == 0 and sz.Y.Offset == 0 and sz.X.Scale > 0 and sz.Y.Scale > 0
end

local function processGuiObject(child: Instance)
    if not child:IsA("GuiObject") then return end
    if isViewportSized(child :: GuiObject) then return end
    local s = ensureScaleFor(child)
    trackScale(s)
end

local function attachScreenGui(sg: ScreenGui)
    if SKIP_GUIS[sg.Name] then return end
    -- istniejące dzieci
    for _, child in ipairs(sg:GetChildren()) do
        processGuiObject(child)
    end
    -- przyszłe dzieci (UI często tworzy ramki po starcie)
    sg.ChildAdded:Connect(function(child)
        processGuiObject(child)
    end)
end

local function attachAll()
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            attachScreenGui(gui)
        end
    end
end

playerGui.ChildAdded:Connect(function(child)
    if child:IsA("ScreenGui") then
        attachScreenGui(child)
    end
end)

attachAll()

-- Reaguj na zmianę rozmiaru ekranu (rotacja, resize Studio, splitscreen).
local function refresh()
    local s = computeScale()
    for _, ui in ipairs(activeScales) do
        if ui.Parent then
            ui.Scale = s
        end
    end
end

local function bindCamera(cam: Camera)
    cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
end

if workspace.CurrentCamera then
    bindCamera(workspace.CurrentCamera)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if workspace.CurrentCamera then
        bindCamera(workspace.CurrentCamera)
        refresh()
    end
end)

-- Pierwszy frame — czasem ViewportSize jest 0 do pierwszego renderu.
task.spawn(function()
    RunService.RenderStepped:Wait()
    refresh()
end)
