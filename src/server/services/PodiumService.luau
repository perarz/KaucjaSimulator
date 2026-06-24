-- PodiumService.luau
-- Dwa podia top-3 (rigi R15 ze skinem najlepszych graczy + taniec):
--   • workspace.Podium       — top wg PIENIĘDZY (LeaderboardService.GetTopMoney)
--   • workspace.PodiumKilli   — top wg ELIMINACJI (LeaderboardService.GetTopKills)
-- Oba: rigi nazwane z cyfrą 1/2/3, HumanoidRootPart anchored. Co RefreshSec diff userId
-- → przy zmianie ApplyDescription (skin) + skala (Config.Podium.Scales) + taniec + name tag.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config             = require(ReplicatedStorage:WaitForChild("Config"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

local cfg = Config.Podium or {}

local PodiumService = {}

type Slot = {
	model: Model,
	humanoid: Humanoid,
	baseCF: CFrame,
	groundY: number,
	uid: number?,
	track: AnimationTrack?,
	loading: boolean,
}

-- ── Helpery ───────────────────────────────────────────────────────────────
local function digitInName(name: string): number?
	local d = string.match(name, "(%d)")
	return d and tonumber(d) or nil
end

local function getPrimary(model: Model): BasePart?
	if model.PrimaryPart then return model.PrimaryPart end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp :: BasePart end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

local function playDance(slot: Slot, rank: number)
	local hum = slot.humanoid
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = hum end
	if slot.track then slot.track:Stop(); slot.track = nil end
	local animId = (cfg.DanceAnimIds and cfg.DanceAnimIds[rank]) or cfg.DanceAnimId or "rbxassetid://507771019"
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
		slot.track = track
	else
		warn("[PodiumService] Nie udało się załadować animacji tańca:", track)
	end
end

local function setNameTag(slot: Slot, rank: number, name: string)
	if not cfg.ShowNameTag then return end
	local head = slot.model:FindFirstChild("Head") or getPrimary(slot.model)
	if not head then return end
	local bb = head:FindFirstChild("PodiumTag")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "PodiumTag"
		bb.Size = UDim2.fromOffset(120, 26)
		bb.StudsOffset = Vector3.new(0, 3.5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 120
		bb.Parent = head
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Lbl"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = false
		lbl.TextSize = 18
		lbl.TextStrokeTransparency = 0.4
		lbl.Parent = bb
	end
	local lbl = bb:FindFirstChild("Lbl") :: TextLabel
	local rankColor = (rank == 1 and Color3.fromRGB(255, 200, 70))
		or (rank == 2 and Color3.fromRGB(205, 210, 225))
		or Color3.fromRGB(210, 140, 80)
	lbl.Text = string.format("#%d  %s", rank, name)
	lbl.TextColor3 = rankColor
end

local function applyUser(slot: Slot, rank: number, uid: number)
	if slot.loading then return end
	slot.loading = true
	task.spawn(function()
		local scale = (cfg.Scales and cfg.Scales[rank]) or 1
		local okDesc, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(uid)
		end)
		if okDesc and desc then
			desc.HeightScale = scale
			desc.WidthScale  = scale
			desc.DepthScale  = scale
			desc.HeadScale   = scale
			local okApply = pcall(function() slot.humanoid:ApplyDescription(desc) end)
			if not okApply then warn("[PodiumService] ApplyDescription nieudane dla uid", uid) end
		else
			warn("[PodiumService] GetHumanoidDescriptionFromUserId nieudane dla uid", uid)
		end
		-- przywróć XZ + podnieś tak, by stopy zostały na poziomie groundY (po skalowaniu)
		local prim = getPrimary(slot.model)
		if prim then
			slot.model:PivotTo(slot.baseCF)
			local bb, sz = slot.model:GetBoundingBox()
			local bottom = bb.Position.Y - sz.Y / 2
			slot.model:PivotTo(slot.baseCF + Vector3.new(0, slot.groundY - bottom, 0))
			prim.Anchored = true
		end
		local okName, name = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
		setNameTag(slot, rank, (okName and name) or ("User" .. uid))
		playDance(slot, rank)
		slot.uid = uid
		slot.loading = false
	end)
end

local function clearSlot(slot: Slot, rank: number)
	slot.uid = nil
	setNameTag(slot, rank, "—")
end

-- ── Pojedyncze podium ────────────────────────────────────────────────────────
local function makePodium(folderName: string, getTop: () -> { { uid: number, value: number } })
	local slots: { [number]: Slot } = {}

	local function collect(): boolean
		local folder = workspace:FindFirstChild(folderName)
		if not folder then
			warn(string.format("[PodiumService] Brak workspace.%s — podium nieaktywne", folderName))
			return false
		end
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") then
				local hum = child:FindFirstChildOfClass("Humanoid")
				local n = digitInName(child.Name)
				if hum and n and n >= 1 and n <= 3 and not slots[n] then
					local prim = getPrimary(child)
					if prim then
						if not child.PrimaryPart then child.PrimaryPart = prim end
						hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
						hum.HealthDisplayDistance = 0
						hum.NameDisplayDistance = 0
						local bb0, sz0 = child:GetBoundingBox()
						slots[n] = {
							model = child, humanoid = hum,
							baseCF = child:GetPivot(),
							groundY = bb0.Position.Y - sz0.Y / 2,
							uid = nil, track = nil, loading = false,
						}
					end
				end
			end
		end
		local count = 0
		for _ in pairs(slots) do count += 1 end
		if count == 0 then
			warn(string.format("[PodiumService] %s: brak rigów (Model+Humanoid, nazwa z cyfrą 1/2/3)", folderName))
			return false
		end
		print(string.format("[PodiumService] %s — rigów: %d", folderName, count))
		return true
	end

	local function refresh()
		local top = getTop()
		for rank = 1, 3 do
			local slot = slots[rank]
			if slot then
				local entry = top[rank]
				local uid = entry and entry.uid or nil
				if uid then
					if slot.uid ~= uid then applyUser(slot, rank, uid) end
				else
					if slot.uid ~= nil then clearSlot(slot, rank) end
				end
			end
		end
	end

	task.spawn(function()
		for _ = 1, 30 do
			if workspace:FindFirstChild(folderName) then break end
			task.wait(1)
		end
		if not collect() then return end
		task.wait(5)  -- daj LeaderboardService czas pobrać top
		while true do
			pcall(refresh)
			task.wait(cfg.RefreshSec or 10)
		end
	end)
end

-- ── Start obu podiów ─────────────────────────────────────────────────────────
makePodium(cfg.FolderName or "Podium", LeaderboardService.GetTopMoney)
makePodium(cfg.KillsFolderName or "PodiumKilli", LeaderboardService.GetTopKills)

print("[PodiumService] gotowy")
return PodiumService
