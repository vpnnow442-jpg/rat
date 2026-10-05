-- Client-side mirror of what the server told us. Read-only for gameplay;
-- the server is always the source of truth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local State = {}

State.phase = "Waiting"
State.endsAt = 0
State.round = 0
State.rounds = 0
State.final = false
State.level = ""
State.extra = {} :: { [string]: any }
State.runners = {} :: { number }
State.me = "idle" -- idle | running | done | dead
State.standings = {} :: { any }
State.speciesOf = {} :: { [number]: string }

local phaseChanged = Instance.new("BindableEvent")
State.phaseChanged = phaseChanged.Event

local meChanged = Instance.new("BindableEvent")
State.meChanged = meChanged.Event

local localId = Players.LocalPlayer.UserId

local function setMe(v: string)
	if State.me ~= v then
		State.me = v
		meChanged:Fire(v)
	end
end

function State.timeLeft(): number
	return math.max(0, State.endsAt - workspace:GetServerTimeNow())
end

function State.isRunner(userId: number): boolean
	return table.find(State.runners, userId) ~= nil
end

function State.init()
	Net.event("MatchState").OnClientEvent:Connect(function(s)
		State.phase = s.phase
		State.endsAt = s.endsAt
		State.round = s.round
		State.rounds = s.rounds
		State.final = s.final
		State.level = s.level
		State.extra = s.extra or {}
		State.runners = s.runners or {}

		if s.phase == "Countdown" or s.phase == "Run" then
			if State.isRunner(localId) and (s.phase == "Countdown" or State.me == "idle") then
				setMe("running")
			end
		else
			setMe("idle")
		end
		phaseChanged:Fire(s.phase)
	end)

	Net.event("Fail").OnClientEvent:Connect(function(userId)
		if userId == localId then
			setMe("dead")
		end
	end)
	Net.event("Finish").OnClientEvent:Connect(function(userId)
		if userId == localId then
			setMe("done")
		end
	end)
	Net.event("Scores").OnClientEvent:Connect(function(standings)
		State.standings = standings
		for _, row in standings do
			State.speciesOf[row.userId] = row.species
		end
	end)
end

return State
