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

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Events            = ReplicatedStorage:WaitForChild("Events")
local ZoneOwnedUpdate   = Events:WaitForChild("ZoneOwnedUpdate")

local owned: { [string]: boolean } = {}
local appliedParts: { [BasePart]: { trans: number, coll: boolean } } = {}

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
end)

-- Gdy serwer dotagguje entry po naszym init (lub respawn rebuilduje strefę) —
-- nasłuchuj nowych instancji i re-apply.
for zoneKey in pairs(Config.Zones or {}) do
	CollectionService:GetInstanceAddedSignal("ZoneEntry_" .. zoneKey):Connect(function(entry)
		if owned[zoneKey] then applyToEntry(entry, true) end
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
