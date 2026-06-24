-- ZoneEntryController.client.luau
-- Odbiera `ZoneOwnedUpdate` od serwera (mapa zoneKey → true) i dla każdego
-- posiadanego klucza ukrywa lokalnie model entry (visibility + CanCollide).
-- Strefa pozostaje fizycznie dla pozostałych graczy; tylko ten klient widzi
-- "puste przejście". Server-side prompt też lokalnie wyłączamy.
--
-- Tagi: serwer woła CollectionService:AddTag(entry, "ZoneEntry_<zoneKey>").

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Events            = ReplicatedStorage:WaitForChild("Events")
local ZoneOwnedUpdate   = Events:WaitForChild("ZoneOwnedUpdate")

local owned: { [string]: boolean } = {}
local appliedParts: { [BasePart]: { trans: number, coll: boolean } } = {}
local updateGuide  -- forward declaration (VFX naprowadzający na entry Pustyni przy queście fabularnym)

local function setHidden(part: BasePart, hidden: boolean)
	if hidden then
		if not appliedParts[part] then
			appliedParts[part] = { trans = part.LocalTransparencyModifier, coll = part.CanCollide }
		end
		part.LocalTransparencyModifier = 1
		part.CanCollide = false
	else
		local saved = appliedParts[part]
		if saved then
			part.LocalTransparencyModifier = saved.trans
			part.CanCollide                = saved.coll
			appliedParts[part] = nil
		end
	end
end

local function applyToEntry(entry: Instance, hidden: boolean)
	-- Wszystkie BaseParty w modelu → ukryj / przywróć
	if entry:IsA("BasePart") then setHidden(entry, hidden) end
	for _, d in ipairs(entry:GetDescendants()) do
		if d:IsA("BasePart") then
			setHidden(d, hidden)
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = not hidden
		end
	end
end

local function refreshZone(zoneKey: string)
	local hidden = owned[zoneKey] == true
	for _, entry in ipairs(CollectionService:GetTagged("ZoneEntry_" .. zoneKey)) do
		applyToEntry(entry, hidden)
	end
end

ZoneOwnedUpdate.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then return end
	owned = {}
	for k, v in pairs(snapshot) do
		if v then owned[k] = true end
	end
	for zoneKey in pairs(Config.Zones or {}) do
		refreshZone(zoneKey)
	end
	if updateGuide then updateGuide() end
end)

-- Gdy serwer dotagguje entry po naszym init (lub respawn rebuilduje strefę) —
-- nasłuchuj nowych instancji i re-apply.
for zoneKey in pairs(Config.Zones or {}) do
	CollectionService:GetInstanceAddedSignal("ZoneEntry_" .. zoneKey):Connect(function(entry)
		if owned[zoneKey] then applyToEntry(entry, true) end
		if updateGuide then updateGuide() end
	end)
end

-- LocalTransparencyModifier ORAZ ProximityPrompt.Enabled mogą zostać zresetowane przez
-- Roblox dla edge-case'ów (zmiana kamery, respawn, ponowne wejście w zasięg promptu) —
-- przez to na kupionej (niewidocznej) bramie znów pokazywał się prompt "Kup wstęp", choć
-- nic tam już nie ma. Heartbeat re-apply (raz na sekundę) wymusza pełny stan ukrycia
-- (party + wyłączony prompt) dla posiadanych stref.
local lastReapply = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastReapply < 1.0 then return end
	lastReapply = now
	for zoneKey in pairs(owned) do
		for _, entry in ipairs(CollectionService:GetTagged("ZoneEntry_" .. zoneKey)) do
			if entry:IsA("BasePart") and entry.LocalTransparencyModifier < 1 then
				setHidden(entry, true)
			end
			for _, d in ipairs(entry:GetDescendants()) do
				if d:IsA("BasePart") and d.LocalTransparencyModifier < 1 then
					setHidden(d, true)
				elseif d:IsA("ProximityPrompt") and d.Enabled then
					d.Enabled = false
				end
			end
		end
	end
end)

-- ════════════════════════════════════════════════════════════════════════════
--  VFX naprowadzający na entry Pustyni — aktywny gdy gracz jest na queście
--  fabularnym "unlock_pustynia" i jeszcze nie odblokował strefy.
-- ════════════════════════════════════════════════════════════════════════════
local StoryQuestInit   = Events:WaitForChild("StoryQuestInit")
local StoryQuestUpdate = Events:WaitForChild("StoryQuestUpdate")

local GUIDE_QUEST_ID = "unlock_pustynia"
local GUIDE_ZONE     = "Pustynia"
local currentStoryId: string? = nil
local guide: { highlight: Highlight, billboard: BillboardGui, tweens: { Tween } }? = nil

local function entryAnchor(entry: Instance): BasePart?
	if entry:IsA("BasePart") then return entry end
	if entry:IsA("Model") and entry.PrimaryPart then return entry.PrimaryPart end
	return entry:FindFirstChildWhichIsA("BasePart", true)
end

local function destroyGuide()
	if not guide then return end
	for _, t in ipairs(guide.tweens) do pcall(function() t:Cancel() end) end
	if guide.highlight then guide.highlight:Destroy() end
	if guide.billboard then guide.billboard:Destroy() end
	guide = nil
end

local function buildGuide()
	if guide then return end
	local entry = CollectionService:GetTagged("ZoneEntry_" .. GUIDE_ZONE)[1]
	if not entry then return end
	local anchor = entryAnchor(entry)
	if not anchor then return end

	-- Highlight (poświata) na całym entry
	local hl = Instance.new("Highlight")
	hl.Adornee          = entry
	hl.FillColor        = Color3.fromRGB(239, 199, 95)
	hl.FillTransparency = 0.5
	hl.OutlineColor     = Color3.fromRGB(255, 240, 180)
	hl.OutlineTransparency = 0
	hl.DepthMode        = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent           = entry

	-- Strzałka + napis nad entry (widoczna przez ściany)
	local bb = Instance.new("BillboardGui")
	bb.Adornee      = anchor
	bb.Size         = UDim2.fromOffset(230, 130)
	bb.StudsOffset  = Vector3.new(0, anchor.Size.Y / 2 + 5, 0)
	bb.AlwaysOnTop  = true
	bb.MaxDistance  = 1000
	bb.LightInfluence = 0
	bb.Parent       = anchor

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(1, 0, 0, 70); arrow.Position = UDim2.fromOffset(0, 0)
	arrow.BackgroundTransparency = 1; arrow.Text = "⬇"; arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = false; arrow.TextSize = 64; arrow.TextColor3 = Color3.fromRGB(239, 199, 95)
	arrow.TextStrokeTransparency = 0.2; arrow.Parent = bb

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 44); label.Position = UDim2.fromOffset(0, 78)
	label.BackgroundColor3 = Color3.new(0, 0, 0); label.BackgroundTransparency = 0.25
	label.Text = "PUSTYNIA — TUTAJ"; label.Font = Enum.Font.GothamBlack
	label.TextSize = 22; label.TextColor3 = Color3.fromRGB(255, 240, 180)
	label.TextStrokeTransparency = 0.4; label.Parent = bb
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 8); lc.Parent = label

	-- Pulsowanie poświaty + bujanie strzałki
	local tweens = {}
	local pulse = TweenService:Create(hl,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.8 })
	pulse:Play(); table.insert(tweens, pulse)
	local baseOff = bb.StudsOffset
	local bob = TweenService:Create(bb,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = baseOff + Vector3.new(0, 1.4, 0) })
	bob:Play(); table.insert(tweens, bob)

	guide = { highlight = hl, billboard = bb, tweens = tweens }
end

updateGuide = function()
	local active = (currentStoryId == GUIDE_QUEST_ID) and (owned[GUIDE_ZONE] ~= true)
	if active then buildGuide() else destroyGuide() end
end

local function onStorySnapshot(s)
	if type(s) ~= "table" then return end
	currentStoryId = s.id  -- nil gdy chain ukończony
	updateGuide()
end
StoryQuestInit.OnClientEvent:Connect(onStorySnapshot)
StoryQuestUpdate.OnClientEvent:Connect(onStorySnapshot)
