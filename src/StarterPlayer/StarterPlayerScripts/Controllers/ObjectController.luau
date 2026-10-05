-- Brings placed objects to life on the client.
--
-- All motion (saws, fans, hammers, shuttles, cannonballs) is computed from the
-- shared server clock, so every player sees the same thing at the same time
-- without the server streaming positions. That's cheaper and smoother.
--
-- Effects that push *your* character (springs, fans, hammers, cannonballs)
-- are applied here too, because your client owns your physics and these
-- must feel instant. Deadly contact is still decided by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)
local Style = require(Shared.Style)

local Movement = require(script.Parent.MovementController)
local Camera = require(script.Parent.CameraController)
local Sound = require(script.Parent.SoundController)
local Fx = require(script.Parent.FxController)
local State = require(script.Parent.State)

local C = Config.Objects
local TAU = math.pi * 2

local ObjectController = {}

type Animated = { part: BasePart, rel: CFrame }
type Record = {
	model: Model,
	id: string,
	pivot: CFrame,
	placedAt: number,
	groups: { [string]: { Animated } },
	ready: boolean,
	-- per-type scratch
	padPush: number?,
	cooldown: number?,
	headPrevX: number?,
	maxDist: number?,
	consumed: { [number]: boolean }?,
	path: { Vector3 }?,
	pathLen: number?,
	pathAt: number?,
	used: boolean?,
	lastExt: number?,
	lastShot: number?,
	lastState: string?,
}

type Bird = { body: Part, left: Part, right: Part, speed: number, offset: number, y: number, z: number }
local birds = {} :: { Bird }
local flakes = {} :: { Part }
local levelConveyors = {} :: { BasePart }
local conveyorLevel: Instance? = nil

local records = {} :: { [Model]: Record }
local NONE = {} :: { Animated }
local balls = {} :: { BasePart }
local ballFolder: Folder

local function now(): number
	return workspace:GetServerTimeNow()
end

local function register(model: Model)
	local id = model:GetAttribute("Id") :: string?
	if not id or records[model] then
		return
	end
	-- Rebuild the exact placement frame from the server's attributes rather
	-- than trusting the replicated pivot.
	local x, y, r = model:GetAttribute("X"), model:GetAttribute("Y"), model:GetAttribute("Rot")
	local pivot = if typeof(x) == "number" and typeof(y) == "number" and typeof(r) == "number"
		then Objects.cframe(x, y, r)
		else model:GetPivot()
	local rec: Record = {
		model = model,
		id = id,
		pivot = pivot,
		placedAt = (model:GetAttribute("PlacedAt") :: number?) or now(),
		groups = {},
		ready = false,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("Group") :: string?
			if g then
				rec.groups[g] = rec.groups[g] or {}
				table.insert(rec.groups[g], { part = d, rel = pivot:ToObjectSpace(d.CFrame) })
			end
		end
	end
	records[model] = rec
	for _, a in rec.groups.bumper or NONE do
		a.part:SetAttribute("BaseSize", a.part.Size)
	end

	-- Placement pop: quick overshoot so it feels like the object "lands"
	Sound.playAt("place", model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") :: BasePart, 0.15)
	local scale = Instance.new("NumberValue")
	scale.Value = 0.5
	local conn = scale.Changed:Connect(function(v)
		if model.Parent then
			model:ScaleTo(math.max(v, 0.05))
		end
	end)
	local tween = TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
	tween.Completed:Once(function()
		conn:Disconnect()
		if model.Parent then
			model:ScaleTo(1)
		end
		rec.ready = true
		Fx.puff(pivot.Position - Vector3.new(0, 1, 0), 4, 1)
	end)
	tween:Play()
end

local function setGroup(rec: Record, name: string, offset: CFrame, velocity: Vector3?)
	local g = rec.groups[name]
	if not g then
		return
	end
	for _, a in g do
		a.part.CFrame = rec.pivot * offset * a.rel
		if velocity then
			a.part.AssemblyLinearVelocity = velocity
		end
	end
end

--------------------------------------------------------------------------
-- Cannonballs (deterministic from the clock, pooled parts)
--------------------------------------------------------------------------

local shotPools = {} :: { [string]: { BasePart } }
local shotCount = {} :: { [string]: number }

local function makeShot(id: string): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	if id == "darts" then
		p.Size = Vector3.new(1.6, 0.2, 0.2)
		p.Color = Style.Forest.WoodDark
		local tip = Instance.new("Part")
		tip.Size = Vector3.new(0.4, 0.4, 0.06)
		tip.Color = Style.UI.Bad
		tip.Anchored = true
		tip.CanCollide = false
		tip.CanQuery = false
		tip.CanTouch = false
		tip.Name = "Fletch"
		tip.Parent = p
	elseif id == "puck" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.5, 1.4, 1.4)
		p.Color = Style.Object.Rubber
	else
		p.Size = Vector3.new(1.6, 0.4, 0.1)
		p.Color = Style.UI.Paper
	end
	p.Parent = ballFolder
	return p
end

local function shot(id: string, pos: Vector3, dir: Vector3, spin: number)
	local n = (shotCount[id] or 0) + 1
	shotCount[id] = n
	local pool = shotPools[id] or {}
	shotPools[id] = pool
	local p = pool[n]
	if not p then
		p = makeShot(id)
		pool[n] = p
	end
	p.Transparency = 0
	local cf: CFrame
	if id == "puck" then
		cf = CFrame.new(pos) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(spin, 0, 0)
	else
		-- point along travel, in the camera's plane
		local angle = math.atan2(dir.Y, dir.X)
		cf = CFrame.new(pos) * CFrame.Angles(0, 0, angle)
	end
	p.CFrame = cf
	local fletch = p:FindFirstChild("Fletch") :: BasePart?
	if fletch then
		fletch.CFrame = cf * CFrame.new(-0.7, 0, 0) * CFrame.Angles(0, 0, math.rad(45))
	end
end

local function ball(i: number): BasePart
	local b = balls[i]
	if not b then
		b = Instance.new("Part")
		b.Shape = Enum.PartType.Ball
		b.Size = Vector3.new(1.4, 1.4, 1.4)
		b.Color = Style.Object.Rubber
		b.Material = Enum.Material.SmoothPlastic
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.Parent = ballFolder
		balls[i] = b
	end
	return b
end

local function cannonRange(rec: Record): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list = {}
	local level = workspace:FindFirstChild("Level")
	local objects = workspace:FindFirstChild("Objects")
	if level then
		table.insert(list, level)
	end
	if objects then
		table.insert(list, objects)
	end
	params.FilterDescendantsInstances = list
	local dir = rec.pivot.RightVector
	local origin = rec.pivot * Vector3.new(1.9, 0.3, 0)
	local best = 90
	-- ignore our own parts by stepping past them
	local hit = workspace:Raycast(origin + dir * 0.2, dir * best, params)
	while hit and hit.Instance:IsDescendantOf(rec.model) do
		origin = hit.Position + dir * 0.05
		hit = workspace:Raycast(origin, dir * best, params)
	end
	if hit and hit.Instance.CanCollide then
		return (hit.Position - (rec.pivot * Vector3.new(1.9, 0.3, 0))).Magnitude
	end
	return best
end

--------------------------------------------------------------------------
-- Per-frame
--------------------------------------------------------------------------

local function inBox(rel: Vector3, hx: number, hy: number): boolean
	return math.abs(rel.X) <= hx and math.abs(rel.Y) <= hy and math.abs(rel.Z) <= 4
end

local function visuals(dt: number)
	local t = now()
	local ballIndex = 0
	table.clear(shotCount)
	local root = Movement.root()
	local canAffect = Movement.enabled and root ~= nil and not (root :: BasePart).Anchored

	for model, rec in records do
		if not model.Parent then
			records[model] = nil
			continue
		end
		if not rec.ready then
			continue
		end
		local age = Objects.age(model, t)
		local id = rec.id

		if id == "saw" then
			setGroup(rec, "spin", CFrame.Angles(0, 0, -age * 7))
		elseif id == "fan" then
			setGroup(rec, "fan", CFrame.Angles(0, age * 16, 0))
			local g = rec.groups.wind
			if g then
				for i, a in g do
					local y = 1.5 + ((age * 14 + i * 5.1) % 14)
					a.part.CFrame = rec.pivot * CFrame.new(a.rel.Position.X, y, a.rel.Position.Z)
				end
			end
		elseif id == "hammer" then
			local angle = math.rad(65) * math.sin(age * TAU / 2.4)
			setGroup(rec, "arm", CFrame.Angles(0, 0, angle))
			if canAffect and root then
				local head: Animated? = nil
				for _, a in rec.groups.arm or NONE do
					if a.part.Name == "Head" then
						head = a
					end
				end
				if head then
					local hx = head.part.Position.X
					local vx = hx - (rec.headPrevX or hx)
					rec.headPrevX = hx
					local rel = head.part.CFrame:PointToObjectSpace(root.Position)
					if inBox(rel, 1.6 + 0.9, 1 + 1.2) and os.clock() > (rec.cooldown or 0) then
						rec.cooldown = os.clock() + 0.7
						local dir = if math.abs(vx) > 0.001 then math.sign(vx) else math.sign(root.Position.X - hx)
						Movement.launch(Vector3.new(dir * C.HammerKnock.X, C.HammerKnock.Y, 0), 0.4)
						Sound.play("bonk", 0.1)
						Fx.burst(root.Position, Style.UI.Paper, 8)
						Fx.streak(root.Position, Vector3.new(dir * C.HammerKnock.X, C.HammerKnock.Y, 0))
						Camera.shake(1.2)
					end
				end
			end
		elseif id == "cannon" then
			rec.maxDist = rec.maxDist or cannonRange(rec)
			rec.consumed = rec.consumed or {}
			local dir = rec.pivot.RightVector
			local muzzle = rec.pivot * Vector3.new(1.9, 0.3, 0)
			local life = (rec.maxDist :: number) / C.CannonSpeed
			local since = age - 1
			if since > 0 then
				local newest = math.floor(since / C.CannonInterval)
				local oldest = math.max(0, math.floor((since - life) / C.CannonInterval))
				for k = oldest, newest do
					local bAge = since - k * C.CannonInterval
					if bAge >= 0 and bAge <= life and not (rec.consumed :: any)[k] then
						if bAge < dt * 1.5 then
							Sound.playAt("cannon", rec.model.PrimaryPart or rec.model:FindFirstChildWhichIsA("BasePart") :: BasePart, 0.1)
						end
						ballIndex += 1
						local pos = muzzle + dir * (bAge * C.CannonSpeed)
						local b = ball(ballIndex)
						b.CFrame = CFrame.new(pos)
						b.Transparency = 0
						if canAffect and root and (root.Position - pos).Magnitude < 2.1 then
							(rec.consumed :: any)[k] = true
							local knock = dir * C.CannonKnock.X + Vector3.new(0, C.CannonKnock.Y, 0)
							Movement.launch(knock, 0.35)
							Sound.play("bonk", 0.1)
							Fx.burst(pos, Style.UI.Paper, 8)
							Camera.shake(1)
						end
					end
				end
			end
		elseif id == "laser" then
			local g = rec.groups.beam
			local beam = g and g[1]
			if beam then
				-- re-measure now and then; pieces can be bombed away mid-match
				if not rec.maxDist or (rec.cooldown or 0) < os.clock() then
					rec.maxDist = Objects.laserLength(model, rec.pivot)
					rec.cooldown = os.clock() + 0.5
				end
				local len = rec.maxDist :: number
				local state = Objects.laserState(age)
				if state == "on" and rec.lastState ~= "on" then
					Sound.playAt("laser", beam.part, 0.1)
				end
				rec.lastState = state
				local thick = if state == "on" then 0.4 else 0.1
				beam.part.Size = Vector3.new(len, thick, thick)
				beam.part.CFrame = rec.pivot * CFrame.new(1 + len / 2, 0, 0)
				if state == "on" then
					beam.part.Transparency = 0.05
				elseif state == "warn" then
					beam.part.Transparency = if math.floor(age * 16) % 2 == 0 then 0.4 else 0.85
				else
					beam.part.Transparency = 1
				end
			end
		elseif id == "trapdoor" then
			local open = Objects.trapdoorOpen(age)
			if open and not rec.used then
				rec.used = true
				Fx.puff(rec.pivot.Position - Vector3.new(0, 0.8, 0), 3, 0.7)
				Sound.playAt("door", model:FindFirstChildWhichIsA("BasePart") :: BasePart, 0.15)
			elseif not open then
				rec.used = false
			end
			-- doors swing down on their outer hinges
			local angle = if open then math.rad(85) else 0
			-- (negative Z rotation drops the left door's inner edge, positive drops the right's)
			setGroup(rec, "doorL", CFrame.new(-2.95, 0, 0) * CFrame.Angles(0, 0, -angle) * CFrame.new(2.95, 0, 0))
			setGroup(rec, "doorR", CFrame.new(2.95, 0, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(-2.95, 0, 0))
			for _, gname in { "doorL", "doorR" } do
				for _, a in rec.groups[gname] or NONE do
					if a.part:GetAttribute("Solid") then
						a.part.CanCollide = not open
					end
				end
			end
		elseif id == "bumper" then
			local push = rec.padPush or 0
			if push > 0 then
				rec.padPush = math.max(0, push - dt * 5)
				local s = 1 + 0.25 * math.sin(push * math.pi)
				for _, a in rec.groups.bumper or NONE do
					a.part.CFrame = rec.pivot * a.rel
					a.part.Size = (a.part:GetAttribute("BaseSize") :: Vector3? or a.part.Size) * s
				end
			end
		elseif id == "punch" then
			local ext = Objects.punchExtend(age)
			setGroup(rec, "glove", CFrame.new(ext * 3.6, 0, 0))
			local prev = rec.lastExt or 0
			rec.lastExt = ext
			if ext > 0.95 and prev < 0.95 then
				Sound.playAt("bonk", rec.model:FindFirstChildWhichIsA("BasePart") :: BasePart, 0.2)
			end
			if canAffect and root and ext > 0.3 and ext >= prev then
				for _, a in rec.groups.glove or NONE do
					if a.part.Name == "Glove" then
						local rel = a.part.CFrame:PointToObjectSpace(root.Position)
						if inBox(rel, 0.9 + 0.9, 0.9 + 1.2) and os.clock() > (rec.cooldown or 0) then
							rec.cooldown = os.clock() + 0.6
							local dir = rec.pivot.RightVector
							Movement.launch(dir * C.PunchKnock.X + Vector3.new(0, C.PunchKnock.Y, 0), 0.4)
							Sound.play("bonk", 0.1)
							Fx.burst(a.part.Position, Style.UI.Paper)
							Camera.shake(1.4)
						end
					end
				end
			end
		elseif Objects.Shooters[id] then
			if not rec.path or os.clock() - (rec.pathAt or 0) > 1 then
				rec.path = Objects.shotPath(id, model, rec.pivot)
				rec.pathLen = Objects.pathLength(rec.path :: { Vector3 })
				rec.pathAt = os.clock()
			end
			local path = rec.path :: { Vector3 }
			for _, s in Objects.activeShots(id, age, rec.pathLen :: number) do
				local pos, dir = Objects.shotPosition(id, path, rec.pivot, s.dist)
				shot(id, pos, dir, s.dist * 0.8)
				if s.k ~= rec.lastShot and s.dist < 4 then
					rec.lastShot = s.k
					local where = model:FindFirstChildWhichIsA("BasePart") :: BasePart
					Sound.playAt(if id == "darts" then "dart" elseif id == "puck" then "puckshot" else "planeshot", where, 0.15)
					Fx.puff(path[1], 2, 0.5)
				end
			end
		elseif id == "jetpack" then
			setGroup(rec, "float", CFrame.new(0, math.sin(age * 2.4) * 0.25, 0) * CFrame.Angles(0, math.sin(age * 1.3) * 0.4, 0))
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Group") == "float" then
					d.LocalTransparencyModifier = if rec.used then 0.7 else 0
				end
			end
		elseif id == "portal" then
			for _, gname in { "swirlA", "swirlB" } do
				local x = if gname == "swirlA" then 0 else Objects.PORTAL_SPAN
				for _, a in rec.groups[gname] or NONE do
					a.part.CFrame = rec.pivot * CFrame.new(x, 0, 0.04) * CFrame.Angles(0, 0, age * (if gname == "swirlA" then 5 else -5)) * CFrame.new(0.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
				end
			end
		elseif id == "coin" then
			local takenBy = model:GetAttribute("TakenBy") :: number?
			local anchor = rec.pivot
			if takenBy then
				-- carried: bob above the carrier's head so everyone can see who has it
				local carrier = Players:GetPlayerByUserId(takenBy)
				local head = carrier and carrier.Character and carrier.Character:FindFirstChild("Head") :: BasePart?
				if head then
					anchor = CFrame.new(head.Position + Vector3.new(0, 3, 0))
				end
				if not rec.used then
					rec.used = true
					Sound.play("points", 0.1)
					Fx.ring(rec.pivot.Position, Style.UI.Gold, 4)
				end
			elseif rec.used then
				rec.used = false
			end
			for _, a in rec.groups.coin or NONE do
				a.part.CFrame = anchor * CFrame.new(0, math.sin(age * 3) * 0.2, 0) * CFrame.Angles(0, age * 3, 0) * a.rel
			end
		elseif id == "spring" then
			local push = rec.padPush or 0
			if push > 0 then
				rec.padPush = math.max(0, push - dt * 4)
				setGroup(rec, "pad", CFrame.new(0, -0.35 * math.sin(push * math.pi), 0))
			end
		elseif id == "crumble" then
			local fallen = model:GetAttribute("Fallen")
			if fallen and not rec.used then
				rec.used = true -- just collapsed: crumbs
				Fx.burst(rec.pivot.Position, Style.Object.Crumble, 10)
				Sound.playAt("crumble", model:FindFirstChildWhichIsA("BasePart") :: BasePart, 0.2)
				Fx.puff(rec.pivot.Position, 4, 1)
			elseif not fallen then
				rec.used = false
			end
			local trig = model:GetAttribute("TriggeredAt") :: number?
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = if fallen then 1 else 0
				end
			end
			if trig and not fallen then
				local shake = CFrame.new((math.random() - 0.5) * 0.15, (math.random() - 0.5) * 0.1, 0)
				model:PivotTo(rec.pivot * shake)
			elseif model:GetPivot() ~= rec.pivot then
				model:PivotTo(rec.pivot)
			end
		end
	end

	for id, pool in shotPools do
		for i = (shotCount[id] or 0) + 1, #pool do
			pool[i].Transparency = 1
			local f = pool[i]:FindFirstChild("Fletch") :: BasePart?
			if f then
				f.CFrame = CFrame.new(0, -500, 0)
			end
			pool[i].CFrame = CFrame.new(0, -500, 0)
		end
	end

	for i = ballIndex + 1, #balls do
		balls[i].Transparency = 1
	end

	-- Ambient level life: flag sway, drifting clouds, the odd bird
	local level = workspace:FindFirstChild("Level")
	local snowing = level ~= nil and level:GetAttribute("World") == "Mountain"
	local cam = workspace.CurrentCamera.CFrame.Position
	for i, f in flakes do
		if snowing then
			local seed = i * 37.17
			local x = cam.X + ((seed * 7 + t * (1 + (i % 3))) % 140) - 70
			local y = cam.Y + 45 - ((seed * 3 + t * (4 + (i % 4))) % 90)
			local z = 3 + (i % 9) * 1.3
			f.CFrame = CFrame.new(x + math.sin(t + seed) * 1.5, y, z)
		elseif f.Position.Y > -400 then
			f.CFrame = CFrame.new(0, -500, 0)
		end
	end
	if level then
		local bmin = level:GetAttribute("BuildMin") :: Vector3?
		local bmax = level:GetAttribute("BuildMax") :: Vector3?
		if bmin and bmax then
			local span = bmax.X - bmin.X + 160
			for _, b in birds do
				local x = bmin.X - 80 + ((t * b.speed + b.offset) % (span * 2))
				local visible = x < bmax.X + 80 and level:GetAttribute("World") ~= "Factory" -- no birds indoors
				local pos = Vector3.new(x, b.y + math.sin(t * 0.8 + b.offset) * 2, b.z)
				local flap = math.sin(t * 9 + b.offset) * 0.6
				local cf = if visible then CFrame.new(pos) else CFrame.new(0, -500, 0)
				b.body.CFrame = cf
				-- a "V" silhouette that flaps in the plane the camera sees
				b.left.CFrame = cf * CFrame.Angles(0, 0, -(0.45 + flap)) * CFrame.new(-0.55, 0, 0)
				b.right.CFrame = cf * CFrame.Angles(0, 0, 0.45 + flap) * CFrame.new(0.55, 0, 0)
			end
		end
		local flag = level:FindFirstChild("Flag") :: BasePart?
		if flag then
			local base = flag:GetAttribute("Base") :: CFrame?
			if not base then
				flag:SetAttribute("Base", flag.CFrame)
				base = flag.CFrame
			end
			local pole = (base :: CFrame) * CFrame.new(-1.7, 0, 0)
			flag.CFrame = pole * CFrame.Angles(0, math.sin(t * 2.2) * 0.18, 0) * CFrame.new(1.7, 0, 0)
		end
		local decor = level:FindFirstChild("Decor")
		if decor then
			for _, m in decor:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("Group") == "gear" then
					local base = m:GetAttribute("Base") :: CFrame?
					if not base then
						m:SetAttribute("Base", m:GetPivot())
						base = m:GetPivot()
					end
					local spin = (m:GetAttribute("Spin") :: number?) or 0.3
					m:PivotTo((base :: CFrame) * CFrame.Angles(0, 0, t * spin))
				elseif m:IsA("Model") and m:GetAttribute("Group") == "cloud" then
					local base = m:GetAttribute("Base") :: CFrame?
					if not base then
						m:SetAttribute("Base", m:GetPivot())
						base = m:GetPivot()
					end
					local x = ((t * 1.2 + (base :: CFrame).X + 200) % 400) - 200
					m:PivotTo(CFrame.new(x, (base :: CFrame).Y, (base :: CFrame).Z))
				end
			end
		end
	end
end

-- Things that physically carry or push you: run before physics.
local function physicsStep(dt: number)
	local t = now()
	local level = workspace:FindFirstChild("Level")
	if level ~= conveyorLevel then
		conveyorLevel = level
		table.clear(levelConveyors)
		if level then
			for _, d in level:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Conveyor") then
					table.insert(levelConveyors, d)
				end
			end
		end
	end
	for _, belt in levelConveyors do
		belt.AssemblyLinearVelocity = Vector3.new(belt:GetAttribute("Conveyor") :: number, 0, 0)
	end
	local root = Movement.root()
	local canAffect = Movement.enabled and root ~= nil and not (root :: BasePart).Anchored
	local windX = 0

	for model, rec in records do
		if not model.Parent or not rec.ready then
			continue
		end
		local age = Objects.age(model, t)

		if rec.id == "mover" then
			local travel = 10
			local w = TAU / 4.5
			local offset = travel / 2 * math.sin(age * w)
			local speed = travel / 2 * w * math.cos(age * w)
			setGroup(rec, "mover", CFrame.new(offset, 0, 0), rec.pivot.RightVector * speed)
		elseif rec.id == "conveyor" then
			local belt = model:FindFirstChild("Belt") :: BasePart?
			if belt then
				belt.AssemblyLinearVelocity = rec.pivot.RightVector * C.ConveyorSpeed
			end
		end

		if not canAffect or not root then
			continue
		end
		local r = root :: BasePart

		if rec.id == "spring" then
			local rel = rec.pivot:PointToObjectSpace(r.Position)
			local up = rec.pivot.UpVector
			local v = r.AssemblyLinearVelocity
			if math.abs(rel.X) < 2.4 and rel.Y > 0.4 and rel.Y < 3.6 and v:Dot(up) <= 4 and os.clock() > (rec.cooldown or 0) then
				rec.cooldown = os.clock() + 0.3
				rec.padPush = 1
				if up.Y > 0.9 then
					Movement.launch(Vector3.new(v.X, C.SpringPower, 0), 0)
				else
					Movement.launch(up * C.SpringPower, 0.35)
				end
				Sound.play("spring", 0.1)
				Fx.ring(rec.pivot * Vector3.new(0, 0.8, 0), Style.Object.Spring, 5)
				Fx.puff(rec.pivot * Vector3.new(0, 0.8, 0), 3, 0.8)
			end
		elseif rec.id == "bumper" then
			local center = rec.pivot.Position
			local off = r.Position - center
			if off.Magnitude < 1.5 + 1.6 and os.clock() > (rec.cooldown or 0) then
				rec.cooldown = os.clock() + 0.35
				rec.padPush = 1
				local dir = if off.Magnitude > 0.01 then off.Unit else Vector3.yAxis
				local v = dir * C.BumperKnock + Vector3.new(0, 18, 0)
				Movement.launch(v, 0.3)
				Sound.play("bumper", 0.15)
				Fx.ring(center, Style.UI.Paper, 6)
				Camera.shake(0.6)
			end
		elseif rec.id == "jetpack" then
			if not rec.used and (r.Position - rec.pivot.Position).Magnitude < 2.6 then
				rec.used = true
				Movement.giveJetpack(C.JetpackTime)
				Sound.play("grab")
				Fx.ring(rec.pivot.Position, Style.UI.Cool, 4)
			end
		elseif rec.id == "portal" then
			if os.clock() > (rec.cooldown or 0) then
				local a = rec.pivot.Position
				local b = (rec.pivot * CFrame.new(Objects.PORTAL_SPAN, 0, 0)).Position
				local from: Vector3?, to: Vector3? = nil, nil
				if (r.Position - a).Magnitude < 1.8 then
					from, to = a, b
				elseif (r.Position - b).Magnitude < 1.8 then
					from, to = b, a
				end
				if from and to then
					rec.cooldown = os.clock() + 0.8
					Movement.teleport(to)
					Fx.ring(from, Style.UI.Cool, 5)
					Fx.ring(to, Style.UI.Accent, 5)
					Sound.play("whoosh")
					Sound.play("portal", 0.1)
				end
			end
		elseif rec.id == "fan" then
			local rel = rec.pivot:PointToObjectSpace(r.Position)
			if math.abs(rel.X) < 1.5 + 0.9 and rel.Y > 0 and rel.Y < 16.5 then
				local up = rec.pivot.UpVector
				-- falls off toward the end of the column so the edge is readable
				local strength = 1 - math.clamp((rel.Y - 10) / 6.5, 0, 1) * 0.6
				windX += up.X * 18 * strength
				if math.abs(up.Y) > 0.1 then
					local v = r.AssemblyLinearVelocity
					local target = C.FanMaxSpeed * up.Y * strength
					if (up.Y > 0 and v.Y < target) or (up.Y < 0 and v.Y > target) then
						local a = math.min(1, dt * 3)
						r.AssemblyLinearVelocity = Vector3.new(v.X, v.Y + (target - v.Y) * a, 0)
					end
				end
			end
		end
	end
	Movement.windX = windX
end

local function explode(pos: Vector3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Style.UI.Paper
	p.Size = Vector3.one
	p.CFrame = CFrame.new(pos)
	p.Parent = ballFolder
	local d = Config.Objects.BombRadius * 2
	local tween = TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(d, d, d),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		p:Destroy()
	end)
	tween:Play()
	Fx.ring(pos, Style.UI.Paper, d)
	Fx.puff(pos, 6, 2)
	Sound.play("poof", 0.1)
	Camera.shake(0.8)
end

function ObjectController.init()
	ballFolder = Instance.new("Folder")
	ballFolder.Name = "ClientFx"
	ballFolder.Parent = workspace

	local function bit(size: Vector3): Part
		local p = Instance.new("Part")
		p.Size = size
		p.Color = Style.UI.InkSoft
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = ballFolder
		return p
	end
	for _ = 1, 40 do
		local f = bit(Vector3.new(0.3, 0.3, 0.3))
		f.Shape = Enum.PartType.Ball
		f.Color = Style.UI.Paper
		f.Transparency = 0.15
		f.CFrame = CFrame.new(0, -500, 0)
		table.insert(flakes, f)
	end
	for i = 1, 3 do
		table.insert(birds, {
			body = bit(Vector3.new(0.35, 0.35, 0.35)),
			left = bit(Vector3.new(1.2, 0.14, 0.1)),
			right = bit(Vector3.new(1.2, 0.14, 0.1)),
			speed = 6 + i * 1.5,
			offset = i * 97,
			y = 44 + i * 6,
			z = -45 - i * 8,
		})
	end

	local function watch(folder: Instance)
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				task.spawn(register, m)
			end
		end
		folder.ChildAdded:Connect(function(m)
			if m:IsA("Model") then
				-- give replication a frame to deliver the parts
				task.wait()
				register(m)
			end
		end)
	end
	task.spawn(function()
		watch(workspace:WaitForChild("Objects"))
	end)

	-- every race starts fresh: jetpacks can be picked up again
	State.phaseChanged:Connect(function(phase)
		if phase == "Countdown" then
			for _, rec in records do
				if rec.id == "jetpack" then
					rec.used = false
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(visuals)
	RunService.PreSimulation:Connect(physicsStep)
	Net.event("Explode").OnClientEvent:Connect(explode)
end

return ObjectController
