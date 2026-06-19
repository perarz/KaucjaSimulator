-- IntroService.luau
-- Rejestruje KeyframeSequence z ServerStorage.RBX_ANIMSAVES i tworzy
-- gotowe Animation w ReplicatedStorage.IntroAnims, żeby klient mógł je odtworzyć.

local ServerStorage           = game:GetService("ServerStorage")
local ReplicatedStorage       = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local IntroService = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

-- Rejestruje pojedynczą KeyframeSequence i wystawia Animation w ReplicatedStorage.IntroAnims
local function registerAnim(folderName: string, seqName: string, exportName: string)
	local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	if not saves then
		warn("[IntroService] Brak ServerStorage.RBX_ANIMSAVES")
		return
	end
	local npcFolder = saves:FindFirstChild(folderName)
	if not npcFolder then
		warn("[IntroService] Brak RBX_ANIMSAVES." .. folderName)
		return
	end
	local seq = npcFolder:FindFirstChild(seqName)
	if not seq or not seq:IsA("KeyframeSequence") then
		warn("[IntroService] Brak KeyframeSequence '" .. seqName .. "' w " .. folderName)
		return
	end

	local ok, idOrErr = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
	end)
	if not ok then
		warn("[IntroService] RegisterKeyframeSequence failed:", idOrErr)
		return
	end

	local animFolder = getOrCreateFolder(ReplicatedStorage, "IntroAnims")
	-- Usuń stary jeśli istnieje
	local existing = animFolder:FindFirstChild(exportName)
	if existing then existing:Destroy() end

	local anim = Instance.new("Animation")
	anim.Name        = exportName
	anim.AnimationId = idOrErr
	anim.Parent      = animFolder

	print("[IntroService] Zarejestrowano animację:", exportName, "→", idOrErr)
end

-- Aktualne animacje
registerAnim("Marcelk1122", "looting", "Looting")

-- ── Pierwsze wejście: trigger cutsceny tutorial ──────────────────────────

local Players              = game:GetService("Players")
local ServerScriptService  = game:GetService("ServerScriptService")
local PlayerDataService    = require(ServerScriptService.PlayerDataService)

local Events         = ReplicatedStorage:WaitForChild("Events")
local PlayIntro      = Events:WaitForChild("PlayIntro")
local IntroFinished  = Events:WaitForChild("IntroFinished")

local function checkAndFireIntro(player: Player)
	task.wait(2.5)  -- daj PlayerDataService czas na załadowanie
	if not player.Parent then return end
	local data = PlayerDataService.GetData(player)
	if not data then return end
	if not data.HasSeenIntro then
		PlayIntro:FireClient(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(checkAndFireIntro, player)
end)
-- Już obecni gracze (przy reloadzie skryptu w Studio)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(checkAndFireIntro, p)
end

IntroFinished.OnServerEvent:Connect(function(player)
	local data = PlayerDataService.GetData(player)
	if not data then return end
	if not data.HasSeenIntro then
		data.HasSeenIntro = true
		PlayerDataService.SaveData(player)
	end
end)

return IntroService
