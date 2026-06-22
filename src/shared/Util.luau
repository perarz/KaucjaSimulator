-- Util.luau
-- Wspólne helpery używane przez wiele serwisów.
-- Single source of truth — gdy zmienia się logika (np. nowy item zajmujący slot),
-- aktualizujesz tylko tu, a nie 4 razy w różnych plikach.

local Util = {}

-- Priorytet anchor'a do ProximityPrompt: Head > HumanoidRootPart > UpperTorso/Torso > PrimaryPart > dowolny BasePart.
-- Akceptuje Instance (Model lub BasePart). Zwraca nil gdy nie ma żadnego BasePart.
function Util.findAnchor(model: Instance): BasePart?
	if model:IsA("BasePart") then return model :: BasePart end
	if not model:IsA("Model") then return nil end
	for _, name in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "Torso" }) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p :: BasePart end
	end
	local pp = (model :: Model).PrimaryPart
	if pp then return pp end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

-- Liczba zajętych slotów plecaka gracza. Suma: butelki + syrop (1) + magnesy + pety.
-- WAŻNE: gdy dodajesz nowy item zajmujący slot, aktualizuj WYŁĄCZNIE tutaj.
function Util.getCarriedCount(data: { [string]: any }): number
	local n = 0
	if data.BackpackContents then
		for _, c in pairs(data.BackpackContents) do n += c end
	end
	if data.Grandpa and data.Grandpa.hasSyrup then n += 1 end
	n += data.MagnetCount or 0
	n += #(data.Pets or {})
	return n
end

-- Liczba butelek w plecaku (suma BackpackContents). Syrop NIE wlicza się (item questowy).
function Util.getBottleCount(data: { [string]: any }): number
	local n = 0
	if data.BackpackContents then
		for _, c in pairs(data.BackpackContents) do n += c end
	end
	return n
end

-- Liczba petów w plecaku (EQ, nie skarbiec).
function Util.getPetCount(data: { [string]: any }): number
	return #(data.Pets or {})
end

-- Liczba akcesoriów w plecaku — obecnie tylko magnesy (syrop to item questowy, nie liczy się).
function Util.getAccessoryCount(data: { [string]: any }): number
	return data.MagnetCount or 0
end

-- Podział pojemności plecaka na kategorie wg Config.BackpackCategorySplit.
-- Zaokrąglenie deterministyczne: bottles=floor(0.7*cap), pets=floor(0.2*cap),
-- accessories=cap-bottles-pets → suma zawsze == totalCapacity (zero "zgubionych" slotów).
-- Single source of truth — klient (EQ layout/licznik) i serwer (blokady) liczą identycznie.
function Util.getCategoryCaps(totalCapacity: number, split: { bottles: number, pets: number, accessories: number }): { bottles: number, pets: number, accessories: number }
	local cap = math.max(0, math.floor(totalCapacity or 0))
	local bottles = math.floor(cap * split.bottles)
	local pets    = math.floor(cap * split.pets)
	local accessories = cap - bottles - pets
	return { bottles = bottles, pets = pets, accessories = accessories }
end

-- Rekurencyjny shallow-by-value deepCopy tabel.
function Util.deepCopy(t: { [any]: any }): { [any]: any }
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = (type(v) == "table") and Util.deepCopy(v) or v
	end
	return copy
end

return Util
