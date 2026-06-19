-- DeskaService.server.luau

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events          = ReplicatedStorage:WaitForChild("Events")
local DeskMount       = Events:WaitForChild("DeskMount")
local DeskDismount    = Events:WaitForChild("DeskDismount")
local DeskMountResult = Events:WaitForChild("DeskMountResult")
local QuickMount      = Events:WaitForChild("QuickMount")

local BOARD_Y_OFFSET = -3.0
local SKATE_SPEED    = 38
local MAX_MOUNT_DIST = 10

local mountedData: { [Player]: { weld: WeldConstraint, board: Model, parts: {} } } = {}

local function getPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then return model.PrimaryPart end
	for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then return v :: BasePart end
	end
	return nil
end

local function mountPlayer(player: Player, board: Model)
	if mountedData[player] then return end

	local char     = player.Character
	local hrp      = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not hrp or not humanoid then return end

	local primary = getPrimaryPart(board)
	if not primary then
		warn("[DeskaService] Brak BasePart w modelu deski")
		return
	end

	local savedParts = {}
	for _, part in board:GetDescendants() do
		if part:IsA("BasePart") then
			savedParts[part] = {
				canCollide = part.CanCollide,
				massless   = part.Massless,
				anchored   = part.Anchored,
			}
			part.Anchored      = false
			part.CanCollide    = false
			part.Massless      = true
			part.Transparency  = 0
		end
	end

	local _, yRot, _ = hrp.CFrame:ToEulerAnglesYXZ()
	primary.CFrame = CFrame.new(hrp.Position + Vector3.new(0, BOARD_Y_OFFSET, 0))
		* CFrame.Angles(0, yRot + math.rad(90), 0)
		* CFrame.Angles(0, 0, math.rad(90))

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = hrp
	weld.Part1  = primary
	weld.Parent = primary

	humanoid.WalkSpeed  = SKATE_SPEED
	humanoid.JumpHeight = 0

	mountedData[player] = { weld = weld, board = board, parts = savedParts }
	DeskMountResult:FireClient(player, true, board)
	print("[DeskaService]", player.Name, "wsiadł na deskę")
end

local function dismountPlayer(player: Player)
	local data = mountedData[player]
	if not data then return end
	mountedData[player] = nil

	if data.weld and data.weld.Parent then
		data.weld:Destroy()
	end

	for part, state in data.parts do
		if part and part.Parent then
			part.CanCollide   = state.canCollide
			part.Massless     = state.massless
			part.Anchored     = state.anchored
			part.Transparency = 1
		end
	end

	local char = player.Character
	if char then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed  = 16
			humanoid.JumpHeight = 7.2
		end
	end

	DeskMountResult:FireClient(player, false, nil)
	print("[DeskaService]", player.Name, "wysiadł z deski")
end

QuickMount.OnServerEvent:Connect(function(player: Player)
	local folder = workspace:FindFirstChild("Deski")
	if not folder then return end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			mountPlayer(player, child :: Model)
			return
		end
	end
end)

DeskMount.OnServerEvent:Connect(function(player: Player, board: Instance?)
	if board and board:IsA("Model") then
		mountPlayer(player, board :: Model)
	else
		-- R bez proximity prompt — znajdź pierwszą deskę
		local folder = workspace:FindFirstChild("Deski")
		if not folder then return end
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				mountPlayer(player, child :: Model)
				return
			end
		end
	end
end)

DeskDismount.OnServerEvent:Connect(function(player: Player)
	dismountPlayer(player)
end)

Players.PlayerRemoving:Connect(dismountPlayer)

print("[DeskaService] Gotowy")
