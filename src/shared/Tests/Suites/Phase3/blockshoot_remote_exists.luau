local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "BlockShoot ConsumeBlock RemoteEvent exists at expected path",

	verify = function(_ctx)
		local blockShootFolder = ReplicatedStorage.Shared:FindFirstChild("BlockShoot")
		if not blockShootFolder then
			return false, "ReplicatedStorage.Shared.BlockShoot folder missing"
		end

		local remotes = blockShootFolder:FindFirstChild("Remotes")
		if not remotes then
			return false, "BlockShoot.Remotes folder missing"
		end

		local consumeBlock = remotes:FindFirstChild("ConsumeBlock")
		if not consumeBlock then
			return false, "ConsumeBlock RemoteEvent missing"
		end
		if not consumeBlock:IsA("RemoteEvent") then
			return false, string.format("ConsumeBlock is %s, expected RemoteEvent", consumeBlock.ClassName)
		end

		return true, "ConsumeBlock RemoteEvent present"
	end,
}
