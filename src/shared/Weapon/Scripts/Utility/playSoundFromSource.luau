local function playSoundFromSource(playerTemplate: AudioPlayer, target: Instance)
	local audioPlayer = playerTemplate:Clone()
	audioPlayer.Parent = target

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = target
	wire.Parent = audioPlayer

	audioPlayer:Play()
	audioPlayer.Ended:Once(function()
		audioPlayer:Destroy()
	end)
end

return playSoundFromSource
