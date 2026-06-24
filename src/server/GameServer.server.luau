-- GameServer.luau
-- Entry point serwera — bootstrapuje wszystkie serwisy
require(script.Parent.PlayerDataService)
require(script.Parent.QuestService)        -- przed wszystkimi co go używają
require(script.Parent.StoryQuestService)   -- linia fabularna; hooki w BottleService/UpgradeService/ShopService/GrandpaService
require(script.Parent.BottleService)
require(script.Parent.UpgradeService)
require(script.Parent.ShopService)
require(script.Parent.LeaderboardService)
require(script.Parent.KoszService)
require(script.Parent.IntroService)
-- SyrupService musi być przed GrandpaService (GrandpaService używa go w hooku Accept)
require(script.Parent.SyrupService)
require(script.Parent.GrandpaService)
require(script.Parent.BankService)
require(script.Parent.CodeService)
require(script.Parent.BackpackEquipService)
require(script.Parent.PvPService)
require(script.Parent.HatShopService)
require(script.Parent.DeathDropService)
require(script.Parent.AdminService)
require(script.Parent.BoostShopService)
require(script.Parent.MagnetService)
require(script.Parent.ZabkaService)
require(script.Parent.PetService)
require(script.Parent.GoldPetService)          -- ulepszanie peta na złotego (rig steve10die)
require(script.Parent.StatsService)            -- panel STATS (snapshot statystyk z DataStore)
require(script.Parent.PodiumService)           -- podium top-3 (rigi ze skinem + taniec)
require(script.Parent.TeleportService)         -- teleportacja do stref mapy
require(script.Parent.ZoneEntryService)        -- bramki Kup-wstęp do stref (Pustynia)
require(script.Parent.TradeService)            -- wymiana gracz↔gracz (pety + kasa)
require(script.Parent.PetSlotShopService)      -- NPC Poland: 1→2 sloty na pety za 7000 zł + 10 Mit
require(script.Parent.PlayerCollisionService)  -- gracze przechodzą przez siebie (brak kolizji)
-- DeskaService to standalone Script (.server.luau) — uruchamia się sam,
-- NIE wymagaj go tutaj (require na Script rzuca "invalid argument").
