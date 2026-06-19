-- wrzuc_do_bramy.luau
-- Wrzuć do: Workspace.Parking.bramy (jako Script)
-- Brama otwiera się trwale po zapłaceniu 500 PLN (ParkingService → ParkingGateEvent).

local parent = script.Parent
local gateA  = parent:WaitForChild("Gate_2A")
local gateB  = parent:WaitForChild("Gate_2B")

local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local startCFrameA = gateA.MeshPart1.CFrame
local startCFrameB = gateB.MeshPart1.CFrame

local ANIM_TIME    = 0.45
local EASING_STYLE = Enum.EasingStyle.Sine
local EASING_DIR   = Enum.EasingDirection.InOut

local function tweenAlongPath(part, cframes, totalTime, easingStyle, easingDirection)
	local n = #cframes - 1
	if n <= 0 then return end
	local segLengths = {}
	local totalLength = 0
	for i = 1, n do
		local dist = (cframes[i + 1].Position - cframes[i].Position).Magnitude
		segLengths[i] = math.max(dist, 0.001)
		totalLength += segLengths[i]
	end
	local startTime = os.clock()
	while true do
		local elapsed = os.clock() - startTime
		local alpha   = math.clamp(elapsed / totalTime, 0, 1)
		local eased   = TweenService:GetValue(alpha, easingStyle, easingDirection)
		local target  = eased * totalLength
		local accum   = 0
		for i = 1, n do
			if target <= accum + segLengths[i] or i == n then
				local segAlpha = math.clamp((target - accum) / segLengths[i], 0, 1)
				part.CFrame = cframes[i]:Lerp(cframes[i + 1], segAlpha)
				break
			end
			accum += segLengths[i]
		end
		if alpha >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	part.CFrame = cframes[n + 1]
end

local function openGate(gate)
	tweenAlongPath(gate.MeshPart1, {
		gate.MeshPart1.CFrame,
		gate.MeshPart2.CFrame,
		gate.MeshPart3.CFrame,
		gate.MeshPart4.CFrame,
	}, ANIM_TIME, EASING_STYLE, EASING_DIR)
end

local function openBoth()
	task.spawn(openGate, gateA)
	task.spawn(openGate, gateB)
end

-- Nasłuchuje na ParkingGateEvent od ParkingService — otwiera bramę przy każdym zakupie
local gateEvent = ServerScriptService:WaitForChild("ParkingGateEvent", 30)
if not gateEvent then
	warn("[wrzuc_do_bramy] Nie znaleziono ParkingGateEvent — upewnij się że ParkingService jest w ServerScriptService")
else
	gateEvent.Event:Connect(function()
		if not parent:GetAttribute("DoorOpen") then
			parent:SetAttribute("DoorOpen", true)
			openBoth()
		end
	end)
	print("[wrzuc_do_bramy] Gotowy — czekam na zakup biletu")
end
