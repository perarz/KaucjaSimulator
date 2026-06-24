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
		-- Paczki złotówek za Robux (Developer Products — ProcessReceipt jak deska VIP).
		-- Konsumowalne: zawsze kupowalne, bez stanu "POSIADASZ".
		MoneyPacks = {
			{ key = "Money1k",  ProductId = 3606062107, Amount = 1000,  PriceRobux = 19,  Name = "1 000 PLN",  image = "rbxassetid://96938417960817" },
			{ key = "Money10k", ProductId = 3606062394, Amount = 10000, PriceRobux = 169, Name = "10 000 PLN", image = "rbxassetid://98184141775824" },
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
			Speed = 100,
			CostType = "Gamepass",          -- Gamepass (one-time unlock), nie Developer Product
			GamepassId = 1883460051,
			RobuxPrice = 39,                -- info-only do UI
			gablota = 4,
			color = Color3.fromRGB(230, 190, 60),
		},
	},
	-- WalkSpeed/JumpHeight przywracane po zejściu z deski
	DeckDismountWalkSpeed = 16,
	DeckDismountJumpHeight = 7.2,
	-- Ikona przycisku hoverboard (HUD) — otwiera menu desek
	DeckMenuIconId = "rbxassetid://71645152463222",

	-- Bank: bazowa pojemność + cena ulepszeń (przycisk ULEPSZ w UI banku).
	-- Każde ulepszenie daje +1 cap. Pierwsze kosztuje BaseCost, każde następne +CostStep.
	-- L0 = 10, L1 = 11 (cost 1000), L2 = 12 (cost 1500), L3 = 13 (cost 2000), ...
	Bank = {
		BaseCapacity = 10,
		UpgradeBaseCost = 1000,
		UpgradeCostStep = 500,
	},

	-- ── Pety ────────────────────────────────────────────────────────────────
	-- Struktura jest zaprojektowana tak, by dodanie nowej rzadkości/klasy = 1 wpis w tabeli.
	-- Każdy pet ma unikalne UUID + (rarity, class). Zajmuje 1 slot w plecaku (jak butelka).
	-- Equipped (max 1) daje bonusy: money mul × skill mul × boost mul (multyplikatywnie);
	-- speed/HP addytywnie do bazy (deska/sprint/MaxHealth).
	Pets = {
		-- Folder modeli wizualnych (1 model per rzadkość — Sprinter i Tank wyglądają tak samo wizualnie).
		-- Ścieżka: ReplicatedStorage.Pets.PetyEnchanted.PetCommon (itd.)
		ModelsFolderPath = { "Pets", "PetyEnchanted" },
		-- Modele ZŁOTYCH petów (gold upgrade): ReplicatedStorage.Pets.PetyGold.Pet<Rarity>
		GoldModelsFolderPath = { "Pets", "PetyGold" },
		ModelNamePrefix  = "Pet",  -- ModelNamePrefix .. rarity → "PetCommon", "PetHuge", ...

		-- Drop weights (suma dowolna — RNG ważona).
		-- Dodanie nowej rzadkości = wpis w Rarities + odpowiednie bonusy w Classes.bonuses.
		Rarities = {
			Common    = { order = 1, weight = 60, moneyMul = 1.1, color = Color3.fromRGB(180, 180, 180), displayName = "Common",    image = "rbxassetid://116042181628072" },
			Rare      = { order = 2, weight = 25, moneyMul = 1.3, color = Color3.fromRGB( 55, 138, 221), displayName = "Rare",      image = "rbxassetid://134038496529761" },
			Epic      = { order = 3, weight = 10, moneyMul = 1.5, color = Color3.fromRGB(127, 119, 221), displayName = "Epic",      image = "rbxassetid://87097975330888"  },
			Legendary = { order = 4, weight =  4, moneyMul = 1.7, color = Color3.fromRGB(239, 159,  39), displayName = "Legendary", image = "rbxassetid://98629817680740"  },
			Huge      = { order = 5, weight =  1, moneyMul = 2.0, color = Color3.fromRGB(220,  60, 200), displayName = "Huge",      image = "rbxassetid://100283554982021" },
		},

		-- Klasy — każda definuje typ efektu + bonusy per rzadkość.
		-- Dodanie nowej klasy = wpis tutaj + wpis w ClassWeights.
		Classes = {
			Sprinter = {
				displayName = "Sprinter",
				effect      = "speed",   -- aplikowane: WalkSpeed (chodzenie/sprint) + deck.Speed na desce
				bonuses     = { Common = 3,  Rare = 5,  Epic = 10, Legendary = 15, Huge = 25  },
			},
			Tank = {
				displayName = "Tank",
				effect      = "hp",      -- aplikowane: Humanoid.MaxHealth (+= bonus na CharacterAdded)
				bonuses     = { Common = 10, Rare = 15, Epic = 25, Legendary = 50, Huge = 100 },
			},
		},
		ClassWeights = { Sprinter = 1, Tank = 1 },  -- 50/50 niezależnie od rzadkości

		-- Koszty
		SingleEggCost   = 500,            -- 1 jajko = 500 zł zawsze
		TripleEggCost   = 1500,           -- 3 jajka = 1500 zł (tylko przy gamepass'ie)
		TripleEggGamepassId = 1884317989, -- gamepass odblokowujący opcję 3-jajek
		TripleEggPriceRobux = 39,         -- cena R$ na Roblox (do wyświetlenia w sklepie)

		-- Hard cap równoczesnych petów wyposażonych (na razie 1)
		MaxEquipped = 1,

		-- Cooldown server-side przy OpenEgg (anty-spam)
		OpenCooldownSec = 4.0,  -- pokrywa animację ruletki (3.5s) + fade-out (0.35s) — defense in depth obok klientowego gate'u spinning.

		-- ── Ulepszanie peta na ZŁOTEGO (rig "steve10die" w workspace.PUSTYNIA) ──
		-- Gracz zaznacza 1-5 petów TEJ SAMEJ rzadkości → koło fortuny. Liczba petów =
		-- procent szansy (1=20% … 5=100%). Wygrana → 1 gold pet (rarity = wsadu, klasa =
		-- klasa większości, statystyki ×StatMultiplier). Przegrana → wsad przepada.
		-- Pety są "stake'owane" przy ZAKRĘĆ; reroll (Robux) pozwala kręcić ponownie tym
		-- samym wsadem. 2x luck (Robux) jednorazowo na spin podwaja procent.
		GoldUpgrade = {
			StatMultiplier = 1.15,         -- gold pet ma +15% do statystyk zwykłego peta tej rzadkości/klasy
			MaxSelect      = 5,            -- max petów na jeden spin
			PercentPerPet  = 20,          -- 1 pet = 20%, 5 petów = 100%
			SpinSeconds    = 3.5,         -- czas animacji koła (jak roulette kosza)
			SpinRotations  = 5,           -- ile pełnych obrotów koła zanim się zatrzyma
			Throttle       = 0.4,         -- anty-spam server-side
			MaxDist        = 18,          -- dystans HRP → rig (anti-exploit)
			RigName        = "steve10die",
			RigContainer   = "PUSTYNIA",  -- katalog/model w workspace zawierający riga

			-- Obrazek gold peta per rzadkość wsadu (część 3 UI + tekstura w EQ).
			-- Tylko te rzadkości można ulepszać (Huge nie ma obrazka → niedozwolone).
			Images = {
				Common    = "rbxassetid://132288921287087",
				Rare      = "rbxassetid://112329854262606",
				Epic      = "rbxassetid://105106767734269",
				Legendary = "rbxassetid://132662083437235",
			},

			-- Developer Products (Robux) — obsługiwane w BoostShopService.ProcessReceipt
			Reroll = {
				ProductId = 3606257973,
				Image     = "rbxassetid://88009445359522",
			},
			DoubleLuck = {
				ProductId = 3606258769,
				Image     = "rbxassetid://125626173802893",
			},
		},
	},

	-- Magnes — używany item z ekwipunku. Aktywacja na 2 min: serwer co tick zbiera
	-- wszystkie butelki w promieniu Radius (= 1.5× normalna odległość zbierania = 5 studs).
	-- Stack zachowuje się jak "1 na slot" — każdy magnes = oddzielny slot, count zawsze 1.
	Magnet = {
		DurationSec      = 120,
		BaseRadius       = 5,    -- normalna ProximityPrompt MaxActivationDistance dla butelek
		RadiusMultiplier = 1.5,  -- magnes działa w 5 * 1.5 = 7.5 studs
		TickInterval     = 0.25, -- jak często sweep
		Name             = "Magnes",
		Color            = Color3.fromRGB(220, 90, 90),
		Desc             = "Aktywuj na 2 minuty. Automatycznie zbiera wszystkie butelki wokół ciebie w zwiększonym promieniu (×1.5).",
		Image            = "rbxassetid://109129872039457",  -- tekstura w slocie EQ
	},

	-- Sklep "Żabka" (workspace.blok_zabki.KasjerZabka) — sprzedaje magnesy za zł.
	Zabka = {
		MagnetCost = 1000,
		PromptText = "Sklep Żabka",
		PromptObject = "Kasjer",
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
	-- Bumped 400→800 żeby ludzie nie zapychali limitu przez wyrzucanie/death-dropy
	-- (gdy limit pełny, BottleService nie respawnuje nowych).
	MaxBottlesHardCap = 800,

	-- Death-drop: po śmierci butelki spadają. Żeby mapa nie zapychała się dropami
	-- przy aktywnym PvP, gdy łączna liczba dropów na mapie > MaxOnMap, despawn
	-- najstarszych nadmiarowych jest natychmiastowy (zamiast czekania DespawnSec).
	DeathDrop = {
		DespawnSec  = 120,  -- standard: 2 minuty bezczynności
		MaxOnMap    = 150,  -- powyżej tego liczby drop bottles, prune najstarszych
	},

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

	-- Tekstury butelek w slotach EQ/banku (jak Config.Pets.Rarities[r].image dla petów).
	-- Klucze = polskie rzadkości butelek. Preload w LoadingController.
	BottleImages = {
		Zwykla     = "rbxassetid://112983880089272",
		Rzadka     = "rbxassetid://96149302704932",
		Epicka     = "rbxassetid://114952458579095",
		Legendarna = "rbxassetid://105678168067263",
		Mityczny   = "rbxassetid://85772474205462",
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
		LuckMultiplier = 2, -- chances dla R/E/L R/E/L × 2, Zwykla zmniejsza się proporcjonalnie
	},

	-- Skill Tree: Stamina — odnoga od Speed L2 (wymaga SpeedLevel >= 2).
	-- Single-level upgrade. +50 max stamina (sumuje się z bonusem czapki).
	StaminaUpgrade = {
		Cost = 3000,
		CostType = "Zlotowki",
		Name = "Wytrzymałość",
		StaminaBonus = 50, -- doliczane do SprintController.STAMINA_MAX_BASE (sumuje z czapką)
	},

	-- Sklep: Plecak (pojemność) — osobny sklep, NIE skill tree
	-- REBALANS: L4 droższy żeby był symbolem endgame'u
	BackpackUpgrades = {
		{ Level = 1, Capacity = 10, Cost = 0, CostType = "Zlotowki", Name = "Reklamówka" },
		{ Level = 2, Capacity = 25, Cost = 200, CostType = "Zlotowki", Name = "Plecak szkolny" },
		{ Level = 3, Capacity = 35, Cost = 900, CostType = "Zlotowki", Name = "Wielki worek" },
		{ Level = 4, Capacity = 50, Cost = 10000, CostType = "Zlotowki", Name = "Wózek sklepowy" }, -- było 2800
	},

	-- Podział pojemności plecaka na kategorie (EQ z 3 zakładkami: BUTELKI / PETY / AKCESORIA).
	-- Butelki 70%, pety 20%, akcesoria (magnesy) 10%. Limity egzekwowane serwerowo
	-- (BottleService/PetService/MagnetService) + pokazywane per-kategoria w EQ.
	-- Zaokrąglenie: bottles=floor(0.7*cap), pets=floor(0.2*cap), accessories=reszta — suma==cap.
	-- Helper: Util.getCategoryCaps(totalCapacity).
	BackpackCategorySplit = {
		bottles     = 0.70,
		pets        = 0.20,
		accessories = 0.10,
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

	-- Podium top-3 (3 rigi z wczytanym skinem top graczy + animacja tańca).
	-- Rigi: workspace.Podium z 3 modelami (R15, Humanoid) nazwanymi tak by zawierały
	-- cyfrę 1/2/3 (np. "Spot1", "Miejsce2", "3"). HumanoidRootPart anchored = stoją w miejscu.
	Podium = {
		FolderName    = "Podium",
		KillsFolderName = "PodiumKilli",  -- podium eliminacji (rigi Spot1/2/3)
		-- Skala rigów per miejsce (1/2/3). Nakładana przez HumanoidDescription (uniform).
		Scales        = { 2.582, 2.091, 2.091 },
		-- Różna animacja tańca (R15) na każdym rigu. Indeks = miejsce.
		DanceAnimIds  = {
			"rbxassetid://507771019",  -- #1
			"rbxassetid://507776043",  -- #2
			"rbxassetid://507777268",  -- #3
		},
		DanceAnimId   = "rbxassetid://507771019",  -- fallback gdy brak w DanceAnimIds
		-- Co ile sekund sprawdzać czy zmienił się top-3 (diff względem cache).
		RefreshSec    = 10,
		ShowNameTag   = true,  -- billboard z nickiem + miejscem nad rigiem
	},

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
			reward = { kind = "zl", amount = 25 },
		},
		{
			id = "collect_rzadka_15",
			desc = "Zbierz 15 Rzadkich butelek",
			kind = "collect",
			rarity = "Rzadka",
			target = 15,
			reward = { kind = "zl", amount = 50 },
		},
		{
			id = "collect_epicka_5",
			desc = "Zbierz 5 Epickich butelek",
			kind = "collect",
			rarity = "Epicka",
			target = 5,
			reward = { kind = "zl", amount = 80 },
		},
		{
			id = "collect_legendarna_1",
			desc = "Zbierz 1 Legendarną butelkę",
			kind = "collect",
			rarity = "Legendarna",
			target = 1,
			reward = { kind = "zl", amount = 100 },
		},
		{
			id = "collect_any_75",
			desc = "Zbierz 75 dowolnych butelek",
			kind = "collect_any",
			target = 75,
			reward = { kind = "zl", amount = 60 },
		},
		{
			id = "earn_500",
			desc = "Zarób 500 zł w butelkomacie",
			kind = "earn",
			target = 500,
			reward = { kind = "zl", amount = 50 },
		},
		{
			id = "earn_2000",
			desc = "Zarób 2000 zł w butelkomacie",
			kind = "earn",
			target = 2000,
			reward = { kind = "zl", amount = 100 },
		},
		{
			id = "search_kosz_8",
			desc = "Przeszukaj 8 koszy",
			kind = "search_kosz",
			target = 8,
			reward = { kind = "zl", amount = 70 },
		},
		{
			id = "empty_backpack_4",
			desc = "Opróżnij plecak 4 razy",
			kind = "empty_backpack",
			target = 4,
			reward = { kind = "zl", amount = 60 },
		},
		{
			id = "buy_skill_1",
			desc = "Kup 1 ulepszenie w drzewku",
			kind = "buy_skill",
			target = 1,
			reward = { kind = "zl", amount = 80 },
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
	MinEpickaOnMap     = 3,

	-- Wstęp do strefy PvP — opłata 300 PLN ZA KAŻDYM RAZEM (bez persystencji).
	-- Dwa sposoby zakupu:
	--   1) Auto-trigger: gracz wchodzi do workspace.PVPZone → wypychanie + GUI płatności
	--   2) KasjerPVP (opcjonalny rig z ProximityPrompt) — preventive zakup zanim wejdziesz
	-- Po opłacie: konsumpcja biletu przy wejściu do strefy + 3s grace (ForceField + miecz disabled)
	PvPEntry = {
		Cost          = 300,
		KasjerName    = "KasjerPVP",      -- opcjonalny rig, jeśli nie istnieje to OK
		PromptText    = "Zapłać za wstęp",
		PromptObject  = "Wstęp do PvP",
	},

	-- Linia fabularna: chain questów po kolei. Każdy ma kind (typ akcji), target (ile potrzeba),
	-- reward (zł), desc (tekst w UI). Po wykonaniu jednego automatycznie startuje następny.
	-- UI: pierwsza inicjacja questa → wielki napis na środku 4s → zmniejsza się i ląduje w rogu (HUD).
	-- Po wykonaniu: WYKONANO na środku + nagroda, po 2s następny.
	StoryQuests = {
		{ id = "collect_10",       desc = "Zbierz 10 butelek",                  kind = "collect_any",    target = 10,  reward = 30  },
		{ id = "deposit_2",        desc = "Oddaj butelki do butelkomatu 2 razy", kind = "deposit",        target = 2,   reward = 50  },
		{ id = "buy_2_skills",     desc = "Kup 2 ulepszenia w drzewku (Menu → Umiejętności)", kind = "buy_skill", target = 2, reward = 100 },
		{ id = "buy_backpack",     desc = "Kup lepszy plecak w sklepie",         kind = "buy_backpack",   target = 1,   reward = 150 },
		{ id = "buy_egg",          desc = "Kup 1 jajko z petem w gablocie petów", kind = "buy_egg",       target = 1,   reward = 250 },
		{ id = "equip_pet",        desc = "Załóż peta (Menu → Ekwipunek → ZAŁÓŻ)", kind = "equip_pet",    target = 1,   reward = 300 },
		{ id = "buy_deck",         desc = "Kup deskę lvl 1 w gablocie (1000 zł)", kind = "buy_deck",      deckKey = "Default", target = 1, reward = 400 },
		{ id = "collect_100",      desc = "Zbierz 100 butelek",                 kind = "collect_any",    target = 100, reward = 600 },
		{ id = "collect_5_legendary", desc = "Zbierz 5 Legendarnych butelek",   kind = "collect_rarity", rarity = "Legendarna", target = 5, reward = 400 },
		{ id = "upgrade_bank",     desc = "Ulepsz pojemność skarbca (Bank → ULEPSZ)", kind = "upgrade_bank", target = 1, reward = 500 },
		{ id = "grandpa_done",     desc = "Pomóż Dziadkowi z syropem klonowym",  kind = "grandpa_done",   target = 1,   reward = 150 },
		{ id = "buy_deck_red",     desc = "Kup deskę lvl 2 - Red (3000 zł)",    kind = "buy_deck",       deckKey = "Red",  target = 1, reward = 200 },
		{ id = "pet_legendary",    desc = "Wylosuj Legendarnego peta z jajka",  kind = "pet_rarity",     petRarity = "Legendary", target = 1, reward = 500 },
		{ id = "buy_deck_blue",    desc = "Kup deskę lvl 3 - Blue (5000 zł)",   kind = "buy_deck",       deckKey = "Blue", target = 1, reward = 500 },
	},
}
