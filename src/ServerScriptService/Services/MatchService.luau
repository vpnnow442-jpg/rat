-- The whole match: pick a level, play N rounds (last one worth double), crown a winner.
-- ~75s per round x 8 rounds keeps a match around 10 minutes.

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

local RoundResults = Net.event("RoundResults")

local MatchService = {}

local function present(): { Player }
	return Players:GetPlayers()
end

local function playMatch(previousLevel: string?): string
	local layout = LevelService.pick(previousLevel)
	BuildService.clearObjects()
	LevelService.build(layout)
	ScoringService.reset()
	for _, p in present() do
		ScoringService.ensure(p)
		PlayerService.park(p)
	end
	ScoringService.broadcast()

	local ctx = RoundService.context
	ctx.level = layout.name
	ctx.round = 0
	ctx.final = false
	RoundService.setPhase("Intro", Config.Match.IntroTime)
	task.wait(Config.Match.IntroTime)

	for round = 1, Config.Match.Rounds do
		local players = present()
		if #players < Config.Match.MinPlayers then
			return layout.name
		end
		-- late joiners slot straight into the next round
		for _, p in players do
			ScoringService.ensure(p)
		end

		ctx.round = round
		ctx.final = round == Config.Match.Rounds
		RoundService.build(players)
		local info = RoundService.run(present())

		local mult = if ctx.final then Config.Match.FinalRoundMultiplier else 1
		local results = ScoringService.score(info, mult)
		RoundResults:FireAllClients(results)
		ScoringService.broadcast()
		RoundService.setPhase("Results", Config.Match.ResultsTime)
		task.wait(Config.Match.ResultsTime)
	end

	local standings = ScoringService.standings()
	local best = standings[1] and standings[1].total or 0
	local winners = {}
	for _, row in standings do
		if row.total == best and best > 0 then
			table.insert(winners, row)
			local p = Players:GetPlayerByUserId(row.userId)
			if p and p.Character then
				local spot = LevelService.flag + Vector3.new(-2 - #winners * 1.8, 2.3, 0)
				PlayerService.toStart(p, spot - Vector3.new(0, 2.3, 0), 1)
				p.Character:SetAttribute("VictoryAt", workspace:GetServerTimeNow())
			end
		end
	end
	RoundService.setPhase("Winner", Config.Match.WinnerTime, { winners = winners, standings = standings })
	task.wait(Config.Match.WinnerTime)
	return layout.name
end

function MatchService.start()
	task.spawn(function()
		local last: string? = nil
		while true do
			if #present() < Config.Match.MinPlayers then
				RoundService.setPhase("Waiting", 0)
				repeat
					task.wait(1)
				until #present() >= Config.Match.MinPlayers
			end
			task.wait(1.5)
			local ok, result = pcall(playMatch, last)
			if ok then
				last = result
			else
				warn("[Match] crashed, restarting:", result)
				task.wait(2)
			end
		end
	end)
end

return MatchService
