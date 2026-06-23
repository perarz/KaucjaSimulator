-- UpgradeService.luau
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage.Config)
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local QuestService      = require(ServerScriptService.QuestService)

local UpgradeService = {}

local Events          = ReplicatedStorage:WaitForChild("Events")
local BuySkillUpgrade = Events:WaitForChild("BuySkillUpgrade")
local SkillTreeUpdate = Events:WaitForChild("SkillTreeUpdate")

local UPGRADE_META = {
	Speed = {
		levelKey = "SpeedLevel",
		table    = Config.SpeedUpgrades,
		apply    = function(player: Player, level: number)
			if level < 1 then return end
			local char = player.Character
			if not char then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = Config.SpeedUpgrades[level].Speed
			end
		end,
	},
	Multiplier = {
		levelKey = "MultiplierLevel",
		table    = Config.MultiplierUpgrades,
		apply    = function(_player: Player, _level: number)
			-- mnożnik aplikowany przy EmptyBackpack
		end,
	},
}

local function deductCost(data: { [string]: any }, cost: number, costType: string): boolean
	if costType == "Zlotowki" then
		if data.Zlotowki < cost then return false end
		data.Zlotowki -= cost
		return true
	end
	return false
end

local function applySpeedOnSpawn(player: Player)
	local function setSpeed()
		local d = PlayerDataService.GetData(player)
		local char = player.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local speedLevel = d.SpeedLevel or 0
		if speedLevel > 0 then
			hum.WalkSpeed = Config.SpeedUpgrades[speedLevel].Speed
		end
	end
	setSpeed()
	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		setSpeed()
	end)
end

Players.PlayerAdded:Connect(function(player: Player)
	task.wait(1)
	applySpeedOnSpawn(player)
end)

BuySkillUpgrade.OnServerEvent:Connect(function(player: Player, upgradeType: string, targetLevel: number)
	local data = PlayerDataService.GetData(player)

	-- ── Węzeł bazowy (Fundament) ────────────────────────────────────────
	if upgradeType == "Base" then
		if (data.BaseLevel or 0) >= 1 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "already" })
			return
		end
		if not deductCost(data, Config.BaseUpgrade.Cost, Config.BaseUpgrade.CostType) then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "broke" })
			return
		end
		data.BaseLevel = 1
		PlayerDataService.UpdateLeaderstats(player)
		QuestService.AddProgress(player, "buy_skill", { amount = 1 })
		pcall(function()
			local sqs = require(script.Parent.StoryQuestService)
			sqs.AddProgress(player, "buy_skill", 1)
		end)
		SkillTreeUpdate:FireClient(player, {
			success     = true,
			upgradeType = "Base",
			newLevel    = 1,
		})
		return
	end

	-- ── Szczęście (odnoga Luck — single-level, wymaga MultiplierLevel >= 2) ──
	if upgradeType == "Luck" then
		if (data.BaseLevel or 0) < 1 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "needBase" })
			return
		end
		if (data.MultiplierLevel or 0) < 2 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "needMult2" })
			return
		end
		if (data.LuckLevel or 0) >= 1 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "already" })
			return
		end
		if not deductCost(data, Config.LuckUpgrade.Cost, Config.LuckUpgrade.CostType) then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "broke" })
			return
		end
		data.LuckLevel = 1
		PlayerDataService.UpdateLeaderstats(player)
		QuestService.AddProgress(player, "buy_skill", { amount = 1 })
		pcall(function()
			local sqs = require(script.Parent.StoryQuestService)
			sqs.AddProgress(player, "buy_skill", 1)
		end)
		SkillTreeUpdate:FireClient(player, {
			success     = true,
			upgradeType = "Luck",
			newLevel    = 1,
		})
		return
	end

	-- ── Wytrzymałość (odnoga Stamina — single-level, wymaga SpeedLevel >= 2) ──
	if upgradeType == "Stamina" then
		if (data.BaseLevel or 0) < 1 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "needBase" })
			return
		end
		if (data.SpeedLevel or 0) < 2 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "needSpeed2" })
			return
		end
		if (data.StaminaLevel or 0) >= 1 then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "already" })
			return
		end
		if not deductCost(data, Config.StaminaUpgrade.Cost, Config.StaminaUpgrade.CostType) then
			SkillTreeUpdate:FireClient(player, { success = false, reason = "broke" })
			return
		end
		data.StaminaLevel = 1
		PlayerDataService.UpdateLeaderstats(player)
		QuestService.AddProgress(player, "buy_skill", { amount = 1 })
		pcall(function()
			local sqs = require(script.Parent.StoryQuestService)
			sqs.AddProgress(player, "buy_skill", 1)
		end)
		SkillTreeUpdate:FireClient(player, {
			success     = true,
			upgradeType = "Stamina",
			newLevel    = 1,
		})
		return
	end

	-- ── Gałęzie Speed / Multiplier ─────────────────────────────────────
	local meta = UPGRADE_META[upgradeType]
	if not meta then return end

	-- Wymagany Fundament
	if (data.BaseLevel or 0) < 1 then
		SkillTreeUpdate:FireClient(player, { success = false, reason = "needBase" })
		return
	end

	local currentLevel = data[meta.levelKey] or 0
	if targetLevel ~= currentLevel + 1 then return end

	local upgrades = meta.table
	if targetLevel > #upgrades then return end

	local upgradeInfo = upgrades[targetLevel]
	if not deductCost(data, upgradeInfo.Cost, upgradeInfo.CostType) then
		SkillTreeUpdate:FireClient(player, { success = false, reason = "broke" })
		return
	end

	data[meta.levelKey] = targetLevel
	meta.apply(player, targetLevel)
	PlayerDataService.UpdateLeaderstats(player)
	QuestService.AddProgress(player, "buy_skill", { amount = 1 })
	pcall(function()
		local sqs = require(script.Parent.StoryQuestService)
		sqs.AddProgress(player, "buy_skill", 1)
	end)

	SkillTreeUpdate:FireClient(player, {
		success     = true,
		upgradeType = upgradeType,
		newLevel    = targetLevel,
	})
end)

return UpgradeService
