# CLAUDE.md — Kaucja Simulator

## Przegląd projektu

**Nazwa gry:** Kaucja Simulator
**Engine:** Roblox Studio
**Stack:** Luau, Rojo, VS Code
**Typ:** Shared-world multiplayer simulator
**Styl wizualny:** Low-poly, pastelowy (paletka jak Survivors Island)

Gracz chodzi po mieście, zbiera butelki różnych rzadkości, oddaje je do butelkomatu i zdobywa złotówki. Za kasę kupuje upgrady które pozwalają zbierać szybciej, więcej i zarabiać więcej — klasyczna pętla progresji.

---

## Core loop

```
ZBIERANIE butelek po mapie
        ↓
ODDANIE do butelkomatu → złotówki
        ↓
ZAKUP upgradów (mnożnik / plecak / transport)
        ↓
(wróć do zbierania, szybciej i efektywniej)
```

---

## Struktura projektu (Rojo)

```
src/
  client/
    controllers/
      CollectController.client.luau         -- zbieranie butelek, HUD, ekwipunek, butelkomat, VFX, SFX PickingUp
      SkillTreeController.client.luau       -- GUI drzewka umiejętności (klawisz U)
      ShopController.client.luau            -- GUI sklepu z plecakami
      KoszController.client.luau            -- roulette UI przy przeszukiwaniu kosza, SFX RouletteTick+Win
      QuestController.client.luau           -- panel questów (klawisz Q)
      IntroController.client.luau           -- silnik cutsceny tutorial (multi-scene)
      LoadingController.client.luau         -- TAP TO CONTINUE + realny preload assetów
      SettingsController.client.luau        -- panel ustawień: replay tutorial + slider głośności SFX
      MobileScaleController.client.luau     -- globalny UIScale per ScreenGui (fit do viewportu)
      LegendaryEventController.client.luau  -- UI eventu Deszcz Legendarek: timer, alert, złoty tint nieba
      GrandpaController.client.luau         -- dialog box dziadka (visual-novel, typewriter, viewport avatar)
      MenuController.client.luau            -- główne menu: 1 przycisk MENU + 4 zakładki z animowanym bubble indicator
      BankController.client.luau            -- standalone split-view SKARBIEC ⇌ EKWIPUNEK, drag&drop, POTWIERDŹ → BankDeposit
      SprintController.client.luau          -- Shift = sprint (+5 WalkSpeed) gated na BaseLevel>=1, cienki biały pasek staminy na dole
      HatShopController.client.luau         -- standalone UI sklepu czapek (workspace.SKLEP2.Cashier), 1 produkt z bonusami HP/stamina/speed
      AdminController.client.luau           -- panel admina (F2), broadcast tekstu + daj sobie zł/butelki
      BoostShopController.client.luau       -- sklep Robux: x2 KASA 10 min za 19 R$, portowany do zakładki SKLEP w menu
      DeskaController.client.luau           -- klawisz R wsiada/wysiada z deski, RenderStepped obraca gracza bokiem względem kamery
      DeckShopController.client.luau        -- GUI zakupu deski przy gablocie + przycisk hoverboard → menu TWOJE DESKI (equip)
  server/
    services/
      BottleService.luau          -- spawn, respawn, rzadkości butelek (tier per obszar), CollectionService tagging
      PlayerDataService.luau      -- DataStore: złotówki, upgrady, stats + leaderstats
      UpgradeService.luau         -- logika kupowania upgradów (Base/Speed/Multiplier/Luck)
      ShopService.luau            -- sklep z plecakami (ProximityPrompt na blacie)
      LeaderboardService.luau     -- OrderedDataStore — ranking aktualnego Zlotowki na SurfaceGui
      KoszService.luau            -- kosze do przeszukiwania (ProximityPrompt HoldDuration=2)
      QuestService.luau           -- 3 questy / 6h, hook do progress, claim z nagrodą
      IntroService.luau           -- rejestracja KeyframeSequence + flaga HasSeenIntro
      GrandpaService.luau         -- quest dziadka: dialog state machine + ProximityPrompt na workspace.Grandpa
      SyrupService.luau           -- spawn/despawn syropu per-player (OwnerUserId gate, client filtruje LocalTransparencyModifier)
      BankService.luau            -- skarbiec na butelki, osobny DataStore BankData_v1, conservation+capacity check
      CodeService.luau            -- kody promocyjne (OGDC=200, PVPOG=500), jednorazowe per gracz w data.RedeemedCodes
      BackpackEquipService.luau   -- zakłada Accessory plecaka (Level 2/3) na postaci, fuzzy attachment match, BackOffset/BackRotation tuning
      PvPService.luau             -- strefa PvP (workspace.PVPZone), miecz z ReplicatedStorage.Sword, normalizacja scale hitboxów
      HatShopService.luau         -- sklep czapki (SKLEP2.Cashier), permanentna Czapka za 5000zł+10×Leg+1×Mit, +50HP/+50stamina/+2speed
      DeathDropService.luau       -- drop butelek po śmierci na ziemię (raycast), instant respawn, 5s cooldown na własne dropy
      AdminService.luau           -- panel admina (Config.Admins, F2), broadcast/giveZl/giveBottles/kick
      BoostShopService.luau       -- Developer Products (Robux), x2 KASA z butelkomatu na 10 min, ProcessReceipt handler (+ grant deski VIP)
      DeskaService.server.luau    -- deski: zakup przy gablotach, owned/equip, jazda po R (clone-per-mount), VIP w Robux (standalone Script)
  shared/
    Config.luau                   -- wszystkie stałe (ceny, wartości, czasy, questy, drop kosza)
default.project.json
CLAUDE.md
```

---

## Config.luau — aktualne wartości

Wszystkie liczby balansowe trzymaj WYŁĄCZNIE w `Config.luau`. Nigdy nie hardkoduj wartości w innych plikach.

```lua
-- src/shared/Config.luau
return {
    -- REBALANS 2026: wartości obniżone żeby spowolnić earn rate
    BottleValues = {
        Zwykla    = 1,
        Rzadka    = 2,
        Epicka    = 3,   -- było 5
        Legendarna = 10, -- było 20
        Mityczny  = 25,  -- było 50 (tier 5 only)
    },

    -- Fallback gdy obszar nie ma tieru w nazwie (T?)
    BottleSpawnChance = {
        Zwykla    = 0.71,
        Rzadka    = 0.20,
        Epicka    = 0.08,
        Legendarna = 0.01,
    },

    -- Szanse per tier obszaru. Tier brany z nazwy Partu w workspace.BottleSpawnAreas:
    -- pierwszy "T<liczba>" w nazwie (case-insensitive). Np. "T1_centrum", "T3_pustynia", "Las_T2".
    -- Brak "T?" → tier 1 (default). Każdy wiersz musi sumować się do 1.0.
    BottleSpawnChanceByTier = {
        [1] = { Zwykla = 0.85, Rzadka = 0.13, Epicka = 0.02, Legendarna = 0.00 }, -- blisko spawna
        [2] = { Zwykla = 0.60, Rzadka = 0.28, Epicka = 0.11, Legendarna = 0.01 }, -- średnio
        [3] = { Zwykla = 0.35, Rzadka = 0.35, Epicka = 0.25, Legendarna = 0.05 }, -- daleko
        [4] = { Zwykla = 0.15, Rzadka = 0.30, Epicka = 0.40, Legendarna = 0.15, Mityczny = 0.00 }, -- endgame
        [5] = { Zwykla = 0.00, Rzadka = 0.00, Epicka = 0.50, Legendarna = 0.45, Mityczny = 0.05 }, -- mityczna strefa (Mit 5% po rebalansie — było 20%)
    },

    BottleRespawnTime = 6,
    -- Spawn density: target = max(MinBottlesPerArea, round(area_surface_XZ * density))
    BottleDensity      = 0.025,   -- ~1 butelka / 40 sq studs
    MinBottlesPerArea  = 3,       -- floor dla małych obszarów
    MaxBottlesHardCap  = 400,     -- safety cap na olbrzymie mapy

    -- Event "Deszcz Legendarek" — co 8-12 min, 15s zalewu legendarkami
    LegendaryEvent = {
        MinIntervalSec = 480,  -- 8 min
        MaxIntervalSec = 720,  -- 12 min
        DurationSec    = 15,
        BottleCount    = 30,
    },

    BottleColors = {
        Zwykla    = Color3.fromRGB(180, 180, 180),
        Rzadka    = Color3.fromRGB(55, 138, 221),
        Epicka    = Color3.fromRGB(127, 119, 221),
        Legendarna = Color3.fromRGB(239, 159, 39),
    },

    -- Węzeł bazowy — odblokuj najpierw (koszt 50). Odblokowuje:
    -- 1) gałęzie Speed i Multiplier w drzewku
    -- 2) BANK SEJF (BankService gate: BaseLevel < 1 → BankInit z {locked=true})
    -- 3) SPRINT na Shift (+5 WalkSpeed) z cienkim białym paskiem staminy na dole ekranu
    BaseUpgrade = {
        Cost     = 50,
        CostType = "Zlotowki",
        Name     = "Fundament",
    },

    -- Skill Tree: Prędkość (WalkSpeed) — wymaga BaseLevel >= 1. Cap = 30.
    -- REBALANS: L3/L4 droższe — endgame jako sensowny grind
    SpeedUpgrades = {
        { Level = 1, Speed = 19, Cost = 250,   CostType = "Zlotowki", Name = "Trucht"  },
        { Level = 2, Speed = 22, Cost = 1500,  CostType = "Zlotowki", Name = "Bieg"    },
        { Level = 3, Speed = 26, Cost = 6000,  CostType = "Zlotowki", Name = "Sprint"  },
        { Level = 4, Speed = 30, Cost = 25000, CostType = "Zlotowki", Name = "Rakieta" },  -- ← MAIN GATE
    },

    -- Skill Tree: Mnożnik kasy — wymaga BaseLevel >= 1. Cap = ×2.5.
    -- REBALANS: L3/L4 droższe
    MultiplierUpgrades = {
        { Level = 1, Multiplier = 1.5, Cost = 250,   CostType = "Zlotowki", Name = "Dobry Węch"     },
        { Level = 2, Multiplier = 2.0, Cost = 1500,  CostType = "Zlotowki", Name = "Kaucyjny Zmysł" },
        { Level = 3, Multiplier = 2.2, Cost = 7000,  CostType = "Zlotowki", Name = "Złoty Nos"      },
        { Level = 4, Multiplier = 2.5, Cost = 30000, CostType = "Zlotowki", Name = "Legenda"        },  -- ← MAIN GATE
    },

    -- Skill Tree: Szczęście — odnoga od Multiplier L2 (single-level, fioletowy hex z ★)
    -- Podwaja szanse na lepsze rzadkości w koszach. Zwykła zmniejsza się proporcjonalnie.
    LuckUpgrade = {
        Cost           = 2000,
        CostType       = "Zlotowki",
        Name           = "Talizman Szczęścia",
        LuckMultiplier = 2,
    },

    -- Sklep: Plecak (pojemność) — osobny sklep, NIE skill tree
    -- REBALANS: L4 droższy (2800 → 10000), L4 bez wizualnego modelu (BackpackEquipService pomija cicho)
    BackpackUpgrades = {
        { Level = 1, Capacity = 10, Cost = 0,     CostType = "Zlotowki", Name = "Reklamówka"     },
        { Level = 2, Capacity = 25, Cost = 200,   CostType = "Zlotowki", Name = "Plecak szkolny" },
        { Level = 3, Capacity = 35, Cost = 900,   CostType = "Zlotowki", Name = "Wielki worek"   },
        { Level = 4, Capacity = 50, Cost = 10000, CostType = "Zlotowki", Name = "Wózek sklepowy" },
    },

    -- Kosz — wagi ilości dropu per rzadkość (Zwykla startuje od 2 — single za słabe po 2s hold + ruletce)
    KoszDropQuantity = {
        Zwykla     = { {2, 28}, {3, 32}, {4, 24}, {5, 16} },
        Rzadka     = { {1, 25}, {2, 45}, {3, 25}, {4, 5} },
        Epicka     = { {1, 50}, {2, 40}, {3, 10} },
        Legendarna = { {1, 100} },
    },

    LeaderboardUpdateInterval = 60,
    LeaderboardMaxEntries     = 10,

    -- Questy — 3 aktywne losowane z puli, refresh co 6h
    QuestActiveCount  = 3,
    QuestRefreshHours = 6,
    Quests = {
        { id = "collect_zwykla_30",    desc = "Zbierz 30 Zwykłych butelek",     kind = "collect",        rarity = "Zwykla",     target = 30, reward = { kind = "zl", amount = 75 } },
        { id = "collect_rzadka_15",    desc = "Zbierz 15 Rzadkich butelek",     kind = "collect",        rarity = "Rzadka",     target = 15, reward = { kind = "zl", amount = 160 } },
        { id = "collect_epicka_5",     desc = "Zbierz 5 Epickich butelek",      kind = "collect",        rarity = "Epicka",     target = 5,  reward = { kind = "zl", amount = 325 } },
        { id = "collect_legendarna_1", desc = "Zbierz 1 Legendarną butelkę",    kind = "collect",        rarity = "Legendarna", target = 1,  reward = { kind = "zl", amount = 650 } },
        { id = "collect_any_75",       desc = "Zbierz 75 dowolnych butelek",    kind = "collect_any",                           target = 75, reward = { kind = "zl", amount = 130 } },
        { id = "earn_500",             desc = "Zarób 500 zł w butelkomacie",    kind = "earn",                                  target = 500, reward = { kind = "zl", amount = 160 } },
        { id = "earn_2000",            desc = "Zarób 2000 zł w butelkomacie",   kind = "earn",                                  target = 2000, reward = { kind = "zl", amount = 500 } },
        { id = "search_kosz_8",        desc = "Przeszukaj 8 koszy",             kind = "search_kosz",                           target = 8,  reward = { kind = "zl", amount = 220 } },
        { id = "empty_backpack_4",     desc = "Opróżnij plecak 4 razy",         kind = "empty_backpack",                        target = 4,  reward = { kind = "zl", amount = 190 } },
        { id = "buy_skill_1",          desc = "Kup 1 ulepszenie w drzewku",     kind = "buy_skill",                             target = 1,  reward = { kind = "zl", amount = 160 } },
    },

    MinLegendarnaOnMap = 1,
    MinEpickaOnMap     = 3,

    -- Quest Dziadka — narracyjny, jednorazowy. Setup: workspace.Grandpa (Model R15 z HumanoidRootPart)
    -- + workspace.SyrupSpawnPoints (folder z Partami SyrupSpawn1/2/3, Anchored, Transparency=1)
    GrandpaQuest = {
        Reward       = 1000,
        PromptDist   = 8,
        SyrupColor   = Color3.fromRGB(120, 70, 30),
        SyrupLight   = Color3.fromRGB(200, 130, 60),
        AvatarImage  = "",                              -- rbxassetid://... — override viewport custom grafiką
        AvatarBg     = Color3.fromRGB(60, 50, 40),
        TypeSpeed    = 35,                              -- znaków/s typewriter
        Dialogs = {
            none         = "Cześć młodzieńcze! Zgubiłem mój syrop klonowy gdzieś w parku. Znajdziesz mi go?",
            justAccepted = "Dobrze, czekam tu na ciebie chłopcze. Powodzenia!",  -- jednorazowo po akcepcie
            active       = "Szukaj dalej w parku, chłopcze. Mój syrop tam gdzieś czeka.",
            ready        = "Och, masz mój syrop! Dawaj go tutaj, dziękuję!",
            done         = "Co tam młodzieńcze?",
        },
        QuestDesc = "Znajdź syrop klonowy dziadka w parku",
    },

    -- Bank: bazowa pojemność + cena ulepszeń (ULEPSZ w UI banku)
    -- Każde ulepszenie daje +1 cap. L0 → 10 (cost 1000), L1 → 11 (cost 1500), L2 → 12 (cost 2000), ...
    Bank = {
        BaseCapacity   = 10,
        UpgradeBaseCost = 1000,
        UpgradeCostStep = 500,
    },

    -- v7: rzadkości po polsku + Grandpa quest + BankCapLevel + Decks itp. dodane przez mergeWithDefaults (BEZ bumpu)
    DataStoreKey = "PlayerData_v7",
}
```

---

## Typy danych gracza

```lua
-- Domyślny profil nowego gracza (PlayerDataService)
local DEFAULT_DATA = {
    Zlotowki        = 0,
    TotalEarned     = 0,        -- do leaderboardu (nigdy nie maleje)
    BaseLevel       = 0,        -- 0 = Fundament nie kupiony, 1 = kupiony (odblokowuje gałęzie)
    MultiplierLevel = 0,        -- 0 = nic nie kupiono, 1+ = kupiony poziom
    BackpackLevel   = 1,
    SpeedLevel      = 0,        -- 0 = nic nie kupiono, 1+ = kupiony poziom
    LuckLevel       = 0,        -- 0 = brak, 1 = kupiony (odnoga od Mult L2, 2× szansy na rzadkości w koszach)
    TotalBottles    = 0,
    BackpackContents = {
        Zwykla    = 0,
        Rzadka    = 0,
        Epicka    = 0,
        Legendarna = 0,
    },
    Quests = {
        activeIds = {},   -- { id1, id2, id3 } — 3 aktywne questy
        progress  = {},   -- [questId] = number
        claimed   = {},   -- [questId] = true
        refreshAt = 0,    -- os.time() do kiedy ważne; po przekroczeniu — auto-refresh
    },
    HasSeenIntro = false, -- true po obejrzeniu cutsceny przy pierwszym wejściu
    Grandpa = {
        state         = "none",  -- "none" | "active" | "done"
        syrupLocation = 0,       -- 1|2|3 — losowane przy przyjęciu questa
        hasSyrup      = false,   -- true gdy gracz podniesie syrop (zajmuje 1 slot plecaka)
    },
    RedeemedCodes = {},      -- [codeKey] = true — kody promocyjne już wykorzystane
    OwnedDecks    = {},      -- [deckKey] = true — posiadane deski (skateboardy)
    EquippedDeck  = "",      -- klucz wyposażonej deski ("" = brak; R jeździ najlepszą posiadaną)
    HatOwned      = false,   -- czapka z HatShop — permanentny zakup, daje +HP +stamina +speed
    BankCapLevel  = 0,       -- liczba kupionych ulepszeń pojemności skarbca (każde +1 cap, koszt 1000 + N×500)
    InventoryStacks = {},    -- persystencja split layoutu ekwipunku między sesjami
}
```

**Leaderstats (auto-replikacja Roblox):**
- `player.leaderstats.Zlotowki` (**NumberValue**) — klient zawsze czyta saldo STĄD; **wspiera grosze** (np. 10.50), zaokrąglane do 2 miejsc po przecinku
- `player.leaderstats.Zarobki` (IntValue) — TotalEarned do leaderboardu (ranking sortuje po int)
- `PlayerDataService.UpdateLeaderstats(player)` synchronizuje cache → leaderstats po każdej zmianie salda

### Grosze (fractional Zlotowki)
- `data.Zlotowki` to **float** — mnożnik 1.5 × 1 zł = 1.50 zł (grosze nie giną)
- Client-side helper `formatAmount(amount)`: integer → `"10"`, float → `"10.50"`, tolerancja 0.005 chroni przed fałszywymi dziesiętnymi od floating-point
- Format używany w: walletHUD (`"X PLN"` / `"X.XX PLN"`), `showEarnText`, `showButelkomatSummary` (ostatni krok animacji licznika), inventory detail panel
- Koszty upgradów i sklepu są zawsze integerami — porównania `cost <= data.Zlotowki` działają poprawnie z floatem

---

## System butelek (BottleService)

### Modele butelek (`ReplicatedStorage.BottleModels`)
- Folder `BottleModels` w `ReplicatedStorage` zawiera 4 modele nazwane: `Zwykla`, `Rzadka`, `Epicka`, `Legendarna`
- Dodatkowo: model `ReplicatedStorage.Mityczny` (bezpośrednio, nie w `BottleModels`) — `SpawnBottle` ma fallback który szuka w `ReplicatedStorage` jeśli brak w folderze
- Każdy model MUSI mieć ustawione `PrimaryPart` (do pivota i jako anchor dla ProximityPrompt/PointLight) — serwer wypisze `warn` jeśli brak
- Serwer klonuje template przy spawnie, anchoruje wszystkie BaseParts, wyłącza `CanCollide`/`CastShadow`
- Fallback: jeśli brak modelu konkretnej rzadkości, spawn użyje cylindra w kolorze rzadkości (z `Config.BottleColors`)

### Obszary spawnu (`workspace.BottleSpawnAreas`) — preferowane
- Folder w `workspace` z dowolną liczbą Partów (Anchored, Transparency=1, CanCollide=false)
- Każdy Part definiuje prostokątny obszar — butelki losują pozycję jednorodnie wewnątrz X/Z na **górnej powierzchni**
- Rotacja Partu (CFrame) respektowana — obszar może być obrócony
- Anti-overlap: do 12 prób na sample żeby trafić pozycję ≥ `MIN_BOTTLE_DIST = 3` studs od istniejących butelek
- Fallback: jeśli brak `BottleSpawnAreas`, system używa starych `BottleSpawnPoints` (folder Partów-markerów) — wtedy hardcoded cap 30 butelek

### Tier-based rzadkości per obszar
- Każdy Part w `BottleSpawnAreas` może mieć w nazwie **`T<liczba>`** (case-insensitive, np. `T1_centrum`, `Las_T2`, `T3_pustynia`)
- Parser regex `[Tt](%d+)` bierze pierwsze dopasowanie — `T_2_las` ❌ (underscore zrywa match), `Tier2_las` ❌
- Brak `T?` w nazwie → tier 1 (default, backwards compat ze starymi mapami)
- Spawn rzadkości czyta `Config.BottleSpawnChanceByTier[tier]` zamiast globalnej `BottleSpawnChance`
- T1 = blisko spawna (głównie Zwykła, 0% Legendarna), T4 = endgame (15% Legendarna)
- **`EnsureRareBottles`** filtruje obszary po `tierAllowsRarity(rarity)` — Legendarka NIE zaspawnuje się w T1 nawet jeśli `MinLegendarnaOnMap = 1` (chyba że istnieje T2+/T3/T4 z chance>0)
- Event "Deszcz Legendarek" ignoruje filtr — zalewa całą mapę

### Density-based spawn (nowy system)
- **Brak globalnego `MaxBottlesOnMap`** — każdy obszar ma swój `target = max(Config.MinBottlesPerArea, round(surface_XZ * Config.BottleDensity))`
- `surface_XZ = area.Size.X * area.Size.Z` (wysokość ignorowana)
- `dynamicMaxBottles = sum(areaTargets)` cap-owane do `Config.MaxBottlesHardCap` (proporcjonalne skalowanie wszystkich gdy przekroczone)
- **Per-area respawn** — `pickAreaNeedingFill()` losuje obszar **wagą deficytu** (target - aktualnie tam butelek). Pusta strefa szybko się wypełnia, pełna nie dostaje więcej
- `isPositionInArea()` używa `area.CFrame:PointToObjectSpace(pos)` — respektuje rotację
- `recomputeAreaTargets()` odpala się przy starcie i przy `ChildAdded`/`ChildRemoved` folderu — możesz dodawać obszary w Studio w trakcie gry
- Logi na start: `[BottleService] Density: N obszarów, target = X butelek`

### Spawn
- Każda butelka to **Model** (lub Part fallback) z `BoolValue "Collected"`, `StringValue "Rarity"` jako dziećmi rodzica
- `ProximityPrompt` (`MaxActivationDistance=5`, `HoldDuration=0`, **`RequiresLineOfSight=false`**) na PrimaryPart
- `PointLight` na PrimaryPart dla Epicka i Legendarna
- Przy starcie serwera wypełnia mapę do `dynamicMaxBottles`
- Rzadkości po polsku: `"Zwykla"`, `"Rzadka"`, `"Epicka"`, `"Legendarna"`, `"Mityczny"` (T5 only)

### Respawn
- **Cykliczna pętla** `startRespawnLoop` budzi się co `Config.BottleRespawnTime` sekund (6s) i dolewa do `min(deficit, SPAWNS_PER_TICK_CAP = 15)` butelek per tick
- Działa niezależnie od zbierania — mapa odnawia się sama nawet jak nikt nie zbiera
- Po zebraniu: dodatkowo wywoływane `scheduleRespawn` (dubluje pętlę, ale density pilnuje limitu)
- Co tick pętli: wywołane też `EnsureRareBottles` — gwarantuje minimum 1x Legendarna i 3x Epicka (pomijane podczas eventu "Deszcz Legendarek")

### Client → Server protokół
- Klient w `connectBottle` szuka prompta przez `FindFirstChildWhichIsA("ProximityPrompt", true)` (recursive — w modelu prompt jest wewnątrz PrimaryPart)
- Jeśli prompt jeszcze nie zreplikowany przy `ChildAdded`, klient nasłuchuje `DescendantAdded` aż dojdzie
- `CollectBottle:FireServer(bottle)` — bottle to Model lub Part; serwer akceptuje oba
- Serwer używa helper `getBottlePos` — `:GetPivot().Position` dla Model, `.Position` dla BasePart

### Pojemność plecaka
`Capacity = Config.BackpackUpgrades[data.BackpackLevel].Capacity`

---

## System zbierania (CollectController + BottleService)

1. Gracz aktywuje `ProximityPrompt` na butelce
2. `CollectController` (client) wysyła RemoteEvent "CollectBottle"
3. `BottleService` (server) weryfikuje: istnieje, nie zebrana, odległość ≤ 12 studs, plecak nie pełny
4. Jeśli OK: usuń butelkę, `BackpackContents[rarity] += 1`, `TotalBottles += 1`
5. **NIE naliczaj złotówek** — kasa liczona przy butelkomacie

---

## Butelkomat

### Identyfikacja butelkomatów — CollectionService
- Serwer taguje części tagiem `"Butelkomat"` przez `CollectionService:AddTag(part, "Butelkomat")`
- Klient nasłuchuje `CollectionService:GetTagged("Butelkomat")` i `GetInstanceAddedSignal`
- **Nie tworzy się automatyczny testowy butelkomat** — gracz musi mieć własny model w workspace

### AutomatKaucyjny
- Serwer szuka `workspace.AutomatKaucyjny` przy starcie, bierze `PrimaryPart` lub pierwszy `BasePart`
- Dodaje `ProximityPrompt` i tag `"Butelkomat"` automatycznie jeśli brak prompta
- Alternatywnie: dodaj tag ręcznie w Studio Tag Editor na dowolnej części

### Logika sprzedaży
- `earned = sum(count * BottleValues[rarity] * multiplier)` gdzie multiplier z MultiplierUpgrades
- Dodaj do `Zlotowki` i `TotalEarned`, resetuj `BackpackContents`, wywołaj `UpdateLeaderstats`

---

## VFX (CollectController)

### showFloatingText(text, color) — zbieranie butelek
- BillboardGui nad głową gracza, losowy offset X
- Pop animacja: TextSize 14 → 52 (Back easing, 0.20s), potem float + fade (Quad, 1.0s)
- Cień (offset +3px), mocny TextStroke

### showEarnText(amount, color) — per-rzadkość przy sprzedaży
- Większy pop: TextSize 16 → 64, float wyżej (do 13 studs)
- Wywoływany staggered z `playDepositEffects`

### showButelkomatSummary(bottlesReturned, earned) — ekranowy popup
- Pełnoekranowe przyciemnienie + panel 430×200 z zaokrąglonymi rogami i złotą obramówką
- Pop-in animacja panelu (Back easing)
- Animowany licznik: "+0 ZŁ" → "+X ZŁ" w 0.9s (28 kroków)
- Automatycznie znika po 2.6s (fade + shrink)

---

## Skill Tree (UpgradeService + SkillTreeController)

### Struktura drzewka
```
[Speed L4]        [Multiplier L4]
[Speed L3]        [Multiplier L3]
[Speed L2]        [Multiplier L2]
[Speed L1]        [Multiplier L1]
        [★ FUNDAMENT]
```

- **Fundament** (BaseUpgrade): węzeł bazowy, koszt 100 zł, tylko odblokowuje gałęzie (brak bonusów)
- Gałąź **Speed** (lewo): 4 poziomy WalkSpeed, wymagają BaseLevel ≥ 1
- Gałąź **Multiplier** (prawo): 4 poziomy mnożnika zarobków, wymagają BaseLevel ≥ 1
- SpeedLevel i MultiplierLevel startują od 0 (nie 1!)
- Zakup wyłącznie po kolei (Level N wymaga N-1)
- Serwer odrzuca zakup gałęzi jeśli `BaseLevel < 1` (reason = "needBase")

### RemoteEvent BuySkillUpgrade
- `upgradeType`: `"Base"` / `"Speed"` / `"Multiplier"`
- `targetLevel`: dla Base zawsze 1, dla gałęzi = currentLevel+1
- Serwer odpowiada przez SkillTreeUpdate: `{ success, upgradeType, newLevel }`

### UI — zaimplementowane
Klawisz **`U`** lub przycisk UMIEJĘTNOŚCI w HUD → `_G["__skillTreeToggle"]()`.

#### Layout panelu — Compact / Wide
- **Compact (`ST_W_COMPACT = 968`)**: tylko canvas + paddings, brak detail panelu — to domyślny stan po otwarciu
- **Wide (`ST_W_WIDE = ST_W_COMPACT + DET_W + CANVAS_PAD`)**: z detail panelem po prawej
- Tween `panel.Size.X` między compact/wide po kliknięciu w hex (Quint 0.26s) — UI rozsuwa się
- Wewnętrzna ramka — **canvas 920×560**, `C_CANVAS = Color3.fromRGB(10, 10, 10)` (głębokie czarne tło), border 3px, radius 8, `ClipsDescendants = true`
- `panel.ClipsDescendants = true` chowa detail w trybie compact
- Detail panel pozycjonowany przy **`DET_X_SHOWN = ST_W_COMPACT`** — dokładnie na prawej krawędzi compact panelu (nie wystaje przy zwiniętym)
- Po prawej **detail panel 320×560** — pojawia się gdy panel jest wide
- Header `C_HEADER` z tytułem "UMIEJĘTNOŚCI" + czerwony X-close
- Auto-reset Size do compact przy zamknięciu drzewka

#### Pan & Zoom
- `treeWorld` — kontener wewnątrz canvasa, `AnchorPoint = (0.5, 0.5)`, `Position = (0.5, 0.5)` → skalowanie pivotuje od środka
- **`DEFAULT_ZOOM = 0.85`** — przy otwieraniu drzewko widać w całości; reset przy każdym `setOpen`
- Pan: trzymanie LPM nad canvasem przesuwa treeWorld; drag działa nawet gdy mysz opuszcza canvas (przez `UserInputService.InputChanged/Ended`)
- Zoom: scroll kółkiem nad canvasem, krok `0.10`, limity **0.50 – 2.00**
- Limity pan: do `±0.6 × size` canvasa w każdym kierunku, clampowane też po zmianie zoomu

#### Hexagon — `makeHex` (SACRED)
```lua
makeHex(parent, cx, cy, opts) → { wrap, setColors, setStroke, flash, button, scale }
```
- `cx, cy` — środek hexa w pikselach (offset wewnątrz parenta)
- `opts`: `hexW` (default 130), `nStrip` (default 320, gęstość krawędzi), `border` (default 8), `fill`, `stroke`, `zIndex`, `onClick`
- Wrap: `AnchorPoint = (0.5, 0.5)` + UIScale dla hover (1.06)
- TextButton overlay (zIndex zi+20, AutoButtonColor=false) łapie hover i klik — wystawia `onClick` callback
- Border to **drugi, większy hex** otaczający fill — uniform thickness na wszystkich krawędziach
- `setColors(fill, stroke)` — pełna zmiana, `setStroke(stroke)` — tylko border (do pulsowania bez rewritowania fillu)

#### Layout drzewka
```
[Speed L4]          [Multi L4]
[Speed L3]          [Multi L3]
[Speed L2]          [Multi L2]
[Speed L1]          [Multi L1]
        [★ Base]
```
- Stałe: `HEX_W = 110`, `BASE_CX = 460`, `BASE_CY = 490`, `BRANCH_DX = 70`, `V_STEP = 120`
- 9 hexów, 8 linii łączących (Base→L1 obu gałęzi diagonalnie, L1→L2→L3→L4 pionowo)
- Linie: `Frame.Rotation` po obliczeniu kąta z `atan2`, skrócone o ~`HEX_W * 0.42` z każdej strony żeby nie wchodziły w hexy

#### Stany węzłów
| Stan | Fill | Stroke | Ikona |
|---|---|---|---|
| **purchased** | accent gałęzi (pełny) | accent (=fill) | własna, ciemna |
| **available** | `lighten(accent, 0.40)` (jasny środek) | pulsujący accent przez Heartbeat | własna, w kolorze `darken(accent, 0.55)` |
| **locked** | `C_HEX_DARK` (28,28,28) | `C_HEX_LOCK` (70,70,70) szary | kłódka, szara |

- Puls dla `available`: `RunService.Heartbeat` z throttle ~30 Hz, stroke oscyluje sinusoidalnie (4 rad/s) między `darken(accent, 0.45)` i `lighten(accent, 0.25)` — `setStroke` używane (nie rewritują fillów dla wydajności)
- Linie: szare domyślnie, przyjmują accent docelowego węzła gdy źródłowy (`from`) jest `purchased`

#### Animacja wejścia
- Każdy hex ma **drugi UIScale** (`entryScale`) niezależny od hover-scale — mnoży się
- Stagger rzędami: Base → L1 → L2 → L3 → L4, opóźnienie **0.07s** między rzędami
- Każdy rząd: tween Scale 0→1 (Back easing, 0.34s) + linie do tych węzłów fade-in transparency 1→0 (Quad, 0.22s)
- Start `0.12s` po `setOpen` żeby panel zdążył wsunąć się slidem

#### Detail panel (po prawej)
- Wysuwa się slidem z prawej krawędzi (`DET_X_HIDDEN` → `DET_X_SHOWN`, Quint 0.26s)
- Zawartość: tytuł, podtytuł (kategoria/poziom), badge statusu (`KUPIONE` / `DOSTĘPNE` / `ZABLOKOWANE`), separator, opis efektu, koszt, przycisk KUP z hover-animacją
- **Toggle**: klik w ten sam hex → chowa; **X w prawym górnym** rogu → chowa
- `applyDetailStatus()` odświeża przy każdej zmianie salda i po `SkillTreeUpdate`
- Auto-chowanie przy zamknięciu drzewka

#### VFX zakupu
- Flash overlay (`flash` z `makeHex`) — biały błysk transparency 0.1 → 1 (Quad, 0.55s) po `SkillTreeUpdate` z `success`

#### Eksport `_G`
- **`_G["__skillTreeToggle"]`** — toggle panelu
- **`_G["__skillTreeState"]`** = `{ data, tryBuy, nodeState, makeHex, treeWorld }` — dostęp do stanu i `makeHex` dla zewnętrznych modułów

#### Listenery klient-side
- `SkillTreeInit` (przy starcie) — uzupełnia `pData` o `baseLevel`, `speedLevel`, `multiplierLevel`, wywołuje `renderNodes`
- `SkillTreeUpdate` — aktualizuje `pData`, odpala `purchaseVFX` (flash), `renderNodes`, odświeża detail panel
- `leaderstats.Zlotowki.Changed` — synchronizuje saldo, odświeża detail panel jeśli otwarty

#### Kolory akcentu (matowe, głębsze)
- Base: `Color3.fromRGB(80, 160, 100)` — forest green
- Speed: `Color3.fromRGB(70, 120, 180)` — steel blue
- Multiplier: `Color3.fromRGB(195, 145, 55)` — muted amber

#### Ikony (asset IDs)
- Base (gwiazdka): `rbxassetid://97427046520791`
- Speed: `rbxassetid://134318061601774`
- Multiplier: `rbxassetid://82455275969069`
- Kłódka: `rbxassetid://136661234578099`

---

## Ekwipunek / Inventory (CollectController)

- Otwiera się jako pełnoekranowy overlay (jak skill tree) — animacja slide + dim tła
- Klawisz `I` lub przycisk EKWIPUNEK w HUD
- Zamykanie: przycisk **X** (czerwony, bez ramki) w headerze lub klawisz `I` (kliknięcie tła NIE zamyka)
- Header pokazuje: `EKWIPUNEK    X/Y` — licznik posiadanych / pojemność (`invCountLbl`, TextSize 20, `C_DIMTEXT`)
- 10 slotów (5×2), `SLOT_SIZE = 140`, `SLOT_GAP = 12`, drag & drop
- Sloty mają `AnchorPoint = (0.5, 0.5)` + `UIScale` — hover-animacja 1.00 → 1.06 (Quad 0.12s) rośnie ze środka
- `ClipsDescendants = true` na slocie — wszystkie dzieci klipowane do zaokrąglonego kształtu
- Hover slotu podczas dragowania używa `C_SLOT_HOV` (48,48,48) — ciemne, nie błyska
- `invOverlay.AutoButtonColor = false` — KRYTYCZNE: bez tego czarne tło jaśnieje na trzymanym LPM podczas dragu
- Flaga `recentlyDragged` zapobiega przypadkowemu zamknięciu po upuszczeniu itemu
- Ghost item podczas dragowania parented do `invGui` (IgnoreGuiInset=true)

### Compact / Wide — panel rozszerza się tylko przy klikniętym itemie
- `INV_W_COMPACT = slotsW + PAD * 2` — domyślnie panel pokazuje tylko sloty
- `INV_W_WIDE    = INV_W_COMPACT + INV_DET_W + PAD` — z detail panelem po prawej
- Tween `panel.Size.X` między compact/wide (Quint 0.26s) — UI "rozsuwa się" przy kliknięciu w slot
- `ClipsDescendants = true` na `invPanel` chowa detail w trybie compact
- Detail panel pozycjonowany przy **`INV_DET_X_SHOWN = INV_W_COMPACT`** — dokładnie na prawej krawędzi compact panelu, żeby nie wystawał przy zwiniętym widoku
- Auto-reset Size do compact przy zamknięciu EQ

### Detail panel (po prawej)
- Wysuwa się po **kliknięciu** w slot z itemem (rozróżnienie klik vs drag: `DRAG_CLICK_THRESHOLD = 5` px ruchu myszy)
- Zaokrąglona ramka stylem Inventory: `C_BG`, border `C_BORDER` 4px
- Czerwony **X** w prawym górnym rogu z hover-animacją `UIScale 1.18`
- Zawartość: tytuł rzadkości (kolor rzadkości, TextSize 22), `Posiadasz: X sztuk`, separator, **Wartość bazowa**, **Razem (×1)**, **Z mnożnikiem (×N.N)** w `C_ACCENT_GREEN`, separator, opis krótki tekst per rzadkość
- Multiplier czytany z `_G["__skillTreeState"].data.MultiplierLevel` (z fallbackiem ×1.0)
- **Instant switch**: klik dowolnego slotu z itemem → detail natychmiast pokazuje ten item, nawet jeśli ma tę samą rzadkość co poprzednio (zero toggle behavior na klik). Chowanie tylko: czerwony X lub zamknięcie ekwipunku
- Auto-refresh przy `UpdateHUD`, `CollectBottleResult` i `playDepositEffects` (zmiana count lub mnożnika)

### Slot z itemem — pomalowany kolorem rzadkości
- **Tło slota** = `darken(rarity.color, 0.45)` — przyciemniona wersja koloru rzadkości
- **UIStroke** = pełny kolor rzadkości
- **Tekst** (nazwa + count) — biały z czarnym `TextStroke` dla czytelności na kolorowym tle
- Stary "accent strip" po lewej zostawiony jako niewidoczny child (legacy dla `startDrag` kompat.)

### VFX Legendarnej
- **Rotujący `UIGradient` overlay** w slocie — żółto-pomarańczowy gradient obraca się 80°/s, transparency 0.15-0.55
- **Pulsujący UIStroke** — kolor cykluje gold ↔ white (sin 4.5 Hz), grubość 3 → 5.5
- Heartbeat aktualizuje co frame dla każdego slotu zawierającego `Legendarna`

---

## HUD (CollectController)

### Portfel (wallet)
- Górna część ekranu, wycentrowany poziomo (`AnchorPoint = (0.5, 0)`, `Position.Y = 6`)
- Format: `"X PLN"` dużą zieloną czcionką (textSize 48, kolor `C_ACCENT_GREEN`)
- Tło `C_BG`, border `C_BORDER` grubości **6**, **bez `UICorner`** (prostokątne rogi — wyróżnia portfel od reszty UI)
- Czyta saldo z `player.leaderstats.Zlotowki.Value` (auto-replikacja)
- Plecak NIE wyświetlany w HUD — widoczny dopiero w panelu ekwipunku

### Stare 4 przyciski HUD — UKRYTE
- Były: EKWIPUNEK, UMIEJĘTNOŚCI, QUESTY, USTAWIENIA stackowane po lewej
- Po przebudowie UI (MenuController) ustawione `Visible = false` ale ich click handlery wciąż żyją (backwards compat)
- Toggle'e (`_G["__inventoryToggle"]`, `_G["__skillTreeToggle"]` itd.) **przekierowane** na `_G["__menuOpen"]() + _G["__menuSetActiveTab"](N)` — klawisze I/U/Q nadal działają (otwierają menu na właściwej zakładce)

### Globalne zasady HUD
- `ScreenGui.IgnoreGuiInset = true` — pozwala umieścić wallet przy samej krawędzi
- Wszystkie elementy używają wspólnej palety (`C_BG`, `C_BORDER`, `C_WHITE`, `C_ACCENT_GREEN`)

---

## Główne Menu (MenuController)

### Cel
Zamiast 4 osobnych przycisków HUD → **jeden przycisk MENU** po lewej. Otwiera kwadratowe menu prawie pełnoekranowe z paskiem zakładek u góry (animowany bubble indicator) i obszarem contentu. Każda zakładka hostuje content swojego kontrolera (zreparentowany z hidden ScreenGui macierzystego kontrolera).

### Wymiary
- Panel: **1380 × 760** (centered, pop-in animacja Quint)
- Tab bar: pełna szerokość minus padding, **wysokość 84**, **pill-shaped** (UICorner radius = TABBAR_H/2), **bez UIStroke**, ciemniejszy zielony `C_TABBAR = (8, 60, 48)`
- Content area: `1332 × 610`, `C_PANEL` tło, UICorner radius 10, ClipsDescendants = true

### Przycisk MENU
- AnchorPoint (0, 0.5), Position (16, 0.5) — środek-lewa krawędź
- Size 200×90, czcionka GothamBlack, TextSize 32
- Hover UIScale 1.06 (Quad 0.12s)

### Pasek zakładek + bubble indicator
- 4 zakładki text-only: **EKWIPUNEK / UMIEJĘTNOŚCI / QUESTY / USTAWIENIA**
- Czcionka **`Enum.Font.LuckiestGuy`** (TextSize 26) — ta sama co tytuł loading screen
- Bubble = Frame z `C_BUBBLE = (170, 221, 102)`, animuje `Position` + `Size` przy klikaniu zakładki (Quint 0.32s)
- Aktywna zakładka ma tekst czarny (na zielonym bubble), nieaktywne `C_DIMTEXT`
- Layout obliczany dynamicznie z `tabBar.AbsoluteSize` (równe komórki per #TABS)

### Animacja przełączania zakładek
- Stary frame **chowa się natychmiast** (`Visible = false`) — bez nakładania na nowy
- Nowy frame **slide-in z prawej** (offset 40 → 0, Quint 0.28s)
- Wcześniejsza wersja miała task.delay na hide starego + tween TextTransparency descendants — usunięte, bo psuło strokes detail panel skill tree

### Hook po przełączeniu zakładki
- Zakładka 2 (UMIEJĘTNOŚCI) → `_G["__skillTreePlayEntry"]()` z opóźnieniem 0.05s (animacja wejścia hexów)

### Otwieranie / zamykanie
- Klik MENU button → toggle (slide-in + dim background 0.35 transparency, Quint 0.28s)
- **Klawisz TAB** → toggle menu, **klawisz ESC** → zamyka
- **X w prawym górnym rogu** → zamyka
- **Klik w tło NIE zamyka** — wyłącznie X, ESC, lub TAB ponownie

### Eksport `_G`
- `_G["__menuToggle"]`, `_G["__menuOpen"]`, `_G["__menuClose"]` — sterowanie z innych kontrolerów (np. SettingsController.replayBtn wywołuje `__menuClose` przed odpaleniem cutsceny)
- `_G["__menuSetActiveTab"](idx)` — przełączenie zakładki z zewnątrz (przekierowania klawiszy I/U/Q i toggle redirects)

### Port istniejących paneli do zakładek
Każdy kontroler (CollectController/SkillTreeController/QuestController/SettingsController) eksportuje swój content (wrap/panel) przez `_G["__xxxReady"] + _G["__xxxWrap"]` lub `__xxxPanel`. MenuController task.spawn czeka na `__xxxReady`, reparentuje element do `contentFrames[N]`, centruje (poza Settings które idą do lewej).

**Zasada portu:** kontroler eksportuje wrapper BEZ własnej ramki (UICorner+UIStroke), BEZ headera (title+X), BEZ background — menu zapewnia ramę. Pierwotne pozycje children z offsetem `HEADER_H + PAD` → set `HEADER_H = 0` (1-line change zamiast bulk reposition).

Każdy stary `setOpen(true|false)` zostaje w plikach ale nie jest wywoływany — toggle'e przekierowane na menu.

---

## Sklep z plecakami (ShopService + ShopController)

### Setup w workspace
- Model `workspace.Sklep` zawiera dziecko **`Blat`** (BasePart lub Model z PrimaryPart)
- Serwer automatycznie dodaje `ProximityPrompt` na blat (`ActionText="Sklep z plecakami"`, `RequiresLineOfSight=false`, `MaxActivationDistance=8`)
- Trigger prompta → `OpenShop:FireClient(player)` → klient pokazuje UI

### UI (ShopController)
- Pełnoekranowy overlay w stylu Inventory: panel `680×~520`, header `C_HEADER` z tytułem "SKLEP — PLECAKI" + czerwony X
- Lista **3 karty** (jedna per `Config.BackpackUpgrades`): badge "LV N", nazwa plecaka, pojemność, status, przycisk KUP z hover-animacją
- Stany karty:
  - **KUPIONE** (level ≤ current) — zielony status, przycisk "POSIADANE ✓"
  - **DOSTĘPNE** (level == current+1, kasy starczy) — niebieski status, zielony KUP
  - **ZA MAŁO ZŁ** (level == current+1, brak kasy) — czerwony status, szary przycisk
  - **WYMAGA LV N** (level > current+1) — szary status, "ZABLOKOWANE"
- Auto-refresh przy `BackpackResult` (po zakupie) i `leaderstats.Zlotowki.Changed`
- Wyjście: X w rogu lub `Escape`

### Logika serwera
- `BuyBackpack:FireServer(targetLevel)` → ShopService waliduje:
  1. `targetLevel == current+1` (sekwencyjny zakup)
  2. `targetLevel <= #Config.BackpackUpgrades` (max 3)
  3. `data.Zlotowki >= upgrade.Cost`
- Sukces → odjęcie kosztu, `data.BackpackLevel = targetLevel`, `UpdateLeaderstats`, `UpdateHUD:FireClient` z nową pojemnością, `BackpackResult:FireClient({success=true, newLevel, newCapacity})`
- Błąd → `BackpackResult` z `reason`: `"already"` / `"sequential"` / `"broke"` / `"max"` / `"bad"`

### RemoteEvents
- `OpenShop` (server → client) — triggered przez ProximityPrompt
- `BuyBackpack` (client → server) — payload: `targetLevel: number`
- `BackpackResult` (server → client) — payload: `{success, reason?, newLevel?, newCapacity?}`

---

## Kosz — przeszukiwanie (KoszService + KoszController)

### Setup w workspace
- Folder **`workspace.Kosze`** z dziećmi (każde = jeden kosz, BasePart lub Model z PrimaryPart)
- Serwer auto-dodaje `ProximityPrompt` (`HoldDuration = 2`, `ActionText="Przeszukaj kosz"`, `RequiresLineOfSight=false`, dist=7)
- `folder.ChildAdded` listener — runtime-added kosze też dostają prompt

### Cooldown
- **30s per kosz** (`KOSZ_COOLDOWN_SEC`) — `koszCooldownUntil[kosz] = tick() + 30`
- Sprawdzane na `Triggered` — odrzuca z `reason="cooldown"` jeśli aktywny

### Logika dropu
1. Sprawdza pojemność: jeśli `carried >= capacity` → `reason="full"`
2. Losuje rzadkość (te same szanse co spawn butelek)
3. Losuje **ilość** (weighted) z `Config.KoszDropQuantity[rarity]`
4. Pre-check: jeśli `carried + count > capacity` → `reason="noSpace"` (z `rarity`, `count`, `freeSpace`)
5. OK → `BackpackContents[rarity] += count`, sync `UpdateHUD`, fire `KoszResult` z `{success, rarity, count}`

### RemoteEvent KoszResult payload
- Success: `{ success=true, rarity, count }`
- Fail: `{ success=false, reason }` gdzie reason: `"full"`, `"noSpace"`, `"cooldown"`
- noSpace dodatkowo: `{ rarity, count, freeSpace }`

### Roulette UI (KoszController)
- Bez panelu chrome — tylko window 416×312 z gradientem fade na krawędziach (UIGradient transparency: opaque w środku, fade na top/bottom)
- **Strip** 36 itemów × `ITEM_H=104` przesuwany pionowo (Quint Out 3.5s)
- Winner na indexie `STRIP_LEN - 1 - WINNER_OFFSET (5)` — 5 buffer itemów PO winnerze żeby strip nie wyglądał na kończący się
- **Indicator** UIStroke 4px biały transparency 0.05 — jedyna widoczna ramka, na panelu (nie window — gradient by ją zfadeował)
- Itemy: `darken(rarity.color, 0.55)` tło + stroke w pełnym kolorze rzadkości + tekst **`+N RZADKOŚĆ`** (decoy itemy losują N ważonym samplingiem z `Config.KoszDropQuantity[rarity]` — gracz widzi prawdopodobne ilości już w trakcie spinu, nie tylko końcowy wynik)
- **VFX Legendarnej** w roulette (jak w EQ): rotujący UIGradient gold/orange + pulsujący stroke (Heartbeat, sin 4.5 Hz)
- Result label: `"+N RARITY"` z fade-in 0.12s → hold 0.55s → fade-out 0.25s (szybko żeby nie męczyć)
- Fail messages: `"PLECAK PEŁNY!"`, `"ZA MAŁO MIEJSCA (X/Y) — ODDAJ DO BUTELKOMATU!"`, `"PUSTY KOSZ"`

---

## Questy (QuestService + QuestController)

### Pula 10 questów (`Config.Quests`)
- collect rarity X (Zwykla/Rzadka/Epicka/Legendarna z różnymi targetami i rewardami)
- collect_any 75
- earn 500/2000 zł
- search_kosz 8
- empty_backpack 4 razy
- buy_skill 1 ulepszenie
- Reward zawsze `{ kind="zl", amount=N }`

### Logika serwera
- **Per-player** quest state w `data.Quests = { activeIds, progress, claimed, refreshAt }`
- `RefreshQuests(player)` — shuffle puli, weź 3, reset progress/claimed, `refreshAt = now + 6h`
- `ensureFreshSet(player)` — auto-refresh gdy `refreshAt <= now` LUB brak setu
- `AddProgress(player, type, params)` — increments każdy quest który matchuje:
  - `"collect"` (rarity, amount) — match po `kind == "collect"` AND `rarity` lub `kind == "collect_any"`
  - `"earn"` (amount), `"search_kosz"`, `"empty_backpack"`, `"buy_skill"`
- `ClaimQuest:FireServer(questId)` → walidacja (active, complete, not claimed) → `data.Zlotowki += reward.amount` → fire `ClaimQuestResult`

### Hooks (server-side)
- `BottleService` collect → `AddProgress("collect", {rarity, amount=1})`
- `BottleService` butelkomat → `AddProgress("earn", {amount})` + `AddProgress("empty_backpack")`
- `KoszService` udane przeszukanie → `AddProgress("collect", {rarity, amount=count})` + `AddProgress("search_kosz")`
- `UpgradeService` Base/Speed/Mult → `AddProgress("buy_skill")`

### Bootstrap
- **GameServer musi require `QuestService` PRZED BottleService/KoszService/UpgradeService** (one go używają na top-level)
- `Players.PlayerAdded` → `task.wait(1)` na load → `ensureFreshSet` → `QuestInit:FireClient`

### UI (QuestController)
- Panel 560×~422, header "QUESTY" + countdown "Nowe za Xh Ym" (Heartbeat refresh co 1s)
- 3 karty, każda: opis questa, pasek progresu (niebieski → zielony gdy complete), `X/Y`, nagroda po prawej, przycisk
- Stan przycisku: **W TRAKCIE** (szary) / **ODBIERZ** (zielony) / **ODEBRANO ✓** (zielony pusty)
- Listener `QuestInit` (snap), `QuestUpdate` (progress delta), `ClaimQuestResult`
- Toggle: klawisz `Q` lub przycisk QUESTY w HUD

### RemoteEvents
- `QuestInit` (server → client) — pełen snapshot
- `QuestUpdate` (server → client) — `{ progress = {[qid]=val, ...} }`
- `ClaimQuest` (client → server) — `questId`
- `ClaimQuestResult` (server → client) — `{ success, questId?, reward?, reason? }`

---

## Cutscena tutorial (IntroService + IntroController)

### Cel
Pierwsze wejście → automatyczna cutscena pokazująca 3 sceny w mini-mapie. Każde kolejne wejście → bez cutsceny. Można replay z USTAWIENIA.

### Studio setup
- **`workspace.CutsceneStage`** (Model) — mini-mapa, statyczna scena (poza zasięgiem głównej mapy)
- **NPC `Marcelk1122`** (R15) w CutsceneStage — statyczna postać w pozie sugerującej akcję (bez animacji teraz)
- **Markery kamery** (Anchored, Transparency=1, CanCollide=false):
  - `Cam_Scene1`, `Cam_Scene1_End` — kamera dolly dla sceny 1
  - `Cam_Scene2`, `Cam_Scene2_End`
  - `Cam_Scene3`, `Cam_Scene3_End`
- **Markery NPC** (opcjonalnie): `NPC_Scene1/2/3` — teleport NPC przed sceną
- **Props per scena** (butelki, kopia AutomatKaucyjny, kopia Kosza) — statyczne w CutsceneStage

### Tabela SCENES (IntroController)
```lua
SCENES = {
    { id="Scene1", text="ZBIERAJ BUTELKI",       cameraStart="Cam_Scene1", cameraEnd="Cam_Scene1_End", duration=3.5,
      bottle = { delay=0, rarity="Legendarna", offset=CFrame.new(0,-0.6,0) } },
    { id="Scene2", text="ODDAWAJ I ZBIERAJ KASE", cameraStart="Cam_Scene2", cameraEnd="Cam_Scene2_End", duration=3.5 },
    { id="Scene3", text="ULEPSZAJ POSTAĆ",        cameraStart="Cam_Scene3", cameraEnd="Cam_Scene3_End", duration=3.5 },
}
```
- Każda scena może mieć: `animName` (z ReplicatedStorage.IntroAnims), `bottle = { delay, rarity, offset }`, `npcMarker` (do teleportu NPC)
- Cut między scenami: kamera teleportuje do `cameraStart` następnej, **tekst fade-out (0.2s) → swap → fade-in**

### Animacje NPC
- `IntroService` rejestruje **`KeyframeSequence` z ServerStorage.RBX_ANIMSAVES.<NpcName>.<seqName>`** via `KeyframeSequenceProvider:RegisterKeyframeSequence(seq)` — zwraca temp AssetId
- Tworzy `Animation` w `ReplicatedStorage.IntroAnims.<exportName>` z tym AnimationId
- Klient: `humanoid:LoadAnimation(animFolder:FindFirstChild(NPC_ANIM_NAME))` → `:Play()`
- **Edycja animacji w Studio wymaga restart playtesta** (snapshot jest cached przy starcie serwera)
- Obecnie scena 1 ma `bottle.delay=0` (butelka od razu w ręce, bo bez animacji — statyczna poza pickup)

### Butelka w ręce
- Klonowana z `ReplicatedStorage.BottleModels[rarity]`
- Parts: `Anchored=false`, `CanCollide=false`, `Massless=true`, `CastShadow=false`
- `WeldConstraint` Part0=`RightHand` (R15), Part1=PrimaryPart butelki
- VFX dla Legendarnej: `PointLight` gold (255,195,70), Brightness=1.2, Range=8
- Cleanup w `stop()` — destroy butelki + stop track + restore kamera

### Letterbox bars + tekst
- TopBar/BotBar (Frame, czarne, `BAR_H = 100`) — slide-in/out (Quint 0.45s/0.30s)
- TextLabel (TextSize 52, GothamBlack, biały, TextStroke) — fade-in/out per scena (Quad 0.4s)
- Skip button "POMIŃ ›" prawy dolny róg + klawisz **`Esc`**

### Hide all GUI during cutscene
- `hideOtherGuis()` — iteruje `playerGui:GetChildren()` i wyłącza wszystkie ScreenGui (oprócz Intro)
- `restoreOtherGuis()` — przywraca tylko te które były enabled
- Generyczne — auto-handles future panels

### Autoplay flow (pierwsze wejście)
1. Server `IntroService.PlayerAdded` → `task.wait(2.5)` na PlayerDataService load → if `not HasSeenIntro` → `PlayIntro:FireClient(player)`
2. Client `IntroController.PlayIntro` listener → `pendingAutoplay = true` → `tryAutoplay()`
3. `tryAutoplay()` czeka na `_G["__loadingDone"]` (set przez LoadingController po tap)
4. Po tap → `tryAutoplay()` wywołane przez LoadingController → `autoPlayMode = true` → `start()`
5. Po końcu (lub Esc) → `stop()` sprawdza `autoPlayMode` → `IntroFinished:FireServer()` → server set `data.HasSeenIntro = true` + SaveData

### Replay z USTAWIENIA
- Przycisk "ZOBACZ INTRO PONOWNIE" → `_G["__playIntroTest"]()` (bez autoplay flag — nie ustawia HasSeenIntro)

### Eksport `_G`
- `_G["__playIntroTest"]` — replay (z Settings/test button)
- `_G["__introTryAutoplay"]` — wywoływane przez LoadingController gdy tap
- `_G["__loadingDone"]` — flag (ustawiany przez LoadingController)

### RemoteEvents
- `PlayIntro` (server → client) — trigger autoplay na pierwsze wejście
- `IntroFinished` (client → server) — set HasSeenIntro=true

---

## Loading screen (LoadingController)

### Realne ładowanie (nie tylko kosmetyka)
1. **WaitForChild `leaderstats`** (timeout 15s) — proxy że PlayerDataService załadował dane gracza
2. **`ContentProvider:PreloadAsync(assets)`** — yieldy ładuje:
   - Wszystkie modele z `ReplicatedStorage.BottleModels`
   - `workspace.AutomatKaucyjny` (jeśli istnieje)
   - `workspace.Sklep` (jeśli istnieje)
   - Wszystkie dzieci `workspace.Kosze` (jeśli istnieje)
3. **Minimum 1.0s** load time — żeby UI nie miknął gdy assety w cache

### UI
- Pełnoekranowy `ScreenGui` `DisplayOrder=200` (nad cutsceną, nad HUD)
- Czarne tło (TextButton — click anywhere dismiss)
- **Tytuł "KAUCJA SIMULATOR"** TextSize 96, **Font `LuckiestGuy`** (cartoony chunky), kolor **`Color3.fromRGB(80, 160, 100)`** (matowy leśny zielony, ten sam co `C_BASE_ACC`)
- Subtitle dynamic: `"ŁADOWANIE"` z animowanymi kropkami (0-3, co 0.5s)
- Status pod tytułem: `"dane gracza…"` → `"modele butelek…"` → `"preload assetów (N)…"`
- **"KLIKNIJ BY KONTYNUOWAĆ"** — pojawia się dopiero po loadzie, pulsuje (sin 3 Hz)
- `loadingReady` flag blokuje tap przed preloadem

### Synchronizacja z autoplay cutsceny
- Ustawia `_G["__loadingDone"] = true` na dismiss
- Wywołuje `_G["__introTryAutoplay"]()` — IntroController wtedy odpala autoplay jeśli `pendingAutoplay`
- Fade out wszystkiego (0.6s Quint In) → `gui:Destroy()` po 0.75s

### Bootstrap
- LocalScript w `StarterPlayerScripts` — pokazuje się od razu przy ładowaniu klienta
- Nie ma toggle / hot-key — jednorazowy ekran

---

## Ustawienia (SettingsController)

### Panel 480×480 w stylu Inventory/Skill Tree
- Header `USTAWIENIA` + czerwony X w prawym górnym
- Sekcja **TUTORIAL**:
  - Description: "Odtwórz cutscenę intro od nowa — pokazuje jak zbierać, oddawać i ulepszać."
  - Button **"ZOBACZ INTRO PONOWNIE"** (niebieski accent `C_ACC_BLUE`) → wywołuje `_G["__playIntroTest"]()`
- Sekcja **DŹWIĘK**:
  - Label "Głośność SFX" + slider (track 10px, knob 26px round, fill w `C_ACCENT_GREEN`)
  - Slider modyfikuje `SoundService.SfxGroup.Volume` (0.0 - 1.0)
  - Procent (`"100%"`) po prawej stronie wiersza
  - Drag obsługiwany przez `UserInputService.InputChanged` (mysz + touch)
  - **Brak persystencji** — głośność resetuje się do 1.0 przy każdym wejściu (TODO: zapis w PlayerData)
- Sekcja **POSTĘP** (danger):
  - Czerwony przycisk "RESETUJ POSTĘP" (`C_DANGER = (180,60,60)`, hover `(220,80,80)`)
  - Klik → pełnoekranowy confirm dialog "NA PEWNO RESETOWAĆ?" z opisem efektu i przyciskami **ANULUJ** / **RESETUJ**
  - Klik **RESETUJ** → confirm znika, pojawia się pełnoekranowy blokujący ekran **"RESETOWANIE POSTĘPU…"** (DisplayOrder=500, czerwony tytuł, "Za chwilę gra uruchomi się ponownie. Nie zamykaj okna.") + `ResetProgress:FireServer()`
  - Server (PlayerDataService): `cache[player] = deepCopy(DEFAULT_DATA)` + `SaveData` + `task.delay(0.3)` → `TeleportService:Teleport(game.PlaceId, player)` (auto-rejoin do tej samej gry)
  - **W Studio teleport nie działa** → fallback `player:Kick("[Studio] Postęp zresetowany. Uruchom playtest ponownie.")` — gracz musi zatrzymać i odpalić playtest. Ekran "RESETOWANIE…" zostaje wtedy na ekranie aż user zamknie playtest (akceptowalne, Studio-only)
- Toggle: przycisk **USTAWIENIA** w HUD (4. w stacku)
- Eksport: `_G["__settingsToggle"]`

### Możliwe rozszerzenia (TODO)
- Persystencja głośności SFX (DataStore)
- Volume slider dla muzyki
- Sensitivity kamery
- Reset DataStore (z confirm)
- Toggle particle effects
- Język UI

---

## Event "Deszcz Legendarek" (BottleService + LegendaryEventController)

### Cel
Serwer-wide event co 8-12 min: mapa czyści się i przez 15s spawnują się **tylko Legendarne** butelki. Buduje hype, sprawia że gracze rzucają wszystko żeby zbierać.

### Logika serwera (BottleService)
- `startLegendaryEventLoop()` w nieskończoność czeka `random(MinIntervalSec, MaxIntervalSec)` (`Config.LegendaryEvent`)
- `startLegendaryEvent()`:
  1. Ustawia flagę `legendaryEventActive = true`
  2. `clearAllBottles()` — czyści całe `workspace.Bottles`
  3. `floodLegendaryBottles(Config.LegendaryEvent.BottleCount)` — spawnuje 30 legendarek
  4. `LegendaryEventStart:FireAllClients({ duration = 15 })`
  5. `task.delay(15, ...)` → koniec: clearBottles, `LegendaryEventEnd:FireAllClients()`, refill normalny pool
- Flaga `legendaryEventActive` respektowana przez `scheduleRespawn` i `startRespawnLoop` — w trakcie eventu wymuszają `"Legendarna"` jako `forcedRarity`
- `EnsureRareBottles` pomijane w trakcie eventu (nie chcemy Epickich)

### Client (LegendaryEventController)
- Złoty pasek z licznikiem u góry (`timerHolder`, slide-in do `Y=110` żeby był pod walletem)
- Alert "DESZCZ LEGENDAREK!" na środku (pop-in 0.35s + auto fade po 1.6s)
- `ColorCorrectionEffect` "__LegendaryEventCC" w Lighting → tint `(255, 220, 160)` + Brightness 0.05 + Saturation 0.15 (tween 0.8s)
- W ostatnich 5s licznika cyfra pulsuje (sin 6 Hz, gold → bright orange)
- Cleanup: clearGoldenSky (tween do RGB(255,255,255), Enabled=false), slideTimerOut

### RemoteEvents
- `LegendaryEventStart` (server → all clients) — payload `{ duration }`
- `LegendaryEventEnd` (server → all clients)

---

## Quest Dziadka (GrandpaService + SyrupService + GrandpaController)

### Cel
Pierwszy quest narracyjny z linią fabularną przenikającą inne systemy: itemy fabularne dzielą plecak z butelkami, dialog ma własny visual-novel UI, syrop spawnuje się per-player w jednej z 3 losowych lokacji. Architekturalny szablon pod przyszłe questy NPC.

### State machine (per gracz, w `data.Grandpa`)
- **`none`** → "Cześć młodzieńcze!..." → [PRZYJMIJ] [ZAMKNIJ]
- **`active` + !hasSyrup** → "Szukaj dalej w parku..." → [ZAMKNIJ]
- **`active` + hasSyrup** (= state "ready" w payload) → "Och, masz mój syrop!" → [ODDAJ (+1000 zł)] [ZAMKNIJ]
- **`done`** → "Co tam młodzieńcze?" → [ZAMKNIJ] (placeholder pod przyszłe questy)
- **Transient "justAccepted"** → tuż po accepcie wysyłany OSOBNY payload "Dobrze, czekam..." → [ZAMKNIJ]. Następnym razem gdy gracz zagada → standardowy `active`

### Setup w Studio
- **`workspace.Grandpa`** — Model R15 z `HumanoidRootPart` i `Head` (serwer szuka HRP, fallback PrimaryPart)
- **`workspace.SyrupSpawnPoints`** — Folder z 3 Partami: `SyrupSpawn1`, `SyrupSpawn2`, `SyrupSpawn3` (Anchored, Transparency=1, CanCollide=false)
- **`workspace.SyrupActive`** — auto-tworzony folder na żywe syropy

### Spawn syropu (SyrupService)
- Server po `GrandpaAccept` losuje `syrupLocation = math.random(1, 3)`, spawnuje model
- Model = klon `ReplicatedStorage.SyrupModel` jeśli istnieje, inaczej **fallback cylinder** w `Config.GrandpaQuest.SyrupColor` (brąz, Material=Glass, rozmiar 2×1.2×1.2, rotowany do leżącej butelki)
- Model dostaje attribute **`OwnerUserId`** + `PointLight` (brąz/gold, range=14) + `ProximityPrompt` (Activation=6, HoldDuration=0)
- **Per-player visibility:** klient (GrandpaController) iteruje `workspace.SyrupActive`, dla modeli z `OwnerUserId ≠ localPlayer.UserId`:
  - `BasePart.LocalTransparencyModifier = 1` (niewidoczne lokalnie)
  - `ProximityPrompt.Enabled = false`
  - `PointLight.Enabled = false`
- **Server-side gate** w `prompt.Triggered`: `if player.UserId ~= ownerUserId then return end` (defense in depth)
- Cooldownów brak — pickup raz, model się destroyuje

### Persystencja syropu
- Gracz disconnect podczas questa → `data.Grandpa` zapisuje state
- PlayerAdded → SyrupService czeka 2s na load DataStore + character spawn → `SpawnFor(player)` jeśli `state="active"` i `!hasSyrup`
- Jeśli `hasSyrup=true` przy reconnect → model NIE spawnuje się (jest w plecaku)
- `ResetProgress` → SyrupService.DespawnFor(player) przed kickiem/teleportem

### Plecak: syrop zajmuje 1 slot
- `data.BackpackContents` to wciąż tylko rzadkości butelek (butelkomat resetuje to pole — syrop musi być oddzielnie)
- `data.Grandpa.hasSyrup` (bool) — wlicza się do `carried` przy każdym sprawdzeniu pojemności
- Hooks: `BottleService.CollectBottle`, `KoszService.Triggered`, `SyrupService.HandlePickup` — wszystkie liczą `carried = sum(BackpackContents) + (hasSyrup and 1 or 0)`
- Pełny plecak + próba pickup syropu → reject z `reason="full"` → komunikat "PLECAK PEŁNY! IDŹ DO BUTELKOMATU"
- Butelkomat NIE czyści `hasSyrup` (tylko BackpackContents)

### Inventory UI — syrop jako 5. typ itemu
- Rozszerzona logika slotów w `CollectController`: stałe `SYRUP_ID = "Syrop_Maple"`, `SYRUP_NAME = "Syrop Dziadka"`, `SYRUP_COLOR = Config.GrandpaQuest.SyrupLight`
- `syncSlotsFromContents()` — najpierw butelki (jak dotąd), potem `if hudData.hasSyrup then addSyrupToInventory() end`
- Renderowanie identyczne jak butelki: `darken(SYRUP_COLOR, 0.45)` tło + pełny SYRUP_COLOR stroke + biały tekst
- Detail panel rozpoznaje `SYRUP_ID` i pokazuje inny widok: "Przedmiot zadania", "Nie sprzedasz tego w butelkomacie", opis questa, BEZ wartości / mnożnika
- `UpdateHUD` payload rozszerzony o `hasSyrup` — synchronizuje stan klienta z serwerem
- `playSfx("PickingUp")` przy podniesieniu syropu, `showFloatingText("SYROP DZIADKA", SYRUP_COLOR)` w brązie

### Quest panel (QuestController) — sekcja DZIADEK warunkowo + ZADANIA DZIENNE
- **DZIADEK** (sekcja na górze, accent kolor `C_SYRUP = Color3.fromRGB(200, 130, 60)`) — **widoczna tylko gdy `state == "active"`**
  - Pojedyncza karta o tej samej strukturze co quest dzienny (opis, pasek progresu, nagroda, status)
  - Pasek progresu `0/1` (brązowy)
  - Status: "ZNAJDŹ W PARKU" lub "ODDAJ DZIADKOWI" (gdy `hasSyrup`). UIStroke `Thickness=0` — spójnie z daily quest claimBtn (płaski styl bez ciemnej obramówki)
  - **BEZ przycisku CLAIM** — odbiór nagrody u dziadka, nie w UI
  - `state == "none"` (nie przyjąłeś) lub `state == "done"` (oddałeś syrop) → sekcja DZIADEK CAŁKOWICIE UKRYTA (grandpaLbl + grandpaContainer Visible=false), ZADANIA DZIENNE + countdown przesunięte do góry, panel skrócony
- **ZADANIA DZIENNE** (sekcja pod spodem, akcent `C_GREEN`)
  - 3 questy z `Config.Quests` z countdown odświeżania
  - `claimBtn` status "W TRAKCIE" / "ODBIERZ" / "ODEBRANO ✓" — `UIStroke.Thickness = 0` (no border, czyściej)
- `relayoutForGrandpaVisibility(showSection)` przelicza pozycje dailyLbl/refreshLbl/cardsContainer i resize panel.Size co render
- Listener `GrandpaState` (RemoteEvent) odświeża kartę dziadka — server fire'uje na PlayerAdded (sync) + każdej tranzycji + pickup syropu

### Visual-novel dialog box (GrandpaController)
- Klasyczny dialog na dole ekranu: **960×220, prostokątny (no UICorner)**, slide-in od dołu
- **Avatar 180×180 po lewej, kwadrat (no UICorner)**, ciemny brąz tło + 4px stroke
- **Twarz dziadka** = `ViewportFrame` klonujący `workspace.Grandpa` (cały model, anchored, Humanoid usunięty), kamera 3.2 studs przed `HumanoidRootPart.LookVector`, FoV=32 (ciasny portret)
- Priorytety źródła avatara: `Config.GrandpaQuest.AvatarImage` (ImageLabel custom) → ViewportFrame z workspace → fallback `👴` emoji
- **Tekst typewriter** — 35 znaków/s (`Config.GrandpaQuest.TypeSpeed`), zmienne `currentText` + `typing` flag
- **Klik gdziekolwiek** (overlay lub box) lub **Space/Enter** → `skipTypewriter()` ustawia `dialogText.Text = currentText` od razu + pokazuje przyciski
- **Brak dimowania ekranu** — overlay zawsze przezroczysty (BackgroundTransparency=1), tylko łapie kliki
- **Pop-in przyciski** (Back easing, Scale 0.6 → 1.0, 0.22s) pojawiają się PO skończeniu pisania
- **Hint** "▼ kliknij by pominąć" w prawym dolnym rogu podczas pisania
- Przyciski **kwadratowe** (no UICorner): PRZYJMIJ/ODDAJ zielone z czarnym tekstem (`makeButton(text, bgColor, textColor, onClick)`), ZAMKNIJ niebieski z białym
- ESC zamyka dialog

### RemoteEvents
- `GrandpaTalk` (legacy, niewykorzystywany — server bezpośrednio fire'uje GrandpaDialog z prompt.Triggered)
- `GrandpaDialog` (server → client) — payload `{ state, text, options = {"accept"|"turnin"|"close"}, reward? }`
- `GrandpaAccept` (client → server) — gracz klika PRZYJMIJ
- `GrandpaTurnIn` (client → server) — gracz klika ODDAJ
- `GrandpaState` (server → client) — payload `{ state, hasSyrup, desc, reward }` — dla QuestController, fire na PlayerAdded + każdej tranzycji
- `SyrupPickupResult` (server → client) — payload `{ success, reason? }` — VFX/SFX feedback

### Bootstrap order (krytyczne!)
- **`SyrupService` musi być wymagany PRZED `GrandpaService`** w `GameServer.server.luau` — GrandpaService używa SyrupService.OnQuestAccepted w handler `GrandpaAccept`
- SyrupService.HandlePickup wymaga GrandpaService dynamicznie przez `pcall(require)` (do `PushStateTo`) — to OK, bo do tego czasu oba są załadowane

## Bank (BankService + BankController)

### Cel
Skarbiec na butelki — gracz może odłożyć butelki na boku zamiast trzymać je w plecaku. Pojemność skarbca **dynamiczna** (`BaseCapacity=10` + każde ulepszenie +1), plecak ma limit z `BackpackUpgrades`. Operacja transferu jest atomowa: gracz przesuwa sloty drag-and-drop w UI, klika POTWIERDŹ, serwer waliduje conservation + capacity i zapisuje.

### Setup w Studio
- **`workspace.BANK`** — Folder/Model zawierający dziecko **`Bankier`** (Model R15 lub BasePart)
- Serwer szuka `workspace.BANK:WaitForChild("Bankier")`, bierze `PrimaryPart` lub pierwszy `BasePart`
- Auto-dodaje `ProximityPrompt` (`ActionText="Otwórz bank"`, `ObjectText="Bankier"`, `MaxActivationDistance=8`, `HoldDuration=0`, `RequiresLineOfSight=false`)

### Persystencja (osobny DataStore)
- **`DataStoreService:GetDataStore("BankData_v1")`** — separate od PlayerData (saldo Zlotowki, upgrady itd.)
- Klucz: `"BankData_v1_" .. player.UserId`
- Wartość: `{ Zwykla=N, Rzadka=N, Epicka=N, Legendarna=N, Mityczny=N }` (tylko integery)
- `data.BankCapLevel` (PlayerData) — liczba ulepszeń pojemności skarbca (każde +1 cap)
- Cache w pamięci serwera: `cache[player] = data`
- Auto-save co 60s + `PlayerRemoving` + `BindToClose`

### Pojemność skarbca i ulepszenia
- `getBankCapacity(pData) = Config.Bank.BaseCapacity + pData.BankCapLevel` (L0 → 10, L1 → 11, L2 → 12...)
- `nextUpgradeCost(pData) = Config.Bank.UpgradeBaseCost + BankCapLevel × Config.Bank.UpgradeCostStep` (L0 → 1000, L1 → 1500, L2 → 2000...)
- `Config.Bank = { BaseCapacity = 10, UpgradeBaseCost = 1000, UpgradeCostStep = 500 }`

### Walidacja transferu (server-side, `handleTransfer`)
1. **Conservation check** per rzadkość: `oldBackpack[r] + oldBank[r] == newBackpack[r] + newBank[r]` — gracz nie może wygenerować butelek z powietrza ani ich zgubić
2. **Capacity check**: `sum(newBackpack) + (hasSyrup and 1 or 0) <= BackpackUpgrades[BackpackLevel].Capacity` — syrop dziadka też liczy się do pojemności plecaka
3. **Bank capacity check**: `sum(newBank) <= getBankCapacity(pData)` — fail z `reason="bankFull"`
4. Sukces → zapis do `pData.BackpackContents` + `cache[player]` (bank), `SaveData` + `saveBank`, fire `UpdateHUD` + `BankResult` (z aktualną `bankCapacity`)
5. Błąd → `BankResult` z `reason`: `"invalid"`, `"conservation"`, `"overCapacity"`, `"bankFull"`, `"locked"`

### Otwarcie banku
- `prompt.Triggered` → server fire `BankInit:FireClient` z payloadem `{ bankContents, backpackContents, backpackCapacity, bankCapacity, bankUpgradeLevel, bankUpgradeCost, zlotowki, hasSyrup }`
- Klient odbiera, buduje sloty (15 na sztywno per panel), staguje zawartość z cache layoutu, pokazuje split-view

### UI (BankController) — split-view SKARBIEC ⇌ EKWIPUNEK
- Standalone `ScreenGui` `BankGui` (`DisplayOrder=50`), NIE port do MenuController — otwierane wyłącznie przez ProximityPrompt
- Panel `TR_W × TR_H` (centered), pop-in animacja (slide Y 0.55 → 0.5, Quint 0.28s) + dim overlay 0.35
- Header `BANK KAUCYJNY` z czerwonym X (zamknij). Counter `X/N` w headerze SKARBIEC (czerwony gdy przekroczony)
- **Lewy panel SKARBIEC** + **Prawy panel EKWIPUNEK** rozdzielone separatorem `⇌` (DIV_W=60)
- **Każdy panel: 15 slotów na sztywno (5 kolumn × 3 rzędy)** — `SLOT_COUNT_B=15`, `SLOT_B=78`, `GAP_B=14`, `COLS_B=5`, `MAX_VIS_ROWS=3`. Identyczne wymiary z głównym ekwipunkiem — split layout per slot index 1:1
- Sloty stylem inventory: `darken(rarityColor, 0.45)` tło + pełny rarityColor stroke + biały tekst z TextStroke
- **VFX Legendarnej / Mitycznej** (jak w EQ): rotujący gold/fioletowy UIGradient + pulsujący stroke (Heartbeat sin 4.5 Hz)
- Dolny pasek (wyśrodkowany layout, AnchorPoint=(0.5,0.5), 24px gaps):
  - **[ZAMKNIJ 130w]** center=-199
  - **[POTWIERDŹ 220w]** center=0 (środek paska)
  - **[ULEPSZ 220w]** center=+244 — amber/gold (`Color3.fromRGB(195,145,55)`)
- Movement-lock przez `_G["__lockMovement"]` przy `BankInit`, `_G["__unlockMovement"]` przy `closeBank`
- SFX `Click` na X-close, ZAMKNIJ, ULEPSZ, klik slotów

### Persystencja split layoutu (1:1 sloty, zero auto-sortowania)
- **Bank side**: `_G["__bankLayoutCache"]` — map `[slotIdx] = { rarity, count }`. Zapisywany w `closeBank` i po sukcesie POTWIERDŹ. Przy re-open: jeśli sumy z cache == server bankContents → restore split per slot; mismatch → fallback flat
- **Inv side**: używa `_G["__inventoryGetLayout"]` / `_G["__inventorySetLayout"]` (position-keyed API z CollectController) — splity ekwipunku zachowane między bankiem a głównym EQ
- Po POTWIERDŹ `smartResyncArr` aplikuje delta z server response zachowując pozycje (dodaje do pierwszego stack tej rzadkości / lub pierwszego wolnego slotu na +diff; usuwa z ostatniego na -diff)
- Jedyny wyjątek od "1:1": pickup butelki podczas otwartego banku → stackuje z istniejącym slotem tej rzadkości (UpdateHUD)

### Drag & drop między panelami
- LPM na slocie → `startDrag` ustawia ghost (klon slota), `drag.startPos` = pozycja myszy
- `DRAG_THR = 5` px — poniżej traktowane jako klik (no-op, brak detail panelu)
- RMB na slocie → `splitSlot` dzieli stack na pół (drag drugiej połowy)
- `MouseEnter` na innym slocie podczas dragu → `C_SLOT_HOV` highlight + zapamiętuje `hovPanel/hovSlotIdx`
- `InputEnded` (LPM up) → `endDrag`:
  - Ten sam panel, różne sloty → swap
  - Różne panele → `performTransfer(fromP, toP, fromIdx, toIdx)`: jeśli `tgt.rarity == src.rarity` → merge, inaczej → swap
- **Capacity check przed transferem** (`invTotalAfter()`) — jeśli wynik przekracza `currentCapacity - (hasSyrup and 1 or 0)`, pokazuje `"ZA MAŁO MIEJSCA W PLECAKU!"` (czerwony toast nad przyciskami, fade po 1.8s)
- Staging tylko client-side — serwer dostaje finalny stan dopiero po POTWIERDŹ

### POTWIERDŹ
- Przycisk wysyła `BankDeposit:FireServer({ newBackpackContents, newBankContents })`
- (Server traktuje `BankDeposit` i `BankWithdraw` identycznie przez `handleTransfer` — kierunek dedukowany z conservation. `BankWithdraw` istnieje w events ale klient zawsze fire'uje `BankDeposit`)
- UI w stanie "ZAPISYWANIE..." (przyciemniony zielony) do czasu `BankResult`
- Sukces → re-stage z `result.bankContents/backpackContents`, render. Fail → `showCapacityError`

### ULEPSZ
- Przycisk wysyła `UpgradeBank:FireServer()` (no payload)
- Server: waliduje BaseLevel ≥ 1, sprawdza `zlotowki >= nextUpgradeCost(pData)`, deductuje koszt, `BankCapLevel += 1`, `UpdateLeaderstats`, `SaveData`, fire `BankResult` z `{ success=true, bankCapacity, bankUpgradeCost, upgraded=true }`
- Klient aktualizuje tekst przycisku na nowy koszt + counter X/N pokazuje nową pojemność
- Fail: `reason="broke"` → "ZA MAŁO ZŁ NA ULEPSZENIE", `reason="locked"` → "BANK ZABLOKOWANY"

### RemoteEvents
- `BankInit` (server → client) — payload `{ bankContents, backpackContents, backpackCapacity, bankCapacity, bankUpgradeLevel, bankUpgradeCost, zlotowki, hasSyrup, locked? }`
- `BankDeposit` (client → server) — payload `{ newBackpackContents, newBankContents }` — używany przez POTWIERDŹ
- `BankWithdraw` (client → server) — zarezerwowany alias, server obsługuje go tym samym `handleTransfer` (niewykorzystywany w obecnym kliencie)
- `BankResult` (server → client) — `{ success=true, bankContents, backpackContents, backpackCapacity, bankCapacity, bankUpgradeCost?, upgraded? }` lub `{ success=false, reason }`
- `UpgradeBank` (client → server) — pusty, trigger zakupu ulepszenia pojemności

### Bootstrap order
- `BankService` wymagany **po wszystkich innych** w `GameServer.server.luau` (zależy tylko od `PlayerDataService`)

### Co bank NIE robi
- Nie trzyma złotówek — to wciąż `data.Zlotowki` w PlayerData
- Nie ma przelewów między graczami — skarbiec osobisty per UserId
- Brak odsetek / interestu — czysty storage z capem

---

## Movement lock (UI blokuje ruch)

### Cel
Gdy gracz jest w UI sklep/bank/quest/menu desek lub podczas spinu roulette kosza — postać nie chodzi. Zapobiega głupim zakupom przy spadaniu z mapy i pozwala spokojnie kliknąć POTWIERDŹ bez przemieszczenia się przy WASD.

### Helper (ref-counted, `_G`)
- Definiowany pierwszy raz w `BankController` (guard `if not _G["__lockMovement"]`):
  ```lua
  _G["__moveLockCount"]   -- licznik aktywnych blokad
  _G["__lockMovement"]()  -- inc + Controls:Disable() jeśli count == 1
  _G["__unlockMovement"]()  -- dec + Controls:Enable() jeśli count == 0
  ```
- Używa `PlayerScripts.PlayerModule:GetControls():Disable()` — standardowy Roblox API, kamera dalej działa
- Ref-count pozwala na zagnieżdżone UI (np. otwarte menu + roulette w trakcie)

### Wywoływane przez
- **BankController** — lock w `BankInit`, unlock w `closeBank`
- **ShopController** — lock/unlock w `setOpen(true/false)`
- **QuestController** — lock/unlock w `setOpen(true/false)`
- **DeckShopController** — lock w `setBuyOpen(true)` / `openMenu()`, unlock w X-close / `closeMenu()` / WYPOSAŻ
- **KoszController** — lock w `showRoulette` start, unlock w `hidePanel` (po 0.85s od końca spinu)

---

## SFX system

### Setup w workspace
- Folder **`workspace.SFX`** z `Sound` instancjami:
  - `PickingUp` — odtwarzane przy pomyślnym zebraniu butelki (CollectController)
  - `RouletteTick` — przy każdym itemie przejeżdżającym przez wskaźnik podczas spinu roulette (KoszController)
  - `Win` — gdy spin kończy się sukcesem (KoszController). Auto-utnij ostatnie **0.6s** (parametr `trimEnd` w helper)
  - `Money` — odtwarzane gdy butelkomat przyjmie butelki (CollectController, w `EmptyBackpackResult.success`)
  - `Buy` — odtwarzane przy udanym zakupie plecaka (ShopController) i przy zakupie węzła drzewka (SkillTreeController)
  - `LevelUp` — odtwarzane razem z `Buy` przy zakupie ulepszenia w drzewku (SkillTreeController)
  - `Click` — kliknięcia UI: X-close we wszystkich panelach, przyciski KUP/POTWIERDŹ/ULEPSZ, klik slotu w ekwipunku (otwarcie detail), klik węzła drzewka, klik zakładki menu, hoverboard, karty desek
  - `Equip` — wyposażenie deski (DeckShop menu TWOJE DESKI → WYPOSAŻ)

### SoundGroup
- Wszystkie SFX podpinane do `SoundService.SfxGroup` (auto-utworzone idempotentnie w każdym kontrolerze)
- Suwak w Ustawieniach modyfikuje `SfxGroup.Volume` w czasie rzeczywistym

### Helper `playSfx`
- Inline w CollectController i KoszController (KoszController obsługuje `opts.trimEnd`)
- Klonuje template z `workspace.SFX`, parent = `SoundService`, ustawia `SoundGroup = SfxGroup`, Play
- Auto-cleanup przez `Sound.Ended:Connect(s:Destroy)` (lub task.wait dla trimEnd)
- Czeka na `s.IsLoaded`/`s.Loaded:Wait()` przed obliczeniem `TimeLength - trimEnd`

### Tick podczas spinu roulette
- `RunService.RenderStepped` w `showRoulette` (po starcie spin tween)
- Liczy `idx = floor((WINDOW_H/2 - ITEM_H/2 - stripY) / ITEM_H + 0.5)` co frame
- Gdy `idx` się zmieni → `playSfx("RouletteTick")` → naturalnie zwalnia bo tween jest Quint Out (decelerujący)
- Connection disconnect na `spin.Completed`

---

## Mobile UI scaling (MobileScaleController)

### Cel
UI projektowane na desktopie (1280×720) — na mobile (~720×400) wystaje poza ekran. Globalny `UIScale` per `ScreenGui` zmniejsza całość proporcjonalnie.

### Logika
- Skala = `min(viewportX/1280, viewportY/720)`, clamp `[0.50, 1.00]`
- Wstrzykiwany jako `UIScale` w każde dziecko-GuiObject każdego `ScreenGui` w `PlayerGui`
- Listener `playerGui.ChildAdded` — nowe ScreenGui (np. KoszController) też dostają scaling
- Listener `ChildAdded` na każdym ScreenGui — przyszłe ramki (panele questów itd.) też
- Reaguje na `Camera.ViewportSize:Changed` (rotacja telefonu, resize Studio) — przelicza w locie

### Wyjątki (`SKIP_GUIS`)
ScreenGui o tych nazwach nie są skalowane (mają własne fullscreen reguły):
- `Loading` — loading screen wypełnia cały ekran
- `Splash` (legacy, nie używany)
- `Intro` — cutscena ma własny letterbox

### Bootstrap
- LocalScript w `StarterPlayerScripts` (ostatni w kolejności po wszystkich UI controllerach)

---

## Leaderboard (LeaderboardService)

### Co rankuje
- **Aktualne saldo Zlotowki** (nie TotalEarned) — gracz spada w rankingu gdy wyda kasę, premiuje aktywnych zbieraczy
- Top `Config.LeaderboardMaxEntries` (10), bez self-ranku

### Setup w workspace
- BasePart o nazwie **`LeaderboardTablica`** w `workspace` (anchored, dowolny rozmiar)
- Serwer auto-tworzy SurfaceGui na **Front face** Partu
- Gracz musi podejść — to nie HUD

### DataStore
- `OrderedDataStore` na kluczu `"Leaderboard_Zlotowki_v1"`
- Klucz = `tostring(player.UserId)`, wartość = **grosze** = `math.floor(zlotowki * 100)` (OrderedDataStore wspiera tylko integery)
- Wartość ÷ 100 przy odczycie żeby odzyskać float

### Pętle
- **Save loop** (co `LeaderboardUpdateInterval` sekund, 60s): dla każdego gracza online wywołuje `SetAsync(userId, grosze)` w parallel (`task.spawn`)
- **Display update** (zaraz po save loop + 2s buffer na replikację): `GetSortedAsync(false, MaxEntries)` → renderuje top N
- **Initial update** przy starcie serwera (przed pierwszą pętlą)
- **`PlayerRemoving`**: finalny zapis wychodzącego gracza

### SurfaceGui layout (CanvasSize 800×1100, FixedSize)
- Header (140px): "RANKING KAUCYJNY — TOP 10", `C_HEADER`, TextSize 48
- Separator 4px `C_BORDER`
- 10 wierszy, alternating `C_BG`/`C_PANEL`, `UICorner` 8, transparency 0.05
- Per wiersz: **rank** (`#N`) + **nazwa gracza** + **kwota** w `C_ACCENT_GREEN` (formatAmount z groszami)
- **Kolory rang**: #1 gold `(255,195,70)`, #2 silver `(200,200,220)`, #3 bronze `(205,130,70)`, reszta `C_DIMTEXT`

### Cache nazw
- `nameCache: {[number]: string}` — uniknięcie spamu `GetNameFromUserIdAsync`
- Najpierw szuka po `Players:GetPlayers()` (online → bierze DisplayName), potem `GetNameFromUserIdAsync` w pcall
- Fallback `"User<userId>"` przy błędzie

---

## Zapis danych (PlayerDataService)

- Natywny `DataStoreService`, klucz: `Config.DataStoreKey .. "_" .. player.UserId`
- Zapis przy: `PlayerRemoving`, auto-save co 60s, `game:BindToClose`
- Przy wczytaniu: uzupełniaj brakujące klucze z `DEFAULT_DATA` (`mergeWithDefaults`)
- Po każdej zmianie salda: wywołaj `PlayerDataService.UpdateLeaderstats(player)`

---

## Styl wizualny (świat 3D)

- **Paleta:** pastelowe, stonowane kolory — jasna zieleń trawy, beżowe chodniki, białe/kremowe budynki
- **Geometria:** uproszczone bryły, brak zbędnych detali, low-poly feel
- **Oświetlenie:** `Atmosphere` włączony, `Bloom` lekki, pora dnia ~10:00 (słonecznie)
- **Mapa:** jedno miasto, ~200×200 studs: centrum, park, osiedle, ulice
- **Butelki:** modele z `ReplicatedStorage.BottleModels` (1 model per rzadkość), `PointLight` na PrimaryPart dla Epicka i Legendarna; fallback to cylinder w kolorze rzadkości

---

## Styl UI (wszystkie ekrany 2D)

Każdy element UI musi trzymać się tego stylu. Nie wolno mieszać z ciemnymi/fioletowymi paletami.

### Paleta UI — green theme (#125B49 / #003527 / #051914 / #AADD66)
```lua
C_BG             = Color3.fromRGB(18, 91, 73)    -- #125B49 — główne tło paneli, wallet, przyciski
C_PANEL          = Color3.fromRGB(24, 110, 90)   -- nieco jaśniejszy panel (np. inventory)
C_HEADER         = Color3.fromRGB(0, 53, 39)     -- #003527 — ciemniejsze tło headerów
C_SLOT           = Color3.fromRGB(8, 60, 48)     -- pusty slot
C_SLOT_OC        = Color3.fromRGB(32, 110, 90)   -- zajęty slot
C_SLOT_HOV       = Color3.fromRGB(14, 75, 60)    -- hover slotu podczas dragu (CIEMNE, nie błyska)
C_BORDER         = Color3.fromRGB(5, 25, 20)     -- #051914 — obramówka (prawie czarna zielonkawa)
C_BORDER_SL      = Color3.fromRGB(8, 30, 24)     -- obramówka slotów
C_WHITE          = Color3.fromRGB(255, 255, 255)
C_DIMTEXT        = Color3.fromRGB(175, 175, 175) -- szary tekst pomocniczy
C_ACCENT_GREEN   = Color3.fromRGB(170, 221, 102) -- #AADD66 — akcent salda (wallet PLN), paski progresu, fill suwaków
```

Kolory są **zduplikowane** jako lokalne stałe w każdym kontrolerze (`CollectController`, `SkillTreeController`, `ShopController`, `KoszController`, `QuestController`, `SettingsController`, `LegendaryEventController`). Zmiana palety = PowerShell `Replace` przez wszystkie pliki (zob. historia chatu).

**Wyjątki utrzymane świadomie:**
- `SkillTreeController.C_CANVAS = (10, 10, 10)` — tło drzewka, intencjonalnie ciemne dla kontrastu hexów
- Skill tree per-branch accents: `C_SPEED_ACC = (70, 120, 180)` blue, `C_MULT_ACC = (195, 145, 55)` amber — rozróżnialność gałęzi
- Kolory rzadkości butelek w `Config.BottleColors` — gameplay, nie chrome UI
- `LegendaryEventController` — złoty motyw (gold, dark gold, bright gold) intencjonalnie kontrastuje z zielonym UI

### Zasady
- **Zaokrąglenie:** `UICorner` wszędzie — panele radius=8, sloty radius=12, przyciski radius=8. **Wyjątek: wallet** (HUD) — bez `UICorner`, prostokątne rogi
- **Obramówka:** `UIStroke` kolor `C_BORDER` (5,25,20), grubość **4** na panelach i przyciskach, **3** na slotach i headerach. **Wallet ma grubość 6**
- **Przezroczystość tła:** 0.05–0.1 (delikatne przeświecanie przez świat)
- **Pełnoekranowe panele** (inventory, skill tree): overlay przyciemnienia 0.30 transparency (70% ciemności)
- **Tekst:** biały `C_WHITE` na głównych etykietach, `C_DIMTEXT` na podpisach/kategoriach
- **Czcionka:** zawsze `Enum.Font.GothamBlack`
- **Akcenty kolorów** (rzadkości, węzły drzewka) zachowują swoje kolory — nie szarość
- **Nie używaj** ciemnych granatów/fioletów jako tła
- **Hover-animacje:** klikalne elementy mają `UIScale` rosnący ze środka (`AnchorPoint = (0.5, 0.5)` jeśli potrzeba) — przyciski 1.00 → 1.06, X-close 1.00 → 1.18, sloty 1.00 → 1.06, tween Quad 0.12s
- **`AutoButtonColor = false`** OBOWIĄZKOWO na każdym `TextButton` używanym jako overlay/tło — Roblox domyślnie rozjaśnia kolor na trzymanym LPM, co rujnuje ciemne overlaye (zwłaszcza widoczne przy dragowaniu)
- **Headery panelu** (Inventory, Skill Tree, Shop): wzór **UICorner radius 8 + bottom-fill mask + separator**:
  1. UICorner 8 na header → zaokrągla wszystkie 4 rogi BG
  2. Child Frame 10px tall, full width, no UICorner, color `C_HEADER`, position `(0, 0, 1, -10)` → maskuje zaokrąglone dolne rogi prostokątem
  3. Child Frame 2px tall, full width, color `C_BORDER`, position `(0, 0, 1, -2)` → cienki separator wizualny
  4. NIE używaj UIStroke na headerze — wymusiłby zaokrąglone bordery na dolnych rogach. Border zapewnia stroke samego panelu.
- **Przycisk X (close)** wszędzie: tekst `"X"` (nie `"✕"` — GothamBlack nie ma tego glifa), TextSize 22-24, **bez ramki**, **bez tła**, kolor `Color3.fromRGB(220, 70, 70)`, hover `(255, 110, 110)` + `UIScale 1.18`. Stałe `X_RED` i `X_RED_HOVER` w każdym pliku UI.

---

## Kody promocyjne (CodeService)

### Cel
Sekcja "KODY" w Ustawieniach pozwala wpisać kod tekstowy i odebrać nagrodę zł. Jednorazowo per gracz.

### Config.Codes
```lua
Codes = {
    OGDC  = { reward = 200 },
    PVPOG = { reward = 500 },
}
```

### Persystencja
- `data.RedeemedCodes = { [codeKey] = true }` w PlayerDataService.DEFAULT_DATA
- Auto-merguje się przez `mergeWithDefaults` → stare zapisy bez RedeemedCodes dostają `{}` przy load

### CodeService
- Throttle 0.5s na gracza (anty-spam)
- Walidacja: uppercase + trim, max 32 znaki
- Sprawdza `data.RedeemedCodes[code]` przed wypłatą → fail z `reason="alreadyUsed"`
- Sukces → `data.Zlotowki += reward`, `RedeemedCodes[code] = true`, `UpdateLeaderstats` + `SaveData`

### RemoteEvents
- `RedeemCode` (client→server, payload: raw string)
- `RedeemCodeResult` (server→client, `{ success, reason?, code?, reward? }`)

---

## Plecak na plecach (BackpackEquipService)

### Cel
Wizualnie zakłada Accessory na plecy gracza w zależności od `data.BackpackLevel`. Level 1 (Reklamówka) pominięte cicho — brak modelu.

### Konwencja Studio
- `ReplicatedStorage.BackpackModels.Level<N>` — Accessory (Level 2, Level 3, opcjonalnie Level 4)
- Brak modelu dla danego poziomu → cicho pomijane (gracz dostaje samą pojemność z Config)

### Equip logic
- Znajduje **dowolny BasePart** w Accessory (Handle, "Gray Backpack", cokolwiek) — pierwszy znaleziony BasePart traktowany jako handle
- Próbuje natywnego `Humanoid:AddAccessory` — Roblox podpina przez Attachment
- **Fuzzy attachment matching**: jeśli Accessory ma Attachment z "Back" w nazwie i character ma Attachment z "Back" na UpperTorso/Torso → match. Działa dla `BackAttachment` ↔ `BodyBackAttachment` (różnica między ręcznie zaimportowanym accessory a standard rig).
- Tag attribute `__BackpackEquipped` → czyszczenie starego equip przy zmianie poziomu (kupno w sklepie wywołuje `Refresh(player)`)

### Korekta pozycji — atrybuty na Accessory ALBO na BasePart wewnątrz
- **`BackOffset`** (Vector3, studs) — translacja w przestrzeni UpperTorso/Torso
- **`BackRotation`** (Vector3, stopnie) — rotacja wokół środka torsa (np. `(0, 180, 0)` jeśli plecak ląduje na brzuchu zamiast na plecach — typowy fix gdy attachment artysty ma odwróconą orientację)
- Korekta aplikowana w lokalnej przestrzeni torsa: `localCF = offsetCF * rotCF * localCF` → gwarancja flip front↔back przy 180° Y

### Hook
- `Players.PlayerAdded.CharacterAdded` → `equipForLevel(char, data.BackpackLevel)`
- `ShopService.tryBuyBackpack` po sukcesie → `pcall(BackpackEquipService.Refresh(player))`

---

## Strefa PvP (PvPService)

### Cel
Gracz w `workspace.PVPZone` dostaje miecz z `ReplicatedStorage.Sword` i traci ForceField. Może zadawać i przyjmować obrażenia. Wyjście ze strefy → miecz usunięty.

### Setup w Studio
- **`workspace.PVPZone`** — BasePart (Anchored, CanCollide=false, Transparency=1) gdziekolwiek w workspace (PvPService szuka rekursywnie)
- **`ReplicatedStorage.Sword`** — Tool (np. ClassicSword z toolboxa) z wbudowanymi skryptami damage

### Detekcja
- Server-side poll co **0.25s** — dla każdego gracza sprawdza czy HRP w boxie strefy (`zone.CFrame:PointToObjectSpace`)
- Respektuje rotację partu

### Damage flow
- ClassicSword ma własne skrypty Touched → `Humanoid:TakeDamage`
- Wejście do strefy: `humanoid.ForceField:Destroy()` → gracz może przyjmować obrażenia
- Gracze poza strefą mają natural ForceField na spawn (~10s Roblox default) — chroni new spawnów
- Damage z miecza działa tylko między graczami bez ForceField → praktycznie tylko w strefie

### Hitbox normalization (anty-przewaga małych skinków)
- R15: na wejście wszystkie scale values (`BodyHeightScale`, `BodyWidthScale`, `BodyDepthScale`, `HeadScale`, `BodyTypeScale`, `BodyProportionScale`) zapisywane do cache i wymuszane na **1.0** → wszyscy identyczny rozmiar
- Na wyjście — przywrócone z cache
- R6 pominięte (statyczny rig, hitboxy już identyczne)

### Respawn
- Roblox default — gracz pada w strefie, odradza się na podstawowym SpawnLocation poza strefą
- Flaga `inZone[p]` resetuje się na CharacterAdded

---

## Sklep czapek (HatShopService + HatShopController)

### Cel
Permanentny zakup czapki z bonusami za butelki + zł. Standalone UI (jak BankController).

### Setup w Studio
- **`workspace.SKLEP2.Cashier`** — Model R6/R15 (Head/HumanoidRootPart/Torso) lub BasePart. ProximityPrompt dodawany na Head jeśli model.
- **`ReplicatedStorage.Czapka`** — Accessory (HatAccessory z HatAttachment)

### Config.HatShop
```lua
HatShop = {
    ItemName     = "Czapka",
    Template     = "Czapka",
    CostZl       = 5000,
    CostBottles  = { Legendarna = 10, Mityczny = 1 },
    HpBonus      = 50,    -- Humanoid.MaxHealth += 50
    StaminaBonus = 50,    -- SprintController.STAMINA_MAX += 50
    SpeedBonus   = 2,     -- SprintController.baseSpeed += 2
}
```

### Persystencja
- `data.HatOwned = false` w DEFAULT_DATA — flaga jednorazowego zakupu

### Walidacja serwera (atomowa)
1. `HatOwned == false` → inaczej `reason="already"`
2. `Zlotowki >= 5000` → inaczej `reason="broke"`
3. `BackpackContents[r] >= count` dla każdej z `CostBottles` → inaczej `reason="bottles"`
4. Sukces: pobiera zł i butelki, `HatOwned = true`, `SaveData`, fire `UpdateHUD` + `applyHatEffects`

### Bonusy
- **HP** — server-side na każdy `CharacterAdded`: `hum.MaxHealth = 100 + 50; hum.Health = MaxHealth`
- **Czapka** — `humanoid:AddAccessory(Czapka:Clone())` z tagiem `__ShopHat`
- **Stamina/Speed** — client-side: `HatStatusUpdate` (`{ owned, speedBonus, staminaBonus, hpBonus }`) → SprintController czyta i dolicza do `STAMINA_MAX` + `baseSpeed`

### RemoteEvents
- `OpenHatShop` (server→client) — ProximityPrompt trigger
- `BuyHat` (client→server)
- `BuyHatResult` (server→client, `{ success, reason?, rarity?, need? }`)
- `HatStatusUpdate` (server→client) — sync stanu + bonusy do SprintController

---

## Drop butelek po śmierci (DeathDropService)

### Cel
Gdy gracz umrze, wszystkie butelki z plecaka spadają w okolicy ciała. Plecak czyszczony, gracz instant-respawnuje.

### Logika
- Hook `Humanoid.Died` (debounce `diedHandled` żeby nie odpalił 2x)
- Pozycja ciała: HRP / Torso / UpperTorso / Head / fallback dowolny BasePart
- Dla każdej butelki: random `(angle, dist)` w promieniu **5 stoodów**, wysokość Y znaleziona raycastem
- **Raycast w dół iteracyjnie pomija invisible triggery** (Transparency ≥ 0.9 → np. PVPZone, BottleSpawnAreas). Max 10 iteracji.
- Spawn przez `BottleService.SpawnBottle(pos, rarity, nil, { DeathDropOwner=UserId, DeathDropExpires=os.clock()+5 })`
- Butelki **anchored + CanCollide=false** — nie kolidują z niczym, nie da się ich poturlać

### Cooldown na własne dropy
- Attribute `DeathDropOwner` + `DeathDropExpires = os.clock() + 5`
- `BottleService.CollectBottle` sprawdza: jeśli `dropOwner == player.UserId AND os.clock() < dropExpires` → reject z `reason="ownDropCooldown"`
- Po 5s właściciel też może pickować — inni gracze od razu

### Respawn
- `task.spawn(player:LoadCharacter())` — natychmiastowy respawn (zero delay)
- Roblox spawnuje na SpawnLocation poza strefą śmierci

### Syrop dziadka
- NIE drop'uje się (quest item, zostaje w `data.Grandpa.hasSyrup`)

### Ręczny drop (przycisk UPUŚĆ w inventory)
- Detail panel w ekwipunku ma czerwony przycisk **"UPUŚĆ 1 SZTUKĘ"** (ukryty dla syropu)
- Klient: `DropBottle:FireServer(rarity)`
- Server (BottleService): zdejmuje 1 sztukę, spawnuje butelkę 3 stoody przed graczem (`hrp.LookVector * 3`), bez cooldownu (możesz od razu podnieść)
- `UpdateHUD` syncuje plecak

---

## Panel admina (AdminService + AdminController)

### Cel
F2 otwiera mały panel dla wybranych graczy: broadcast tekstu na ekran wszystkich + samoobsługa zł/butelek.

### Config.Admins
Lista nazw użytkowników Roblox **lub** UserIds (liczby):
```lua
Admins = {
    463763381,    -- UserId (odporne na rename)
    "PROGGam3r",  -- nazwa jako fallback
}
```

### Server flow
- `AdminInit:FireClient(player, { isAdmin })` na PlayerAdded — klient enable F2 tylko gdy true
- `AdminAction:OnServerEvent` waliduje admin status na każdej akcji (anti-cheat)
- Throttle 0.3s między akcjami

### Akcje
- **broadcast** — `AdminBroadcast:FireAllClients({ message, from })` → klient pokazuje duży tekst na środku ekranu (5s, fade in/out)
- **giveZl** — dodaje zł do salda (max 1M per akcja)
- **giveBottles** — dodaje butelki danej rzadkości (max 1000)
- **kick** — `target:Kick("[Admin] reason")`

### Broadcast HUD (dla wszystkich graczy)
- Black box na środku ekranu, gold border, czarny stroke
- Font Gotham (nie GothamBlack — chudy, czytelny)
- Auto fade po 5s

### RemoteEvents
- `AdminInit` (server→client, `{ isAdmin }`)
- `AdminAction` (client→server, `{ action, message?, amount?, rarity?, count?, target?, reason? }`)
- `AdminBroadcast` (server→all clients, `{ message, from }`)

---

## Boost shop (BoostShopService + BoostShopController)

### Cel
Developer Product w Robux — x2 KASA z butelkomatu na 10 minut za 19 R$. Dostępny w zakładce SKLEP w menu.

### Config.BoostShop
```lua
BoostShop = {
    DoubleEarn = {
        ProductId   = 3605052667,  -- ← Developer Product ID z Roblox dashboard
        DurationSec = 600,         -- 10 min
        Multiplier  = 2,
        Name        = "x2 KASA z butelkomatu",
        PriceRobux  = 19,
    },
}
```

### ProcessReceipt
- `MarketplaceService.ProcessReceipt = function(receiptInfo)` — Roblox callback po finalizacji zakupu
- Validacja: `receiptInfo.ProductId == Config.BoostShop.DoubleEarn.ProductId` → `activateDoubleEarn(player)`
- Zwraca `Enum.ProductPurchaseDecision.PurchaseGranted` (lub `NotProcessedYet` na error → Roblox spróbuje ponownie)

### Aktywacja
- `doubleEarnUntil[player] = os.clock() + 600` (cumulative — re-zakup dolicza)
- Co 1s server fire'uje `BoostStatusUpdate` z pozostałym czasem
- BottleService.EmptyBackpack: `multiplier *= BoostShopService.GetEarnMultiplier(player)` — mnoży się ze skill tree multiplierem

### Klient
- Karta w zakładce **SKLEP** menu (4. zakładka między QUESTY a USTAWIENIA)
- Mały badge w prawym górnym rogu HUD gdy aktywny: "x2 KASA 9:42"
- Przycisk "KUP — 19 R$" → `PromptBoostPurchase:FireServer("DoubleEarn")` → server otwiera `MarketplaceService:PromptProductPurchase`

### Brak persystencji
- Restart serwera → boost ginie. Konsumowalny produkt, nie problem.

### RemoteEvents
- `PromptBoostPurchase` (client→server, payload: `productKey` string)
- `BoostStatusUpdate` (server→client, `{ doubleEarnRemainingSec, productId, priceRobux }`)

---

## Deski / Skateboardy (DeskaService + DeskaController + DeckShopController)

### Cel
Gracz kupuje deski (skateboardy) przy gablotach, wyposaża wybraną i jeździ po naciśnięciu **R**. 4 typy o rosnącej prędkości: **Default < Red < Blue < VIP**.

### Config.Decks (tablica = ranking prędkości; ostatnia = najszybsza)
```lua
Decks = {
    { key="Default", name="Deska Default", model="DeskaDefault", Speed=40, CostType="Zlotowki", Cost=1000, gablota=1, color=... },
    { key="Red",     name="Deska Red",     model="DeskaRed",     Speed=48, CostType="Zlotowki", Cost=3000, gablota=2, color=... },
    { key="Blue",    name="Deska Blue",    model="DeskaBlue",    Speed=56, CostType="Zlotowki", Cost=5000, gablota=3, color=... },
    { key="VIP",     name="Deska VIP",     model="DeskaVIP",     Speed=68, CostType="Robux", RobuxProductId=0, RobuxPrice=30, gablota=4, color=... },
}
DeckMenuIconId = "rbxassetid://123773463706470"  -- ikona przycisku hoverboard w HUD
```
- `model` = nazwa Modelu w `workspace.Deski` (szablon klonowany przy jeździe)
- `gablota` = numer gabloty w `workspace.Gabloty` która sprzedaje tę deskę
- **VIP RobuxProductId = 0** — placeholder, wpisz Developer Product ID z dashboardu Roblox

### Persystencja (PlayerData, merge bez bumpu klucza)
- `data.OwnedDecks = { [deckKey]=true }` — posiadane deski
- `data.EquippedDeck = ""` — wyposażona deska ("" = brak; R jeździ najlepszą posiadaną)

### Setup w Studio
- **`workspace.Deski`** — Folder z 4 Modelami: `DeskaDefault`, `DeskaRed`, `DeskaBlue`, `DeskaVIP` (każdy z PrimaryPart). To szablony — DeskaService klonuje je przy jeździe do `workspace.ActiveDecks` (auto-folder)
- **`workspace.Gabloty`** — Folder z `Gablota1..4` (BasePart lub Model z PrimaryPart). DeskaService auto-dodaje ProximityPrompt, mapuje numer w nazwie → deck przez pole `gablota`

### Przepływ
1. **Zakup**: ProximityPrompt na gablocie → `OpenDeckShop:FireClient(deckKey)` → panel zakupu (nazwa, prędkość, cena, KUP). Default/Red/Blue za zł (`BuyDeck`), VIP → `MarketplaceService:PromptProductPurchase`. Grant VIP w **BoostShopService.ProcessReceipt** (jedyny ProcessReceipt w grze) → `DeskaService.GrantDeck(player, "VIP")`
2. **Jazda (R)**: `DeskMount:FireServer(nil)` → serwer klonuje szablon wyposażonej (lub najlepszej posiadanej) deski, weld do HRP, `WalkSpeed = deck.Speed`, `JumpHeight = 0`. Ponowne R = dismount (`DeskDismount`)
3. **Menu desek**: przycisk hoverboard w HUD (lewa strona, pod MENU) → panel TWOJE DESKI z 4 kartami. Klik karty → detale (prędkość, status) + przycisk **WYPOSAŻ** (`EquipDeck`) → serwer ustawia EquippedDeck + natychmiast wsiada na tę deskę
- `DeckStatus:FireClient({owned, equipped, riding})` synchronizuje stan (PlayerAdded + każda zmiana)

### Mount/dismount (DeskaController — visuals)
- DeskMountResult(success, board) → animacja jazdy (`SKATE_ANIM_ID`), gracz bokiem (AutoRotate=false + RenderStepped obraca HRP od kamery), wycisza dźwięki kroków
- Dismount przywraca `Config.DeckDismountWalkSpeed=16` / `DeckDismountJumpHeight=7.2`
- Respawn czyści osierocony klon deski (weld ginie z postacią)

### RemoteEvents
- `DeskMount`/`DeskDismount`/`DeskMountResult`/`QuickMount` — jazda
- `OpenDeckShop` (server→client) — trigger gabloty
- `BuyDeck` (client→server) / `BuyDeckResult` (server→client `{success, reason?, deckKey?}`)
- `EquipDeck` (client→server) — wyposaż + wsiądź
- `DeckStatus` (server→client) — sync owned/equipped/riding

### Bootstrap
- `DeskaService` to **standalone Script** (`.server.luau`) — uruchamia się sam, NIE jest wymagany w GameServer. VIP (Robux) grantowany przez `BoostShopService.ProcessReceipt` → BindableEvent `ServerScriptService.GrantDeckEvent`

---

## Panel admina — dodawanie kodów (AdminService.addCode)
- Panel admina (F2) ma sekcję **DODAJ KOD PROMOCYJNY**: pole kodu + nagroda zł + DODAJ → `AdminAction({ action="addCode", code, reward })`
- Serwer mutuje `Config.Codes[code] = { reward }` w pamięci — **żyje do restartu serwera** (CodeService czyta `Config.Codes` server-side na żywo, więc działa od razu)
- Walidacja: kod uppercase 1-32 znaki, reward 1-1 000 000

---

## Zmiany od MVP — szybki przegląd

- **Menu ma 5 zakładek** (zmiana z 4): EKWIPUNEK / UMIEJĘTNOŚCI / QUESTY / **SKLEP** / USTAWIENIA. Settings na indeksie 5.
- **Sklep z plecakami przeniesiony**: `workspace.Sklep.Blat` → **`workspace.BUTELKOMANIACY.Kasjer`** (Model R6/R15)
- **Fundament w drzewku** odblokowuje teraz: gałęzie Speed/Mult + BANK (locked panel jeśli BaseLevel<1) + SPRINT (Shift, cienki biały pasek staminy)
- **Mityczny rarity** + **tier 5 strefy** — model w `ReplicatedStorage.Mityczny` (BottleService ma fallback dla modeli poza folderem `BottleModels`), wartość 50 zł, fioletowy z czarnym gradientem VFX
- **Inventory detail panel** ma przycisk **UPUŚĆ** (czerwony) — wyrzuca 1 sztukę przed gracza, bez cooldownu
- **Bank capacity dynamiczna** — `Config.Bank.BaseCapacity=10` + ulepszenia z przycisku **ULEPSZ** (każde +1 cap, koszt 1000 → 1500 → 2000...). Counter `X/N` w headerze SKARBIEC (czerwony gdy przekroczony), POTWIERDŹ odrzuca z `reason="bankFull"`
- **Bank UI = 15 slotów na sztywno** (5×3) — identycznie z głównym EQ. Split layout 1:1 per slot index, zachowany między sesjami (cache `_G["__bankLayoutCache"]`, inv side przez `__inventoryGetLayout`/`__inventorySetLayout`). Zero auto-sortowania/stackowania (wyjątek: pickup butelki podczas otwartego banku)
- **Right-click split** — w bank slotach i inventory slotach RMB dzieli stack na pół (floor(count/2)). Syrop nie dzieli się
- **Parking USUNIĘTY** — feature zakupu biletu parkingowego (500 PLN) wycofany. Deski nie wymagały biletu — sprzedaż przez gabloty działa niezależnie. Folder `workspace.Parking.Gabloty` nadal może być używany jako lokalizacja gablot (DeskaService ma fallback do `workspace.Gabloty`)
- **Movement-lock w UI** — `_G["__lockMovement"]`/`__unlockMovement` (ref-counted, `PlayerModule:GetControls():Disable()`) wywoływane w: bank, shop, quest, deck shop/menu, kosz roulette
- **SFX `Click` + `Equip`** — dodane do workspace.SFX. Click: X-close, KUP, POTWIERDŹ, ULEPSZ, klik slotu/węzła/zakładki menu. Equip: WYPOSAŻ deski
- **Detail panel ekwipunku — instant switch** — klik dowolnego slotu natychmiast zmienia content detail panelu (zero toggle behavior na klik). Chowanie tylko: czerwony X lub zamknięcie EQ
- **DataStoreKey** wciąż `PlayerData_v7` — nie bumpowane, bo `mergeWithDefaults` ogarnia nowe pola (HatOwned, RedeemedCodes, Grandpa, Decks, BankCapLevel)

---

## Zasady kodowania

- Wszystkie stałe balansowe tylko w `Config.luau` — zero hardkodowanych liczb gdzie indziej
- `RemoteEvent` i `RemoteFunction` tylko w `ReplicatedStorage`
- Nigdy nie ufaj klientowi — każda akcja weryfikowana po stronie serwera
- Każdy plik zaczyna się od `-- [NazwaPliku].luau`
- Używaj `task.spawn` i `task.delay` zamiast `spawn`/`delay`, `task.wait()` zamiast `wait()`
- DataStore zawsze w pcall z obsługą błędu
- Czcionka UI: zawsze `Enum.Font.GothamBlack` (stała `FONT_MAIN`) — wszędzie: HUD, GUI, skill tree
- Saldo złotówek klient czyta WYŁĄCZNIE z `player.leaderstats.Zlotowki.Value` — nigdy przez RemoteEvent
- Rzadkości butelek to polskie klucze: `"Zwykla"`, `"Rzadka"`, `"Epicka"`, `"Legendarna"` — nigdy angielskie

---

## Kolejność implementacji (MVP)

1. ✅ `Config.luau` — fundament wszystkiego
2. ✅ `PlayerDataService` — zapis/odczyt + leaderstats
3. ✅ `BottleService` — spawn + respawn butelek + CollectionService tagging
4. ✅ `CollectController` — zbieranie + ekwipunek (full-screen) + butelkomat + HUD + VFX + splash
5. ✅ `UpgradeService` + `SkillTreeController` — drzewko: 9 hexów (Base + 4 Speed + 4 Mult), pan/zoom, hover-anim, pulsujący stroke "available", detail panel, VFX zakupu
6. ✅ `ShopService` + `ShopController` — sklep z plecakami: ProximityPrompt na `workspace.Sklep.Blat`, UI z 4 kartami
7. ✅ `LeaderboardService` — ranking aktualnego salda Zlotowki na SurfaceGui (`workspace.LeaderboardTablica`), top 10 z medalami
8. ✅ `KoszService` + `KoszController` — przeszukiwanie koszy (`workspace.Kosze`), hold E 2s, roulette UI z wieloma butelkami per drop, VFX Legendarnej
9. ✅ `QuestService` + `QuestController` — 3 questy z 6h refresh, pula 10 questów, hooks do collect/earn/search/empty/buy_skill, panel UI z paskami progresu
10. ✅ `IntroService` + `IntroController` + `LoadingController` + `SettingsController` — tutorial cutscena 3-scenowa, autoplay na pierwsze wejście (HasSeenIntro flag), preload assetów, replay z USTAWIENIA
11. ✅ `MobileScaleController` — globalny `UIScale` per ScreenGui, fit do viewport
12. ✅ `LegendaryEventController` + `BottleService.startLegendaryEventLoop` — event "Deszcz Legendarek" co 8-12 min
13. ✅ Green color theme (#125B49 / #003527 / #051914 / #AADD66) — globalna podmiana palety
14. ✅ SFX: workspace.SFX (PickingUp, RouletteTick, Win), SoundGroup `SfxGroup`, slider w Ustawieniach
15. ✅ Density-based bottle spawn — `Config.BottleDensity`, per-area target z deficytem
16. Dopracowanie mapy i stylu wizualnego
17. Polish: muzyka tła, particle effects, więcej SFX (clink, ka-ching itp.)
18. Animacje NPC dla cutsceny (deposit, rummage — Looting już usunięte, teraz statyczne pozy)
19. Persystencja głośności SFX (DataStore)
20. ✅ Tier-based bottle spawn — `Config.BottleSpawnChanceByTier`, parser nazwy obszaru (T1_centrum, T3_pustynia itd.)
21. ✅ Quest Dziadka — `GrandpaService` + `SyrupService` + `GrandpaController` (visual-novel dialog, viewport avatar, per-player syrop, sekcje DZIADEK/ZADANIA DZIENNE w QuestController)

## Aktualny stan RemoteEvents (default.project.json)
- `CollectBottle`, `CollectBottleResult` — zbieranie
- `EmptyBackpack`, `EmptyBackpackResult` — butelkomat
- `UpdateHUD` — sync HUD klienta (po zmianie capacity/contents/hasSyrup)
- `BuySkillUpgrade`, `SkillTreeUpdate`, `SkillTreeInit` — drzewko
- `OpenShop`, `BuyBackpack`, `BackpackResult` — sklep
- `KoszResult` — wynik przeszukania kosza
- `QuestInit`, `QuestUpdate`, `ClaimQuest`, `ClaimQuestResult` — questy dzienne
- `PlayIntro`, `IntroFinished` — cutscena tutorial
- `LegendaryEventStart`, `LegendaryEventEnd` — event "Deszcz Legendarek" (server → all clients)
- `ResetProgress` — gracz prosi o reset z Settings (client → server), serwer czyści dane + teleport/kick
- `GrandpaTalk`, `GrandpaDialog`, `GrandpaAccept`, `GrandpaTurnIn`, `GrandpaState` — quest dziadka
- `SyrupPickupResult` — VFX/SFX feedback po pickup syropu
- `BankInit`, `BankDeposit`, `BankWithdraw`, `BankResult` — skarbiec banku
- `RedeemCode`, `RedeemCodeResult` — kody promocyjne w Settings
- `DropBottle` — ręczne upuszczanie butelek z ekwipunku (przycisk UPUŚĆ w detail panelu)
- `OpenHatShop`, `BuyHat`, `BuyHatResult`, `HatStatusUpdate` — sklep czapek
- `AdminInit`, `AdminAction`, `AdminBroadcast` — panel admina + broadcast HUD dla wszystkich
- `BoostStatusUpdate`, `PromptBoostPurchase` — Robux boost shop
- `DeskMount`, `DeskDismount`, `DeskMountResult`, `QuickMount` — jazda na desce
- `OpenDeckShop`, `BuyDeck`, `BuyDeckResult`, `EquipDeck`, `DeckStatus` — sklep/menu/equip desek
- `SyncInventoryLayout` — klient wysyła per-slot layout ekwipunku do serwera (persystencja splitów)
- `UpgradeBank` — klient prosi o zakup ulepszenia pojemności skarbca (+1 cap, koszt rośnie liniowo)

## Aktualne `_G` eksporty (cross-controller)
- `_G["__skillTreeToggle"]` — toggle skill tree (HUD button / klawisz U)
- `_G["__skillTreeState"]` — `{ data, tryBuy, nodeState, makeHex, treeWorld }` — używane przez Inventory detail panel do mnożnika
- `_G["__questToggle"]` — toggle questów (HUD button / Q)
- `_G["__settingsToggle"]` — toggle ustawień (HUD button)
- `_G["__playIntroTest"]` — replay cutsceny (przycisk w Settings)
- `_G["__introTryAutoplay"]` — wywoływane przez LoadingController, IntroController decyduje czy auto-startuje
- `_G["__loadingDone"]` — bool, ustawiany przez LoadingController po tap
- Quest dziadka **nie używa `_G`** — komunikacja przez dedykowane RemoteEventy (GrandpaState, GrandpaDialog, SyrupPickupResult), GrandpaController sam łapie `workspace.SyrupActive` dla per-player visibility

## Quick reference — gdzie co siedzi w workspace
| Folder/Model | Co zawiera | Wymagane przez |
|---|---|---|
| `workspace.Bottles` | Auto-tworzone — folder na live butelki | BottleService (auto) |
| `workspace.BottleSpawnAreas` | Parts (Anchored, Transparency=1) — obszary spawnu | BottleService (preferowane) |
| `workspace.BottleSpawnPoints` | Parts-markery (fallback gdy brak Areas) | BottleService (fallback) |
| `workspace.AutomatKaucyjny` | Model z BlackPanel / PrimaryPart — butelkomat | BottleService (tag) |
| `workspace.Butelkomaty` (opcjonalny) | Folder z dodatkowymi butelkomatami | BottleService (tag) |
| `workspace.Sklep` | Model z dzieckiem `Blat` (BasePart / Model) | ShopService |
| `workspace.Kosze` | Folder z koszami (BasePart / Model z PrimaryPart) | KoszService |
| `workspace.LeaderboardTablica` | BasePart na ranking | LeaderboardService |
| `workspace.SFX` | Folder z `Sound` instancjami: `PickingUp`, `RouletteTick`, `Win` | CollectController, KoszController (SoundGroup `SfxGroup`) |
| `workspace.CutsceneStage` | Mini-mapa + markery `Cam_Scene1/2/3/_End` + NPC `Marcelk1122` (R15) | IntroController |
| `workspace.Grandpa` | Model R15 NPC z HumanoidRootPart + Head (do dialogu + viewport avatar) | GrandpaService, GrandpaController |
| `workspace.SyrupSpawnPoints` | Folder z `SyrupSpawn1/2/3` (Anchored Parts, 3 możliwe lokacje syropu) | SyrupService |
| `workspace.SyrupActive` | Auto-tworzony — folder na żywe modele syropu (per-player) | SyrupService (auto) |
| `workspace.BANK` | Folder/Model z dzieckiem `Bankier` (Model R15 lub BasePart) | BankService |
| `workspace.BUTELKOMANIACY` | Folder/Model z dzieckiem `Kasjer` (Model R6/R15 lub BasePart) | ShopService (sklep z plecakami) |
| `workspace.SKLEP2` | Folder/Model z dzieckiem `Cashier` (R6/R15 lub BasePart) | HatShopService |
| `workspace.Deski` | Folder z 4 Modelami: `DeskaDefault/DeskaRed/DeskaBlue/DeskaVIP` (PrimaryPart) — szablony desek | DeskaService (klonuje) |
| `workspace.Parking.Gabloty` / `workspace.Gabloty` | Folder z `Gablota1..4` (BasePart/Model) — sprzedaż desek przez ProximityPrompt. DeskaService szuka najpierw `Parking.Gabloty`, fallback `workspace.Gabloty` lub rekurencyjnie | DeskaService |
| `workspace.ActiveDecks` | Auto-tworzony — klony desek aktualnie jeżdżących graczy | DeskaService (auto) |
| `workspace.PVPZone` | BasePart (Anchored, CanCollide=false, Transparency=1) — strefa PvP gdziekolwiek w workspace | PvPService |
| `ReplicatedStorage.Sword` | Tool — ClassicSword z toolboxa | PvPService (klonuje do plecaka w strefie) |
| `ReplicatedStorage.Czapka` | Accessory (HatAccessory) — czapka z bonusami | HatShopService |
| `ReplicatedStorage.BackpackModels` | Folder z `Level1/2/3/4` (Accessory) — wizual plecaków per BackpackLevel | BackpackEquipService |
| `ReplicatedStorage.BottleModels` | 4 modele (Zwykla, Rzadka, Epicka, Legendarna) z PrimaryPart | BottleService, KoszController, IntroController |
| `ReplicatedStorage.SyrupModel` (opcjonalny) | Model syropu z PrimaryPart — fallback to cylinder gdy brak | SyrupService |
| `ServerStorage.RBX_ANIMSAVES.<NpcName>.<seqName>` | KeyframeSequence animacji (przed registracją) | IntroService (register → ReplicatedStorage.IntroAnims) |
| `ReplicatedStorage.IntroAnims` | Auto-utworzone — `Animation` instances do gotowych odtworzenia | IntroController (`humanoid:LoadAnimation`) |

## Bootstrap order (GameServer)
```lua
require(script.Parent.PlayerDataService)
require(script.Parent.QuestService)        -- przed BottleService/KoszService/UpgradeService
require(script.Parent.BottleService)
require(script.Parent.UpgradeService)
require(script.Parent.ShopService)
require(script.Parent.LeaderboardService)
require(script.Parent.KoszService)
require(script.Parent.IntroService)
require(script.Parent.SyrupService)        -- przed GrandpaService (GrandpaAccept hook woła SyrupService.OnQuestAccepted)
require(script.Parent.GrandpaService)
require(script.Parent.BankService)
require(script.Parent.CodeService)
require(script.Parent.BackpackEquipService)
require(script.Parent.PvPService)
require(script.Parent.HatShopService)
require(script.Parent.DeathDropService)
require(script.Parent.AdminService)
require(script.Parent.BoostShopService)
-- DeskaService to standalone Script (.server.luau) — uruchamia się sam, NIE wymagaj go tutaj
-- (Rojo rejestruje plik z sufiksem .server.luau jako Script w ServerScriptService, require na Script rzuca błąd)
-- VIP (Robux) grantowany przez BoostShopService.ProcessReceipt → BindableEvent ServerScriptService.GrantDeckEvent
```
