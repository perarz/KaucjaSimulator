-- QuestController.luau
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local function playSfx(name: string)
	local folder = workspace:FindFirstChild("SFX")
	local tmpl = folder and folder:FindFirstChild(name)
	if not (tmpl and tmpl:IsA("Sound")) then return end
	local grp = SoundService:FindFirstChild("SfxGroup")
	if not grp then grp = Instance.new("SoundGroup"); grp.Name = "SfxGroup"; grp.Parent = SoundService end
	local s = tmpl:Clone(); s.SoundGroup = grp; s.Parent = SoundService; s:Play()
	s.Ended:Connect(function() s:Destroy() end)
end

local Config            = require(ReplicatedStorage:WaitForChild("Config"))
local Events            = ReplicatedStorage:WaitForChild("Events")
local QuestInit         = Events:WaitForChild("QuestInit")
local QuestUpdate       = Events:WaitForChild("QuestUpdate")
local ClaimQuest        = Events:WaitForChild("ClaimQuest")
local ClaimQuestResult  = Events:WaitForChild("ClaimQuestResult")
local GrandpaState      = Events:WaitForChild("GrandpaState")
local StoryQuestInit    = Events:WaitForChild("StoryQuestInit")
local StoryQuestUpdate  = Events:WaitForChild("StoryQuestUpdate")
local StoryQuestClaim   = Events:WaitForChild("StoryQuestClaim")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

-- ── Paleta ────────────────────────────────────────────────────────────────

local FONT       = Enum.Font.GothamBlack
local C_BG       = Color3.fromRGB(18, 91, 73)
local C_PANEL    = Color3.fromRGB(24, 110, 90)
local C_HEADER   = Color3.fromRGB(0, 53, 39)
local C_CARD     = Color3.fromRGB(14, 75, 60)
local C_BORDER   = Color3.fromRGB(5, 25, 20)
local C_WHITE    = Color3.fromRGB(255, 255, 255)
local C_DIMTEXT  = Color3.fromRGB(175, 175, 175)
local C_GREEN    = Color3.fromRGB(170, 221, 102)
local C_BLUE     = Color3.fromRGB(88, 166, 255)
local C_SYRUP    = Color3.fromRGB(200, 130, 60)  -- akcent dla questa dziadka
local C_GOLD     = Color3.fromRGB(239, 199, 95)  -- akcent dla story questa
local X_RED      = Color3.fromRGB(220, 70, 70)
local X_RED_HOVER = Color3.fromRGB(255, 110, 110)

-- ── Stan ──────────────────────────────────────────────────────────────────

local questState = {
	activeIds = {},
	progress  = {},
	claimed   = {},
	refreshAt = 0,
}

-- Stan questa dziadka (z RemoteEvent GrandpaState)
local grandpaQuest = {
	state    = "none",   -- "none" | "active" | "done"
	hasSyrup = false,
	desc     = "Znajdź syrop klonowy dziadka w parku",
	reward   = 1000,
}

-- Stan questa fabularnego (z RemoteEvent StoryQuest*)
local storyQuest = {
	active       = false,
	idx          = 1,
	total        = 0,
	desc         = "",
	progress     = 0,
	target       = 1,
	reward       = 0,
	readyToClaim = false,
}

local isOpen = false

local function findQuest(id: string)
	for _, q in ipairs(Config.Quests) do
		if q.id == id then return q end
	end
	return nil
end

-- ── ScreenGui ─────────────────────────────────────────────────────────────

local PANEL_W  = 560
-- HEADER_H = 0 — panel mieszka w zakładce MenuController, własny header schowany.
-- Pozycje children referencują HEADER_H jako offset Y, więc samo wyzerowanie
-- shifuje całość do góry.
local HEADER_H = 0
local CARD_H   = 110
local CARD_GAP = 12
local PAD      = 22
local SECTION_LBL_H = 26
local SECTION_GAP   = 6   -- między section label a pierwszą kartą
local DAILY_AREA = Config.QuestActiveCount * CARD_H + (Config.QuestActiveCount - 1) * CARD_GAP

-- Layout pionowy:
-- header / PAD / "DZIADEK" label / SECTION_GAP / grandpa card / CARD_GAP / "ZADANIA DZIENNE" label / SECTION_GAP / daily cards / PAD
local PANEL_H  = HEADER_H + PAD
	+ SECTION_LBL_H + SECTION_GAP + CARD_H + CARD_GAP
	+ SECTION_LBL_H + SECTION_GAP + DAILY_AREA
	+ PAD

local gui = Instance.new("ScreenGui")
gui.Name           = "Quests"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = false
gui.Parent         = playerGui

local overlay = Instance.new("TextButton")
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.AutoButtonColor        = false
overlay.ZIndex                 = 1
overlay.Parent                 = gui

-- Maksymalna widoczna wysokość panelu — content menu MenuController ma ~610px,
-- zostawiamy bufor 30px. Powyżej tego włącza się scroll.
local MAX_VISIBLE_H = 580

local panel = Instance.new("ScrollingFrame")
panel.Size                  = UDim2.fromOffset(PANEL_W, MAX_VISIBLE_H)
panel.AnchorPoint           = Vector2.new(0.5, 0.5)
panel.Position              = UDim2.new(0.5, 0, 0.55, 0)
panel.BackgroundTransparency = 1
panel.BorderSizePixel       = 0
panel.ClipsDescendants      = true
panel.ZIndex                = 2
panel.CanvasSize            = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.ScrollBarThickness    = 6
panel.ScrollBarImageColor3  = Color3.fromRGB(8, 50, 35)
panel.ScrollingDirection    = Enum.ScrollingDirection.Y
panel.AutomaticCanvasSize   = Enum.AutomaticSize.None
panel.Parent                = gui

-- Header — niewidoczny w nowym UI (zakładka MenuController ma swój pasek)
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.Visible          = false
header.BackgroundColor3 = C_HEADER
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = header
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(1, 0, 0, 10)
	fill.Position         = UDim2.new(0, 0, 1, -10)
	fill.BackgroundColor3 = C_HEADER
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 3
	fill.Parent           = header
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, 0, 0, 2)
	sep.Position         = UDim2.new(0, 0, 1, -2)
	sep.BackgroundColor3 = C_BORDER
	sep.BorderSizePixel  = 0
	sep.ZIndex           = 5
	sep.Parent           = header
end

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(0, 200, 1, 0)
title.Position               = UDim2.fromOffset(22, 0)
title.BackgroundTransparency = 1
title.Text                   = "QUESTY"
title.TextSize               = 18
title.Font                   = FONT
title.TextColor3             = C_WHITE
title.TextXAlignment         = Enum.TextXAlignment.Left
title.ZIndex                 = 4
title.Parent                 = header

-- refreshLbl ("Nowe za Xh Ym") — siedzi obok "ZADANIA DZIENNE" label
-- (jego Position ustawiamy dalej, po deklaracji sekcji daily — patrz niżej)
local refreshLbl = Instance.new("TextLabel")
refreshLbl.AnchorPoint            = Vector2.new(1, 0)
refreshLbl.BackgroundTransparency = 1
refreshLbl.Text                   = ""
refreshLbl.TextSize               = 14
refreshLbl.Font                   = FONT
refreshLbl.TextColor3             = C_DIMTEXT
refreshLbl.TextXAlignment         = Enum.TextXAlignment.Right
refreshLbl.ZIndex                 = 4
refreshLbl.Parent                 = panel

-- Close X
local closeBtn = Instance.new("TextButton")
closeBtn.Size                   = UDim2.fromOffset(36, 36)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Position               = UDim2.new(1, -12, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "X"
closeBtn.TextSize               = 24
closeBtn.Font                   = FONT
closeBtn.TextColor3             = X_RED
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 5
closeBtn.Parent                 = header
do
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = closeBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.18 }):Play()
		closeBtn.TextColor3 = X_RED_HOVER
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.00 }):Play()
		closeBtn.TextColor3 = X_RED
	end)
end

-- ── Karty questów ────────────────────────────────────────────────────────

type CardHandle = {
	slot:        number,
	frame:       Frame,
	descLbl:     TextLabel,
	progBarBG:   Frame,
	progBarFill: Frame,
	progLbl:     TextLabel,
	rewardLbl:   TextLabel,
	claimBtn:    TextButton,
	claimStroke: UIStroke,
}

local cards: { CardHandle } = {}

-- Sekcja: DZIADEK
local grandpaLbl = Instance.new("TextLabel")
grandpaLbl.Size                   = UDim2.new(1, -PAD * 2, 0, SECTION_LBL_H)
grandpaLbl.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD)
grandpaLbl.BackgroundTransparency = 1
grandpaLbl.Text                   = "DZIADEK"
grandpaLbl.Font                   = FONT
grandpaLbl.TextSize               = 16
grandpaLbl.TextColor3             = C_SYRUP
grandpaLbl.TextXAlignment         = Enum.TextXAlignment.Left
grandpaLbl.ZIndex                 = 3
grandpaLbl.Parent                 = panel

local grandpaContainer = Instance.new("Frame")
grandpaContainer.Size                   = UDim2.new(1, -PAD * 2, 0, CARD_H)
grandpaContainer.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD + SECTION_LBL_H + SECTION_GAP)
grandpaContainer.BackgroundTransparency = 1
grandpaContainer.BorderSizePixel        = 0
grandpaContainer.ZIndex                 = 3
grandpaContainer.Parent                 = panel

-- Sekcja: FABUŁA (story quest)
local storyLbl = Instance.new("TextLabel")
storyLbl.Size                   = UDim2.new(1, -PAD * 2, 0, SECTION_LBL_H)
storyLbl.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD)  -- ustawiane przez relayout
storyLbl.BackgroundTransparency = 1
storyLbl.Text                   = "FABUŁA"
storyLbl.Font                   = FONT
storyLbl.TextSize               = 16
storyLbl.TextColor3             = C_GOLD
storyLbl.TextXAlignment         = Enum.TextXAlignment.Left
storyLbl.ZIndex                 = 3
storyLbl.Parent                 = panel

local storyContainer = Instance.new("Frame")
storyContainer.Size                   = UDim2.new(1, -PAD * 2, 0, CARD_H)
storyContainer.Position               = UDim2.fromOffset(PAD, HEADER_H + PAD + SECTION_LBL_H + SECTION_GAP)
storyContainer.BackgroundTransparency = 1
storyContainer.BorderSizePixel        = 0
storyContainer.ZIndex                 = 3
storyContainer.Parent                 = panel

-- Pojedyncza karta story (struktura jak grandpa card, bez claim)
local storyCard = {
	frame       = Instance.new("Frame"),
	descLbl     = nil :: TextLabel?,
	progBarBG   = nil :: Frame?,
	progBarFill = nil :: Frame?,
	progLbl     = nil :: TextLabel?,
	rewardLbl   = nil :: TextLabel?,
	statusLbl   = nil :: TextLabel?,
}

do
	local frame = storyCard.frame
	frame.Size = UDim2.new(1, 0, 0, CARD_H)
	frame.Position = UDim2.fromOffset(0, 0)
	frame.BackgroundColor3 = C_CARD
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	frame.Parent = storyContainer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = frame

	local descLbl = Instance.new("TextLabel")
	descLbl.Size                   = UDim2.new(1, -224, 0, 28)
	descLbl.Position               = UDim2.fromOffset(16, 14)
	descLbl.BackgroundTransparency = 1
	descLbl.Font                   = FONT
	descLbl.TextSize               = 16
	descLbl.TextColor3             = C_WHITE
	descLbl.TextXAlignment         = Enum.TextXAlignment.Left
	descLbl.TextYAlignment         = Enum.TextYAlignment.Top
	descLbl.TextWrapped            = true
	descLbl.Text                   = ""
	descLbl.ZIndex                 = 4
	descLbl.Parent                 = frame
	storyCard.descLbl = descLbl

	local progBarBG = Instance.new("Frame")
	progBarBG.Size = UDim2.new(1, -224, 0, 14)
	progBarBG.Position = UDim2.new(0, 16, 1, -34)
	progBarBG.BackgroundColor3 = Color3.fromRGB(8, 50, 35)
	progBarBG.BorderSizePixel = 0
	progBarBG.ZIndex = 4
	progBarBG.Parent = frame
	local pbc = Instance.new("UICorner"); pbc.CornerRadius = UDim.new(0, 4); pbc.Parent = progBarBG
	storyCard.progBarBG = progBarBG

	local progBarFill = Instance.new("Frame")
	progBarFill.Size = UDim2.fromScale(0, 1)
	progBarFill.BackgroundColor3 = C_GOLD
	progBarFill.BorderSizePixel = 0
	progBarFill.ZIndex = 5
	progBarFill.Parent = progBarBG
	local pfc = Instance.new("UICorner"); pfc.CornerRadius = UDim.new(0, 4); pfc.Parent = progBarFill
	storyCard.progBarFill = progBarFill

	local progLbl = Instance.new("TextLabel")
	progLbl.Size = UDim2.new(1, 0, 1, 0)
	progLbl.BackgroundTransparency = 1
	progLbl.Font = FONT; progLbl.TextSize = 11
	progLbl.TextColor3 = C_WHITE
	progLbl.TextStrokeColor3 = Color3.new(0, 0, 0); progLbl.TextStrokeTransparency = 0.4
	progLbl.Text = "0 / 0"
	progLbl.ZIndex = 6
	progLbl.Parent = progBarBG
	storyCard.progLbl = progLbl

	local rewardLbl = Instance.new("TextLabel")
	rewardLbl.Size = UDim2.fromOffset(190, 28)
	rewardLbl.AnchorPoint = Vector2.new(1, 0)
	rewardLbl.Position = UDim2.new(1, -210, 0, 14)
	rewardLbl.BackgroundTransparency = 1
	rewardLbl.Font = FONT; rewardLbl.TextSize = 16
	rewardLbl.TextColor3 = C_GOLD
	rewardLbl.TextXAlignment = Enum.TextXAlignment.Right
	rewardLbl.Text = "+0 zł"
	rewardLbl.ZIndex = 4
	rewardLbl.Parent = frame
	storyCard.rewardLbl = rewardLbl

	-- Status/Claim: TextButton (klik = ODBIERZ gdy gotowy)
	local statusLbl = Instance.new("TextButton")
	statusLbl.Size = UDim2.fromOffset(190, 50)
	statusLbl.AnchorPoint = Vector2.new(1, 1)
	statusLbl.Position = UDim2.new(1, -14, 1, -14)
	statusLbl.BackgroundColor3 = C_BG; statusLbl.BorderSizePixel = 0
	statusLbl.Text = "W TRAKCIE"
	statusLbl.TextSize = 15
	statusLbl.Font = FONT
	statusLbl.TextColor3 = C_DIMTEXT
	statusLbl.AutoButtonColor = false
	statusLbl.ZIndex = 4
	statusLbl.Parent = frame
	local stC = Instance.new("UICorner"); stC.CornerRadius = UDim.new(0, 8); stC.Parent = statusLbl
	local stS = Instance.new("UIStroke"); stS.Color = C_BORDER; stS.Thickness = 0; stS.Parent = statusLbl
	statusLbl.MouseButton1Click:Connect(function()
		-- Klikalny tylko gdy gotowy do odbioru (logika w renderStory)
		if storyQuest.readyToClaim then
			storyQuest.readyToClaim = false  -- prewencja double-fire'a
			statusLbl.Active = false
			statusLbl.Text = "..."
			StoryQuestClaim:FireServer()
		end
	end)
	storyCard.statusLbl = statusLbl
end

-- Sekcja: ZADANIA DZIENNE
local dailyLbl = Instance.new("TextLabel")
dailyLbl.Size                   = UDim2.new(1, -PAD * 2, 0, SECTION_LBL_H)
dailyLbl.Position               = UDim2.fromOffset(PAD,
	HEADER_H + PAD + SECTION_LBL_H + SECTION_GAP + CARD_H + CARD_GAP)
dailyLbl.BackgroundTransparency = 1
dailyLbl.Text                   = "ZADANIA DZIENNE"
dailyLbl.Font                   = FONT
dailyLbl.TextSize               = 16
dailyLbl.TextColor3             = C_GREEN
dailyLbl.TextXAlignment         = Enum.TextXAlignment.Left
dailyLbl.ZIndex                 = 3
dailyLbl.Parent                 = panel

-- refreshLbl wyrównane do dailyLbl (ten sam Y), po prawej
refreshLbl.Size     = UDim2.new(0, 240, 0, SECTION_LBL_H)
refreshLbl.Position = UDim2.new(1, -PAD, 0,
	HEADER_H + PAD + SECTION_LBL_H + SECTION_GAP + CARD_H + CARD_GAP)

local cardsContainer = Instance.new("Frame")
cardsContainer.Size                   = UDim2.new(1, -PAD * 2, 0, DAILY_AREA)
cardsContainer.Position               = UDim2.fromOffset(PAD,
	HEADER_H + PAD + SECTION_LBL_H + SECTION_GAP + CARD_H + CARD_GAP + SECTION_LBL_H + SECTION_GAP)
cardsContainer.BackgroundTransparency = 1
cardsContainer.BorderSizePixel        = 0
cardsContainer.ZIndex                 = 3
cardsContainer.Parent                 = panel

local function buildCard(slot: number): CardHandle
	local frame = Instance.new("Frame")
	frame.Size            = UDim2.new(1, 0, 0, CARD_H)
	frame.Position        = UDim2.fromOffset(0, (slot - 1) * (CARD_H + CARD_GAP))
	frame.BackgroundColor3 = C_CARD
	frame.BorderSizePixel = 0
	frame.ZIndex          = 3
	frame.Parent          = cardsContainer
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
		local s = Instance.new("UIStroke")
		s.Color = C_BORDER; s.Thickness = 3; s.Parent = frame
	end

	-- Opis questa
	local descLbl = Instance.new("TextLabel")
	descLbl.Size                   = UDim2.new(0, PANEL_W - PAD*2 - 220, 0, 28)
	descLbl.Position               = UDim2.fromOffset(16, 12)
	descLbl.BackgroundTransparency = 1
	descLbl.Text                   = ""
	descLbl.TextSize               = 16
	descLbl.Font                   = FONT
	descLbl.TextColor3             = C_WHITE
	descLbl.TextXAlignment         = Enum.TextXAlignment.Left
	descLbl.TextYAlignment         = Enum.TextYAlignment.Top
	descLbl.TextWrapped            = true
	descLbl.ZIndex                 = 4
	descLbl.Parent                 = frame

	-- Pasek progresu — tło
	local progBarBG = Instance.new("Frame")
	progBarBG.Size            = UDim2.new(0, PANEL_W - PAD*2 - 220, 0, 14)
	progBarBG.Position        = UDim2.fromOffset(16, 56)
	progBarBG.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	progBarBG.BorderSizePixel = 0
	progBarBG.ZIndex          = 4
	progBarBG.Parent          = frame
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = progBarBG
		local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 2; s.Parent = progBarBG
	end

	local progBarFill = Instance.new("Frame")
	progBarFill.Size            = UDim2.new(0, 0, 1, 0)
	progBarFill.BackgroundColor3 = C_BLUE
	progBarFill.BorderSizePixel = 0
	progBarFill.ZIndex          = 5
	progBarFill.Parent          = progBarBG
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = progBarFill
	end

	-- Tekst progresu "X/Y"
	local progLbl = Instance.new("TextLabel")
	progLbl.Size                   = UDim2.new(0, PANEL_W - PAD*2 - 220, 0, 18)
	progLbl.Position               = UDim2.fromOffset(16, 76)
	progLbl.BackgroundTransparency = 1
	progLbl.Text                   = ""
	progLbl.TextSize               = 12
	progLbl.Font                   = FONT
	progLbl.TextColor3             = C_DIMTEXT
	progLbl.TextXAlignment         = Enum.TextXAlignment.Left
	progLbl.ZIndex                 = 4
	progLbl.Parent                 = frame

	-- Nagroda label
	local rewardLbl = Instance.new("TextLabel")
	rewardLbl.Size                   = UDim2.fromOffset(190, 24)
	rewardLbl.AnchorPoint            = Vector2.new(1, 0)
	rewardLbl.Position               = UDim2.new(1, -14, 0, 14)
	rewardLbl.BackgroundTransparency = 1
	rewardLbl.Text                   = ""
	rewardLbl.TextSize               = 16
	rewardLbl.Font                   = FONT
	rewardLbl.TextColor3             = C_GREEN
	rewardLbl.TextXAlignment         = Enum.TextXAlignment.Right
	rewardLbl.ZIndex                 = 4
	rewardLbl.Parent                 = frame

	-- Przycisk KUP/CLAIM
	local claimBtn = Instance.new("TextButton")
	claimBtn.Size                 = UDim2.fromOffset(190, 50)
	claimBtn.AnchorPoint          = Vector2.new(1, 1)
	claimBtn.Position             = UDim2.new(1, -14, 1, -14)
	claimBtn.BackgroundColor3     = C_BG
	claimBtn.BorderSizePixel      = 0
	claimBtn.Text                 = "TRWA…"
	claimBtn.TextSize             = 15
	claimBtn.Font                 = FONT
	claimBtn.TextColor3           = C_DIMTEXT
	claimBtn.AutoButtonColor      = false
	claimBtn.ZIndex               = 4
	claimBtn.Parent               = frame

	local claimStroke
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = claimBtn
		claimStroke = Instance.new("UIStroke")
		claimStroke.Color = C_BORDER; claimStroke.Thickness = 0  -- bez obramowki — czyściej
		claimStroke.Parent = claimBtn
		local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = claimBtn
		local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		claimBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.04 }):Play() end)
		claimBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1.00 }):Play() end)
	end

	return {
		slot        = slot,
		frame       = frame,
		descLbl     = descLbl,
		progBarBG   = progBarBG,
		progBarFill = progBarFill,
		progLbl     = progLbl,
		rewardLbl   = rewardLbl,
		claimBtn    = claimBtn,
		claimStroke = claimStroke,
	}
end

for i = 1, Config.QuestActiveCount do
	cards[i] = buildCard(i)
	local slot = i
	cards[i].claimBtn.MouseButton1Click:Connect(function()
		local qid = questState.activeIds[slot]
		if not qid then return end
		ClaimQuest:FireServer(qid)
	end)
end

-- ── Karta questa dziadka ────────────────────────────────────────────────
-- Wzoruje się na buildCard, ale zamiast przycisku ODBIERZ — status label
-- (claim jest u dziadka, nie tu).

local grandpaCard = {
	frame       = Instance.new("Frame"),
	descLbl     = nil :: TextLabel?,
	progBarBG   = nil :: Frame?,
	progBarFill = nil :: Frame?,
	progLbl     = nil :: TextLabel?,
	rewardLbl   = nil :: TextLabel?,
	statusLbl   = nil :: TextLabel?,
	emptyLbl    = nil :: TextLabel?,
}

do
	local frame = grandpaCard.frame
	frame.Size            = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = C_CARD
	frame.BorderSizePixel = 0
	frame.ZIndex          = 3
	frame.Parent          = grandpaContainer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
	local s = Instance.new("UIStroke"); s.Color = C_BORDER; s.Thickness = 3; s.Parent = frame

	-- Opis
	local descLbl = Instance.new("TextLabel")
	descLbl.Size                   = UDim2.new(0, PANEL_W - PAD*2 - 220, 0, 28)
	descLbl.Position               = UDim2.fromOffset(16, 12)
	descLbl.BackgroundTransparency = 1
	descLbl.Text                   = grandpaQuest.desc
	descLbl.TextSize               = 16
	descLbl.Font                   = FONT
	descLbl.TextColor3             = C_WHITE
	descLbl.TextXAlignment         = Enum.TextXAlignment.Left
	descLbl.TextYAlignment         = Enum.TextYAlignment.Top
	descLbl.TextWrapped            = true
	descLbl.ZIndex                 = 4
	descLbl.Parent                 = frame
	grandpaCard.descLbl = descLbl

	-- Pasek progresu
	local progBarBG = Instance.new("Frame")
	progBarBG.Size            = UDim2.new(0, PANEL_W - PAD*2 - 220, 0, 14)
	progBarBG.Position        = UDim2.fromOffset(16, 56)
	progBarBG.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	progBarBG.BorderSizePixel = 0
	progBarBG.ZIndex          = 4
	progBarBG.Parent          = frame
	do
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 4); cc.Parent = progBarBG
		local ss = Instance.new("UIStroke"); ss.Color = C_BORDER; ss.Thickness = 2; ss.Parent = progBarBG
	end
	local progBarFill = Instance.new("Frame")
	progBarFill.Size            = UDim2.new(0, 0, 1, 0)
	progBarFill.BackgroundColor3 = C_SYRUP
	progBarFill.BorderSizePixel = 0
	progBarFill.ZIndex          = 5
	progBarFill.Parent          = progBarBG
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 4); pc.Parent = progBarFill
	grandpaCard.progBarBG   = progBarBG
	grandpaCard.progBarFill = progBarFill

	-- Tekst progresu "0/1"
	local progLbl = Instance.new("TextLabel")
	progLbl.Size                   = UDim2.new(0, PANEL_W - PAD*2 - 220, 0, 18)
	progLbl.Position               = UDim2.fromOffset(16, 76)
	progLbl.BackgroundTransparency = 1
	progLbl.Text                   = "0 / 1"
	progLbl.TextSize               = 12
	progLbl.Font                   = FONT
	progLbl.TextColor3             = C_DIMTEXT
	progLbl.TextXAlignment         = Enum.TextXAlignment.Left
	progLbl.ZIndex                 = 4
	progLbl.Parent                 = frame
	grandpaCard.progLbl = progLbl

	-- Nagroda
	local rewardLbl = Instance.new("TextLabel")
	rewardLbl.Size                   = UDim2.fromOffset(190, 24)
	rewardLbl.AnchorPoint            = Vector2.new(1, 0)
	rewardLbl.Position               = UDim2.new(1, -14, 0, 14)
	rewardLbl.BackgroundTransparency = 1
	rewardLbl.Text                   = "Nagroda: " .. grandpaQuest.reward .. " ZŁ"
	rewardLbl.TextSize               = 16
	rewardLbl.Font                   = FONT
	rewardLbl.TextColor3             = C_GREEN
	rewardLbl.TextXAlignment         = Enum.TextXAlignment.Right
	rewardLbl.ZIndex                 = 4
	rewardLbl.Parent                 = frame
	grandpaCard.rewardLbl = rewardLbl

	-- Status label zamiast przycisku claim
	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size                   = UDim2.fromOffset(190, 50)
	statusLbl.AnchorPoint            = Vector2.new(1, 1)
	statusLbl.Position               = UDim2.new(1, -14, 1, -14)
	statusLbl.BackgroundColor3       = C_BG
	statusLbl.BorderSizePixel        = 0
	statusLbl.Text                   = "ZNAJDŹ"
	statusLbl.TextSize               = 15
	statusLbl.Font                   = FONT
	statusLbl.TextColor3             = C_DIMTEXT
	statusLbl.ZIndex                 = 4
	statusLbl.Parent                 = frame
	local stC = Instance.new("UICorner"); stC.CornerRadius = UDim.new(0, 8); stC.Parent = statusLbl
	local stS = Instance.new("UIStroke"); stS.Color = C_BORDER; stS.Thickness = 0; stS.Parent = statusLbl  -- bez obramowki — spójnie z daily quest claimBtn
	grandpaCard.statusLbl = statusLbl

	-- Empty state label (wyświetlany gdy state="none" lub "done")
	local emptyLbl = Instance.new("TextLabel")
	emptyLbl.Size                   = UDim2.new(1, -32, 1, -24)
	emptyLbl.Position               = UDim2.fromOffset(16, 12)
	emptyLbl.BackgroundTransparency = 1
	emptyLbl.Text                   = ""
	emptyLbl.TextSize               = 14
	emptyLbl.Font                   = FONT
	emptyLbl.TextColor3             = C_DIMTEXT
	emptyLbl.TextXAlignment         = Enum.TextXAlignment.Center
	emptyLbl.TextYAlignment         = Enum.TextYAlignment.Center
	emptyLbl.TextWrapped            = true
	emptyLbl.Visible                = false
	emptyLbl.ZIndex                 = 5
	emptyLbl.Parent                 = frame
	grandpaCard.emptyLbl = emptyLbl
end

local STORY_SECTION_H   = SECTION_LBL_H + SECTION_GAP + CARD_H + CARD_GAP
local DZIADEK_SECTION_H = SECTION_LBL_H + SECTION_GAP + CARD_H + CARD_GAP

-- Kolejność sekcji od góry: FABUŁA (cond) → DZIADEK (cond) → ZADANIA DZIENNE (always)
local function relayoutSections(showStory: boolean, showGrandpa: boolean)
	local y = HEADER_H + PAD

	storyLbl.Visible       = showStory
	storyContainer.Visible = showStory
	if showStory then
		storyLbl.Position       = UDim2.fromOffset(PAD, y)
		storyContainer.Position = UDim2.fromOffset(PAD, y + SECTION_LBL_H + SECTION_GAP)
		y += STORY_SECTION_H
	end

	grandpaLbl.Visible       = showGrandpa
	grandpaContainer.Visible = showGrandpa
	if showGrandpa then
		grandpaLbl.Position       = UDim2.fromOffset(PAD, y)
		grandpaContainer.Position = UDim2.fromOffset(PAD, y + SECTION_LBL_H + SECTION_GAP)
		y += DZIADEK_SECTION_H
	end

	dailyLbl.Position       = UDim2.fromOffset(PAD,  y)
	refreshLbl.Position     = UDim2.new(1, -PAD, 0,  y)
	cardsContainer.Position = UDim2.fromOffset(PAD,  y + SECTION_LBL_H + SECTION_GAP)

	-- Bazowy panel = PANEL_H - DZIADEK (bo PANEL_H zakłada grandpa visible). Dodajemy sekcje widoczne.
	local basePanelH = PANEL_H - DZIADEK_SECTION_H
	local extraH     = (showStory and STORY_SECTION_H or 0) + (showGrandpa and DZIADEK_SECTION_H or 0)
	local fullH      = basePanelH + extraH
	-- CanvasSize = pełna zawartość. Size panelu (visible viewport) zostaje stała.
	-- Gdy fullH > MAX_VISIBLE_H, ScrollingFrame automatycznie pokaże scrollbar.
	panel.CanvasSize = UDim2.fromOffset(PANEL_W, fullH)
end

-- Stary alias dla istniejącego renderGrandpa
local function relayoutForGrandpaVisibility(showGrandpa: boolean)
	relayoutSections(storyQuest.active, showGrandpa)
end

local function renderGrandpa()
	local g = grandpaQuest
	local active = (g.state == "active")
	-- Pokazuj sekcję DZIADEK tylko gdy quest jest aktywny (state == "active").
	-- "none" i "done" → cała sekcja ukryta, daily questy zajmują miejsce.
	relayoutSections(storyQuest.active, active)
	if not active then return end

	-- Quest aktywny → pokaż content karty
	grandpaCard.descLbl.Visible     = true
	grandpaCard.progBarBG.Visible   = true
	grandpaCard.progLbl.Visible     = true
	grandpaCard.rewardLbl.Visible   = true
	grandpaCard.statusLbl.Visible   = true
	grandpaCard.emptyLbl.Visible    = false

	local prog = g.hasSyrup and 1 or 0
	grandpaCard.progLbl.Text       = string.format("%d / 1", prog)
	grandpaCard.progBarFill.Size   = UDim2.fromScale(prog, 1)
	if g.hasSyrup then
		grandpaCard.statusLbl.Text       = "ODDAJ DZIADKOWI"
		grandpaCard.statusLbl.TextColor3 = C_SYRUP
		local s = grandpaCard.statusLbl:FindFirstChildOfClass("UIStroke")
		if s then s.Color = C_SYRUP end
		grandpaCard.progBarFill.BackgroundColor3 = C_SYRUP
	else
		grandpaCard.statusLbl.Text       = "ZNAJDŹ W PARKU"
		grandpaCard.statusLbl.TextColor3 = C_DIMTEXT
		local s = grandpaCard.statusLbl:FindFirstChildOfClass("UIStroke")
		if s then s.Color = C_BORDER end
		grandpaCard.progBarFill.BackgroundColor3 = C_SYRUP
	end
end

-- ── Render ───────────────────────────────────────────────────────────────

local function formatTimeLeft(seconds: number): string
	if seconds <= 0 then return "wkrótce!" end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if h > 0 then
		return string.format("Nowe za %dh %dm", h, m)
	elseif m > 0 then
		return string.format("Nowe za %dm %ds", m, s)
	end
	return string.format("Nowe za %ds", s)
end

local function renderCards()
	for slot = 1, Config.QuestActiveCount do
		local card = cards[slot]
		local qid = questState.activeIds[slot]
		if not qid then
			card.descLbl.Text   = "—"
			card.progLbl.Text   = ""
			card.rewardLbl.Text = ""
			card.progBarFill.Size = UDim2.new(0, 0, 1, 0)
			card.claimBtn.Text  = "—"
			card.claimBtn.TextColor3 = C_DIMTEXT
			card.claimBtn.BackgroundColor3 = C_BG
			card.claimStroke.Color = C_BORDER
			continue
		end
		local quest = findQuest(qid)
		if not quest then continue end

		card.descLbl.Text   = quest.desc
		local prog = questState.progress[qid] or 0
		local target = quest.target
		card.progLbl.Text   = string.format("%d / %d", prog, target)
		local ratio = math.clamp(prog / target, 0, 1)
		card.progBarFill.Size = UDim2.fromScale(ratio, 1)

		-- Nagroda
		card.rewardLbl.Text = "Nagroda: " .. quest.reward.amount .. " ZŁ"

		-- Stan przycisku
		if questState.claimed[qid] then
			card.claimBtn.Text       = "ODEBRANO ✓"
			card.claimBtn.TextColor3 = C_GREEN
			card.claimBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
			card.claimStroke.Color   = C_GREEN
			card.progBarFill.BackgroundColor3 = C_GREEN
		elseif prog >= target then
			card.claimBtn.Text       = "ODBIERZ"
			card.claimBtn.TextColor3 = Color3.new(0, 0, 0)
			card.claimBtn.BackgroundColor3 = C_GREEN
			card.claimStroke.Color   = C_GREEN
			card.progBarFill.BackgroundColor3 = C_GREEN
		else
			card.claimBtn.Text       = "W TRAKCIE"
			card.claimBtn.TextColor3 = C_DIMTEXT
			card.claimBtn.BackgroundColor3 = C_BG
			card.claimStroke.Color   = C_BORDER
			card.progBarFill.BackgroundColor3 = C_BLUE
		end
	end
end

-- ── Refresh timer (Heartbeat throttle) ───────────────────────────────────

local refreshAccum = 0
RunService.Heartbeat:Connect(function(dt)
	refreshAccum += dt
	if refreshAccum < 1 then return end
	refreshAccum = 0
	-- Refresh countdown zawsze updateowany — panel siedzi w MenuController
	local left = (questState.refreshAt or 0) - os.time()
	refreshLbl.Text = formatTimeLeft(left)
end)

-- ── Toggle ───────────────────────────────────────────────────────────────

local POS_SHOW = UDim2.new(0.5, 0, 0.5,  0)
local POS_HIDE = UDim2.new(0.5, 0, 0.55, 0)
local TI_OPEN  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_CLOSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local questMoveLocked = false
local function setOpen(open: boolean)
	isOpen = open
	if open and not questMoveLocked then
		questMoveLocked = true
		if _G["__lockMovement"] then _G["__lockMovement"]() end
	elseif not open and questMoveLocked then
		questMoveLocked = false
		if _G["__unlockMovement"] then _G["__unlockMovement"]() end
	end
	if open then
		gui.Enabled              = true
		panel.Position           = POS_HIDE
		overlay.BackgroundTransparency = 1
		renderCards()
		renderGrandpa()
		local left = (questState.refreshAt or 0) - os.time()
		refreshLbl.Text = formatTimeLeft(left)
		TweenService:Create(panel,   TI_OPEN, { Position = POS_SHOW }):Play()
		TweenService:Create(overlay, TI_OPEN, { BackgroundTransparency = 0.30 }):Play()
	else
		TweenService:Create(panel, TI_CLOSE, { Position = POS_HIDE }):Play()
		local tw = TweenService:Create(overlay, TI_CLOSE, { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if not isOpen then gui.Enabled = false end
		end)
		tw:Play()
	end
end

closeBtn.MouseButton1Click:Connect(function() playSfx("Click"); setOpen(false) end)

-- Eksport toggle do HUD (przycisk QUESTY)
-- Eksport panelu dla MenuController — przeniesie go do zakładki 3 (QUESTY)
_G["__questsPanel"] = panel
_G["__questsReady"] = true

-- Toggle kieruje do MenuController na zakładkę 3 (QUESTY)
_G["__questToggle"] = function()
	if _G["__menuSetActiveTab"] then
		_G["__menuOpen"]()
		_G["__menuSetActiveTab"](3)
	else
		setOpen(not isOpen)  -- fallback
	end
end

UserInputService.InputBegan:Connect(function(input, proc)
	if proc then return end
	if input.KeyCode == Enum.KeyCode.Q then
		if _G["__questToggle"] then _G["__questToggle"]() end
	end
end)

-- ── Remote listeners ─────────────────────────────────────────────────────

-- Render zawsze (panel siedzi w MenuController, isOpen flag już nie używana)
QuestInit.OnClientEvent:Connect(function(snap)
	questState.activeIds = snap.activeIds or {}
	questState.progress  = snap.progress  or {}
	questState.claimed   = snap.claimed   or {}
	questState.refreshAt = snap.refreshAt or 0
	renderCards()
end)

QuestUpdate.OnClientEvent:Connect(function(payload)
	if payload.progress then
		for qid, val in pairs(payload.progress) do
			questState.progress[qid] = val
		end
		renderCards()
	end
end)

ClaimQuestResult.OnClientEvent:Connect(function(result)
	if result.success then
		questState.claimed[result.questId] = true
		renderCards()
	end
end)

GrandpaState.OnClientEvent:Connect(function(payload)
	if not payload then return end
	grandpaQuest.state    = payload.state    or grandpaQuest.state
	grandpaQuest.hasSyrup = payload.hasSyrup or false
	if payload.desc   then grandpaQuest.desc   = payload.desc end
	if payload.reward then grandpaQuest.reward = payload.reward end
	if grandpaCard.rewardLbl then
		grandpaCard.rewardLbl.Text = "Nagroda: " .. grandpaQuest.reward .. " ZŁ"
	end
	if grandpaCard.descLbl then
		grandpaCard.descLbl.Text = grandpaQuest.desc
	end
	renderGrandpa()
end)

-- ── Story quest render + listeners ────────────────────────────────────────
local function renderStory()
	if not storyQuest.active then
		relayoutSections(false, grandpaQuest.state == "active")
		return
	end
	storyCard.descLbl.Text     = storyQuest.desc
	storyCard.rewardLbl.Text   = string.format("+%d zł", storyQuest.reward or 0)
	local target = math.max(1, storyQuest.target or 1)
	storyCard.progBarFill.Size = UDim2.fromScale(math.clamp(storyQuest.progress / target, 0, 1), 1)
	storyCard.progLbl.Text     = string.format("%d / %d", storyQuest.progress, target)
	-- Przełączanie status/claim
	if storyQuest.readyToClaim then
		storyCard.statusLbl.Text             = "ODBIERZ"
		storyCard.statusLbl.BackgroundColor3 = C_GREEN
		storyCard.statusLbl.TextColor3       = Color3.new(0, 0, 0)
		storyCard.statusLbl.Active           = true
		storyCard.progBarFill.BackgroundColor3 = C_GREEN
	else
		storyCard.statusLbl.Text             = string.format("%d/%d", storyQuest.idx, storyQuest.total)
		storyCard.statusLbl.BackgroundColor3 = C_BG
		storyCard.statusLbl.TextColor3       = C_GOLD
		storyCard.statusLbl.Active           = false
		storyCard.progBarFill.BackgroundColor3 = C_GOLD
	end
	relayoutSections(true, grandpaQuest.state == "active")
end

local function applyStoryPayload(snap)
	if not snap then return end
	if snap.done then
		storyQuest.active = false
	else
		storyQuest.active       = true
		storyQuest.idx          = snap.idx or 1
		storyQuest.total        = snap.total or 1
		storyQuest.desc         = snap.desc or ""
		storyQuest.progress     = snap.progress or 0
		storyQuest.target       = snap.target or 1
		storyQuest.reward       = snap.reward or 0
		storyQuest.readyToClaim = snap.readyToClaim == true
	end
	renderStory()
end

StoryQuestInit.OnClientEvent:Connect(applyStoryPayload)
StoryQuestUpdate.OnClientEvent:Connect(applyStoryPayload)

-- Initial render — empty state przy starcie klienta, prawdziwe dane po QuestInit/StoryQuestInit
renderGrandpa()
renderStory()
renderCards()
