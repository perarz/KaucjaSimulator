-- CodeService.luau
-- Walidacja kodów promocyjnych z Ustawień. Kod = uppercase string z Config.Codes.
-- Każdy kod jednorazowy per gracz (zapisywany w data.RedeemedCodes[codeKey]).
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local PlayerDataService = require(script.Parent.PlayerDataService)

local Events           = ReplicatedStorage:WaitForChild("Events")
local RedeemCode       = Events:WaitForChild("RedeemCode")
local RedeemCodeResult = Events:WaitForChild("RedeemCodeResult")

-- Anti-spam: max 1 próba na 0.5s na gracza
local lastAttempt: { [Player]: number } = {}
local THROTTLE_SEC = 0.5

RedeemCode.OnServerEvent:Connect(function(player: Player, rawCode: any)
	if type(rawCode) ~= "string" then
		RedeemCodeResult:FireClient(player, { success = false, reason = "invalid" })
		return
	end

	local now = os.clock()
	if lastAttempt[player] and now - lastAttempt[player] < THROTTLE_SEC then
		RedeemCodeResult:FireClient(player, { success = false, reason = "throttle" })
		return
	end
	lastAttempt[player] = now

	local code = string.upper(string.gsub(rawCode, "%s", ""))
	if #code == 0 or #code > 32 then
		RedeemCodeResult:FireClient(player, { success = false, reason = "invalid" })
		return
	end

	local entry = Config.Codes and Config.Codes[code]
	if not entry then
		RedeemCodeResult:FireClient(player, { success = false, reason = "unknown" })
		return
	end

	local data = PlayerDataService.GetData(player)
	if data.RedeemedCodes and data.RedeemedCodes[code] then
		RedeemCodeResult:FireClient(player, { success = false, reason = "alreadyUsed" })
		return
	end

	local reward = tonumber(entry.reward) or 0
	if reward <= 0 then
		RedeemCodeResult:FireClient(player, { success = false, reason = "invalid" })
		return
	end

	data.RedeemedCodes = data.RedeemedCodes or {}
	data.RedeemedCodes[code] = true
	data.Zlotowki = (data.Zlotowki or 0) + reward
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.SaveData(player)

	RedeemCodeResult:FireClient(player, { success = true, code = code, reward = reward })
end)

Players.PlayerRemoving:Connect(function(p) lastAttempt[p] = nil end)

return {}
