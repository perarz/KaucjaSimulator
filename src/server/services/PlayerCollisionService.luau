-- PlayerCollisionService.luau
-- Wyłącza kolizje między graczami — postacie mogą przechodzić przez siebie.
-- Standardowe podejście Roblox: collision group "Players" nie-kolidująca sama ze sobą.
-- Walka PvP używa Humanoid:TakeDamage (nie kolizji fizycznych), więc to nie wpływa na miecz.
local Players        = game:GetService("Players")
local PhysicsService  = game:GetService("PhysicsService")

local GROUP = "Players"

-- Rejestracja grupy (idempotentnie — RegisterCollisionGroup rzuca gdy istnieje)
pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
		PhysicsService:RegisterCollisionGroup(GROUP)
	end
end)
-- Gracze nie kolidują między sobą (kolidują nadal z mapą = grupa "Default")
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)

local function applyToPart(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = GROUP
	end
end

local function setupCharacter(char: Model)
	-- Wszystkie obecne party + dokładane później (np. akcesoria, plecak)
	for _, d in ipairs(char:GetDescendants()) do
		applyToPart(d)
	end
	char.DescendantAdded:Connect(applyToPart)
end

local function onPlayer(player: Player)
	if player.Character then setupCharacter(player.Character) end
	player.CharacterAdded:Connect(setupCharacter)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end

print("[PlayerCollisionService] gotowy — gracze przechodzą przez siebie")
return {}
