-- Server entry point. Services are plain modules; order matters only here.

local Services = script.Parent.Services

local PlayerService = require(Services.PlayerService)
local LevelService = require(Services.LevelService)
local BuildService = require(Services.BuildService)
local RoundService = require(Services.RoundService)
local LobbyService = require(Services.LobbyService)
local MatchService = require(Services.MatchService)

PlayerService.init()
LevelService.init()
BuildService.init()
RoundService.init()
LobbyService.init()
MatchService.start()
