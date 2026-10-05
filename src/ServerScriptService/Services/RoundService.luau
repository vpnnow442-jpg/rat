-- One round = build phase + run phase. Also owns the phase broadcast,
-- since every phase change goes through here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlayerService = require(script.Parent.PlayerService)
local LevelService = require(script.Parent.LevelService)
local BuildService = require(script.Parent.BuildService)
local HazardService = require(script.Parent.HazardService)
local ScoringService = require(script.Parent.ScoringService)

local MatchState = Net.event("MatchState")
local FailEvent = Net.event("Fail")
local FinishEvent = Net.event("Finish")

local RoundService = {}

RoundService.phase = "Waiting"
RoundService.context = { round = 0, rounds = Config.Match.Rounds, final = false, level = "" }

local status = {} :: { [Player]: string } -- running | done | dead
local runners = {} :: { Player }

function RoundService.setPhase(phase: string, duration: number, extra: { [string]: any }?)
	RoundService.phase = phase
	local ids = {}
	for _, p in runners do
		table.insert(ids, p.UserId)
	end
	MatchState:FireAllClients({
		phase = phase,
		endsAt = workspace:GetServerTimeNow() + duration,
		round = RoundService.context.round,
		rounds = RoundService.context.rounds,
		final = RoundService.context.final,
		level = RoundService.context.level,
		runners = ids,
		extra = extra or {},
	})
end

-- Late joiners get the current phase immediately instead of a blank screen
function RoundService.resend(player: Player)
	local ids = {}
	for _, p in runners do
		table.insert(ids, p.UserId)
	end
	MatchState:FireClient(player, {
		phase = RoundService.phase,
		endsAt = workspace:GetServerTimeNow(),
		round = RoundService.context.round,
		rounds = RoundService.context.rounds,
		final = RoundService.context.final,
		level = RoundService.context.level,
		runners = ids,
		extra = {},
	})
end

local function waitUntil(duration: number, done: () -> boolean)
	local elapsed = 0
	while elapsed < duration and not done() do
		elapsed += task.wait(0.1)
	end
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

function RoundService.build(players: { Player })
	table.clear(runners)
	for _, p in players do
		PlayerService.park(p)
	end
	BuildService.open(players, RoundService.context.round)
	RoundService.setPhase("Build", Config.Match.BuildTime)
	waitUntil(Config.Match.BuildTime, function()
		return BuildService.everyonePlaced(players)
	end)
	BuildService.close()
	task.wait(0.6) -- let the last "pop" land before the camera moves
end

--------------------------------------------------------------------------
-- Run
--------------------------------------------------------------------------

local runStarted = 0
local finishers = {} :: { ScoringService.Finish }
local kills = {} :: { [number]: number }

local function isRunning(player: Player): boolean
	return RoundService.phase == "Run" and status[player] == "running"
end

local function fail(player: Player, cause: string, killerId: number?)
	if not isRunning(player) then
		return
	end
	status[player] = "dead"
	if killerId and killerId ~= player.UserId then
		kills[killerId] = (kills[killerId] or 0) + 1
	end
	local char = player.Character
	if char then
		char:SetAttribute("FailAt", workspace:GetServerTimeNow())
	end
	FailEvent:FireAllClients(player.UserId, cause, killerId)
	task.delay(1.4, function()
		if status[player] == "dead" then
			PlayerService.park(player)
		end
	end)
end

local function finish(player: Player)
	if not isRunning(player) then
		return
	end
	local elapsed = os.clock() - runStarted
	if elapsed < Config.World.GoalMinTime then
		return -- nobody legit gets here this fast
	end
	status[player] = "done"
	table.insert(finishers, { player = player, timeLeft = Config.Match.RunTime - elapsed })
	local char = player.Character
	if char then
		char:SetAttribute("VictoryAt", workspace:GetServerTimeNow())
	end
	FinishEvent:FireAllClients(player.UserId, #finishers)
	task.delay(0.25, function()
		if status[player] == "done" then
			PlayerService.freeze(player)
		end
	end)
end

function RoundService.run(players: { Player }): ScoringService.RunInfo
	table.clear(status)
	table.clear(finishers)
	table.clear(kills)
	table.clear(runners)
	HazardService.resetRound()

	for i, p in players do
		if p.Parent then
			table.insert(runners, p)
			status[p] = "ready"
			PlayerService.toStart(p, LevelService.spawn, i)
		end
	end

	RoundService.setPhase("Countdown", Config.Match.CountdownTime)
	task.wait(Config.Match.CountdownTime)

	runStarted = os.clock()
	for _, p in runners do
		status[p] = "running"
	end
	RoundService.setPhase("Run", Config.Match.RunTime)
	for _, p in runners do
		PlayerService.release(p)
	end

	local goalConn: RBXScriptConnection? = nil
	if LevelService.goalZone then
		goalConn = LevelService.goalZone.Touched:Connect(function(hit)
			if hit.Name == "HumanoidRootPart" then
				local p = Players:GetPlayerFromCharacter(hit.Parent)
				if p then
					finish(p)
				end
			end
		end)
	end

	waitUntil(Config.Match.RunTime, function()
		-- cheap fall check at 10Hz instead of a Heartbeat loop
		for _, p in runners do
			if status[p] == "running" then
				local root = PlayerService.root(p)
				if not root or not p.Parent then
					status[p] = "dead"
				elseif root.Position.Y < Config.World.KillY then
					fail(p, "fall")
				end
			end
		end
		for _, p in runners do
			if status[p] == "running" then
				return false
			end
		end
		return true
	end)

	for _, p in runners do
		if status[p] == "running" then
			fail(p, "time")
		end
	end
	if goalConn then
		goalConn:Disconnect()
	end
	RoundService.phase = "RunOver"
	task.wait(1.5) -- let the last tumble finish on screen

	return {
		runners = table.clone(runners),
		finishers = table.clone(finishers),
		kills = table.clone(kills),
	}
end

function RoundService.init()
	HazardService.isRunning = isRunning
	HazardService.onDeadly = function(player, model)
		fail(player, model:GetAttribute("Id") :: string, model:GetAttribute("Owner") :: number)
	end
	Players.PlayerAdded:Connect(function(p)
		task.wait(1)
		RoundService.resend(p)
		ScoringService.broadcast()
	end)
end

return RoundService
