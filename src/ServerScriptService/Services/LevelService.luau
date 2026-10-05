-- Builds a layout into the world: playable pieces, start, flag, safe zones,
-- and a background with just enough life in it (trees, hills, a river, clouds).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Levels = require(Shared.Levels)
local Style = require(Shared.Style)

local F = Style.Forest
local LevelService = {}

LevelService.layout = nil :: Levels.Layout?
LevelService.goalZone = nil :: BasePart?
LevelService.spawn = Vector3.zero
LevelService.flag = Vector3.zero

local level: Folder

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function solid(p: Part): Part
	p.CanCollide = true
	p.CanQuery = true
	p:SetAttribute("Solid", true)
	return p
end

local function blob(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = part(parent, name, size, cf, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
local BOTTOM = -26

--------------------------------------------------------------------------
-- Playable pieces
--------------------------------------------------------------------------

local builders = {}

builders.ground = function(p: Levels.Piece, rng: Random)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	solid(part(level, "Grass", Vector3.new(w + 0.6, 1.2, 8.4), CFrame.new(cx, p.top - 0.6, 0), F.Grass))
	local h = p.top - 1.2 - BOTTOM
	solid(part(level, "Dirt", Vector3.new(w, h, 8), CFrame.new(cx, BOTTOM + h / 2, 0), F.Dirt))
	part(level, "DirtBand", Vector3.new(w + 0.02, 1.4, 8.02), CFrame.new(cx, p.top - 3.2, 0), F.DirtDark)
	-- a couple of grass tufts at the back edge, never in the play lane
	for _ = 1, math.max(1, math.floor(w / 8)) do
		local x = rng:NextNumber(p.x0 + 1, p.x1 - 1)
		blob(level, "Tuft", Vector3.new(1.4, 1, 1), CFrame.new(x, p.top + 0.2, -3.4), F.GrassDark)
	end
end

-- A floating grassy chunk: the "high route" piece
builders.ledge = function(p: Levels.Piece, rng: Random)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	solid(part(level, "Grass", Vector3.new(w + 0.6, 1.2, 7.4), CFrame.new(cx, p.top - 0.6, 0), F.Grass))
	solid(part(level, "Dirt", Vector3.new(w, 2.6, 7), CFrame.new(cx, p.top - 2.5, 0), F.Dirt))
	blob(level, "Underside", Vector3.new(w * 0.8, 3.4, 6), CFrame.new(cx, p.top - 3.6, 0), F.DirtDark)
	blob(level, "Root", Vector3.new(0.6, 2.4, 0.6), CFrame.new(cx + rng:NextNumber(-w / 3, w / 3), p.top - 5, 1.6), F.Bark)
	blob(level, "Tuft", Vector3.new(1.4, 1, 1), CFrame.new(cx + rng:NextNumber(-w / 3, w / 3), p.top + 0.2, -3), F.GrassDark)
end

builders.stump = function(p: Levels.Piece)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local h = p.top - BOTTOM
	solid(part(level, "Stump", Vector3.new(h, w, w), CFrame.new(cx, BOTTOM + h / 2, 0) * UPRIGHT, F.Bark, Enum.PartType.Cylinder))
	part(level, "Rings", Vector3.new(0.12, w - 0.8, w - 0.8), CFrame.new(cx, p.top + 0.02, 0) * UPRIGHT, F.Wood, Enum.PartType.Cylinder)
	blob(level, "Moss", Vector3.new(w * 0.7, 0.8, w * 0.6), CFrame.new(cx - w * 0.15, p.top - 0.1, -w * 0.25), F.GrassDark)
end

builders.rock = function(p: Levels.Piece)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local h = p.top - BOTTOM
	solid(part(level, "Rock", Vector3.new(w, h, 6), CFrame.new(cx, BOTTOM + h / 2, 0), F.Stone))
	blob(level, "RockCap", Vector3.new(w + 0.6, 2.2, 6.4), CFrame.new(cx, p.top - 0.9, 0), F.Stone)
end

builders.log = function(p: Levels.Piece)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	solid(part(level, "Log", Vector3.new(w, 4, 4), CFrame.new(cx, p.top - 2, 0), F.Bark, Enum.PartType.Cylinder))
	for _, x in { p.x0, p.x1 } do
		part(level, "LogEnd", Vector3.new(0.3, 3.4, 3.4), CFrame.new(x, p.top - 2, 0), F.Wood, Enum.PartType.Cylinder)
		local sx = x + (x == p.x0 and 3 or -3)
		local h = p.top - 4 - BOTTOM
		part(level, "Support", Vector3.new(3, h, 3), CFrame.new(sx, BOTTOM + h / 2, 0), F.Stone)
	end
	-- a little branch stub for character
	part(level, "Branch", Vector3.new(2.6, 0.7, 0.7), CFrame.new(cx + w * 0.2, p.top - 0.4, -1.6) * CFrame.Angles(0, 0, math.rad(35)), F.Bark)
end

builders.tree = function(p: Levels.Piece, rng: Random)
	local w = p.x1 - p.x0
	local cx = (p.x0 + p.x1) / 2
	local h = p.top - 1 - BOTTOM
	part(level, "Trunk", Vector3.new(h, 2.4, 2.4), CFrame.new(cx, BOTTOM + h / 2, -0.5) * UPRIGHT, F.Bark, Enum.PartType.Cylinder)
	solid(part(level, "Deck", Vector3.new(w, 1, 6), CFrame.new(cx, p.top - 0.5, 0), F.Wood))
	part(level, "DeckTrim", Vector3.new(w + 0.02, 0.24, 6.02), CFrame.new(cx, p.top - 0.9, 0), F.WoodDark)
	-- canopy sits behind the lane so it frames the platform without hiding anyone
	local leaf = F.Leaf[rng:NextInteger(1, #F.Leaf)]
	blob(level, "Canopy", Vector3.new(w + 7, 7, 5), CFrame.new(cx, p.top + 5, -5), leaf)
	blob(level, "Canopy", Vector3.new(w + 2, 5, 4), CFrame.new(cx + 2, p.top + 9, -6), F.Leaf[1])
end

--------------------------------------------------------------------------
-- Start, flag, background
--------------------------------------------------------------------------

local function buildStart(spawn: Vector3)
	part(level, "SignPost", Vector3.new(0.4, 3.2, 0.4), CFrame.new(spawn.X - 4, spawn.Y + 1.6, -2.6), F.WoodDark)
	local board = part(level, "Sign", Vector3.new(2.8, 1.2, 0.3), CFrame.new(spawn.X - 4, spawn.Y + 3, -2.6), F.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(140, 60)
	gui.LightInfluence = 1
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Style.Font.Title
	label.TextScaled = true
	label.TextColor3 = F.WoodDark
	label.Text = "GO  >"
	label.Parent = gui
	-- SurfaceGui Front faces -Z; turn the board around so the camera reads it
	board.CFrame *= CFrame.Angles(0, math.pi, 0)
end

local function buildFlag(flag: Vector3)
	part(level, "FlagBase", Vector3.new(1.6, 0.6, 1.6), CFrame.new(flag.X, flag.Y + 0.3, -1), F.Stone)
	part(level, "Pole", Vector3.new(0.35, 9, 0.35), CFrame.new(flag.X, flag.Y + 4.5, -1), Style.UI.Paper)
	part(level, "PoleTop", Vector3.new(0.7, 0.7, 0.7), CFrame.new(flag.X, flag.Y + 9.1, -1), Style.UI.Gold, Enum.PartType.Ball)
	local cloth = part(level, "Flag", Vector3.new(3.4, 2.2, 0.12), CFrame.new(flag.X + 1.85, flag.Y + 7.7, -1), Style.UI.Accent)
	cloth:SetAttribute("Group", "flag")

	local zone = part(level, "GoalZone", Vector3.new(5, 8, 6), CFrame.new(flag.X, flag.Y + 4, 0), Style.UI.Gold)
	zone.Transparency = 1
	zone.CanTouch = true
	LevelService.goalZone = zone
end

local function safeZone(center: Vector3)
	local z = part(level, "SafeZone", Vector3.new(10, 8, 6), CFrame.new(center.X, center.Y + 4, 0), Style.UI.Good)
	z.Transparency = 1
	z.CanQuery = true
end

local function buildBackground(layout: Levels.Layout, rng: Random)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = level

	local midX = (layout.buildMin.X + layout.buildMax.X) / 2

	local water = part(decor, "River", Vector3.new(420, 1, 150), CFrame.new(midX, -14, -40), F.Water)
	water.Transparency = 0.1
	water.CastShadow = false

	for i = 1, 5 do
		local w = rng:NextNumber(90, 150)
		blob(decor, "Hill", Vector3.new(w, w * 0.5, 30), CFrame.new(midX - 200 + i * 75 + rng:NextNumber(-20, 20), -12, -150), F.HillFar)
	end
	for i = 1, 4 do
		local w = rng:NextNumber(60, 100)
		blob(decor, "Hill", Vector3.new(w, w * 0.45, 24), CFrame.new(midX - 160 + i * 70 + rng:NextNumber(-15, 15), -14, -95), F.Hill)
	end

	-- Background trees: varied but restrained (one silhouette, three greens)
	for _ = 1, 16 do
		local x = rng:NextNumber(layout.buildMin.X - 40, layout.buildMax.X + 40)
		local z = rng:NextNumber(-60, -16)
		local h = rng:NextNumber(18, 34)
		part(decor, "Trunk", Vector3.new(h, 1.6, 1.6), CFrame.new(x, -14 + h / 2, z) * UPRIGHT, F.Bark, Enum.PartType.Cylinder)
		local leaf = F.Leaf[rng:NextInteger(1, #F.Leaf)]
		local r = rng:NextNumber(7, 11)
		blob(decor, "Leaves", Vector3.new(r, r * 1.1, r), CFrame.new(x, -14 + h + r * 0.2, z), leaf)
		blob(decor, "Leaves", Vector3.new(r * 0.7, r * 0.75, r * 0.7), CFrame.new(x + r * 0.35, -14 + h + r * 0.65, z + 1), leaf)
	end

	for i = 1, 6 do
		local cloud = Instance.new("Model")
		cloud.Name = "Cloud"
		local x = midX - 150 + i * 55 + rng:NextNumber(-15, 15)
		local y = rng:NextNumber(58, 85)
		local s = rng:NextNumber(0.8, 1.4)
		blob(cloud, "Puff", Vector3.new(16, 6, 6) * s, CFrame.new(x, y, -110), F.Cloud)
		blob(cloud, "Puff", Vector3.new(9, 6, 5) * s, CFrame.new(x - 4 * s, y + 2.2 * s, -110), F.Cloud)
		blob(cloud, "Puff", Vector3.new(8, 5, 5) * s, CFrame.new(x + 4 * s, y + 1.6 * s, -110), F.Cloud)
		for _, p in cloud:GetChildren() do
			(p :: BasePart).CastShadow = false
		end
		cloud.WorldPivot = CFrame.new(x, y, -110)
		cloud:SetAttribute("Group", "cloud")
		cloud.Parent = decor
	end
end

local function setupLighting()
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(96, 92, 104)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 146, 156)
	Lighting.ShadowSoftness = 0.35
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.05
	Lighting.GlobalShadows = true

	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") then
			c:Destroy()
		end
	end
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.26
	atmo.Offset = 0.1
	atmo.Haze = 1.2
	atmo.Glare = 0
	atmo.Color = Color3.fromRGB(236, 226, 206)
	atmo.Decay = Color3.fromRGB(150, 170, 180)
	atmo.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.06
	cc.Contrast = 0.04
	cc.Parent = Lighting
end

--------------------------------------------------------------------------

function LevelService.build(layout: Levels.Layout)
	LevelService.clear()
	LevelService.layout = layout
	local rng = Random.new(layout.seed)

	level = Instance.new("Folder")
	level.Name = "Level"
	level:SetAttribute("Name", layout.name)
	level:SetAttribute("BuildMin", Vector3.new(layout.buildMin.X, layout.buildMin.Y, 0))
	level:SetAttribute("BuildMax", Vector3.new(layout.buildMax.X, layout.buildMax.Y, 0))

	for _, piece in layout.pieces do
		builders[piece.kind](piece, rng)
	end

	LevelService.spawn = Vector3.new(layout.spawn.X, layout.spawn.Y, 0)
	LevelService.flag = Vector3.new(layout.flag.X, layout.flag.Y, 0)
	level:SetAttribute("Spawn", LevelService.spawn)
	level:SetAttribute("Flag", LevelService.flag)

	buildStart(LevelService.spawn)
	buildFlag(LevelService.flag)
	safeZone(LevelService.spawn)
	safeZone(LevelService.flag)
	buildBackground(layout, rng)

	level.Parent = workspace
end

function LevelService.clear()
	local old = workspace:FindFirstChild("Level")
	if old then
		old:Destroy()
	end
	LevelService.goalZone = nil
end

function LevelService.objectsFolder(): Folder
	local f = workspace:FindFirstChild("Objects")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Objects"
		f.Parent = workspace
	end
	return f :: Folder
end

function LevelService.pick(previous: string?): Levels.Layout
	local pool = {}
	for _, l in Levels.Forest do
		if l.name ~= previous then
			table.insert(pool, l)
		end
	end
	return pool[math.random(1, #pool)]
end

function LevelService.init()
	setupLighting()
	LevelService.objectsFolder()
end

return LevelService
