-- The non-Forest worlds: their playable pieces, backgrounds and lighting.
-- Forest lives in LevelService itself; every world shares the same rules:
-- details only behind the lane or under the walking surface.
--
-- MOUNTAIN : snow, cliffs, natural ice (keeps your momentum), pines, peaks
-- FACTORY  : steel floors, girders, pipes, conveyor belts, toxic goo below

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Levels = require(Shared.Levels)
local Style = require(Shared.Style)

local Mo = Style.Mountain
local Fa = Style.Factory

export type Ctx = {
	part: (Instance, string, Vector3, CFrame, Color3, Enum.PartType?) -> Part,
	solid: (Part) -> Part,
	blob: (Instance, string, Vector3, CFrame, Color3) -> Part,
	level: Folder,
	BOTTOM: number,
	UPRIGHT: CFrame,
}

export type World = {
	builders: { [string]: (Ctx, Levels.Piece, Random) -> () },
	background: (Ctx, Folder, Levels.Layout, Random) -> (),
	lighting: () -> (),
}

local Worlds = {} :: { [string]: World }

local function resetLighting()
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
end

local function atmosphere(density: number, haze: number, color: Color3, decay: Color3)
	local a = Instance.new("Atmosphere")
	a.Density = density
	a.Offset = 0.1
	a.Haze = haze
	a.Glare = 0
	a.Color = color
	a.Decay = decay
	a.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.05
	cc.Contrast = 0.04
	cc.Parent = Lighting
end

-- A triangle silhouette: a block turned 45 degrees, half sunk below `baseY`
local function peak(c: Ctx, parent: Instance, x: number, baseY: number, z: number, size: number, depth: number, color: Color3): Part
	local p = c.part(parent, "Peak", Vector3.new(size, size, depth), CFrame.new(x, baseY, z) * CFrame.Angles(0, 0, math.rad(45)), color)
	p.CastShadow = false
	return p
end

--------------------------------------------------------------------------
-- MOUNTAIN
--------------------------------------------------------------------------

local mountain: World = {
	builders = {},
	background = function() end,
	lighting = function() end,
}

local function snowLumps(c: Ctx, p: Levels.Piece, rng: Random)
	local w = p.x1 - p.x0
	for _ = 1, math.max(1, math.floor(w / 7)) do
		local x = rng:NextNumber(p.x0 + 1, p.x1 - 1)
		c.blob(c.level, "Drift", Vector3.new(rng:NextNumber(1.6, 3), 0.9, 1.4), CFrame.new(x, p.top + 0.15, -3.2), Mo.SnowShade)
	end
	for _ = 1, math.max(2, math.floor(w / 4)) do
		local x = rng:NextNumber(p.x0 + 0.5, p.x1 - 0.5)
		c.blob(c.level, "SnowLip", Vector3.new(rng:NextNumber(0.8, 1.6), 0.6, 0.5), CFrame.new(x, p.top - 1.1, 4.15), Mo.Snow)
	end
end

mountain.builders.ground = function(c, p, rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	c.solid(c.part(c.level, "Snow", Vector3.new(w + 0.6, 1.2, 8.4), CFrame.new(cx, p.top - 0.6, 0), Mo.Snow))
	local h = p.top - 1.2 - c.BOTTOM
	c.solid(c.part(c.level, "Rock", Vector3.new(w, h, 8), CFrame.new(cx, c.BOTTOM + h / 2, 0), Mo.Rock))
	c.part(c.level, "Strata", Vector3.new(w + 0.02, 1, 8.02), CFrame.new(cx, p.top - 4, 0), Mo.RockDark)
	snowLumps(c, p, rng)
end

mountain.builders.ice = function(c, p, rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local slab = c.solid(c.part(c.level, "Ice", Vector3.new(w + 0.4, 1.2, 8.2), CFrame.new(cx, p.top - 0.6, 0), Mo.Ice))
	slab:SetAttribute("Surface", "ice")
	local h = p.top - 1.2 - c.BOTTOM
	c.solid(c.part(c.level, "Rock", Vector3.new(w, h, 8), CFrame.new(cx, c.BOTTOM + h / 2, 0), Mo.Rock))
	for _ = 1, math.max(2, math.floor(w / 5)) do
		local x = rng:NextNumber(p.x0 + 1, p.x1 - 1)
		c.part(c.level, "Shine", Vector3.new(0.14, 0.8, 0.05), CFrame.new(x, p.top - 0.6, 4.13) * CFrame.Angles(0, 0, math.rad(-30)), Color3.new(1, 1, 1))
	end
end

mountain.builders.ledge = function(c, p, rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	c.solid(c.part(c.level, "Snow", Vector3.new(w + 0.6, 1.2, 7.4), CFrame.new(cx, p.top - 0.6, 0), Mo.Snow))
	c.solid(c.part(c.level, "Rock", Vector3.new(w, 2.6, 7), CFrame.new(cx, p.top - 2.5, 0), Mo.Rock))
	c.blob(c.level, "Underside", Vector3.new(w * 0.8, 3.4, 6), CFrame.new(cx, p.top - 3.6, 0), Mo.RockDark)
	-- icicles hang behind the lane, never in front of a runner
	for _ = 1, math.max(2, math.floor(w / 3)) do
		local x = rng:NextNumber(p.x0 + 0.8, p.x1 - 0.8)
		local len = rng:NextNumber(0.8, 1.8)
		c.part(c.level, "Icicle", Vector3.new(0.35, len, 0.35), CFrame.new(x, p.top - 3.8 - len / 2, -2) * CFrame.Angles(0, math.rad(45), 0), Mo.Ice)
	end
end

mountain.builders.cliff = function(c, p, rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local h = p.top - c.BOTTOM
	c.solid(c.part(c.level, "Cliff", Vector3.new(w, h, 7), CFrame.new(cx, c.BOTTOM + h / 2, 0), Mo.Rock))
	c.blob(c.level, "SnowCap", Vector3.new(w + 1, 1.6, 7.4), CFrame.new(cx, p.top - 0.4, 0), Mo.Snow)
	for i = 1, 2 do
		local y = p.top - 5 - i * rng:NextNumber(4, 6)
		c.part(c.level, "Notch", Vector3.new(w * 0.6, 0.6, 0.3), CFrame.new(cx + rng:NextNumber(-0.5, 0.5), y, 3.6), Mo.RockDark)
	end
end

mountain.background = function(c, decor, layout, rng)
	local midX = (layout.buildMin.X + layout.buildMax.X) / 2
	local mist = c.part(decor, "Mist", Vector3.new(460, 1, 160), CFrame.new(midX, -16, -40), Mo.Mist)
	mist.Transparency = 0.3
	mist.CastShadow = false

	for i = 1, 7 do
		local s = rng:NextNumber(90, 140)
		local x = midX - 260 + i * 75 + rng:NextNumber(-20, 20)
		peak(c, decor, x, -20, -175, s, 20, Mo.PeakFar)
		peak(c, decor, x, -20 + s * 0.707 - s * 0.18 * 0.707 * 2, -174, s * 0.36, 20.5, Mo.Snow)
	end
	for i = 1, 5 do
		local s = rng:NextNumber(70, 105)
		local x = midX - 200 + i * 80 + rng:NextNumber(-15, 15)
		peak(c, decor, x, -24, -115, s, 16, Mo.Peak)
		peak(c, decor, x, -24 + s * 0.707 - s * 0.2 * 0.707 * 2, -114, s * 0.4, 16.5, Mo.Snow)
	end

	-- pines: trunk + three stacked triangles
	for _ = 1, 18 do
		local x = rng:NextNumber(layout.buildMin.X - 40, layout.buildMax.X + 40)
		local z = rng:NextNumber(-60, -18)
		local h = rng:NextNumber(14, 26)
		local base = -14
		c.part(decor, "Trunk", Vector3.new(h * 0.3, 1.2, 1.2), CFrame.new(x, base + h * 0.15, z) * c.UPRIGHT, Style.Forest.Bark, Enum.PartType.Cylinder)
		for k = 0, 2 do
			local size = h * (0.5 - k * 0.12)
			peak(c, decor, x, base + h * 0.3 + k * h * 0.22, z, size, 3, if k % 2 == 0 then Mo.Pine else Mo.PineDark)
		end
	end

	for i = 1, 5 do
		local cloud = Instance.new("Model")
		cloud.Name = "Cloud"
		local x = midX - 150 + i * 65 + rng:NextNumber(-15, 15)
		local y = rng:NextNumber(62, 88)
		local s = rng:NextNumber(0.8, 1.3)
		c.blob(cloud, "Puff", Vector3.new(16, 6, 6) * s, CFrame.new(x, y, -110), Mo.Snow)
		c.blob(cloud, "Puff", Vector3.new(9, 6, 5) * s, CFrame.new(x - 4 * s, y + 2.2 * s, -110), Mo.Snow)
		for _, p in cloud:GetChildren() do
			(p :: BasePart).CastShadow = false
		end
		cloud.WorldPivot = CFrame.new(x, y, -110)
		cloud:SetAttribute("Group", "cloud")
		cloud.Parent = decor
	end
end

mountain.lighting = function()
	resetLighting()
	Lighting.ClockTime = 12.8
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(118, 126, 146)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 178, 198)
	atmosphere(0.3, 1.7, Color3.fromRGB(226, 234, 244), Color3.fromRGB(168, 186, 212))
end

Worlds.Mountain = mountain

--------------------------------------------------------------------------
-- FACTORY
--------------------------------------------------------------------------

local factory: World = {
	builders = {},
	background = function() end,
	lighting = function() end,
}

local function hazardStripe(c: Ctx, x0: number, x1: number, y: number, front: number)
	local w = x1 - x0
	c.part(c.level, "Stripe", Vector3.new(w, 0.45, 0.05), CFrame.new((x0 + x1) / 2, y, front), Fa.Hazard)
	local n = math.floor(w / 1.4)
	for i = 0, n - 1 do
		local p = c.part(c.level, "Chevron", Vector3.new(0.35, 0.6, 0.06), CFrame.new(x0 + 0.7 + i * 1.4, y, front + 0.01) * CFrame.Angles(0, 0, math.rad(40)), Style.UI.Ink)
		p.CastShadow = false
	end
end

factory.builders.ground = function(c, p, _rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	c.solid(c.part(c.level, "Floor", Vector3.new(w + 0.4, 1, 8.2), CFrame.new(cx, p.top - 0.5, 0), Fa.Floor))
	local h = p.top - 1 - c.BOTTOM
	c.solid(c.part(c.level, "Concrete", Vector3.new(w, h, 8), CFrame.new(cx, c.BOTTOM + h / 2, 0), Fa.Concrete))
	hazardStripe(c, p.x0, p.x1, p.top - 1.4, 4.03)
end

factory.builders.girder = function(c, p, _rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	c.solid(c.part(c.level, "Flange", Vector3.new(w, 0.6, 4), CFrame.new(cx, p.top - 0.3, 0), Fa.Girder))
	c.part(c.level, "Web", Vector3.new(w, 1.4, 1), CFrame.new(cx, p.top - 1.3, 0), Fa.GirderDark)
	c.part(c.level, "Flange", Vector3.new(w, 0.5, 3.4), CFrame.new(cx, p.top - 2.2, 0), Fa.Girder)
	for x = p.x0 + 1, p.x1 - 1, 2 do
		c.part(c.level, "Rivet", Vector3.new(0.25, 0.25, 0.06), CFrame.new(x, p.top - 1.3, 0.53), Fa.SteelDark)
	end
	-- hung on chains from the ceiling (behind the lane)
	for _, x in { p.x0 + 1.5, p.x1 - 1.5 } do
		local len = 80 - p.top
		c.part(c.level, "Chain", Vector3.new(0.2, len, 0.2), CFrame.new(x, p.top + len / 2, -1.5), Fa.SteelDark)
	end
end

factory.builders.pipe = function(c, p, _rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local h = p.top - c.BOTTOM
	c.solid(c.part(c.level, "Pipe", Vector3.new(h, w, w), CFrame.new(cx, c.BOTTOM + h / 2, 0) * c.UPRIGHT, Fa.Pipe, Enum.PartType.Cylinder))
	c.part(c.level, "Cap", Vector3.new(0.6, w + 0.6, w + 0.6), CFrame.new(cx, p.top - 0.3, 0) * c.UPRIGHT, Fa.SteelDark, Enum.PartType.Cylinder)
	for y = p.top - 6, c.BOTTOM + 4, -6 do
		c.part(c.level, "Flange", Vector3.new(0.4, w + 0.4, w + 0.4), CFrame.new(cx, y, 0) * c.UPRIGHT, Fa.SteelDark, Enum.PartType.Cylinder)
	end
end

factory.builders.conveyor = function(c, p, _rng)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local speed = p.speed or 10
	local belt = c.solid(c.part(c.level, "Belt", Vector3.new(w, 1, 4.4), CFrame.new(cx, p.top - 0.5, 0), Fa.Belt))
	belt:SetAttribute("Conveyor", speed)
	belt.AssemblyLinearVelocity = Vector3.new(speed, 0, 0)
	for _, x in { p.x0, p.x1 } do
		c.part(c.level, "Roller", Vector3.new(4.5, 1.1, 1.1), CFrame.new(x, p.top - 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0), Fa.Steel, Enum.PartType.Cylinder)
		local h = p.top - 1 - c.BOTTOM
		c.part(c.level, "Leg", Vector3.new(1, h, 1), CFrame.new(x + (if x == p.x0 then 1.5 else -1.5), c.BOTTOM + h / 2, -1.2), Fa.SteelDark)
	end
	-- arrows on the belt face show which way it runs
	local dir = if speed >= 0 then 1 else -1
	for x = p.x0 + 2, p.x1 - 2, 3 do
		c.part(c.level, "Arrow", Vector3.new(0.7, 0.14, 0.05), CFrame.new(x, p.top - 0.35, 2.23) * CFrame.Angles(0, 0, math.rad(-38 * dir)), Fa.Hazard)
		c.part(c.level, "Arrow", Vector3.new(0.7, 0.14, 0.05), CFrame.new(x, p.top - 0.65, 2.23) * CFrame.Angles(0, 0, math.rad(38 * dir)), Fa.Hazard)
	end
end

factory.background = function(c, decor, layout, rng)
	local midX = (layout.buildMin.X + layout.buildMax.X) / 2
	local goo = c.part(decor, "Goo", Vector3.new(460, 1, 120), CFrame.new(midX, -14, -20), Fa.Goo)
	goo.Transparency = 0.08
	goo.CastShadow = false

	-- the back wall: brick with mortar lines and a row of warm windows
	local wall = c.part(decor, "Wall", Vector3.new(520, 140, 2), CFrame.new(midX, 50, -40), Fa.Brick)
	wall.CastShadow = false
	for y = -10, 110, 7 do
		c.part(decor, "Mortar", Vector3.new(520, 0.4, 0.1), CFrame.new(midX, y, -38.95), Fa.BrickDark).CastShadow = false
	end
	for i = 0, 12 do
		local x = midX - 240 + i * 40
		local win = c.part(decor, "Window", Vector3.new(16, 14, 0.2), CFrame.new(x, 58, -38.9), Fa.Window)
		win.CastShadow = false
		c.part(decor, "Mullion", Vector3.new(0.5, 14, 0.25), CFrame.new(x, 58, -38.85), Fa.SteelDark).CastShadow = false
		c.part(decor, "Transom", Vector3.new(16, 0.5, 0.25), CFrame.new(x, 58, -38.85), Fa.SteelDark).CastShadow = false
	end
	-- pipes running along the wall
	for _, y in { 28, 34 } do
		c.part(decor, "WallPipe", Vector3.new(520, 1.6, 1.6), CFrame.new(midX, y, -37.5), Fa.Pipe, Enum.PartType.Cylinder).CastShadow = false
	end
	-- big slow gears (the client turns them)
	for i = 1, 4 do
		local gear = Instance.new("Model")
		gear.Name = "Gear"
		local x = midX - 150 + i * 70 + rng:NextNumber(-10, 10)
		local y = rng:NextNumber(4, 20)
		local r = rng:NextNumber(7, 11)
		local center = CFrame.new(x, y, -34)
		c.part(gear, "Disc", Vector3.new(1, r * 2, r * 2), center * CFrame.Angles(0, math.pi / 2, 0), Fa.SteelDark, Enum.PartType.Cylinder)
		c.part(gear, "Hub", Vector3.new(1.2, r * 0.6, r * 0.6), center * CFrame.Angles(0, math.pi / 2, 0), Fa.Steel, Enum.PartType.Cylinder)
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			c.part(gear, "Tooth", Vector3.new(r * 0.28, r * 0.28, 0.9), center * CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0), Fa.SteelDark)
		end
		for _, p in gear:GetChildren() do
			(p :: BasePart).CastShadow = false
		end
		gear.WorldPivot = center
		gear:SetAttribute("Group", "gear")
		gear:SetAttribute("Spin", if i % 2 == 0 then 0.3 else -0.3)
		gear.Parent = decor
	end
end

factory.lighting = function()
	resetLighting()
	Lighting.ClockTime = 17.4
	Lighting.Brightness = 1.7
	Lighting.Ambient = Color3.fromRGB(122, 106, 98)
	Lighting.OutdoorAmbient = Color3.fromRGB(152, 134, 124)
	atmosphere(0.34, 1, Color3.fromRGB(232, 204, 176), Color3.fromRGB(122, 102, 92))
end

Worlds.Factory = factory

return Worlds
