-- Turns what happened in a run into points.
--
-- The rules, in one breath:
--   first to Config.Match.PointsToWin wins the match
--   finish 1st/2nd/3rd/4th+ -> 100/75/50/25
--   take someone out with your object -> +25 each (max 75 a round)
--   small bonuses: clutch finish, finishing via a route you built
--   BUT if everyone finishes, it was TOO EASY: nobody scores
--   and if nobody finishes, it was TOO HARD: trap points don't count
-- So the best level is one that's deadly but beatable. That's the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlayerService = require(script.Parent.PlayerService)
local HazardService = require(script.Parent.HazardService)

local ScoresEvent = Net.event("Scores")

local ScoringService = {}

ScoringService.totals = {} :: { [Player]: number }

export type Finish = { player: Player, timeLeft: number }
export type RunInfo = {
	runners: { Player },
	finishers: { Finish },
	kills: { [number]: number }, -- killer UserId -> opponents taken out
}

local ORDINAL = { "1st", "2nd", "3rd" }

local function ordinal(n: number): string
	return ORDINAL[n] or (tostring(n) .. "th")
end

function ScoringService.reset()
	table.clear(ScoringService.totals)
end

function ScoringService.ensure(player: Player)
	if ScoringService.totals[player] == nil then
		ScoringService.totals[player] = 0
	end
end

function ScoringService.standings()
	local list = {}
	for player, total in ScoringService.totals do
		if player.Parent then
			table.insert(list, {
				userId = player.UserId,
				name = player.DisplayName,
				species = PlayerService.species[player],
				total = total,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.total > b.total
	end)
	return list
end

function ScoringService.broadcast()
	ScoresEvent:FireAllClients(ScoringService.standings())
end

function ScoringService.score(info: RunInfo, multiplier: number)
	local S = Config.Scoring
	local n, f = #info.runners, #info.finishers
	local verdict: string? = nil
	if n >= 2 and f == n then
		verdict = "TOO_EASY"
	elseif f == 0 then
		verdict = "TOO_HARD"
	end

	local rows = {}
	for _, player in info.runners do
		if not player.Parent then
			continue
		end
		ScoringService.ensure(player)
		local items = {}
		local function add(cat: string, label: string, pts: number)
			table.insert(items, { cat = cat, label = label, points = pts * multiplier })
		end

		local place: number? = nil
		for i, fin in info.finishers do
			if fin.player == player then
				place = i
				if verdict == nil then
					add("finish", ordinal(i), S.Place[math.min(i, #S.Place)])
					if fin.timeLeft <= S.ClutchWindow then
						add("clutch", "Clutch", S.Clutch)
					end
					if HazardService.usedOwnRoute(player) then
						add("route", "Own route", S.OwnRoute)
					end
				end
			end
		end

		local kills = info.kills[player.UserId] or 0
		if kills > 0 and verdict == nil then
			add("trap", if kills == 1 then "Trap" else ("Trap x" .. kills), math.min(kills * S.Trap, S.TrapCap))
		end

		local gained = 0
		for _, it in items do
			gained += it.points
		end
		local before = ScoringService.totals[player]
		ScoringService.totals[player] += gained

		table.insert(rows, {
			before = before,
			userId = player.UserId,
			name = player.DisplayName,
			species = PlayerService.species[player],
			finished = place ~= nil,
			items = items,
			gained = gained,
			total = ScoringService.totals[player],
		})
	end

	-- Sorted by the match standing, so the chart reads like a race
	table.sort(rows, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.gained > b.gained
	end)

	return { verdict = verdict, multiplier = multiplier, rows = rows, target = Config.Match.PointsToWin }
end

return ScoringService
