-- Config.luau
return {
	-- Lista adminów (nazwy Roblox lub UserId). Klawisz F2 otwiera panel admina.
	Admins = {
		463763381, -- PROGGam3r (UserId — odporne na rename)
		"PROGGam3r", -- nazwa jako fallback
		2802364954, -- nowy admin
	},

	-- Boost shop: Developer Products w Robux
	BoostShop = {
		DoubleEarn = {
			ProductId = 3605052667,
			DurationSec = 600, -- 10 minut
			Multiplier = 2,
			Name = "x2 KASA z butelkomatu",
			PriceRobux = 19, -- info-only (real price jest w Roblox dashboard)
		},
	},

	-- Deski (skateboardy) — kupowane przy gablotach (workspace.Gabloty.Gablota1..4),
	-- jeżdżone po naciśnięciu R. Każda deska to model w workspace.Deski o nazwie `model`.
	-- Kolejność w tablicy = ranking prędkości (ostatnia = najszybsza = "najlepsza" przy R).
	-- gablota = numer gabloty która sprzedaje tę deskę (Gablota1 → Default, itd.)
	-- Default/Red/Blue płatne w złotówkach; VIP w Robux (Developer Product).
	Decks = {
		{
			key = "Default",
			name = "Deska Default",
			model = "DeskaDefault",
			Speed = 40,
			CostType = "Zlotowki",
			Cost = 1000,
			gablota = 1,
			color = Color3.fromRGB(190, 190, 190),
		},
		{
			key = "Red",
			name = "Deska Red",
			model = "DeskaRed",
			Speed = 48,
			CostType = "Zlotowki",
			Cost = 3000,
			gablota = 2,
			color = Color3.fromRGB(205, 70, 70),
		},
		{
			key = "Blue",
			name = "Deska Blue",
			model = "DeskaBlue",
			Speed = 56,
			CostType = "Zlotowki",
			Cost = 5000,
			gablota = 3,
			color = Color3.fromRGB(70, 120, 205),
		},
		{
			key = "VIP",
			name = "Deska VIP",
			model = "DeskaVIP",
			Speed = 68,
			CostType = "Robux",
			RobuxProductId = 3605653942,
			RobuxPrice = 30,
			gablota = 4,
			color = Color3.fromRGB(230, 190, 60),
		},
	},
	-- WalkSpeed/JumpHeight przywracane po zejściu z deski
	DeckDismountWalkSpeed = 16,
	DeckDismountJumpHeight = 7.2,
	-- Ikona przycisku hoverboard (HUD) — otwiera menu desek
	DeckMenuIconId = "rbxassetid://123773463706470",

	-- Bank: bazowa pojemność + cena ulepszeń (przycisk ULEPSZ w UI banku).
	-- Każde ulepszenie daje +1 cap. Pierwsze kosztuje BaseCost, każde następne +CostStep.
	-- L0 = 10, L1 = 11 (cost 1000), L2 = 12 (cost 1500), L3 = 13 (cost 2000), ...
	Bank = {
		BaseCapacity = 10,
		UpgradeBaseCost = 1000,
		UpgradeCostStep = 500,
	},

	-- Sklep czapek (workspace.SKLEP2.Cashier) — jednorazowy zakup permanentnej czapki z bonusami
	HatShop = {
		ItemName = "Czapka",
		Template = "Czapka", -- ReplicatedStorage.Czapka (Accessory)
		CostZl = 5000,
		CostBottles = { Legendarna = 10, Mityczny = 1 },
		HpBonus = 50, -- doliczane do Humanoid.MaxHealth
		StaminaBonus = 50, -- doliczane do SprintController.STAMINA_MAX
		SpeedBonus = 2, -- doliczane do baseSpeed w SprintController
	},

	-- Kody promocyjne — wpisywane w Ustawieniach. Klucz = kod (uppercase), reward = zł.
	-- Każdy kod jednorazowy per gracz (zapisywany w data.RedeemedCodes).
	Codes = {
		OGDC = { reward = 200 },
		PVPOG = { reward = 500 },
		HOLYFINDER = { reward = 1000 },
		PARKOUR = { reward = 150 },
	},

	-- Wartości bazowe butelek (złotówki)
	-- REBALANS 2026: zmniejszone żeby spowolnić earn rate
	-- (top 1 robił 300k w 3h przy Mit=50 → teraz ~100k w 3h)
	BottleValues = {
		Zwykla = 1,
		Rzadka = 2,
		Epicka = 3, -- było 5
		Legendarna = 10, -- było 20
		Mityczny = 25, -- było 50
	},

	-- Szanse spawnu (sumują się do 1.0) — fallback gdy obszar nie ma tieru
	BottleSpawnChance = {
		Zwykla = 0.71,
		Rzadka = 0.20,
		Epicka = 0.08,
		Legendarna = 0.01,
		Mityczny = 0.00,
	},

	-- Szanse spawnu per tier obszaru. Tier brany z nazwy Partu w BottleSpawnAreas:
	-- pierwszy "T<liczba>" w nazwie (np. "T1_centrum", "T3_pustynia", "Las_T2").
	-- Brak "T?" w nazwie → tier 1.
	-- Każdy wiersz musi sumować się do 1.0.
	BottleSpawnChanceByTier = {
		[1] = { Zwykla = 0.85, Rzadka = 0.13, Epicka = 0.02, Legendarna = 0.00, Mityczny = 0.00 }, -- blisko spawna
		[2] = { Zwykla = 0.60, Rzadka = 0.28, Epicka = 0.11, Legendarna = 0.01, Mityczny = 0.00 }, -- średnio
		[3] = { Zwykla = 0.35, Rzadka = 0.35, Epicka = 0.25, Legendarna = 0.05, Mityczny = 0.00 }, -- daleko
		[4] = { Zwykla = 0.15, Rzadka = 0.30, Epicka = 0.40, Legendarna = 0.15, Mityczny = 0.00 }, -- endgame
		[5] = { Zwykla = 0.00, Rzadka = 0.00, Epicka = 0.50, Legendarna = 0.45, Mityczny = 0.05 }, -- mityczna strefa (Mit 5% — była 20%, prawdziwie rzadka)
	},

	BottleRespawnTime = 6,
	-- Gęstość butelek: ile butelek na 1 jednostkę powierzchni (X*Z) obszaru spawnu.
	-- 0.025 ≈ 1 butelka na 40 sq studs. Per-area target = max(MinBottlesPerArea, round(surf * density)).
	BottleDensity = 0.025,
	-- Minimum butelek na obszar — zapewnia że małe party też mają sens.
	MinBottlesPerArea = 3,
	-- Twardy limit zabezpieczający (na wypadek olbrzymich obszarów).
	MaxBottlesHardCap = 400,

	-- Event "Deszcz Legendarek" — przez 15s mapa pełna samych Legendarnych.
	-- Średnio raz na 5-10 min (losowy interwał).
	LegendaryEvent = {
		MinIntervalSec = 480, -- 8 min
		MaxIntervalSec = 720, -- 12 min
		DurationSec = 15,
		BottleCount = 30, -- ile legendarek zaspawnować na czas eventu
	},

	-- Kolory butelek
	BottleColors = {
		Zwykla = Color3.fromRGB(180, 180, 180),
		Rzadka = Color3.fromRGB(55, 138, 221),
		Epicka = Color3.fromRGB(127, 119, 221),
		Legendarna = Color3.fromRGB(239, 159, 39),
		Mityczny = Color3.fromRGB(120, 40, 180), -- deep purple — bazowy kolor (slotów/strokeów). Gradient fiolet↔czarny rysuje VFX w slotach
	},

	-- Węzeł bazowy — odblokuj najpierw, żeby mieć dostęp do gałęzi
	BaseUpgrade = {
		Cost = 50,
		CostType = "Zlotowki",
		Name = "Fundament",
	},

	-- Skill Tree: Prędkość (WalkSpeed)
	-- REBALANS: krzywa cen rośnie ostrzej w L3/L4 żeby endgame trwał dłużej
	SpeedUpgrades = {
		{ Level = 1, Speed = 19, Cost = 250, CostType = "Zlotowki", Name = "Trucht" },
		{ Level = 2, Speed = 22, Cost = 1500, CostType = "Zlotowki", Name = "Bieg" }, -- było 1200
		{ Level = 3, Speed = 26, Cost = 6000, CostType = "Zlotowki", Name = "Sprint" }, -- było 3500
		{ Level = 4, Speed = 30, Cost = 25000, CostType = "Zlotowki", Name = "Rakieta" }, -- było 8000  ← MAIN GATE
	},

	-- Skill Tree: Mnożnik kasy
	-- REBALANS: krzywa cen rośnie ostrzej w L3/L4 żeby endgame trwał dłużej
	MultiplierUpgrades = {
		{ Level = 1, Multiplier = 1.5, Cost = 250, CostType = "Zlotowki", Name = "Dobry Węch" },
		{ Level = 2, Multiplier = 2.0, Cost = 1500, CostType = "Zlotowki", Name = "Kaucyjny Zmysł" }, -- było 1200
		{ Level = 3, Multiplier = 2.2, Cost = 7000, CostType = "Zlotowki", Name = "Złoty Nos" }, -- było 3500
		{ Level = 4, Multiplier = 2.5, Cost = 30000, CostType = "Zlotowki", Name = "Legenda" }, -- było 8000  ← MAIN GATE
	},

	-- Skill Tree: Szczęście — odnoga od Multiplier L2 (wymaga MultiplierLevel >= 2)
	-- Single-level upgrade. Podwaja szanse na lepsze rzadkości w koszach (Rzadka, Epicka, Legendarna).
	LuckUpgrade = {
		Cost = 2000,
		CostType = "Zlotowki",
		Name = "Talizman Szczęścia",
		LuckMultiplier = 2, -- chances dla R/E/L × 2, Zwykla zmniejsza się proporcjonalnie
	},

	-- Sklep: Plecak (pojemność) — osobny sklep, NIE skill tree
	-- REBALANS: L4 droższy żeby był symbolem endgame'u
	BackpackUpgrades = {
		{ Level = 1, Capacity = 10, Cost = 0, CostType = "Zlotowki", Name = "Reklamówka" },
		{ Level = 2, Capacity = 25, Cost = 200, CostType = "Zlotowki", Name = "Plecak szkolny" },
		{ Level = 3, Capacity = 35, Cost = 900, CostType = "Zlotowki", Name = "Wielki worek" },
		{ Level = 4, Capacity = 50, Cost = 10000, CostType = "Zlotowki", Name = "Wózek sklepowy" }, -- było 2800
	},

	-- Kosz — wagi ilości dropu per rzadkość
	-- Format: { {count, weight}, ... } — wagi nie muszą sumować się do 100
	-- Zwykla zaczyna od 2 — pojedyncza butelka po 2s trzymania + ruletce jest za słaba
	KoszDropQuantity = {
		Zwykla = { { 2, 28 }, { 3, 32 }, { 4, 24 }, { 5, 16 } },
		Rzadka = { { 1, 25 }, { 2, 45 }, { 3, 25 }, { 4, 5 } },
		Epicka = { { 1, 50 }, { 2, 40 }, { 3, 10 } },
		Legendarna = { { 1, 100 } },
		Mityczny = { { 1, 100 } },
	},

	-- Leaderboard
	LeaderboardUpdateInterval = 60,
	LeaderboardMaxEntries = 10,

	-- Questy — 3 aktywne losowane z puli, refresh co X godzin
	QuestActiveCount = 3,
	QuestRefreshHours = 6,
	Quests = {
		{
			id = "collect_zwykla_30",
			desc = "Zbierz 30 Zwykłych butelek",
			kind = "collect",
			rarity = "Zwykla",
			target = 30,
			reward = { kind = "zl", amount = 75 },
		},
		{
			id = "collect_rzadka_15",
			desc = "Zbierz 15 Rzadkich butelek",
			kind = "collect",
			rarity = "Rzadka",
			target = 15,
			reward = { kind = "zl", amount = 160 },
		},
		{
			id = "collect_epicka_5",
			desc = "Zbierz 5 Epickich butelek",
			kind = "collect",
			rarity = "Epicka",
			target = 5,
			reward = { kind = "zl", amount = 250 },
		},
		{
			id = "collect_legendarna_1",
			desc = "Zbierz 1 Legendarną butelkę",
			kind = "collect",
			rarity = "Legendarna",
			target = 1,
			reward = { kind = "zl", amount = 300 },
		},
		{
			id = "collect_any_75",
			desc = "Zbierz 75 dowolnych butelek",
			kind = "collect_any",
			target = 75,
			reward = { kind = "zl", amount = 200 },
		},
		{
			id = "earn_500",
			desc = "Zarób 500 zł w butelkomacie",
			kind = "earn",
			target = 500,
			reward = { kind = "zl", amount = 160 },
		},
		{
			id = "earn_2000",
			desc = "Zarób 2000 zł w butelkomacie",
			kind = "earn",
			target = 2000,
			reward = { kind = "zl", amount = 300 },
		},
		{
			id = "search_kosz_8",
			desc = "Przeszukaj 8 koszy",
			kind = "search_kosz",
			target = 8,
			reward = { kind = "zl", amount = 220 },
		},
		{
			id = "empty_backpack_4",
			desc = "Opróżnij plecak 4 razy",
			kind = "empty_backpack",
			target = 4,
			reward = { kind = "zl", amount = 190 },
		},
		{
			id = "buy_skill_1",
			desc = "Kup 1 ulepszenie w drzewku",
			kind = "buy_skill",
			target = 1,
			reward = { kind = "zl", amount = 250 },
		},
	},

	-- Quest Dziadka (Grandpa) — narracyjny, jednorazowy
	-- Spawn pointy w workspace.SyrupSpawnPoints (Party: SyrupSpawn1, SyrupSpawn2, SyrupSpawn3)
	-- Dziadek = workspace.Grandpa (Model z HumanoidRootPart)
	GrandpaQuest = {
		Reward = 1000,
		PromptDist = 8,
		SyrupColor = Color3.fromRGB(120, 70, 30), -- brąz syropu (fallback gdy brak modelu)
		SyrupLight = Color3.fromRGB(200, 130, 60), -- jasny brąz/gold dla VFX
		-- Avatar dziadka — kwadratowy obrazek po lewej stronie dialogu
		-- Wstaw asset id (rbxassetid://...) gdy będziesz miał grafikę
		AvatarImage = "",
		AvatarBg = Color3.fromRGB(60, 50, 40), -- ciemny brąz pod avatarem
		TypeSpeed = 35, -- znaków/s typewriter
		Dialogs = {
			none = "Cześć młodzieńcze! Zgubiłem mój syrop klonowy gdzieś w parku. Znajdziesz mi go?",
			justAccepted = "Dobrze, czekam tu na ciebie chłopcze. Powodzenia!",
			active = "Szukaj dalej w parku, chłopcze. Mój syrop tam gdzieś czeka.",
			ready = "Och, masz mój syrop! Dawaj go tutaj, dziękuję!",
			done = "Co tam młodzieńcze?",
		},
		QuestDesc = "Znajdź syrop klonowy dziadka w parku",
	},

	-- DataStore — v7: rzadkości po polsku
	-- (Grandpa dodany jako nowe pole, mergeWithDefaults uzupełni — BEZ bumpu)
	DataStoreKey = "PlayerData_v7",

	-- Gwarancje rzadkości na mapie
	MinLegendarnaOnMap = 1,
	MinEpickaOnMap = 3,
}
