# CLAUDE.md — Kaucja Simulator

## Przegląd

**Roblox** game (Luau + Rojo). Low-poly pastel city. Gracz zbiera butelki o różnych rzadkościach, oddaje do butelkomatu za złotówki, kupuje upgrady. Klasyczna pętla progresji + linia fabularna + PvP + skarbiec + sklepy.

**Core loop:** zbieraj butelki → oddaj do butelkomatu → kup upgrady (skill tree / plecak / deska) → szybciej zbieraj.

---

## Struktura projektu (Rojo)

```
src/
  client/controllers/
    CollectController         -- zbieranie + EQ + butelkomat + HUD + VFX (15 slotów fixed)
    SkillTreeController       -- drzewko (Fundament + Speed/Mult/Luck), pan/zoom
    ShopController            -- sklep plecaków (ProximityPrompt na workspace.BUTELKOMANIACY.Kasjer)
    KoszController            -- roulette UI dla koszy
    QuestController            -- daily questy (3 z 6h refresh) + sekcja dziadek + sekcja FABUŁA (scroll)
    StoryQuestController       -- linia fabularna: centralny reveal → corner HUD w prawym dolnym + przycisk ODBIERZ
    IntroController           -- cutscena tutorial przy pierwszym wejściu
    LoadingController         -- TAP TO CONTINUE + ContentProvider preload
    SettingsController        -- reset postępu + kody + slider SFX + replay intro
    MobileScaleController     -- globalny UIScale per ScreenGui
    MobileControlsController  -- TYLKO touch: thumbstick lewy dolny + SPRINT/DESKA po prawej
    LegendaryEventController  -- HUD eventu Deszcz Legendarek
    GrandpaController         -- visual-novel dialog dziadka
    MenuController            -- przycisk MENU (środek dół) + 4 zakładki z bubble indicator
    BankController            -- split-view SKARBIEC ⇌ EKWIPUNEK (15 slotów × 2), POTWIERDŹ + ULEPSZ
    SprintController          -- Shift sprint gated na BaseLevel ≥ 1; biały pasek staminy
    HatShopController         -- standalone UI sklep czapek
    AdminController           -- panel admina (F2)
    ShopCatalogController     -- osobny przycisk SKLEP w HUD (lewo od MENU) + katalog Robux (VIP/Boost/TripleEgg)
    DeskaController           -- R = wsiada/wysiada deski, gracz bokiem do kamery
    DeckShopController        -- GUI zakupu deski przy gablocie + menu TWOJE DESKI (hoverboard button)
    PvPEntryGuiController     -- GUI płatności 300 zł za wstęp do PvP
  server/
    GameServer.server         -- bootstrap require'ów
    services/
      PlayerDataService       -- DataStore PlayerData_v7 + leaderstats
      QuestService            -- daily questy: pula 10, 3 aktywne, refresh 6h
      StoryQuestService       -- linia fabularna: 8 questów w chain, claim manually, preFillProgress
      BottleService           -- spawn/respawn, density per-area, tier per nazwa partu (T1-T5)
      UpgradeService          -- Base/Speed/Mult/Luck
      ShopService             -- plecaki
      LeaderboardService      -- ranking aktualnego Zlotowki (OrderedDataStore)
      KoszService             -- kosze 30s cooldown
      IntroService            -- KeyframeSequence rejestr
      GrandpaService          -- state machine: none/active/done
      SyrupService            -- per-player syrop (OwnerUserId gate)
      BankService             -- BankData_v1 osobny DataStore, conservation + capacity + ULEPSZ
      CodeService             -- kody jednorazowe (OGDC/PVPOG/HOLYFINDER/PARKOUR)
      BackpackEquipService    -- Accessory plecaka na postaci
      PvPService              -- detekcja PVPZone, SAFEZONE FF, push-out, grace 3s, miecz, force-dismount deski
      PvPEntryService         -- płatność 300 zł → PvPAccess attribute. Opcjonalny KasjerPVP prompt
      HatShopService          -- permanentny zakup czapki
      DeathDropService        -- drop butelek po śmierci (raycast pozycji), 2 min despawn, 5s own pickup cooldown
      AdminService            -- broadcast/giveZl/giveBottles/kick/addCode
      BoostShopService        -- Developer Products Robux, ProcessReceipt → VIP deska grant
      DeskaService            -- standalone Script: gabloty, mount/dismount, weld do HRP, zakaz w PVPZone/SAFEZONE
  shared/
    Config.luau               -- stałe balansowe (rzadkości, ceny, questy, story chain, deski, PvP)
default.project.json
```

---

## Workflow z właścicielem repo

**Zawsze przed zmianą/dodaniem czegoś — zadaj kilka pytań żeby rozwiać wątpliwości**, zanim ruszysz pliki. Dotyczy:
- nowych mechanik (np. "dodaj system X") — dopytaj o zakres, edge case'y, czy ma persystować, czy działa w PvP itd.
- refaktorów struktur danych (np. zmiana DataStore schema) — dopytaj o migrację i wpływ na obecnych graczy
- decyzji architektonicznych z >1 sensownym wyborem (np. "osobna lista vs unified inventory") — przedstaw 2-3 opcje z trade-off'ami zanim wybierzesz

Pomijaj pytania tylko gdy zmiana jest oczywista i mała (literówka, jedna linia fixu z konkretnego błędu, dokumentacja).

Workflow większych zmian: **plan → pytania → potwierdzenie → robota → raport**, nie "robota → niespodzianka".

---

## Konwencje

- **Wszystkie wartości balansowe w `Config.luau`** — zero hardkodów gdzie indziej.
- **RemoteEvent/RemoteFunction** w `ReplicatedStorage.Events`.
- **Nigdy nie ufaj klientowi** — server weryfikuje każdą akcję.
- **Saldo** klient czyta tylko z `player.leaderstats.Zlotowki.Value` (wspiera grosze, format `X PLN` / `X.XX PLN`).
- **Rzadkości BUTELEK** zawsze polskie klucze: `"Zwykla"`, `"Rzadka"`, `"Epicka"`, `"Legendarna"`, `"Mityczny"`.
- **Rzadkości PETÓW** — angielskie klucze: `"Common"`, `"Rare"`, `"Epic"`, `"Legendary"`, `"Huge"` (osobny system, `Config.Pets.Rarities`). NIE polonizować — zmiana kluczy rozwala zapisane `data.Pets` w DataStore (każdy pet ma `rarity` przechowywaną dosłownie).
- **Font** UI: `Enum.Font.GothamBlack` (tytuły `LuckiestGuy`).
- **Plik nagłówek:** `-- [Nazwa].luau` na początku.
- **task.spawn/wait/delay**, nigdy stare `spawn`/`wait`.
- **Wspólne helpery** w `ReplicatedStorage.Util` (src/shared/Util.luau): `findAnchor(model)`, `getCarriedCount(data)`, `deepCopy(t)`. Nie dubluj w serwisach.
- **Anti-exploit** — każdy server handler kupna/transferu/akcji NPC waliduje: (1) per-player throttle (0.3-1s), (2) dystans HRP→anchor NPC (15-18 studs). Patrz pattern w `BankService.guardBankRequest`, `ShopService.tryBuyBackpack`.

---

## DataStore

- `Config.DataStoreKey = "PlayerData_v7"` — nie bumpujemy, nowe pola dodawane przez `mergeWithDefaults`.
- BankService osobny store: `"BankData_v1"`.
- Leaderboard osobny: OrderedDataStore `"Leaderboard_Zlotowki_v1"` (grosze jako int).
- **Retry** — `GetAsync`/`SetAsync` mają 3 próby z exponential backoff (0.5/1.5/3s) w PlayerDataService i BankService.
- **Load fail guard** — gdy GetAsync zwróci błąd po 3 próbach, gracz dostaje `__loadFailed = true` w cache; SaveData jest gate'owany żeby nie nadpisać postępu pustymi danymi; gracz jest kickowany.
- **BindToClose** — równoległy `SaveData` per gracz (task.spawn + counter + Event:Wait), timeout 25s. Sekwencyjny zapis nie zdąży przy 10+ graczach (Roblox daje ~30s).

---

## Typy danych gracza (DEFAULT_DATA w PlayerDataService)

```lua
{
    Zlotowki = 0,            -- float, wspiera grosze (×1.5 mnożnik)
    TotalEarned = 0,         -- do leaderboardu, nigdy nie maleje
    BaseLevel = 0,           -- Fundament (gating Speed/Mult/Bank/Sprint)
    SpeedLevel = 0,          -- 0-4
    MultiplierLevel = 0,     -- 0-4
    LuckLevel = 0,           -- 0/1 (odnoga od Mult L2)
    BackpackLevel = 1,       -- 1-4
    TotalBottles = 0,
    BackpackContents = { Zwykla=0, Rzadka=0, Epicka=0, Legendarna=0, Mityczny=0 },
    Quests = { activeIds={}, progress={}, claimed={}, refreshAt=0 },
    StoryQuestIndex = 1,     -- 1-based numer aktualnego questa w chain
    StoryQuestProgress = 0,
    HasSeenIntro = false,
    Grandpa = { state="none", syrupLocation=0, hasSyrup=false },
    RedeemedCodes = {},      -- [code] = true (jednorazowe)
    OwnedDecks = {},         -- [deckKey] = true
    EquippedDeck = "",
    HatOwned = false,
    BankCapLevel = 0,        -- +1 cap per ulepszenie
    InventoryStacks = {},    -- persystencja split EQ
    MagnetCount = 0,         -- magnesy w plecaku (1 slot każdy)
    Pets = {},               -- lista { id (uuid), rarity, class } — 1 slot każdy
    EquippedPet = "",        -- UUID wyposażonego peta (bonusy money/speed/HP)
    BankPets = {},           -- pety w skarbcu (osobne od EQ)
}
```

---

## Linia fabularna (StoryQuestService + StoryQuestController + sekcja FABUŁA w QuestController)

### Cel
Onboarding — gracz wie co robić. 14 questów w ustalonej kolejności (Config.StoryQuests). Po wykonaniu kliknij ODBIERZ → wypłata + auto-start następnego.

### Chain (Config.StoryQuests)
1. Zbierz 10 butelek (30 zł)
2. Oddaj do butelkomatu 2× (50 zł)
3. Kup 2 ulepszenia w drzewku (100 zł)
4. Kup lepszy plecak (150 zł)
5. Kup 1 jajko z petem (250 zł)
6. Załóż peta (300 zł)
7. Kup deskę lvl 1 - Default (400 zł)
8. Zbierz 100 butelek (600 zł)
9. Zbierz 5 Legendarnych butelek (400 zł)
10. Ulepsz skarbiec (500 zł)
11. Pomóż Dziadkowi (150 zł)
12. Kup deskę lvl 2 - Red (200 zł)
13. Wylosuj Legendarnego peta (500 zł)
14. Kup deskę lvl 3 - Blue (500 zł)

### Mechanika
- `StoryQuestService.AddProgress(player, kind, amount, params?)` — hooki w istniejących serwisach (BottleService.CollectBottle/EmptyBackpack, KoszService, UpgradeService.Buy*, ShopService.tryBuyBackpack, DeskaService.grantDeckInternal, GrandpaService.GrandpaTurnIn, PetService.OpenEgg/EquipPet, BankService.UpgradeBank). Wszystkie przez `pcall(require...)`.
- Po dopełnieniu targetu → `readyToClaim = true` w snapshot. **NIE wypłaca automatycznie**. Gracz klika ODBIERZ → `StoryQuestClaim:FireServer()` → wypłata + `Index++` + reset `Progress` + po 2.5s nowy `StoryQuestInit`.
- **`preFillProgress`** — przy `fireInit` na świeży quest sprawdza stan gracza. Jeśli ma już najlepszy plecak / 2+ skille / jakąś deskę → quest startuje od razu jako gotowy do odbioru.
- **`PlayerDataService.SaveData` USUNIĘTE z `AddProgress`** — SetAsync yieldował 1-2s i blokował `CollectBottleResult` (SFX/VFX delay). Save zostaje w `claimAndAdvance` + auto-save co 60s.

### Kindy
- `collect_any` (bez filtra), `collect_rarity` (z `params.rarity == q.rarity`)
- `deposit`, `buy_skill`, `buy_backpack`, `buy_deck`, `grandpa_done`
- `buy_egg` (otwarcie jajka), `equip_pet` (założenie peta), `upgrade_bank` (ULEPSZ skarbca)
- `pet_rarity` (wylosowanie peta — `params.rarity == q.petRarity`)

### UI
- **Corner HUD** (`StoryQuestController`) — prawy dolny róg, 460×130. Header "FABUŁA X/Y", desc, nagroda gold, pasek/ODBIERZ.
- **Centralny reveal** — 4s "NOWY QUEST" przy starcie, 2s "WYKONANO!" przy claim. Click-to-skip (TextButton overlay).
- **Sekcja FABUŁA w menu** (`QuestController`) — karta z nagrodą, statusem `idx/total` lub przyciskiem ODBIERZ. Panel ekrany QUESTY jest **ScrollingFrame 560×580** z dynamic CanvasSize (sekcje FABUŁA + DZIADEK + ZADANIA DZIENNE).

### RemoteEvents
- `StoryQuestInit` (server→client) — nowy quest lub sync
- `StoryQuestUpdate` — progress
- `StoryQuestComplete` — WYKONANO + reward
- `StoryQuestClaim` (client→server) — gracz klika ODBIERZ

---

## Daily questy (QuestService + QuestController)

3 questy losowane z puli 10, refresh co 6h. Pula obniżona ~70% w 2026 rebalansie (25/50/80/100/60/50/100/70/60/80 zł).

Hooki te same co story (BottleService, KoszService itp.) — dzielą wspólne `AddProgress` calls.

---

## Quest Dziadka (GrandpaService + SyrupService + GrandpaController)

### State machine (per gracz, `data.Grandpa`)
- `none` → "Cześć!" + PRZYJMIJ → `active` (losuje 1/2/3 SyrupSpawnPoint, spawnuje syrop per-player)
- `active` bez syropu → "Szukaj dalej" → ZAMKNIJ
- `active` z syropem → "Och, masz mój syrop!" + ODDAJ → `done` + 1000 zł
- `done` → "Co tam?"

### Per-player syrop
- Server tworzy w `workspace.SyrupActive` z attribute `OwnerUserId`.
- Klient (GrandpaController) iteruje folder i ustawia `LocalTransparencyModifier = 1` + `Prompt.Enabled = false` dla cudzych syropów (server-side gate w prompt.Triggered jako defense in depth).
- Syrop zajmuje 1 slot plecaka (`hasSyrup` wlicza się do `carried`). Butelkomat NIE czyści syropu.

### UI
- Visual-novel dialog box (960×220 prostokątny, awatar 180×180 z ViewportFrame klonującym `workspace.Grandpa`), typewriter 35 znaków/s, klik/Space skipuje.

---

## System butelek (BottleService)

### Spawn
- **Density per-area** — `workspace.BottleSpawnAreas` to folder z Partami (Anchored, transparent). Każdy ma target = `max(MinBottlesPerArea, round(surface_XZ * BottleDensity))`. `MaxBottlesHardCap = 400`.
- **Tier per nazwa partu**: regex `[Tt](%d+)` → tier 1-5. `Config.BottleSpawnChanceByTier`. T1 = blisko spawnu (głównie Zwykła), T5 = mityczna strefa (5% Mit po rebalansie 2026).
- **Modele** w `ReplicatedStorage.BottleModels.{Zwykla,Rzadka,Epicka,Legendarna}` + osobno `ReplicatedStorage.Mityczny` (fallback poza folderem). PrimaryPart obowiązkowy.
- Anti-overlap: min 3 studs między butelkami.

### Respawn
- Cykliczna pętla co `BottleRespawnTime = 6s`, dolewa do `min(deficit, 15)` butelek.
- `EnsureRareBottles` — min 1 Legendarna, 3 Epickie. Skipowane podczas eventu "Deszcz Legendarek".
- Per-area: `pickAreaNeedingFill` losuje obszar z wagą deficytu.

### Event "Deszcz Legendarek"
- Co 8-12 min, 15s. Mapa czyszczona, 30 Legendarek spawnowanych globalnie, ColorCorrection złoty tint.
- Server: `LegendaryEventStart/End:FireAllClients`.

### Wartości (Config.BottleValues, rebalans 2026)
- Zwykla=1, Rzadka=2, Epicka=3, Legendarna=10, Mityczny=25 (zmniejszone z 50)

---

## Zbieranie + Butelkomat

- `CollectBottle:FireServer(bottle)` — server akceptuje Model/BasePart, helper `getBottlePos` ogarnia oba.
- Plecak full → reject. ProximityPrompt na PrimaryPart, `RequiresLineOfSight=false`, dist=5.
- **Butelkomat** — `CollectionService` tag `"Butelkomat"`. `workspace.AutomatKaucyjny` auto-taggowany. Ręczne tagi w Studio też działają.
- `earned = Σ(count * BottleValues[rarity] * Multiplier)` (multiplier z drzewka). Plecak czyszczony, fire `UpdateHUD` + `Money` SFX.

---

## Drzewko (UpgradeService + SkillTreeController)

### Struktura
- **Fundament** (cost 50): gating dla Speed/Mult, Bank, Sprint.
- **Speed L1-L4**: WalkSpeed 19/22/26/30. Cost 250/1500/6000/25000 (rebalans 2026).
- **Multiplier L1-L4**: ×1.5/2.0/2.2/2.5. Cost 250/1500/7000/30000.
- **Luck** (odnoga od Mult L2, single-level): ×2 szansa lepszych rzadkości w koszach. Cost 2000.

### UI
- 9 hexów, pan/zoom (zoom 0.5-2.0, default 0.85). Panel **compact** (968px) ↔ **wide** (1288px) — detail panel po prawej pojawia się przy kliknięciu hexa.
- Stany: purchased (full color), available (jasny fill + pulsujący stroke), locked (szary + kłódka).
- Klawisz **U** lub zakładka UMIEJĘTNOŚCI w menu.

---

## Plecak (Sklep — ShopService + ShopController)

- `workspace.BUTELKOMANIACY.Kasjer` (Model lub BasePart) → ProximityPrompt → GUI.
- 4 poziomy: Reklamówka(10), Plecak szkolny(25, 200zł), Wielki worek(35, 900zł), Wózek sklepowy(50, 10000zł — main gate).
- L4 cicho pomijany przez BackpackEquipService (brak modelu). Reszta: Accessory w `ReplicatedStorage.BackpackModels.Level{N}`.
- Atrybuty na Accessory: `BackOffset` (Vector3 studs), `BackRotation` (Vector3 stopnie) — fix gdy plecak ląduje na brzuchu.

---

## Inventory (CollectController)

- **15 slotów na sztywno (5×3)** — `SLOT_COUNT = 15`. Hover-scale 1.06. Kolor slota = `darken(rarity.color, 0.45)` + stroke pełny rarity color + biały tekst.
- **VFX Legendarnej**: rotujący gold UIGradient + pulsujący stroke. **VFX Mitycznej**: fiolet/czarny.
- **Detail panel** po prawej — slide-in, **instant switch** (klik dowolnego slotu natychmiast zmienia content, nie toggle). Pokazuje: rzadkość, count, wartość, mnożnik, przycisk **UPUŚĆ** (czerwony, drop 1 sztuki przed gracza). Syrop też renderuje się w slocie ale BEZ ceny/UPUŚĆ.
- **Position-keyed layout** — `_G["__inventoryGetLayout"]/__inventorySetLayout` (map [slotIdx]={rarity,count}). Persystencja przez `SyncInventoryLayout:FireServer` do `data.InventoryStacks`. Bank UI używa tego API żeby split 1:1.
- **Right-click** = split stack na pół (drag drugiej połowy).
- Klawisz **I** lub zakładka EKWIPUNEK w menu.

---

## Bank (BankService + BankController)

### Setup
- `workspace.BANK.Bankier` (R15/BasePart) → ProximityPrompt.
- **Locked** jeśli `BaseLevel < 1` → `BankInit{locked=true}` → osobny panel "Kup Fundament".

### UI — split-view SKARBIEC ⇌ EKWIPUNEK
- **15 slotów per panel** (5×3, identyczne wymiary z głównym EQ).
- Counter X/N w headerze SKARBIEC (czerwony przy przekroczeniu).
- Dolny pasek: **ZAMKNIJ (center=-199)** ↔ **POTWIERDŹ (center=0)** ↔ **ULEPSZ (center=+244)** — wyśrodkowane z 24px gap.

### Persystencja split layoutu (1:1, ZERO auto-stackowania)
- **Bank side**: `_G["__bankLayoutCache"]` — saved on close + po POTWIERDŹ. Restore jeśli sumy z cache == server bankContents.
- **Inv side**: position-keyed przez `__inventoryGetLayout/__inventorySetLayout`.
- Wyjątek od 1:1: pickup butelki podczas otwartego banku → stackuje (UpdateHUD).
- **Discard-on-unconfirmed-close**: `closeBank` utrwala layout TYLKO gdy `trPanel.Visible` i `not hasUncommittedChanges()` (układ == snapshot serwera `serverBpContents`/`serverBankContents`/pet-sety z BankInit/BankResult). Niezatwierdzony transfer EQ↔SKARBIEC jest porzucany — inaczej zredukowany layout EQ trafiał do shared inventory i przeniesione butelki znikały z widoku na zawsze.

### Pojemność + ULEPSZ
- `BaseCapacity=10`, każde ulepszenie `+1 cap`, koszt `1000 + N×500` (L0→1000, L1→1500, L2→2000...).
- ULEPSZ button → `UpgradeBank:FireServer()` → server waliduje BaseLevel + zł, deductuje, BankCapLevel++, fire `BankResult{upgraded=true, bankCapacity, bankUpgradeCost}`.

### Walidacja transferu (handleTransfer)
1. Conservation per rzadkość (oldBp + oldBk == newBp + newBk)
2. Plecak: `sum(newBp) + (hasSyrup ? 1 : 0) <= BackpackUpgrades[level].Capacity`
3. Bank: `sum(newBk) <= getBankCapacity(pData)`
4. Sukces → `UpdateHUD` + `BankResult{bankCapacity}`. Fail: reason `invalid/conservation/overCapacity/bankFull/locked`.

**Pet-overflow guard (klient):** bank UI ma 15 slotów, ale plecak do 50 — gdy butelki+pety > 15 pety wypadały z list i serwer odrzucał `conservation` → "BŁĄD ZAPISU". Fix: przy POTWIERDŹ reconcile UUIDów względem `serverEqPetIds`/`serverBankPetIds` (snapshot z BankInit, odświeżany przez UpdateHUD/PetStatusUpdate gdy bank otwarty) — brakujące pety wracają na oryginalną stronę. Inv-side build też waliduje sumy butelek vs `data.backpackContents` (jak bank-side `layoutOk`).

### RemoteEvents
- `BankInit`, `BankDeposit` (POTWIERDŹ), `BankWithdraw` (alias), `BankResult`, `UpgradeBank`.

---

## Kosz (KoszService + KoszController)

- `workspace.Kosze` — folder. Auto ProximityPrompt z HoldDuration=2. Cooldown **30s** per kosz.
- Drop: rzadkość (z tych samych szans co spawn) + count weighted (`Config.KoszDropQuantity`).
- Pre-check `noSpace` przed zwrotem (z `freeSpace`). 
- **Roulette UI** — 36 itemów, Quint Out 3.5s spin, RouletteTick SFX co przejście przez wskaźnik, Win SFX z trimEnd=0.6s. VFX Legendarnej (rotating gold gradient + pulsujący stroke).

---

## HUD + Menu

### HUD (CollectController)
- **Wallet** centered top — `"X PLN"` zielone TextSize 48, prostokątny (bez UICorner), border 6px. Czyta `leaderstats.Zlotowki.Value`.
- Starych 4 przycisków HUD NIE MA — `Visible=false`. Toggle'e (`_G["__inventoryToggle"]` itd.) **przekierowane** na `_G["__menuOpen"]() + __menuSetActiveTab(N)`.

### MenuController
- **Przycisk MENU w idealnym środku dolnej krawędzi ekranu** (203×135, ikona `rbxassetid://99401921944526`, AnchorPoint(0.5,1), Position(0.5,0,1,-20), hover scale 1.12 + rotation 6°).
- Panel 1480×880, tab bar pill-shaped z animowanym bubble indicator.
- **4 zakładki**: EKWIPUNEK / UMIEJĘTNOŚCI / QUESTY / USTAWIENIA. (SKLEP jest osobnym GUI — patrz ShopCatalogController.)
- Sterowanie: **TAB** toggle, **ESC** close, X w prawym górnym. Klik w tło NIE zamyka.
- Klawisze I/U/Q przekierowane na menu (`__menuSetActiveTab`). USTAWIENIA = tab idx **4** (było 5 przed usunięciem SKLEP).
- Eksporty: `_G["__menuOpen/Close/Toggle/SetActiveTab"]`.

### ShopCatalogController (sklep Robux)
- **Osobny przycisk SKLEP w HUD** (135×135, ikona `rbxassetid://93988211403086`, AnchorPoint(0.5,1), Position(0.5,-184,1,-20) — środek dół, po LEWO od MENU z gap 14px).
- Panel 1100×720 z headerem "SKLEP" + X-close + ScrollingFrame z UIGridLayout (3 kolumny, cell 310×310, AutomaticCanvasSize.Y).
- **3 karty placeholder (kolor+litera, bez obrazków — user dorzuci ID)**:
  - **VIP Deska** (Gamepass `Config.Decks[VIP].GamepassId = 1883460051`, 30 R$) — POSIADASZ gdy `DeckStatus.owned.VIP`.
  - **x2 KASA** (Developer Product `Config.BoostShop.DoubleEarn.ProductId = 3605052667`, 19 R$) — AKTYWNE z timerem `BoostStatusUpdate.doubleEarnRemainingSec`. Można doliczyć (cumulative).
  - **Triple Egg** (Gamepass `Config.Pets.TripleEggGamepassId = 1884317989`) — POSIADASZ gdy `PetStatusUpdate.hasGamepass`.
- Zakup: VIP / Triple = `MarketplaceService:PromptGamePassPurchase`; x2 KASA = `PromptBoostPurchase:FireServer("DoubleEarn")` → server `MarketplaceService:PromptProductPurchase`.
- Sterowanie: ESC zamyka, X w headerze. Klik w tło NIE zamyka.
- **Floating HUD timer** (prawy górny, 170×44) widoczny przy aktywnym boost — pokazuje `x2 KASA X:YY`.
- BoostShopController **został usunięty** w 2026 — cała logika tutaj.

### Hoverboard button (DeckShopController)
- 135×135 (lewa strona, pod MENU), ikona z `Config.DeckMenuIconId`, hover scale 1.12 + rotation 6°. Otwiera menu TWOJE DESKI.

---

## Deski (DeskaService + DeskaController + DeckShopController)

### Konfiguracja (Config.Decks)
- Default(40 speed, 1000 zł), Red(48, 3000), Blue(56, 5000), VIP(100, 30 R$, ProductId 3605653942).
- `model = "DeskaDefault"` itp. → szablon w `workspace.Deski`.
- `gablota = 1..4` → mapowanie na `workspace.Parking.Gabloty.Gablota{N}` (fallback `workspace.Gabloty` lub rekursywne szukanie).

### Mount/dismount
- **R** wsiada na wyposażoną (lub najlepszą posiadaną) deskę. R w jeździe = dismount.
- **Force unsit przy mount** — jeśli `humanoid.SeatPart ~= nil` (siedzi na huśtawce/krześle), `Sit=false + ChangeState(Jumping) + wait(0.15)` zanim weld. Inaczej dwie welds na HRP → gracz pod mapą.
- Mount clone'uje template do `workspace.ActiveDecks`, weld do HRP, `WalkSpeed = deck.Speed`, `JumpHeight = 0`.
- Dismount: `WalkSpeed = Config.DeckDismountWalkSpeed (16)`, `JumpHeight = Config.DeckDismountJumpHeight (7.2)`.
- DeskaController: animacja jazdy (`SKATE_ANIM_ID`), gracz bokiem (AutoRotate=false + RenderStepped obraca HRP od kamery), wycisza dźwięki kroków.

### Zakaz w PvP/SAFEZONE
- `DeskaService.mountPlayer` sprawdza `isInBlockedZone` (PVPZone + SAFEZONE) → reject.
- **PvPService fire'uje BindableEvent `ForceDeskDismountEvent`** (ServerScriptService) przy wejściu w PVPZone lub SAFEZONE → DeskaService.dismountPlayer (idempotent).

### Sprint × Deska
- DeskaController: `_G["__deskaMounted"] = true/false` przy mount/dismount.
- SprintController early-return w Heartbeat gdy mounted → nie nadpisuje WalkSpeed deski, pasek staminy ukryty.

### RemoteEvents
- `DeskMount/DeskDismount/DeskMountResult/QuickMount` — jazda.
- `OpenDeckShop` (server→client, gablota) / `BuyDeck` (client→server) / `BuyDeckResult` / `EquipDeck` / `DeckStatus` (sync owned/equipped/riding).
- VIP grant przez `BoostShopService.ProcessReceipt` → BindableEvent `GrantDeckEvent`.

DeskaService to **standalone Script** (.server.luau) — NIE wymagaj w GameServer (require na Script błąd).

---

## PvP (PvPService + PvPEntryService + PvPEntryGuiController)

### Setup
- `workspace.PVPZone` — BasePart (Anchored, CanCollide=false, Transparency=1), gdziekolwiek w workspace (server szuka rekurencyjnie).
- `workspace.SAFEZONE` — BasePart, bufor wokół wejścia do PvP.
- `ReplicatedStorage.Sword` — Tool (np. ClassicSword).

### Cykl
- Server poll co 0.25s sprawdza pozycję każdego gracza w PVPZone i SAFEZONE.
- **SAFEZONE** — wejście → dodaje `ForceField "SafeZoneFF"`. Wyjście → zdejmuje. Działa nawet w 0.25s push window (zabezpieczenie przed killem).
- **PVPZone** — sprawdza w kolejności:
  1. `was == true` (już z mieczem) → nic
  2. `player:GetAttribute("PvPAccess") == true` → konsumuje (=false), `giveSwordWithGrace`
  3. Brak biletu → `pushOutOfZone` co tick + `OpenPvPEntry:FireClient` raz

### Push out
- Radialnie od środka strefy po XZ (Y zachowane).
- `pushDist = sqrt(half.X² + half.Z²) + 1` — diagonalna + 1 stud bufor (2026 update — było +6, gracz wylatywał za daleko).
- Cooldown `PUSH_COOLDOWN = 0.4s` (anti-spam, poll i tak 0.25s).
- `lastPushAt` tracking per player.

### Płatność
- **Brak fizycznej bramy** (2026 — usunięte brama_pvp + Sensor + kasjer prompt jako required).
- `BuyPvPEntry:FireServer` → server odejmuje 300 zł, ustawia `player:SetAttribute("PvPAccess", true)`.
- Następny poll tick (≤0.25s) zauważa atrybut → wpuszcza z mieczem + 3s grace (ForceField "PvPGraceFF" + `sword.Enabled = false`).
- **KasjerPVP** (opcjonalny rig w workspace) — jeśli istnieje, dostaje ProximityPrompt z alternatywnym GUI. Jeśli nie, zone-based trigger wystarczy.

### Hitbox normalization
- R15 w strefie → wszystkie scale values (BodyHeightScale, BodyWidthScale, BodyDepthScale, HeadScale, BodyTypeScale, BodyProportionScale) → 1.0. Cache w `originalScales`. Restore przy wyjściu. R6 pomijane.

### GUI close on zone exit
- Gracz odejdzie >20 studs poza diagonal strefy → `ClosePvPEntry:FireClient` + reset `guiShownFor` flag.

### RemoteEvents
- `OpenPvPEntry` (server→client, pokaż GUI), `ClosePvPEntry`, `BuyPvPEntry` (client→server), `PvPEntryResult`.

---

## Mobile controls (MobileControlsController)

### Detekcja
- `UserInputService.TouchEnabled` (bez excludowania KeyboardEnabled — Studio mobile emulator ma keyboard true).

### Joystick
- `StarterPlayer.DevTouchMovementMode = "Thumbstick"` w project.json (statyczny, nie DynamicThumbstick).
- Pozycja przesunięta: `THUMBSTICK_POS = UDim2.new(0, 140, 1, -60)` (140px od lewej, 60px od dołu).
- **`GetPropertyChangedSignal("Position")` lock** — Roblox PlayerModule nadpisuje co frame, więc na każdą zmianę natychmiast wracamy do naszej pozycji. Flaga `applying` zapobiega rekursji.
- Re-lock przy CharacterAdded i ChildAdded(TouchGui).

### Przyciski po prawej
- **SPRINT** (trzymanie = Shift) — fire `_G["__sprintStart/End"]` z SprintController. MouseLeave failsafe.
- **DESKA** (tap = R) — fire `_G["__deskaToggle"]` z DeskaController.
- 110×110 koła, ułożone w prawym dolnym (SPRINT wyżej, DESKA niżej).

---

## SFX

### Folder `workspace.SFX` z Sound instancjami
- `PickingUp` — zbieranie butelki (CollectController)
- `Money` — przyjęcie butelek w butelkomacie
- `RouletteTick` — co item przez wskaźnik w roulette kosza
- `Win` — koniec spin roulette (trimEnd=0.6s)
- `Buy` — zakup plecaka / węzła drzewka
- `LevelUp` — zakup ulepszenia w drzewku (razem z Buy)
- `Click` — UI clicks: X-close we wszystkich panelach, KUP/POTWIERDŹ/ULEPSZ, klik slotu/węzła/zakładki menu, hoverboard, karty desek
- `Equip` — wyposażenie deski

### Pipeline
- `SoundService.SfxGroup` — wszystkie SFX podpinane. Slider w Ustawieniach modyfikuje `SfxGroup.Volume`.
- Inline `playSfx(name, opts?)` helper w każdym kontrolerze (clone z workspace.SFX, parent SoundService, `Ended:Connect(Destroy)`).

---

## Movement lock (UI blokuje ruch)

### Helper (ref-counted, `_G`)
- Definiowany pierwszy raz w `BankController` (guard `if not _G["__lockMovement"]`).
- `_G["__lockMovement"]()` → inc + `PlayerModule:GetControls():Disable()` jeśli count == 1.
- `_G["__unlockMovement"]()` → dec + `Enable()` jeśli count == 0.

### Wywoływane przez
- BankController (BankInit / closeBank)
- ShopController, QuestController (setOpen true/false)
- DeckShopController (setBuyOpen / openMenu / closeMenu / WYPOSAŻ)
- KoszController (showRoulette start → hidePanel po 0.85s)

---

## Drop butelek po śmierci (DeathDropService)

- Hook `Humanoid.Died` (debounce `diedHandled`).
- Spawn każdej butelki w losowym miejscu w promieniu **5 studs**, `findGroundY` z raycastem (iteracyjnie pomija invisible triggery typu PVPZone).
- Butelka `Anchored=true, CanCollide=false`. Attribute `DeathDropOwner = UserId`, `DeathDropExpires = clock + 5s` (właściciel nie może pickować przez 5s).
- **2 minuty despawn** — `task.delay(120, ...)` per butelka. Jeśli ktoś podniesie wcześniej, no-op.
- Instant respawn (`LoadCharacter`).
- Syrop dziadka NIE drop'uje się (quest item).

---

## Sklep czapek (HatShopService + HatShopController)

- `workspace.SKLEP2.Cashier` → ProximityPrompt.
- Permanentny zakup: 5000 zł + 10 Legendarna + 1 Mityczny. Sprawdzane atomowo server-side.
- Bonusy: +50 HP (Humanoid.MaxHealth na CharacterAdded), +50 stamina (SprintController.STAMINA_MAX), +2 speed (baseSpeed).
- `ReplicatedStorage.Czapka` (Accessory) dodawana na każdy spawn jeśli `data.HatOwned`.
- Klient: `HatStatusUpdate` event przekazuje bonusy do SprintController.

---

## Boost shop (BoostShopService + BoostShopController)

- Developer Product Robux. Aktualny: **x2 KASA z butelkomatu na 10 min** (ProductId `3605052667`, 19 R$).
- `MarketplaceService.ProcessReceipt` → `activateDoubleEarn(player)` → `doubleEarnUntil[p] = clock + 600`.
- BottleService.EmptyBackpack: `multiplier *= BoostShopService.GetEarnMultiplier(player)` (mnoży się ze skill tree mult).
- Klient: badge w prawym górnym HUD gdy aktywny ("x2 KASA 9:42"). Karta w **ShopCatalogController** (osobne GUI sklepu, nie zakładka menu — przeniesione w 2026).
- Brak persystencji boostu (restart serwera = ginie). Konsumowalny produkt.
- VIP deska (`Config.Decks.VIP.RobuxProductId = 3605653942`) też przez ProcessReceipt → BindableEvent `GrantDeckEvent` → DeskaService.grantDeck.

---

## System petów (PetService + PetGablotaController)

### Założenia
- Gracz podchodzi do `workspace.Pets.GablotyPetow.Gablota` (ProximityPrompt) → 2 opcje: 1 jajko (500 zł) lub 3 jajka (1500 zł, wymaga Gamepass `1884317989`).
- Drop: weighted RNG (Config.Pets.Rarities.weight + ClassWeights). 5 rzadkości (Common→Huge) × 2 klasy (Sprinter/Tank).
- Każdy pet = unikalny UUID + (rarity, class). Zajmuje 1 slot pojemności (jak butelka). Storage w `data.Pets` (EQ) i `data.BankPets` (skarbiec).
- Max 1 equipped pet — daje bonusy multiplykatywne (money) + addytywne (speed/HP).
- Wizualny pet podąża za graczem (server-spawn w `workspace.ActivePets`, Heartbeat lerp behind HRP). Chowa się w PVPZone/SAFEZONE.

### Bonusy
- **Money:** Common ×1.1, Rare ×1.3, Epic ×1.5, Legendary ×1.7, Huge ×2.0 — multiplikuje się ze skill tree i BoostShop boost.
- **Speed (Sprinter):** +3/+5/+10/+15/+25. Dodaje się do baseSpeed (chodzenie/sprint) ORAZ do `deck.Speed` (Default 40 + Huge 25 = 65).
- **HP (Tank):** +10/+15/+25/+50/+100. `MaxHealth = 100 + hatBonus + petTankBonus` — single source of truth w `PetService.applyPetEffects` (HatShop deleguje by uniknąć race).

### Struktura
- Konfiguracja w `Config.Pets`:
  ```
  Rarities = { Common = { order, weight, moneyMul, color, displayName, image }, ... }  -- image = tekstura w slocie EQ
  Classes  = { Sprinter = { effect="speed", bonuses={Common=3,...} }, Tank = ... }
  ClassWeights = { Sprinter = 1, Tank = 1 }
  ModelsFolderPath = { "Pets", "PetyZwykle" }
  ModelNamePrefix  = "Pet"  -- → ReplicatedStorage.Pets.PetyZwykle.PetHuge
  ```
- Dodanie nowej rzadkości = 1 wpis w `Rarities` + bonusy w `Classes.<class>.bonuses[rarity]` + model `Pet<Name>` w `ReplicatedStorage.Pets.PetyZwykle`.

### UI
- **Inventory:** każdy pet = osobny slot w głównym EQ (id=`Pet_<uuid>`), kolor per rzadkość + **tekstura** (`Config.Pets.Rarities[r].image`, ImageLabel ScaleType=Fit, ZIndex 1 — nad glow, pod nazwą klasy/count; preload w LoadingController). Klik → detail panel z **ZAŁÓŻ/ZDEJMIJ** + **WYRZUĆ**.
- **Bank:** pety renderują się w slotach bank/eq, drag pet ↔ bank działa (swap, no-merge). Conservation server-side po UUIDach.
- **Roulette:** 1 jajko = 1 strip, 3 jajka = 3 strippy obok siebie. Quint Out 3.5s spin, jeden start + jeden Win SFX. Polish: animowany gradient ramki dla Legendary/Huge, screen shake gdy HUGE.

### RemoteEvents
`OpenPetGablota` / `BuyEggOpen` / `PetRouletteResult` / `EquipPet` / `UnequipPet` / `DiscardPet` / `PetStatusUpdate` / `PromptPetGamepassBuy`.

### BindableEvents
- `ServerScriptService.ForceDespawnPetEvent` — PvPService fire'uje przy wejściu w PVPZone/SAFEZONE.

### Pułapki
1. **HP race między HatShop a PetService** — single source of truth = `PetService.applyPetEffects`, HatShop deleguje do niego.
2. **Multiplier order** — `final = base × skillMul × boostMul × petMul` (wszystkie multiplikatywne).
3. **Pet UUID** — `HttpService:GenerateGUID(false)`.
4. **SaveData yield** — NIE w hot path (OpenEgg/Equip/Discard) — auto-save 60s + PlayerRemoving.
5. **Visual pet po respawnie** — `syncVisual` w `CharacterAdded`.
6. **Bank conservation petów** — server sprawdza zbiór UUIDów PRZED zastosowaniem (anti-duplikacja).

---

## Wymiana / Trading (TradeService + TradeController)

### Założenia
- Wymiana gracz↔gracz w obrębie serwera (bez dystansu). Przedmioty: **pety z EQ (`data.Pets`),
  włącznie z założonym** (auto-unequip przy transferze; skarbiec `BankPets` POZA wymianą) + **pieniądze**.
- **Serwer autorytatywny.** Pet logic (remove/add/unequip/refresh) zostaje w `PetService`
  (single source of truth) — TradeService woła `PetService.RemovePets/AddPets/FindPet/CountPets/GetPetCap/RefreshAfterTrade`.

### Przycisk + lista
- Przycisk **WYMIANA** w HUD: lewa strona, **stos deska(-190) / teleport(0) / wymiana(+190)** (anchor (0,0.5)).
  Ikona `Config.Trade.ButtonIconId`. (Przesunięcie desek/teleportu zrobione w DeckShop/TeleportController.)
- Klik → lista aktywnych graczy (`Players:GetPlayers()` client-side, awatar `rbxthumb` + nick + INVITE).

### Flow
1. `TradeInvite(targetUserId)` → odbiorca dostaje `TradeInvited` → popup „<nick> zaprosił cię do wymiany”
   (trochę nad środkiem) z akceptuj (`AcceptIconId`) / anuluj (`CancelIconId`). **Bez blokady ruchu** (anti-grief).
2. `TradeRespond{fromUserId,accept}`. Odmowa → `TradeInviteResult{accepted=false}` → zapraszający widzi
   „<nick> odmówił wymiany”. Zajęty/inne zaproszenie → `TradeInviteResult{message}`.
3. Akceptacja → sesja + `TradeStart` do obu → okno wymiany (2 kolumny: TWOJA OFERTA ⇆ OFERTA gracza).
4. `TradeOffer{pets,money}` per zmiana. Pet klik = **checkmark** (overlay jak gold upgrade). Kwota = TextBox (FocusLost).
   **Każda zmiana resetuje OBIE akceptacje** + przerywa odliczanie (anti-scam, `resetAcceptance`).
5. `TradeAccept` od obu → `counting=true` + **3s odliczanie** (`Config.Trade.CountdownSec`). Po Akceptuj
   pojawia się **Anuluj** (`TradeCancel`) — działa też w trakcie odliczania, bez odliczania przerywa od razu.
6. Po 3s `executeTrade`: walidacja (własność petów / kasa / wolne sloty 20% plecaka) **bez yieldów →
   atomowy swap**, potem `SaveData` obu (poza atomowym blokiem). Brak miejsca/kasy → **cała wymiana
   anulowana** z komunikatem (`TradeEnd{reason="failed"}`). OK → `TradeEnd{reason="completed", received}`.

### Anti-scam / pułapki
- `countdownToken` — `task.delay(3s)` wykonuje transfer tylko gdy token niezmieniony (zmiana/anuluj inkrementują).
- Walidacja i mutacja w `executeTrade` **bez yieldów pomiędzy** (atomowość) — SaveData dopiero po swapie.
- `PlayerRemoving` przerywa sesję drugiego gracza (`TradeEnd reason="cancelled"`) + czyści zaproszenia.

### RemoteEvents
`TradeInvite`/`TradeInvited`/`TradeRespond`/`TradeInviteResult`/`TradeStart`/`TradeOffer`/`TradeSync`/`TradeAccept`/`TradeCancel`/`TradeEnd`.

### Config (`Config.Trade`)
`ButtonIconId`, `AcceptIconId`, `CancelIconId`, `CountdownSec=3`, `InviteTimeout=30`, `Throttle=0.5`, `MaxMoney`.

---

## Panel admina (AdminService + AdminController)

- `Config.Admins` — lista UserId i/lub nazw.
- F2 otwiera panel. Akcje: **broadcast** (czarny box gold border w centrum 5s), **giveZl** (max 1M), **giveBottles** (max 1000), **kick**, **addCode**.
- **Globalne akcje (cross-server)**: `broadcast` i `addCode` działają na WSZYSTKICH serwerach.
  - Live propagacja przez `MessagingService` (topiki `AdminBroadcast` / `AdminAddCode`).
  - Stosowane lokalnie od razu (instant feedback + działa w Studio); echo własnego serwera ignorowane po `game.JobId` (anti-duplikacja).
  - `addCode` dodatkowo utrwalany w DataStore `AdminCodes_v1` (klucz `ALL`, atomowy `UpdateAsync`) — serwery startujące PÓŹNIEJ ładują kody na starcie. Broadcast jest tylko live (efemeryczny).
- `giveZl`/`giveBottles`/`giveMagnet`/`kick` pozostają lokalne (dotyczą jednego gracza/serwera).
- Throttle 0.3s między akcjami. Każda akcja waliduje admin status (anti-cheat).
- Przycisk close i wszystkie buttony bez UIStroke (Thickness=0 — czytelność).

---

## Kody promocyjne (CodeService)

- Wpisywane w Ustawieniach. `Config.Codes`: OGDC=200, PVPOG=500, HOLYFINDER=1000, PARKOUR=150.
- Throttle 0.5s. Walidacja: uppercase, max 32 chars, sprawdza `data.RedeemedCodes[code]`.
- AdminAction "addCode" dodaje kod **globalnie** (wszystkie serwery): live przez `MessagingService` + persystencja w DataStore `AdminCodes_v1` (świeże serwery ładują na starcie). Patrz sekcja Panel admina.

---

## Leaderboard (LeaderboardService)

- **Aktualne Zlotowki** (nie TotalEarned) — gracz spada jak wyda kasę.
- `workspace.LeaderboardTablica` (BasePart) → auto SurfaceGui na Front face.
- OrderedDataStore `Leaderboard_Zlotowki_v1`, wartość = `math.floor(zlotowki * 100)` (grosze jako int).
- Top 10, save co 60s + display update +2s buffer. Cache nazw.
- Kolory: #1 gold, #2 silver, #3 bronze, reszta dim.

---

## Cutscena tutorial (IntroService + IntroController + LoadingController)

- `workspace.CutsceneStage` — mini-mapa z markerami `Cam_Scene1/2/3/_End`, NPC `Marcelk1122`, props.
- 3 sceny po 3.5s każdy + cut (Esc/POMIŃ button skip). Tekst fade + letterbox bars + hide all GUI.
- Autoplay tylko przy pierwszym wejściu (flaga `HasSeenIntro` w DataStore). Replay z USTAWIENIA.
- **LoadingController** — ContentProvider:PreloadAsync na BottleModels + workspace.AutomatKaucyjny + Sklep + Kosze. Synchronizacja z autoplay przez `_G["__loadingDone"]` + `__introTryAutoplay`.

---

## Ustawienia (SettingsController)

- Replay tutorial → `_G["__playIntroTest"]`.
- Slider głośności SFX → `SoundService.SfxGroup.Volume`.
- Reset postępu → confirm dialog → `ResetProgress:FireServer` → `cache[player] = deepCopy(DEFAULT_DATA)` + SaveData + Teleport (lub Kick w Studio).

---

## Styl wizualny

### Świat
- Pastelowe low-poly, Bloom lekki, pora dnia ~10:00, Atmosphere on.
- Mapa ~200×200 studs: centrum, park, osiedle, ulice.

### UI — green theme
- `C_BG=#125B49`, `C_PANEL=#186E5A`, `C_HEADER=#003527`, `C_BORDER=#051914`, `C_ACCENT_GREEN=#AADD66`.
- Specjalne akcenty: `C_SYRUP=(200,130,60)` dziadek, `C_GOLD=(239,199,95)` story quest, blue/amber dla skill tree gałęzi.
- UICorner 8 na panelach, 12 na slotach, 8 na przyciskach. UIStroke 4 panel, 3 slot, 0 na przyciskach typu KUP/ODBIERZ (poprawia czytelność tekstu).
- Wallet bez UICorner (prostokątne rogi).
- AutoButtonColor = false OBOWIĄZKOWO na TextButton overlay'ach.
- Headery panelu: UICorner 8 + bottom-fill mask + 2px separator (zob. zasady).
- Hover-animacje przez UIScale 1.06 (przyciski), 1.18 (X-close).

---

## Quick reference — workspace structure

| Folder/Model | Co | Wymagane przez |
|---|---|---|
| `workspace.Bottles` | Auto folder live butelek | BottleService |
| `workspace.BottleSpawnAreas` | Parts (tier per nazwa `T<N>`) | BottleService |
| `workspace.AutomatKaucyjny` | Model butelkomatu | BottleService (tag) |
| `workspace.BUTELKOMANIACY.Kasjer` | Model/BasePart sklepu plecaków | ShopService |
| `workspace.Kosze` | Folder koszy | KoszService |
| `workspace.SFX` | Sound: PickingUp/Money/RouletteTick/Win/Buy/LevelUp/Click/Equip | wszyscy |
| `workspace.LeaderboardTablica` | BasePart rankingu | LeaderboardService |
| `workspace.CutsceneStage` | Mini-mapa + markery + NPC Marcelk1122 | IntroController |
| `workspace.Grandpa` | Model R15 NPC | GrandpaService, GrandpaController |
| `workspace.SyrupSpawnPoints` | Folder z SyrupSpawn1/2/3 | SyrupService |
| `workspace.SyrupActive` | Auto folder live syropów (per-player) | SyrupService |
| `workspace.BANK.Bankier` | Model/BasePart bank | BankService |
| `workspace.SKLEP2.Cashier` | Model/BasePart sklep czapek | HatShopService |
| `workspace.Deski.{DeskaDefault,Red,Blue,VIP}` | Modele szablonów desek | DeskaService |
| `workspace.Parking.Gabloty.Gablota{1-4}` | Gabloty desek (fallback workspace.Gabloty) | DeskaService |
| `workspace.ActiveDecks` | Auto folder aktywnych desek | DeskaService |
| `workspace.PVPZone` | BasePart strefy PvP | PvPService |
| `workspace.SAFEZONE` | BasePart bufora przed PvP | PvPService |
| `workspace.KasjerPVP` (opcjonalny) | Rig z alt promptem płatności | PvPEntryService |
| `ReplicatedStorage.Sword` | Tool ClassicSword | PvPService |
| `ReplicatedStorage.Czapka` | Accessory | HatShopService |
| `ReplicatedStorage.BackpackModels.Level{1-4}` | Accessory | BackpackEquipService |
| `ReplicatedStorage.BottleModels.{Zwykla,Rzadka,Epicka,Legendarna}` + `ReplicatedStorage.Mityczny` | Modele butelek | BottleService |
| `ReplicatedStorage.SyrupModel` (opcjonalny) | Model syropu (fallback cylinder) | SyrupService |
| `ReplicatedStorage.IntroAnims` | Auto Animation instances | IntroController |
| `ServerStorage.RBX_ANIMSAVES.<NpcName>.<seq>` | KeyframeSequence | IntroService |
| `ServerScriptService.GrantDeckEvent` | Auto BindableEvent (BoostShop→DeskaService VIP) | BoostShopService |
| `ServerScriptService.ForceDeskDismountEvent` | Auto BindableEvent (PvP→DeskaService) | PvPService |

---

## Bootstrap order (GameServer.server.luau)

```lua
require(script.Parent.PlayerDataService)
require(script.Parent.QuestService)         -- przed BottleService/Kosz/Upgrade
require(script.Parent.StoryQuestService)    -- linia fabularna, hooki w innych serwisach
require(script.Parent.BottleService)
require(script.Parent.UpgradeService)
require(script.Parent.ShopService)
require(script.Parent.LeaderboardService)
require(script.Parent.KoszService)
require(script.Parent.IntroService)
require(script.Parent.SyrupService)         -- przed GrandpaService
require(script.Parent.GrandpaService)
require(script.Parent.BankService)
require(script.Parent.CodeService)
require(script.Parent.BackpackEquipService)
require(script.Parent.PvPService)
require(script.Parent.HatShopService)
require(script.Parent.DeathDropService)
require(script.Parent.AdminService)
require(script.Parent.BoostShopService)
require(script.Parent.PlayerCollisionService)  -- collision group "Players" — gracze przechodzą przez siebie
-- DeskaService i PvPEntryService to standalone Scripty (.server.luau) — uruchamiają się same
```

---

## Aktualny stan RemoteEvents (default.project.json)

`CollectBottle`/`CollectBottleResult`/`DropBottle`/`SyncInventoryLayout`/`EmptyBackpack`/`EmptyBackpackResult`/`UpdateHUD` — bottle flow
`BuySkillUpgrade`/`SkillTreeUpdate`/`SkillTreeInit` — drzewko
`OpenShop`/`BuyBackpack`/`BackpackResult` — sklep plecaków
`KoszResult` — kosze
`QuestInit`/`QuestUpdate`/`ClaimQuest`/`ClaimQuestResult` — daily questy
`StoryQuestInit`/`StoryQuestUpdate`/`StoryQuestComplete`/`StoryQuestClaim` — story
`PlayIntro`/`IntroFinished` — cutscena
`LegendaryEventStart`/`LegendaryEventEnd` — event
`ResetProgress` — Settings
`GrandpaTalk`/`GrandpaDialog`/`GrandpaAccept`/`GrandpaTurnIn`/`GrandpaState`/`SyrupPickupResult` — dziadek
`BankInit`/`BankDeposit`/`BankWithdraw`/`BankResult`/`UpgradeBank` — bank
`RedeemCode`/`RedeemCodeResult` — kody
`OpenHatShop`/`BuyHat`/`BuyHatResult`/`HatStatusUpdate` — czapki
`AdminInit`/`AdminAction`/`AdminBroadcast` — admin
`BoostStatusUpdate`/`PromptBoostPurchase` — Robux
`DeskMount`/`DeskDismount`/`DeskMountResult`/`QuickMount`/`OpenDeckShop`/`BuyDeck`/`BuyDeckResult`/`EquipDeck`/`DeckStatus` — deski
`OpenPvPEntry`/`ClosePvPEntry`/`BuyPvPEntry`/`PvPEntryResult` — PvP entry

---

## `_G` eksporty (cross-controller)

- `_G["__menuOpen/Close/Toggle/SetActiveTab"]` — sterowanie menu z innych kontrolerów (klawisze I/U/Q przekierowane).
- `_G["__skillTreeToggle"]`, `_G["__skillTreeState"]` — `{data, tryBuy, nodeState, makeHex, treeWorld}`, używane przez inventory detail panel do mnożnika.
- `_G["__playIntroTest"]`, `_G["__introTryAutoplay"]`, `_G["__loadingDone"]` — cutscena/loading koordynacja.
- `_G["__inventoryGetLayout"]/__inventorySetLayout` — position-keyed inventory API (używane przez BankController).
- `_G["__bankLayoutCache"]` — split layout banku w session.
- `_G["__lockMovement"]/__unlockMovement` / `__moveLockCount` — ref-counted PlayerModule.Controls:Disable().
- `_G["__sprintStart"]/__sprintEnd` — fake Shift down/up (mobile SPRINT button).
- `_G["__deskaToggle"]` — fake R (mobile DESKA button).
- `_G["__deskaMounted"]` — flag dla SprintController (nie nadpisuj WalkSpeed deski).

Quest dziadka NIE używa `_G` — przez dedykowane RemoteEvents (GrandpaState/Dialog/SyrupPickupResult).

---

## Najważniejsze pułapki (rzeczy które mogły zaskoczyć)

1. **DataStore.SetAsync yielduje** — NIE wywołuj SaveData w hot pathach (np. CollectBottle hooks). 2026 fix: usunięte z StoryQuestService.AddProgress.
2. **Seat × Deska** — gracz siedzący na huśtawce + R → 2 welds na HRP → pod mapę. Fix: force `Sit=false + ChangeState(Jumping) + wait(0.15)` w mountPlayer.
3. **Sprint × Deska** — SprintController nadpisuje WalkSpeed ustawiony przez deskę. Fix: `_G["__deskaMounted"]` early-return w sprint Heartbeat ORAZ guard w `applySpeed()` (event-driven calle typu PetStatusUpdate przy otwarciu jajka clobberowały prędkość deski → wolny ruch). Po zejściu z deski `wasMounted` transition przywraca prędkość pieszą.
4. **Roblox PlayerModule resetuje thumbstick position** — fix: `GetPropertyChangedSignal("Position")` lock z flagą `applying`.
5. **DevTouchMovementMode wymaga elevated permissions** z LocalScript — ustaw przez `StarterPlayer.DevTouchMovementMode` w project.json.
6. **Studio mobile emulator** ma `KeyboardEnabled = true` — nie excludować z gate'a touch.
7. **CollectionService tag "Butelkomat"** — server może auto-taggować workspace.AutomatKaucyjny, ale Studio user może ręcznie taggować Parts.
8. **Atrybuty na Accessory** (`BackOffset`/`BackRotation`/`OwnerUserId`/`DeathDropOwner`) — używane w wielu miejscach do per-instance config.
9. **Bank UI 15 slotów na sztywno** — NIE zmienia rozmiaru per BankCapLevel. Capacity tylko w counter X/N i w validation server-side.
10. **Linia fabularna preFillProgress** — gracz z najlepszym plecakiem dostaje quest 4 jako gotowy od razu (klika ODBIERZ).
