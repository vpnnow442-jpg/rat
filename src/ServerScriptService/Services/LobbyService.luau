-- Menus, parties and who's actually playing.
--
-- Public server : you open the menu, press PLAY, and join the next round.
--                 Roblox's own server filling keeps public servers topped up.
-- Party server  : a private (reserved) server with a 5-letter room code.
--                 Friends join with the code or an in-game invite.
--                 The host presses START; after a match everyone returns
--                 to the party screen for a rematch.
--
-- Teleports and private servers only work in a PUBLISHED game.
-- In Studio these return a friendly error instead of failing silently.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlayerService = require(script.Parent.PlayerService)

local LobbyState = Net.event("LobbyState")
local LobbyFn = Net.func("Lobby")

local LobbyService = {}

LobbyService.mode = "public" -- "public" | "party"
LobbyService.code = nil :: string?
LobbyService.hostId = nil :: number?
LobbyService.inMatch = false

-- Set by MatchService so the lobby knows who is mid-race
LobbyService.isRacing = function(_player: Player): boolean
	return false
end

local queued = {} :: { [Player]: boolean }
local partyStarted = false
local joinOrder = {} :: { Player }
local lastAction = {} :: { [Player]: number }

local CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789" -- no 0/O, 1/I/L
local CODE_TTL = 6 * 60 * 60

local codes: MemoryStoreSortedMap? = nil
pcall(function()
	codes = MemoryStoreService:GetSortedMap("PartyCodes")
end)

local function isReservedServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

function LobbyService.participants(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if LobbyService.mode == "party" or queued[p] then
			table.insert(list, p)
		end
	end
	return list
end

function LobbyService.ready(): boolean
	if LobbyService.mode == "party" then
		return partyStarted and #Players:GetPlayers() >= 1
	end
	return #LobbyService.participants() >= Config.Match.MinPlayers
end

function LobbyService.broadcast()
	local members = {}
	for _, p in joinOrder do
		if p.Parent then
			table.insert(members, {
				userId = p.UserId,
				name = p.DisplayName,
				species = PlayerService.species[p],
				queued = queued[p] == true,
			})
		end
	end
	LobbyState:FireAllClients({
		mode = LobbyService.mode,
		code = LobbyService.code,
		hostId = LobbyService.hostId,
		inMatch = LobbyService.inMatch,
		members = members,
	})
end

function LobbyService.matchStarted()
	LobbyService.inMatch = true
	LobbyService.broadcast()
end

function LobbyService.matchEnded()
	LobbyService.inMatch = false
	if LobbyService.mode == "party" then
		partyStarted = false
	end
	LobbyService.broadcast()
end

--------------------------------------------------------------------------
-- Teleports
--------------------------------------------------------------------------

local function newCode(): string
	local chars = {}
	for i = 1, 5 do
		local n = math.random(1, #CODE_CHARS)
		chars[i] = CODE_CHARS:sub(n, n)
	end
	return table.concat(chars)
end

local function teleportTo(player: Player, access: string, code: string, host: number?)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = access
	options:SetTeleportData({ code = code, host = host })
	TeleportService:TeleportAsync(game.PlaceId, { player }, options)
end

local NOT_PUBLISHED = "Parties work once the game is published (not in Studio)."

local function createParty(player: Player)
	if RunService:IsStudio() or game.PlaceId == 0 or not codes then
		return { ok = false, err = NOT_PUBLISHED }
	end
	local ok, err = pcall(function()
		local store = codes :: MemoryStoreSortedMap
		local code = newCode()
		for _ = 1, 5 do
			if store:GetAsync(code) == nil then
				break
			end
			code = newCode()
		end
		local access = TeleportService:ReserveServer(game.PlaceId)
		store:SetAsync(code, access, CODE_TTL)
		teleportTo(player, access, code, player.UserId)
	end)
	if not ok then
		warn("[Lobby] create failed:", err)
		return { ok = false, err = "Couldn't create a party. Try again in a moment." }
	end
	return { ok = true }
end

local function joinParty(player: Player, code: any)
	if typeof(code) ~= "string" then
		return { ok = false, err = "Enter a 5-letter code" }
	end
	code = code:upper():gsub("[^%w]", "")
	if #code ~= 5 then
		return { ok = false, err = "Codes are 5 letters" }
	end
	if code == LobbyService.code then
		return { ok = false, err = "You're already in this party" }
	end
	if RunService:IsStudio() or game.PlaceId == 0 or not codes then
		return { ok = false, err = NOT_PUBLISHED }
	end
	local access: string? = nil
	local ok = pcall(function()
		access = (codes :: MemoryStoreSortedMap):GetAsync(code)
	end)
	if not ok then
		return { ok = false, err = "Couldn't look up that code. Try again." }
	end
	if not access then
		return { ok = false, err = "No party with that code" }
	end
	local tok, terr = pcall(teleportTo, player, access :: string, code, nil)
	if not tok then
		warn("[Lobby] join failed:", terr)
		return { ok = false, err = "Couldn't join. Try again." }
	end
	return { ok = true }
end

local function leaveParty(player: Player)
	if LobbyService.mode ~= "party" then
		return { ok = false, err = "You're not in a party" }
	end
	local ok = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	return if ok then { ok = true } else { ok = false, err = "Couldn't leave right now" }
end

--------------------------------------------------------------------------
-- Actions from the menu
--------------------------------------------------------------------------

local function onInvoke(player: Player, action: any, arg: any)
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.4 then
		return { ok = false, err = "Slow down" }
	end
	lastAction[player] = now

	if action == "play" then
		if LobbyService.mode ~= "public" then
			return { ok = false, err = "Waiting for the host to start" }
		end
		queued[player] = true
		LobbyService.broadcast()
		return { ok = true }
	elseif action == "menu" then
		if LobbyService.isRacing(player) then
			return { ok = false, err = "Finish the round first" }
		end
		queued[player] = nil
		LobbyService.broadcast()
		return { ok = true }
	elseif action == "create" then
		if LobbyService.mode == "party" then
			return { ok = false, err = "You're already in a party" }
		end
		return createParty(player)
	elseif action == "join" then
		return joinParty(player, arg)
	elseif action == "leave" then
		return leaveParty(player)
	elseif action == "start" then
		if LobbyService.mode ~= "party" or player.UserId ~= LobbyService.hostId then
			return { ok = false, err = "Only the host can start" }
		end
		if LobbyService.inMatch then
			return { ok = false, err = "A match is already running" }
		end
		partyStarted = true
		LobbyService.broadcast()
		return { ok = true }
	elseif action == "species" then
		if typeof(arg) ~= "string" or not Characters.ById[arg] then
			return { ok = false, err = "Unknown animal" }
		end
		if LobbyService.isRacing(player) then
			return { ok = false, err = "Change after this race" }
		end
		PlayerService.setSpecies(player, arg)
		LobbyService.broadcast()
		return { ok = true }
	end
	return { ok = false, err = "Unknown action" }
end

--------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	table.insert(joinOrder, player)
	local data = player:GetJoinData()
	local tp = data and data.TeleportData
	if LobbyService.mode == "party" then
		if typeof(tp) == "table" then
			if not LobbyService.code and typeof(tp.code) == "string" then
				LobbyService.code = tp.code
			end
			if tp.host == player.UserId then
				LobbyService.hostId = player.UserId
			end
		end
		if not LobbyService.hostId then
			LobbyService.hostId = player.UserId
		end
	else
		-- Accepted an in-game invite to a party? Its code rides along as launch data.
		local launch = data and data.LaunchData
		if typeof(launch) == "string" and #launch == 5 then
			task.delay(2, function()
				if player.Parent then
					joinParty(player, launch)
				end
			end)
		end
	end
	task.defer(LobbyService.broadcast)
end

local function onPlayerRemoving(player: Player)
	queued[player] = nil
	lastAction[player] = nil
	local i = table.find(joinOrder, player)
	if i then
		table.remove(joinOrder, i)
	end
	if player.UserId == LobbyService.hostId then
		-- hand the crown to whoever's been here longest
		local nextHost = joinOrder[1]
		LobbyService.hostId = nextHost and nextHost.UserId
	end
	LobbyService.broadcast()
end

function LobbyService.init()
	if isReservedServer() then
		LobbyService.mode = "party"
	end
	LobbyFn.OnServerInvoke = onInvoke
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return LobbyService
