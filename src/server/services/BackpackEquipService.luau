-- BackpackEquipService.luau
-- Zakłada Accessory plecaka na postać w zależności od data.BackpackLevel.
-- Konwencja: ReplicatedStorage.BackpackModels.Level<N> — Accessory.
-- Opcjonalne atrybuty (na Accessory ALBO na BasePart w środku):
--   BackOffset   (Vector3, studs)   — offset pozycji względem UpperTorso
--   BackRotation (Vector3, stopnie) — rotacja wokół UpperTorso (0,180,0 = flip z brzucha na plecy)
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService:WaitForChild("PlayerDataService"))

local BackpackEquipService = {}

local EQUIP_TAG = "__BackpackEquipped"   -- attribute na sklonowanym obiekcie do cleanup'u

local function getModelsFolder(): Folder?
	local f = ReplicatedStorage:FindFirstChild("BackpackModels")
	return (f and f:IsA("Folder")) and f or nil
end

local function clearOldEquip(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:GetAttribute(EQUIP_TAG) then
			d:Destroy()
		end
	end
end

local function isWelded(part: BasePart): boolean
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("Weld") or c:IsA("WeldConstraint") or c:IsA("Motor6D") then
			return true
		end
	end
	return false
end

local function findFirstBasePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then return inst :: BasePart end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

local function findCharacterAttachment(character: Model, accAttName: string): (Attachment?, BasePart?)
	-- 1) exact match po nazwie attachmentu w całej postaci
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Attachment") and d.Name == accAttName and d.Parent and d.Parent:IsA("BasePart") then
			return d :: Attachment, d.Parent :: BasePart
		end
	end
	-- 2) fuzzy: jeśli attachment z accessory zawiera "Back" — szukamy attachmentu z "Back" w nazwie na UpperTorso
	local lower = string.lower(accAttName)
	for _, candidate in ipairs({ "UpperTorso", "Torso" }) do
		local torso = character:FindFirstChild(candidate)
		if torso and torso:IsA("BasePart") then
			for _, c in ipairs(torso:GetChildren()) do
				if c:IsA("Attachment") then
					local cl = string.lower(c.Name)
					if string.find(cl, "back") and string.find(lower, "back") then
						return c :: Attachment, torso :: BasePart
					end
				end
			end
		end
	end
	return nil, nil
end

local function equipAccessory(character: Model, template: Accessory)
	local clone = template:Clone()
	clone:SetAttribute(EQUIP_TAG, true)

	local handle = findFirstBasePart(clone)
	if not handle then
		warn("[BackpackEquipService] Accessory", template.Name, "nie ma żadnego BasePart — pomijam")
		clone:Destroy()
		return
	end

	local accAtt = handle:FindFirstChildOfClass("Attachment")
	local charAtt, anchorPart = nil, nil
	if accAtt then
		charAtt, anchorPart = findCharacterAttachment(character, accAtt.Name)
	end
	if not anchorPart then
		anchorPart = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if not (anchorPart and anchorPart:IsA("BasePart")) then
			warn("[BackpackEquipService] Brak UpperTorso/Torso — nie mogę założyć", template.Name)
			clone:Destroy()
			return
		end
	end

	-- Przygotuj handle do welda
	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored   = false
			p.CanCollide = false
			p.Massless   = true
			p.CastShadow = false
		end
	end

	clone.Parent = character

	-- Pozycjonowanie: attachment-to-attachment jeśli mamy oba, inaczej offset z atrybutu
	-- Atrybut może siedzieć na Accessory ALBO na BasePart w środku (user-friendly fallback)
	local function readAttr(name: string)
		local v = clone:GetAttribute(name)
		if v == nil and handle then v = handle:GetAttribute(name) end
		return v
	end
	local offsetPos = readAttr("BackOffset")
	local offsetRot = readAttr("BackRotation")
	if typeof(offsetPos) ~= "Vector3" then offsetPos = Vector3.new(0, 0, 0.6) end
	if typeof(offsetRot) ~= "Vector3" then offsetRot = Vector3.new(0, 0, 0) end

	local hasUserOffset = (readAttr("BackOffset") ~= nil) or (readAttr("BackRotation") ~= nil)
	print(string.format("[BackpackEquipService] %s: hasUserOffset=%s offset=%s rot=%s accAtt=%s charAtt=%s",
		template.Name, tostring(hasUserOffset), tostring(offsetPos), tostring(offsetRot),
		accAtt and accAtt.Name or "nil", charAtt and charAtt.Name or "nil"))

	local rotCF    = CFrame.fromOrientation(math.rad(offsetRot.X), math.rad(offsetRot.Y), math.rad(offsetRot.Z))
	local offsetCF = CFrame.new(offsetPos)

	local targetCFrame
	if accAtt and charAtt then
		-- Krok 1: wyrównaj attachmenty (standard Roblox)
		local aligned = charAtt.WorldCFrame * accAtt.CFrame:Inverse()
		-- Krok 2: korekta w lokalnej przestrzeni UpperTorso — rotacja kręci wokół środka torsa,
		-- offset przesuwa względem orientacji torsa. Tak `BackRotation = (0,180,0)` GWARANTUJE flip z brzucha na plecy.
		local torsoCF  = (anchorPart :: BasePart).CFrame
		local localCF  = torsoCF:ToObjectSpace(aligned)
		localCF        = offsetCF * rotCF * localCF
		targetCFrame   = torsoCF * localCF
	else
		targetCFrame = (anchorPart :: BasePart).CFrame * offsetCF * rotCF
	end
	handle.CFrame = targetCFrame

	-- Reposition reszty modelu względem handla (zachowując ich oryginalne offsety)
	-- → niepotrzebne jeśli wszystko już jest spojone wewnętrznie w Accessory; ale na wszelki:
	-- (skipujemy, jeśli accessory ma tylko handle + Mesh, nie trzeba pivotować całości)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchorPart
	weld.Part1 = handle
	weld.Parent = handle
end

local function equipForLevel(character: Model, level: number)
	clearOldEquip(character)
	local folder = getModelsFolder()
	if not folder then return end
	local template = folder:FindFirstChild("Level" .. tostring(level))
	if not template then return end  -- brak templatu dla tego poziomu — cicho pomijamy

	if template:IsA("Accessory") then
		equipAccessory(character, template)
	else
		warn("[BackpackEquipService] Level", level, "ma nieobsługiwany typ (oczekiwano Accessory):", template.ClassName)
	end
end

function BackpackEquipService.Refresh(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local data = PlayerDataService.GetData(player)
	equipForLevel(char, data.BackpackLevel or 1)
end

local function onCharacter(player: Player, character: Model)
	-- Czekamy aż Humanoid + UpperTorso się zreplikują
	character:WaitForChild("Humanoid", 5)
	character:WaitForChild("UpperTorso", 5)
	task.wait(0.2)
	local data = PlayerDataService.GetData(player)
	equipForLevel(character, data.BackpackLevel or 1)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(char) onCharacter(p, char) end)
	if p.Character then task.spawn(onCharacter, p, p.Character) end
end

return BackpackEquipService
