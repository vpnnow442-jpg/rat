-- Small, short-lived effects. Pooled parts, one update loop, nothing glows.
--   puff     : dust when you jump or land hard
--   confetti : someone reached the flag
--   ring     : a flat ring that expands and fades (bumper hits, bomb poof)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Style = require(ReplicatedStorage.Shared.Style)

local Fx = {}

type Particle = {
	part: Part,
	vel: Vector3,
	gravity: number,
	life: number,
	age: number,
	spin: number,
	from: Vector3,
	to: Vector3,
	alpha: number,
}

local active = {} :: { Particle }
local pool = {} :: { Part }
local folder: Folder

local CONFETTI = { Style.UI.Accent, Style.UI.Gold, Style.UI.Good, Style.UI.Cool, Style.UI.Paper }
local FACE_CAMERA = CFrame.Angles(0, math.pi / 2, 0)

local function get(shape: Enum.PartType): Part
	local p = table.remove(pool) or Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = folder
	return p
end

local function spawn(p: Part, cf: CFrame, vel: Vector3, gravity: number, life: number, from: Vector3, to: Vector3, alpha: number, spin: number?)
	p.CFrame = cf
	p.Size = from
	p.Transparency = alpha
	table.insert(active, {
		part = p,
		vel = vel,
		gravity = gravity,
		life = life,
		age = 0,
		spin = spin or 0,
		from = from,
		to = to,
		alpha = alpha,
	})
end

function Fx.puff(pos: Vector3, count: number?, strength: number?)
	local s = strength or 1
	for i = 1, count or 3 do
		local p = get(Enum.PartType.Ball)
		p.Color = Style.UI.Paper
		local side = if i % 2 == 0 then 1 else -1
		local vel = Vector3.new(side * (2 + math.random() * 3) * s, (1 + math.random() * 2) * s, 0)
		spawn(p, CFrame.new(pos + Vector3.new(side * 0.4, 0.2, 0.6)), vel, 0, 0.35 + math.random() * 0.1, Vector3.one * 0.6, Vector3.one * (1.4 + math.random() * 0.6) * s, 0.25)
	end
end

function Fx.confetti(pos: Vector3)
	for i = 1, 18 do
		local p = get(Enum.PartType.Block)
		p.Color = CONFETTI[(i % #CONFETTI) + 1]
		local vel = Vector3.new((math.random() - 0.5) * 26, 20 + math.random() * 16, 0)
		local size = Vector3.new(0.35, 0.35, 0.08)
		local cf = CFrame.new(pos + Vector3.new(0, 1.5, 1)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		spawn(p, cf, vel, 60, 1.4 + math.random() * 0.5, size, size, 0, (math.random() - 0.5) * 16)
	end
end

function Fx.ring(pos: Vector3, color: Color3, size: number)
	local p = get(Enum.PartType.Cylinder)
	p.Color = color
	spawn(p, CFrame.new(pos + Vector3.new(0, 0, 1.2)) * FACE_CAMERA, Vector3.zero, 0, 0.3, Vector3.new(0.1, 1, 1), Vector3.new(0.1, size, size), 0.3)
end

local function step(dt: number)
	for i = #active, 1, -1 do
		local a = active[i]
		a.age += dt
		local t = a.age / a.life
		if t >= 1 then
			a.part.Parent = nil
			table.insert(pool, a.part)
			table.remove(active, i)
			continue
		end
		a.vel -= Vector3.new(0, a.gravity * dt, 0)
		local ease = 1 - (1 - t) * (1 - t)
		a.part.Size = a.from:Lerp(a.to, ease)
		a.part.CFrame = (a.part.CFrame + a.vel * dt) * CFrame.Angles(a.spin * dt, a.spin * dt * 0.7, 0)
		-- fade over the last 40% of life
		a.part.Transparency = a.alpha + (1 - a.alpha) * math.clamp((t - 0.6) / 0.4, 0, 1)
	end
end

function Fx.init()
	folder = Instance.new("Folder")
	folder.Name = "Fx"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(step)
end

return Fx
