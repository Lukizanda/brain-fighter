local function getRayDirections(origin: CFrame, numberOfRays: number, spreadAngle: number, seed: number): { Vector3 }
	-- Random seeds are ints. Since we'll generally be passing in a timestamp as the seed,
	-- we need to multiply it to make sure it isn't the same for an entire second.
	local random = Random.new(seed * 100_000)

	local rays = {}

	for _ = 1, numberOfRays do
		local roll = random:NextNumber() * math.pi * 2
		local pitch = random:NextNumber() * spreadAngle

		local rayCFrame = origin * CFrame.Angles(0, 0, roll) * CFrame.Angles(pitch, 0, 0)
		table.insert(rays, rayCFrame.LookVector)
	end

	return rays
end

return getRayDirections
