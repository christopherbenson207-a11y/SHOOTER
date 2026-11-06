--!strict
-- MULTIPLAYER: the 1v1 duel (7 Nov 2026). The duel place's whole game is this mode; ServerScriptService.DuelServer runs
-- it and MatchHud / DuelClient show it. Every number for the match lives here.
--
-- The match: two players, first to RoundsToWin rounds. A round is one life each. The players spawn at opposite ends of
-- the yard (Map.Spawns A1-A3 and B1-B3), held still for Countdown seconds, then fight. The one left standing takes the
-- round. When the clock runs out the healthier player takes it; level health is a draw and nobody scores. Ends swap
-- every round so neither side keeps the better end. After the match both can REMATCH (both yes = start now) or go back
-- to the LOBBY; with nobody choosing, a new match starts when the window ends.
-- Shape from Rivals' duels (first to 5, quick rounds, rematch button); vault: Case Study - Rivals.

local Duel = {
	RoundsToWin = 5,
	RoundTime = 90, -- seconds of fighting per round
	Countdown = 3, -- frozen at the spawn, then GO
	FirstWait = 4, -- after both are in, before round 1's countdown
	RoundPause = 4, -- after a round is decided
	RematchWindow = 15, -- after the match: REMATCH / LOBBY
	LoneRespawn = 3, -- a player waiting alone who dies comes back after this
	Credit = 8, -- seconds a hit counts for the kill

	-- Leaving the play box (Map.Bounds.PlayBox): a warning, then this much a second.
	Bounds = { Grace = 3, Damage = 20 },

	-- Scrip at the end of a match (Profile.Earn), plus a bit per round won.
	Pay = { Win = 150, Loss = 50, PerRound = 15, Forfeit = 100 },

	-- Match points (the HUD's points; Progression's XP reads PointsEarned).
	Points = { Kill = 100, Headshot = 50, Round = 50, Match = 250 },

	-- One short line each, shown on the HUD's notice (one at a time).
	Lines = {
		Waiting = "WAITING FOR AN OPPONENT",
		Found = "OPPONENT FOUND",
		Go = "GO",
		RoundWon = "ROUND WON",
		RoundLost = "ROUND LOST",
		Draw = "DRAW",
		Won = "VICTORY",
		Lost = "DEFEAT",
		Left = "YOUR OPPONENT LEFT",
		OutOfBounds = "GET BACK IN THE YARD",
	},
}

-- Weapon rounds (owner, 5 Nov 2026: "keep the mode fresh"). Round 1 of a match is each player's own loadout, the
-- primary and secondary picked in the lobby (Kit.Resolve). From round 2 on, both players get the same kit, drawn at
-- random from Kits by Weight and never the kit of the round before. A kit with a weapon the place does not have
-- (not in GameConfig.Guns) is left out of the draw, so the melee kits join as soon as the place has them.
-- Name is the short word on the round notice ("ROUND 3 · SNIPERS"). No bandages in a duel: a round is one life.
Duel.Kits = {
	{ Name = "RIFLES", Items = { "AK", "Pistol" }, Weight = 2 },
	{ Name = "SHOTGUNS", Items = { "Shotgun", "Pistol" }, Weight = 2 },
	{ Name = "SNIPERS", Items = { "Sniper" }, Weight = 2 },
	{ Name = "PISTOLS", Items = { "Pistol" }, Weight = 1 },
	{ Name = "KNIVES", Items = { "Knife" }, Weight = 1 },
	{ Name = "AXES", Items = { "Axe" }, Weight = 1 },
}
Duel.OwnKitName = "YOUR LOADOUT"
Duel.Bandages = 0

export type Kit = { Name: string, Items: { string }, Weight: number }

-- A kit for the next round: weighted draw from the kits whose weapons all exist (has(name) says), never lastName.
-- Falls back to any usable kit when only the last one is usable; nil when none is.
function Duel.PickKit(has: (string) -> boolean, lastName: string?, rng: Random): Kit?
	local usable: { Kit } = {}
	local total = 0
	for _, kit in Duel.Kits do
		local ok = kit.Name ~= lastName
		for _, item in kit.Items do
			if not has(item) then
				ok = false
				break
			end
		end
		if ok then
			table.insert(usable, kit)
			total += kit.Weight
		end
	end
	if #usable == 0 then
		for _, kit in Duel.Kits do
			if kit.Name == lastName then
				return kit
			end
		end
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, kit in usable do
		roll -= kit.Weight
		if roll <= 0 then
			return kit
		end
	end
	return usable[#usable]
end

-- The two ends of the yard. Round 1 deals the first duelist end A; ends swap every round.
Duel.Ends = { "A", "B" }

function Duel.EndFor(slot: number, round: number): string
	local flip = (round % 2 == 0)
	if slot == 1 then
		return if flip then "B" else "A"
	end
	return if flip then "A" else "B"
end

-- Who takes a round that ran out of time: the healthier one, nil on a draw.
function Duel.TimeoutWinner(healthA: number, healthB: number): number?
	if math.abs(healthA - healthB) < 0.5 then
		return nil
	end
	return if healthA > healthB then 1 else 2
end

function Duel.MatchPay(won: boolean, rounds: number, forfeit: boolean?): number
	local P = Duel.Pay
	if forfeit then
		return P.Forfeit + rounds * P.PerRound
	end
	return (if won then P.Win else P.Loss) + rounds * P.PerRound
end

return Duel
