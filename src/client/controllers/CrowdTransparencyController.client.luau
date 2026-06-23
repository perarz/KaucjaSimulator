-- CrowdTransparencyController.client.luau
-- Robi pół-przezroczystych innych graczy gdy zasłaniają widok lub stoją blisko.
-- LocalTransparencyModifier działa TYLKO klientowo — inni gracze nadal się widzą normalnie.
-- Przy 40 graczach na serwerze ich ciała zasłaniały NPC, prompty, butelki — to fix.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local cam         = Workspace.CurrentCamera

-- Gdy inny gracz jest BLIŻEJ kamery niż NEAR_DIST od kamery LUB pomiędzy kamerą a localPlayerem —
-- robimy go pół-przezroczystego. NEAR_DIST większy niż typowa odległość kamera-postać (15-20).
local NEAR_DIST       = 22
local FADED_TRANSPARENCY = 0.75   -- 0 = pełny, 1 = niewidoczny
local DEFAULT_TRANSPARENCY = 0    -- "nie zmieniaj" baseline

local function setCharacterTransparency(char: Model, value: number)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Pomijamy HumanoidRootPart (i tak niewidoczny), żeby nie zaburzać fizyki/animacji
			if d.Name ~= "HumanoidRootPart" then
				d.LocalTransparencyModifier = value
			end
		elseif d:IsA("Decal") then
			-- Twarz też lokalnie wyciszamy
			d.LocalTransparencyModifier = value
		end
	end
end

local function getDistance(a: Vector3, b: Vector3): number
	return (a - b).Magnitude
end

RunService.RenderStepped:Connect(function()
	if not cam then cam = Workspace.CurrentCamera; if not cam then return end end
	local localChar = localPlayer.Character
	local localHrp  = localChar and localChar:FindFirstChild("HumanoidRootPart")
	if not (localHrp and localHrp:IsA("BasePart")) then return end

	local camPos = cam.CFrame.Position
	local localPos = (localHrp :: BasePart).Position

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if char and hrp and hrp:IsA("BasePart") then
				local hp = (hrp :: BasePart).Position
				local distToLocal = getDistance(hp, localPos)
				local distToCam   = getDistance(hp, camPos)
				-- Faduj jeśli blisko local gracza ALBO blisko kamery (zasłania widok)
				local shouldFade = distToLocal < NEAR_DIST or distToCam < NEAR_DIST
				setCharacterTransparency(char, shouldFade and FADED_TRANSPARENCY or DEFAULT_TRANSPARENCY)
			end
		end
	end
end)

print("[CrowdTransparencyController] gotowy — inni gracze pół-przezroczyści gdy blisko")
