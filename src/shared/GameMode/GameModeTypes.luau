export type PlayerScore = {
	kills: number,
	deaths: number,
	assists: number,
}

export type GameState = {
	roundState: string,
	timeRemaining: number,
	scores: { [number]: PlayerScore }, -- keyed by Player.UserId
	winnerId: number?,
	winnerName: string?,
}

export type KillFeedEntry = {
	killerId: number,
	killerName: string,
	victimId: number,
	victimName: string,
	weaponName: string,
}

export type GameModeConfig = {
	name: string,
	scoreLimit: number,
	timeLimit: number,
	respawnTime: number,
	teamBased: boolean,
}

return nil
