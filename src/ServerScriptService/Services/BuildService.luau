-- Deals cards, validates placement requests, spawns objects.
-- The client only *asks* to place; every rule is re-checked here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)

local HazardService = require(script.Parent.HazardService)
local LevelService = require(script.Parent.LevelService)

local HandEvent = Net.event("Hand")
local PlaceEvent = Net.event("Place")
local PlaceResult = Net.event("PlaceResult")
local Explode = Net.event("Explode")
local Cursor = Net.unreliable("Cursor")

local BuildService = {}

local hands = {} :: { [Player]: { string } }
local placed = {} :: { [Player]: boolean }
local lastCursor = {} :: { [Player]: number }
local open = false

local function weightedPick(pool: { Objects.Def }): Objects.Def
	local total = 0
	for _, d in pool do
		total += d.weight
	end
	local r = math.random() * total
	for _, d in pool do
		r -= d.weight
		if r <= 0 then
			return d
		end
	end
	return pool[#pool]
end

-- Every hand has at least one route piece, so the level can always grow a way through.
local function deal(round: number): { string }
	local hand = {}
	local function pool(filter: (Objects.Def) -> boolean)
		local list = {}
		for _, d in Objects.List do
			if filter(d) and not table.find(hand, d.id) and (d.id ~= "bomb" or round > 1) then
				table.insert(list, d)
			end
		end
		return list
	end
	table.insert(hand, weightedPick(pool(function(d)
		return d.kind == "route"
	end)).id)
	while #hand < Config.Match.HandSize do
		table.insert(hand, weightedPick(pool(function()
			return true
		end)).id)
	end
	-- shuffle so the route card isn't always first
	for i = #hand, 2, -1 do
		local j = math.random(1, i)
		hand[i], hand[j] = hand[j], hand[i]
	end
	return hand
end

local function finite(n: any): boolean
	return typeof(n) == "number" and n == n and math.abs(n) < 1e4
end

local function bomb(pos: Vector3)
	local r = Config.Objects.BombRadius
	for _, model in LevelService.objectsFolder():GetChildren() do
		local def = Objects.ById[model:GetAttribute("Id") :: string]
		if not def then
			continue
		end
		local fp = Objects.footprint(def, model:GetAttribute("Rot") :: number)
		local mx, my = model:GetAttribute("X") :: number, model:GetAttribute("Y") :: number
		-- distance from blast centre to the object's footprint rectangle
		local dx = math.max(math.abs(pos.X - mx) - fp.X / 2, 0)
		local dy = math.max(math.abs(pos.Y - my) - fp.Y / 2, 0)
		if dx * dx + dy * dy <= r * r then
			model:Destroy()
		end
	end
	Explode:FireAllClients(pos)
end

function BuildService.spawn(owner: Player, def: Objects.Def, x: number, y: number, rot: number): Model
	local model = Objects.build(def.id)
	model:PivotTo(Objects.cframe(x, y, rot))
	model:SetAttribute("Owner", owner.UserId)
	model:SetAttribute("OwnerName", owner.DisplayName)
	model:SetAttribute("X", x)
	model:SetAttribute("Y", y)
	model:SetAttribute("Rot", rot)
	model:SetAttribute("PlacedAt", workspace:GetServerTimeNow())
	model.Parent = LevelService.objectsFolder()

	local belt = model:FindFirstChild("Belt") :: BasePart?
	if belt then
		belt.AssemblyLinearVelocity = belt.CFrame.RightVector * Config.Objects.ConveyorSpeed
	end
	HazardService.watch(model)
	return model
end

local function onPlace(player: Player, id: any, x: any, y: any, rot: any)
	local function reject(reason: string)
		PlaceResult:FireClient(player, false, reason)
	end
	if not open or placed[player] then
		return reject("Building is closed")
	end
	if typeof(id) ~= "string" or not finite(x) or not finite(y) or not finite(rot) then
		return reject("Bad request")
	end
	if rot % 90 ~= 0 then
		return reject("Bad rotation")
	end
	rot %= 360
	local hand = hands[player]
	local def = Objects.ById[id]
	if not hand or not def or not table.find(hand, id) then
		return reject("That card isn't yours")
	end

	local sx, sy = Objects.snap(def, x, y, rot)
	local ok, reason = Objects.check(def, sx, sy, rot)
	if not ok then
		return reject(reason or "Can't place there")
	end

	placed[player] = true
	hands[player] = nil
	if def.id == "bomb" then
		bomb(Vector3.new(sx, sy, 0))
	else
		BuildService.spawn(player, def, sx, sy, rot)
	end
	PlaceResult:FireClient(player, true)
	HandEvent:FireClient(player, nil)
	return
end

local function onCursor(player: Player, id: any, x: any, y: any, rot: any)
	if not open or placed[player] or not hands[player] then
		return
	end
	local now = os.clock()
	if now - (lastCursor[player] or 0) < 0.06 then
		return
	end
	lastCursor[player] = now
	if typeof(id) ~= "string" or not finite(x) or not finite(y) or not finite(rot) then
		return
	end
	if id ~= "" and not table.find(hands[player], id) then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Cursor:FireClient(other, player.UserId, id, x, y, rot)
		end
	end
end

function BuildService.open(players: { Player }, round: number)
	table.clear(hands)
	table.clear(placed)
	for _, p in players do
		hands[p] = deal(round)
		HandEvent:FireClient(p, hands[p])
	end
	open = true
end

function BuildService.close()
	open = false
	for p in hands do
		HandEvent:FireClient(p, nil)
	end
	table.clear(hands)
	for _, p in Players:GetPlayers() do
		Cursor:FireClient(p, 0, "", 0, 0, 0) -- userId 0 = clear all ghosts
	end
end

function BuildService.everyonePlaced(players: { Player }): boolean
	for _, p in players do
		if p.Parent and not placed[p] then
			return false
		end
	end
	return true
end

function BuildService.clearObjects()
	LevelService.objectsFolder():ClearAllChildren()
end

function BuildService.init()
	PlaceEvent.OnServerEvent:Connect(onPlace)
	Cursor.OnServerEvent:Connect(onCursor)
	Players.PlayerRemoving:Connect(function(p)
		hands[p] = nil
		placed[p] = nil
		lastCursor[p] = nil
	end)
end

return BuildService
