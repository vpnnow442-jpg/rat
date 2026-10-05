-- Server-side object behaviour that has to be authoritative:
-- deadly contact, crumbling ledges, and "you used your own route" tracking.
-- Knockback/launch effects run on the client (it owns its character's physics),
-- because they must feel instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Objects = require(Shared.Objects)

local HazardService = {}

-- Set by RoundService
HazardService.isRunning = function(_player: Player): boolean
	return false
end
HazardService.onDeadly = function(_player: Player, _model: Model) end

local touchedOwn = {} :: { [Player]: boolean }
local crumbles = {} :: { Model }
local lasers = {} :: { Model }
local shooters = {} :: { Model }
local coins = {} :: { Model }
local paths = {} :: { [Model]: { path: { Vector3 }, len: number, at: number } }

local function playerFromHit(hit: BasePart): Player?
	if hit.Name ~= "HumanoidRootPart" then
		return nil
	end
	return Players:GetPlayerFromCharacter(hit.Parent)
end

local function crumble(model: Model)
	if model:GetAttribute("TriggeredAt") then
		return
	end
	model:SetAttribute("TriggeredAt", workspace:GetServerTimeNow())
	task.delay(Config.Objects.CrumbleDelay, function()
		if not model.Parent then
			return
		end
		model:SetAttribute("Fallen", true)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p:GetAttribute("Solid") then
				p.CanCollide = false
			end
		end
		task.delay(Config.Objects.CrumbleRespawn, function()
			HazardService.restore(model)
		end)
	end)
end

function HazardService.restore(model: Model)
	if not model.Parent then
		return
	end
	model:SetAttribute("TriggeredAt", nil)
	model:SetAttribute("Fallen", nil)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Solid") then
			p.CanCollide = true
		end
	end
end

function HazardService.watch(model: Model)
	local def = Objects.ById[model:GetAttribute("Id") :: string]
	local owner = model:GetAttribute("Owner") :: number
	local isRoute = def and def.kind == "route"

	for _, p in model:GetDescendants() do
		if not p:IsA("BasePart") then
			continue
		end
		if p:GetAttribute("Deadly") then
			p.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if player and HazardService.isRunning(player) then
					HazardService.onDeadly(player, model)
				end
			end)
		elseif p:GetAttribute("Solid") and (isRoute or p:GetAttribute("Crumble")) then
			p.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if not player or not HazardService.isRunning(player) then
					return
				end
				if p:GetAttribute("Crumble") then
					crumble(model)
				end
				if isRoute and player.UserId == owner then
					touchedOwn[player] = true
				end
			end)
		end
	end

	if model:FindFirstChild("Slab") and (model:FindFirstChild("Slab") :: BasePart):GetAttribute("Crumble") then
		table.insert(crumbles, model)
	end
	if def and def.id == "laser" then
		table.insert(lasers, model)
	elseif def and Objects.Shooters[def.id] then
		table.insert(shooters, model)
	elseif def and def.id == "coin" then
		table.insert(coins, model)
	end
end

local function pivotOf(model: Model): CFrame
	return Objects.cframe(model:GetAttribute("X") :: number, model:GetAttribute("Y") :: number, model:GetAttribute("Rot") :: number)
end

-- Called ~10x a second during a run. Lasers are checked by geometry instead
-- of Touched, because their on/off state comes from the clock.
local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- distance from point p to segment a-b
local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude
end

function HazardService.tick(running: { Player })
	local now = workspace:GetServerTimeNow()

	-- Projectiles: check the stretch each one covered since the last tick,
	-- so fast darts can't skip past someone between checks.
	for i = #shooters, 1, -1 do
		local m = shooters[i]
		if not m.Parent then
			table.remove(shooters, i)
			paths[m] = nil
			continue
		end
		local id = m:GetAttribute("Id") :: string
		local pivot = pivotOf(m)
		local cache = paths[m]
		if not cache or now - cache.at > 1 then
			local path = Objects.shotPath(id, m, pivot)
			cache = { path = path, len = Objects.pathLength(path), at = now }
			paths[m] = cache
		end
		local c = cache :: { path: { Vector3 }, len: number, at: number }
		local age = now - (m:GetAttribute("PlacedAt") :: number)
		local step = Objects.Shooters[id].speed * 0.12
		for _, shot in Objects.activeShots(id, age, c.len) do
			local a = Objects.shotPosition(id, c.path, pivot, math.max(shot.dist - step, 0))
			local b = Objects.shotPosition(id, c.path, pivot, shot.dist)
			for _, player in running do
				local root = rootOf(player)
				if root and segDist(root.Position, a, b) < 1.4 then
					HazardService.onDeadly(player, m)
				end
			end
		end
	end

	-- Coins: first runner to touch one carries it
	for i = #coins, 1, -1 do
		local m = coins[i]
		if not m.Parent then
			table.remove(coins, i)
			continue
		end
		if m:GetAttribute("TakenBy") then
			continue
		end
		local pos = pivotOf(m).Position
		for _, player in running do
			local root = rootOf(player)
			if root and (root.Position - pos).Magnitude < 2.4 then
				m:SetAttribute("TakenBy", player.UserId)
				break
			end
		end
	end

	for i = #lasers, 1, -1 do
		local m = lasers[i]
		if not m.Parent then
			table.remove(lasers, i)
			continue
		end
		local age = now - (m:GetAttribute("PlacedAt") :: number)
		if Objects.laserState(age) ~= "on" then
			continue
		end
		local pivot = pivotOf(m)
		local a = pivot * Vector3.new(1, 0, 0)
		local dir = pivot.RightVector
		local len = Objects.laserLength(m, pivot)
		for _, player in running do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local rel = root.Position - a
				local along = math.clamp(rel:Dot(dir), 0, len)
				if (rel - dir * along).Magnitude < 1.15 then
					HazardService.onDeadly(player, m)
				end
			end
		end
	end
end

-- Called at the start of each run so the level is identical for everyone
-- How many coins this player is carrying
function HazardService.coinsOf(player: Player): number
	local n = 0
	for _, m in coins do
		if m.Parent and m:GetAttribute("TakenBy") == player.UserId then
			n += 1
		end
	end
	return n
end

-- Taken out? Your coins drop back where they were.
function HazardService.dropCoins(player: Player)
	for _, m in coins do
		if m.Parent and m:GetAttribute("TakenBy") == player.UserId then
			m:SetAttribute("TakenBy", nil)
		end
	end
end

function HazardService.resetRound()
	table.clear(touchedOwn)
	for _, m in coins do
		if m.Parent then
			m:SetAttribute("TakenBy", nil)
		end
	end
	for i = #crumbles, 1, -1 do
		local m = crumbles[i]
		if m.Parent then
			HazardService.restore(m)
		else
			table.remove(crumbles, i)
		end
	end
end

function HazardService.usedOwnRoute(player: Player): boolean
	return touchedOwn[player] == true
end

return HazardService
