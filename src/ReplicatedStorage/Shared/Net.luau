--!strict
-- All remotes in one place. Server creates them, clients wait for them.
-- Rule: clients only ever *ask*. The server decides everything that matters.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RELIABLE = {
	"MatchState", -- S->C  phase, timers, round
	"Scores", -- S->C  totals
	"Hand", -- S->C  your cards for this build phase (nil closes)
	"Place", -- C->S  request to place a card
	"PlaceResult", -- S->C  ok / reason
	"Fail", -- S->C  someone got taken out
	"Finish", -- S->C  someone reached the flag
	"RoundResults", -- S->C  per-player breakdown
	"Explode", -- S->C  bomb went off (visual only)
	"Notify", -- S->C  small toast
}

local UNRELIABLE = {
	"Cursor", -- C->S->C  live ghost previews of other builders
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in RELIABLE do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in UNRELIABLE do
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

return Net
