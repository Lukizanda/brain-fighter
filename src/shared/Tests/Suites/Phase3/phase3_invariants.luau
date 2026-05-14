local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "Phase 3 structural invariants — modules and remotes present",

	verify = function(_ctx)
		local failures: { string } = {}

		local shared = ReplicatedStorage.Shared

		local requiredModules = {
			"BlockSpawner",
			"BlockShoot",
			"BossAdapter",
			"LetterBlocks",
			"WordBuffer",
			"MindFullManager",
			"EnergyReservoirs",
		}
		for _, name in requiredModules do
			local mod = shared:FindFirstChild(name)
			if not mod then
				table.insert(failures, string.format("missing shared module: %s", name))
			end
		end

		local consumeBlock = shared:FindFirstChild("BlockShoot")
			and shared.BlockShoot:FindFirstChild("Remotes")
			and shared.BlockShoot.Remotes:FindFirstChild("ConsumeBlock")
		if not consumeBlock or not consumeBlock:IsA("RemoteEvent") then
			table.insert(failures, "BlockShoot.Remotes.ConsumeBlock RemoteEvent missing")
		end

		local letterBlockTemplate = shared:FindFirstChild("LetterBlocks")
			and shared.LetterBlocks:FindFirstChild("Template")
		if not letterBlockTemplate then
			table.insert(failures, "LetterBlocks.Template missing")
		end

		if #failures > 0 then
			return false, table.concat(failures, "; ")
		end
		return true, string.format("all %d modules + remotes present", #requiredModules)
	end,
}
