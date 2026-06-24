-- MusicController.client.luau
-- Muzyka w tle — 3 utwory grane w kolejce jeden po drugim, w pętli (po ostatnim wraca do pierwszego).
-- Osobny SoundGroup "MusicGroup" (niezależny od SFX). Per-klient.
local SoundService = game:GetService("SoundService")

local TRACKS = {
	"rbxassetid://71812363424859",
	"rbxassetid://106613607763613",
	"rbxassetid://83256010224011",
}

local MUSIC_VOLUME = 0.4

-- SoundGroup dla muzyki (osobny od SfxGroup)
local group = SoundService:FindFirstChild("MusicGroup")
if not group then
	group = Instance.new("SoundGroup")
	group.Name = "MusicGroup"
	group.Volume = 1
	group.Parent = SoundService
end

-- Jeden reużywalny Sound — zmieniamy SoundId i gramy następny po zakończeniu.
local sound = Instance.new("Sound")
sound.Name        = "BackgroundMusic"
sound.SoundGroup  = group
sound.Looped      = false
sound.Volume      = MUSIC_VOLUME
sound.Parent      = SoundService

local index = 0

local function playNext()
	index = (index % #TRACKS) + 1
	sound.SoundId = TRACKS[index]
	sound.TimePosition = 0
	sound:Play()
end

-- Po zakończeniu utworu — następny w kolejce (pętla).
sound.Ended:Connect(playNext)

-- Failsafe: jeśli utwór się nie załaduje (np. zły asset), przeskocz po chwili na następny,
-- żeby kolejka nie utknęła. Sprawdzamy czy faktycznie gra.
sound.Loaded:Connect(function()
	if not sound.IsPlaying then sound:Play() end
end)

task.spawn(function()
	while true do
		task.wait(5)
		-- jeśli nic nie gra i nie ładuje się — pchnij kolejkę dalej
		if not sound.IsPlaying and sound.TimeLength == 0 and sound.SoundId ~= "" then
			playNext()
		end
	end
end)

playNext()

print("[MusicController] gotowy — kolejka", #TRACKS, "utworów")
