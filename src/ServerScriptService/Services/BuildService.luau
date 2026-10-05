-- The pick box and the build phase.
--
-- Pick: a crate opens with (players + 2) pieces. First click wins a piece;
-- whoever's too slow gets a leftover. Fighting over the good piece is the point.
-- Build: everyone places the piece they grabbed.
--
-- The client only *asks* to pick or place; every rule is re-checked here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)

local HazardService = require(script.Parent.HazardService)
local LevelService = require(script.Parent.LevelService)

local BoxEvent = Net.event("Box")
local PickEvent = Net.event("Pick")
local HandEvent = Net.event("Hand")
local PlaceEvent = Net.event("Place")
local PlaceResult = Net.event("PlaceResult")
local Explode = Net.event("Explode")
local Cursor = Net.unreliable("Cursor")

local BuildService = {}

type Slot = { id: string, takenBy: number }

local box = {} :: { Slot }
local pickers = {} :: { Player }
local picked = {} :: { [Player]: string }
local hands = {} :: { [Player]: { string } }
local placed = {} :: { [Player]: boolean }
local lastCursor = {} :: { [Player]: number }
local pickOpen = false
local buildOpen = false

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

-- Roll the box. Rules: about a third are route pieces so the level can always
-- grow a way through; at most one bomb, and never in round 1 (nothing to bomb).
local function roll(count: number, round: number): { string }
	local items = {}
	local function from(filter: (Objects.Def) -> boolean): string?
		local pool = {}
		for _, d in Objects.List do
			if filter(d) and (d.id ~= "bomb" or (round > 1 and not table.find(items, "bomb"))) then
				table.insert(pool, d)
			end
		end
		if #pool == 0 then
			return nil
		end
		return weightedPick(pool).id
	end
	local routes = math.max(1, math.ceil(count / 3))
	for _ = 1, routes do
		table.insert(items, from(function(d)
			return d.kind == "route"
		end) :: string)
	end
	while #items < count do
		-- avoid more than two of the same thing so the box feels varied
		local id = from(function(d)
			local n = 0
			for _, it in items do
				if it == d.id then
					n += 1
				end
			end
			return n < 2
		end)
		table.insert(items, id :: string)
	end
	for i = #items, 2, -1 do
		local j = math.random(1, i)
		items[i], items[j] = items[j], items[i]
	end
	return items
end

local function finite(n: any): boolean
	return typeof(n) == "number" and n == n and math.abs(n) < 1e4
end

local function sendBox()
	local payload = {}
	for i, s in box do
		payload[i] = { id = s.id, takenBy = s.takenBy }
	end
	local ids = {}
	for _, p in pickers do
		table.insert(ids, p.UserId)
	end
	BoxEvent:FireAllClients(payload, ids)
end

--------------------------------------------------------------------------
-- Pick
--------------------------------------------------------------------------

local function onPick(player: Player, slot: any)
	if not pickOpen or picked[player] or not table.find(pickers, player) then
		return
	end
	if typeof(slot) ~= "number" or slot ~= slot then
		return
	end
	local s = box[math.floor(slot)]
	if not s or s.takenBy ~= 0 then
		return -- someone beat you to it
	end
	s.takenBy = player.UserId
	picked[player] = s.id
	sendBox()
end

function BuildService.openPick(players: { Player }, round: number)
	table.clear(box)
	table.clear(picked)
	pickers = table.clone(players)
	for _, id in roll(#players + Config.Match.BoxExtra, round) do
		table.insert(box, { id = id, takenBy = 0 })
	end
	pickOpen = true
	sendBox()
end

function BuildService.everyonePicked(): boolean
	for _, p in pickers do
		if p.Parent and not picked[p] then
			return false
		end
	end
	return true
end

-- Too slow? You get whatever's left.
function BuildService.closePick()
	pickOpen = false
	for _, p in pickers do
		if p.Parent and not picked[p] then
			local free = {}
			for _, s in box do
				if s.takenBy == 0 then
					table.insert(free, s)
				end
			end
			local s = free[math.random(1, #free)]
			if s then
				s.takenBy = p.UserId
				picked[p] = s.id
			end
		end
	end
	sendBox()
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

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
	if not buildOpen or placed[player] then
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
		return reject("That piece isn't yours")
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
	if not buildOpen or placed[player] or not hands[player] then
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

function BuildService.openBuild(players: { Player })
	table.clear(hands)
	table.clear(placed)
	for _, p in players do
		local id = picked[p]
		if id and p.Parent then
			hands[p] = { id }
			HandEvent:FireClient(p, hands[p])
		else
			placed[p] = true -- nothing to place (joined mid-pick)
		end
	end
	buildOpen = true
end

function BuildService.closeBuild()
	buildOpen = false
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
	PickEvent.OnServerEvent:Connect(onPick)
	PlaceEvent.OnServerEvent:Connect(onPlace)
	Cursor.OnServerEvent:Connect(onCursor)
	Players.PlayerRemoving:Connect(function(p)
		hands[p] = nil
		placed[p] = nil
		picked[p] = nil
		lastCursor[p] = nil
	end)
end

return BuildService
