-- PodiumService.luau
-- Podium top-3: 3 rigi (R15) z wczytanym skinem najlepszych graczy + animacja tańca.
-- Źródło rankingu = LeaderboardService.GetTop() (ta sama lista co tablica).
--
-- Mechanika podmiany "kto kogo przebił":
--   • co Config.Podium.RefreshSec czytamy top-3 i porównujemy userId na każdym miejscu
--     z tym co aktualnie stoi (slotUid). Jeśli się różni → ApplyDescription nowego gracza.
--   • dzięki cache'owi NIE nakładamy skina co cykl (ApplyDescription yielduje), tylko przy zmianie.
--
-- Setup w Studio:
--   workspace.Podium (Model/Folder) → 3 rigi R15 z Humanoidem, nazwy zawierające 1/2/3
--   (np. Spot1/Spot2/Spot3). Ustaw HumanoidRootPart.Anchored = true i wypozycjonuj na podium.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

local cfg = Config.Podium or {}

local PodiumService = {}

-- ── Znajdź rigi podium ──────────────────────────────────────────────────────
type Slot = {
	model: Model,
	humanoid: Humanoid,
	baseCF: CFrame,
	groundY: number,     -- Y spodu riga w momencie startu (żeby po skalowaniu stopy zostały na podium)
	uid: number?,        -- aktualnie wczytany userId (cache)
	track: AnimationTrack?,
	loading: boolean,
}

local slots: { [number]: Slot } = {}  -- [1..3] = Slot

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

local function collectSlots()
	local folder = workspace:FindFirstChild(cfg.FolderName or "Podium")
	if not folder then
		warn(string.format("[PodiumService] Brak workspace.%s — podium nieaktywne", cfg.FolderName or "Podium"))
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
					local bb0, sz0 = child:GetBoundingBox()
					slots[n] = {
						model = child,
						humanoid = hum,
						baseCF = child:GetPivot(),
						groundY = bb0.Position.Y - sz0.Y / 2,  -- spód riga (stopy) przy skali z Studio
						uid = nil,
						track = nil,
						loading = false,
					}
				end
			end
		end
	end
	local count = 0
	for _ in pairs(slots) do count += 1 end
	if count == 0 then
		warn("[PodiumService] Nie znaleziono rigów (Model z Humanoidem, nazwa z cyfrą 1/2/3) w Podium")
		return false
	end
	print("[PodiumService] Znaleziono rigów:", count)
	return true
end

-- ── Animacja tańca (różna per miejsce) ───────────────────────────────────────
local function playDance(slot: Slot, rank: number)
	local hum = slot.humanoid
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	-- Zatrzymaj poprzedni track (po ApplyDescription rig mógł zresetować animacje)
	if slot.track then
		slot.track:Stop()
		slot.track = nil
	end
	local animId = (cfg.DanceAnimIds and cfg.DanceAnimIds[rank]) or cfg.DanceAnimId or "rbxassetid://507771019"
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
		slot.track = track
	else
		warn("[PodiumService] Nie udało się załadować animacji tańca:", track)
	end
end

-- ── Name tag (billboard) ─────────────────────────────────────────────────────
local function setNameTag(slot: Slot, rank: number, name: string)
	if not cfg.ShowNameTag then return end
	local head = slot.model:FindFirstChild("Head") or getPrimary(slot.model)
	if not head then return end
	local bb = head:FindFirstChild("PodiumTag")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "PodiumTag"
		bb.Size = UDim2.fromOffset(220, 60)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 120
		bb.Parent = head
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Lbl"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
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

-- ── Wczytanie gracza na riga ─────────────────────────────────────────────────
local function applyUser(slot: Slot, rank: number, uid: number)
	if slot.loading then return end
	slot.loading = true
	task.spawn(function()
		local scale = (cfg.Scales and cfg.Scales[rank]) or 1
		local okDesc, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(uid)
		end)
		if okDesc and desc then
			-- Uniform scale przez HumanoidDescription (nakładany razem ze skinem)
			desc.HeightScale = scale
			desc.WidthScale  = scale
			desc.DepthScale  = scale
			desc.HeadScale   = scale
			local okApply = pcall(function()
				slot.humanoid:ApplyDescription(desc)
			end)
			if not okApply then
				warn("[PodiumService] ApplyDescription nieudane dla uid", uid)
			end
		else
			warn("[PodiumService] GetHumanoidDescriptionFromUserId nieudane dla uid", uid)
		end
		-- ApplyDescription/skala mogły przesunąć riga — przywróć XZ z baseCF i podnieś tak,
		-- żeby stopy zostały na poziomie groundY (inaczej powiększony rig zapada się w podium).
		local prim = getPrimary(slot.model)
		if prim then
			slot.model:PivotTo(slot.baseCF)
			local bb, sz = slot.model:GetBoundingBox()
			local bottom = bb.Position.Y - sz.Y / 2
			slot.model:PivotTo(slot.baseCF + Vector3.new(0, slot.groundY - bottom, 0))
			prim.Anchored = true
		end
		-- nick
		local okName, name = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
		setNameTag(slot, rank, (okName and name) or ("User" .. uid))
		playDance(slot, rank)
		slot.uid = uid
		slot.loading = false
	end)
end

local function clearSlot(slot: Slot, rank: number)
	-- Brak gracza na tym miejscu — zostaw riga, ale wyczyść tag
	slot.uid = nil
	setNameTag(slot, rank, "—")
end

-- ── Pętla odświeżania ────────────────────────────────────────────────────────
local function refresh()
	local top = LeaderboardService.GetTop()  -- { {uid, value}, ... } posortowane malejąco
	for rank = 1, 3 do
		local slot = slots[rank]
		if slot then
			local entry = top[rank]
			local uid = entry and entry.uid or nil
			if uid then
				if slot.uid ~= uid then
					applyUser(slot, rank, uid)  -- ktoś nowy na tym miejscu → podmień skin
				end
			else
				if slot.uid ~= nil then clearSlot(slot, rank) end
			end
		end
	end
end

-- ── Setup ────────────────────────────────────────────────────────────────────
task.spawn(function()
	-- Poczekaj aż rigi i ranking będą gotowe
	for _ = 1, 30 do
		if workspace:FindFirstChild(cfg.FolderName or "Podium") then break end
		task.wait(1)
	end
	if not collectSlots() then return end

	-- Pierwsze odświeżenie po krótkim czasie (żeby LeaderboardService zdążył pobrać top)
	task.wait(5)
	while true do
		pcall(refresh)
		task.wait(cfg.RefreshSec or 10)
	end
end)

print("[PodiumService] gotowy")
return PodiumService
