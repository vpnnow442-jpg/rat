-- The whole match: pick a level, play rounds until someone crosses
-- PointsToWin (or MaxRounds runs out, last round double), crown a winner.
-- With bigger maps a round is ~1.5-2 minutes, so a match lands around 10-15.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlayerService = require(script.Parent.PlayerService)
local LevelService = require(script.Parent.LevelService)
local BuildService = require(script.Parent.BuildService)
local RoundService = require(script.Parent.RoundService)
local ScoringService = require(script.Parent.ScoringService)
local LobbyService = require(script.Parent.LobbyService)

local RoundResults = Net.event("RoundResults")

local MatchService = {}

local function leaders(): { any }
	local standings = ScoringService.standings()
	local best = standings[1] and standings[1].total or 0
	local list = {}
	for _, row in standings do
		if row.total == best and best > 0 then
			table.insert(list, row)
		end
	end
	return list
end

local function playMatch()
	local M = Config.Match
	BuildService.clearObjects()
	ScoringService.reset()
	for _, p in LobbyService.participants() do
		ScoringService.ensure(p)
		PlayerService.park(p)
	end
	ScoringService.broadcast()
	LobbyService.matchStarted()

	local ctx = RoundService.context
	ctx.level = LevelService.layout and LevelService.layout.name or ""
	ctx.round = 0
	ctx.final = false
	RoundService.setPhase("Intro", M.IntroTime, { target = M.PointsToWin })
	task.wait(M.IntroTime)

	for round = 1, M.MaxRounds do
		local players = LobbyService.participants()
		if #players == 0 then
			break
		end
		for _, p in players do
			ScoringService.ensure(p) -- late joiners slot straight in
		end

		ctx.round = round
		ctx.final = round == M.MaxRounds
		RoundService.build(players)
		local info = RoundService.run(LobbyService.participants())

		local mult = if ctx.final then M.LastRoundMultiplier else 1
		local results = ScoringService.score(info, mult)
		RoundResults:FireAllClients(results)
		ScoringService.broadcast()
		RoundService.setPhase("Results", M.ResultsTime)
		task.wait(M.ResultsTime)

		local top = ScoringService.standings()[1]
		if top and top.total >= M.PointsToWin then
			break
		end
	end

	local winners = leaders()
	for i, row in winners do
		local p = Players:GetPlayerByUserId(row.userId)
		if p and p.Character then
			local spot = LevelService.flag + Vector3.new(-2 - i * 1.8, 0, 0)
			PlayerService.toStart(p, spot, 1)
			p.Character:SetAttribute("VictoryAt", workspace:GetServerTimeNow())
		end
	end
	RoundService.setPhase("Winner", M.WinnerTime, {
		winners = winners,
		standings = ScoringService.standings(),
		target = M.PointsToWin,
	})
	task.wait(M.WinnerTime)
	for _, p in Players:GetPlayers() do
		PlayerService.park(p)
	end
	LobbyService.matchEnded()
end

function MatchService.start()
	LobbyService.isRacing = RoundService.isRacing
	task.spawn(function()
		local last: string? = nil
		while true do
			-- Fresh level between matches so the menu has something to look at
			local layout = LevelService.pick(last)
			last = layout.name
			BuildService.clearObjects()
			LevelService.build(layout)
			RoundService.context.level = layout.name
			RoundService.context.round = 0
			RoundService.setPhase("Waiting", 0)

			repeat
				task.wait(0.5)
			until LobbyService.ready()
			task.wait(1)

			local ok, err = pcall(playMatch)
			if not ok then
				warn("[Match] crashed, restarting:", err)
				LobbyService.matchEnded()
				task.wait(2)
			end
		end
	end)
end

return MatchService
