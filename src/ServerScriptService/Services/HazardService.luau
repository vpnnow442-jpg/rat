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
	end
end

local function pivotOf(model: Model): CFrame
	return Objects.cframe(model:GetAttribute("X") :: number, model:GetAttribute("Y") :: number, model:GetAttribute("Rot") :: number)
end

-- Called ~10x a second during a run. Lasers are checked by geometry instead
-- of Touched, because their on/off state comes from the clock.
function HazardService.tick(running: { Player })
	local now = workspace:GetServerTimeNow()
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
function HazardService.resetRound()
	table.clear(touchedOwn)
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
