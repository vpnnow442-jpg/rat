--!strict
-- Placeable object definitions + their models.
-- The server builds the real thing; the client builds the same model for
-- ghost previews and card icons, so what you see is exactly what you get.
--
-- Model conventions (read by server services and client controllers):
--   part attribute Solid   -> you can stand on it
--   part attribute Deadly  -> touching it with your hitbox takes you out
--   part attribute Surface -> "ice" | "honey"
--   part attribute Group   -> client animates it: "spin" | "fan" | "arm" | "mover" | "wind" | "pad"

local Style = require(script.Parent.Style)
local Config = require(script.Parent.Config)

local O = Style.Object
local F = Style.Forest
local DEPTH = 4
local FRONT = DEPTH / 2 + 0.02

export type Def = {
	id: string,
	name: string,
	blurb: string,
	kind: "route" | "trap" | "tool",
	size: Vector2, -- footprint at rotation 0
	weight: number,
	travel: number?,
}

local Objects = {}

Objects.List = {
	{ id = "plank", name = "Plank", blurb = "A trusty wooden ledge.", kind = "route", size = Vector2.new(6, 1), weight = 3 },
	{ id = "longplank", name = "Long Plank", blurb = "Bridges a big gap. Or blocks one.", kind = "route", size = Vector2.new(10, 1), weight = 2 },
	{ id = "pillar", name = "Pillar", blurb = "A tall post. Wall-jump off it.", kind = "route", size = Vector2.new(1, 6), weight = 1 },
	{ id = "crate", name = "Crate", blurb = "Solid. Stack it, hide behind it.", kind = "route", size = Vector2.new(3, 3), weight = 2 },
	{ id = "spring", name = "Spring", blurb = "Boing. Tilt it to launch sideways.", kind = "route", size = Vector2.new(3, 2), weight = 2 },
	{ id = "conveyor", name = "Conveyor", blurb = "Carries you along. Or into things.", kind = "route", size = Vector2.new(8, 1), weight = 2 },
	{ id = "mover", name = "Shuttle", blurb = "Slides back and forth on a rail.", kind = "route", size = Vector2.new(5, 1), weight = 2, travel = 10 },
	{ id = "ice", name = "Ice", blurb = "Slippery. Fast, if you're brave.", kind = "route", size = Vector2.new(8, 1), weight = 1 },
	{ id = "crumble", name = "Crumbly Ledge", blurb = "Falls apart right after you land.", kind = "route", size = Vector2.new(4, 1), weight = 1 },
	{ id = "decoy", name = "Trick Plank", blurb = "Looks like a plank. Isn't. (No nails.)", kind = "trap", size = Vector2.new(6, 1), weight = 1 },
	{ id = "honey", name = "Honey", blurb = "Sticky. Slow feet, weak jumps.", kind = "trap", size = Vector2.new(6, 1), weight = 1 },
	{ id = "spikes", name = "Spikes", blurb = "Don't.", kind = "trap", size = Vector2.new(4, 1), weight = 2 },
	{ id = "saw", name = "Buzzsaw", blurb = "Spins. Hurts.", kind = "trap", size = Vector2.new(5, 5), weight = 2 },
	{ id = "hammer", name = "Swing Hammer", blurb = "Knocks you flying. Timing matters.", kind = "trap", size = Vector2.new(2, 2), weight = 2 },
	{ id = "fan", name = "Fan", blurb = "Blows everyone the way it points.", kind = "trap", size = Vector2.new(3, 2), weight = 2 },
	{ id = "cannon", name = "Cannon", blurb = "Lobs slow cannonballs. Knockback.", kind = "trap", size = Vector2.new(3, 2), weight = 1 },
	{ id = "trapdoor", name = "Trapdoor", blurb = "Solid... until it drops open.", kind = "trap", size = Vector2.new(6, 1), weight = 1 },
	{ id = "bumper", name = "Bumper", blurb = "Bounces you away, pinball style.", kind = "trap", size = Vector2.new(3, 3), weight = 1 },
	{ id = "laser", name = "Laser", blurb = "Blinks on and off. Deadly when on.", kind = "trap", size = Vector2.new(2, 2), weight = 1 },
	{ id = "punch", name = "Punch Box", blurb = "", kind = "trap", size = Vector2.new(3, 3), weight = 2 },
	{ id = "darts", name = "Dart Shooter", blurb = "", kind = "trap", size = Vector2.new(2, 2), weight = 2 },
	{ id = "puck", name = "Puck Launcher", blurb = "", kind = "trap", size = Vector2.new(3, 2), weight = 1 },
	{ id = "plane", name = "Plane Launcher", blurb = "", kind = "trap", size = Vector2.new(2, 2), weight = 1 },
	{ id = "jetpack", name = "Jetpack", blurb = "", kind = "route", size = Vector2.new(2, 2), weight = 1 },
	{ id = "portal", name = "Portal", blurb = "", kind = "route", size = Vector2.new(3, 3), weight = 1 },
	{ id = "coin", name = "Coin", blurb = "", kind = "tool", size = Vector2.new(2, 2), weight = 1 },
	{ id = "bomb", name = "Bomb", blurb = "Clears objects nearby. Fix a ruined level.", kind = "tool", size = Vector2.new(1, 1), weight = 1 },
} :: { Def }

Objects.ById = {} :: { [string]: Def }
for _, def in Objects.List do
	Objects.ById[def.id] = def
end

--------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------

function Objects.footprint(def: Def, rot: number): Vector2
	local w = def.size.X + (def.travel or 0)
	local h = def.size.Y
	if rot % 180 ~= 0 then
		return Vector2.new(h, w)
	end
	return Vector2.new(w, h)
end

-- Snap so the footprint's edges land on whole studs (pieces line up flush)
function Objects.snap(def: Def, x: number, y: number, rot: number): (number, number)
	local fp = Objects.footprint(def, rot)
	local sx = math.floor(x - fp.X / 2 + 0.5) + fp.X / 2
	local sy = math.floor(y - fp.Y / 2 + 0.5) + fp.Y / 2
	return sx, sy
end

function Objects.cframe(x: number, y: number, rot: number): CFrame
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, math.rad(rot))
end

--------------------------------------------------------------------------
-- Timed objects: both server and client compute state from the same clock
--------------------------------------------------------------------------

Objects.LASER_PERIOD = 3.2
-- "on" for 1.4s, a short "warn" flicker before it fires again, otherwise "off"
function Objects.laserState(age: number): string
	local t = age % Objects.LASER_PERIOD
	if t < 1.4 then
		return "on"
	elseif t > Objects.LASER_PERIOD - 0.5 then
		return "warn"
	end
	return "off"
end

Objects.TRAPDOOR_PERIOD = 4
function Objects.trapdoorOpen(age: number): boolean
	return age % Objects.TRAPDOOR_PERIOD > 2.8
end

-- Punch Box: rests, then snaps out fast, holds, and pulls back. 0..1 extension.
Objects.PUNCH_PERIOD = 2.6
function Objects.punchExtend(age: number): number
	local t = age % Objects.PUNCH_PERIOD
	if t < 1.9 then
		return 0
	elseif t < 1.98 then
		return (t - 1.9) / 0.08
	elseif t < 2.3 then
		return 1
	end
	return 1 - (t - 2.3) / 0.3
end

Objects.PORTAL_SPAN = 14 -- distance from the entry ring to the exit ring

--------------------------------------------------------------------------
-- Shooters: darts fly straight, pucks bounce off walls, planes glide in a
-- wave through everything. Positions come purely from the clock + level
-- geometry, so the server (deaths) and every client (visuals) agree.
--------------------------------------------------------------------------

export type Shooter = { interval: number, speed: number, delay: number, muzzle: Vector3, mode: string, range: number, wave: number? }

Objects.Shooters = {
	darts = { interval = 2.0, speed = 34, delay = 0.8, muzzle = Vector3.new(1.1, 0, 0), mode = "ray", range = 70 },
	puck = { interval = 3.0, speed = 24, delay = 1.2, muzzle = Vector3.new(1.7, -0.3, 0), mode = "bounce", range = 110 },
	plane = { interval = 3.2, speed = 13, delay = 1.0, muzzle = Vector3.new(1.2, 0.3, 0), mode = "fixed", range = 60, wave = 2.2 },
} :: { [string]: Shooter }

-- Raycast against solid level/object geometry only. Skips anything that
-- moves or vanishes on clients (shuttles, trapdoors, crumbly ledges) so the
-- server and clients always compute the same path.
function Objects.castSolid(origin: Vector3, dir: Vector3, maxLen: number, ignore: Model?): (number, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list = {}
	for _, name in { "Level", "Objects" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	params.FilterDescendantsInstances = list
	local traveled = 0
	local o = origin
	for _ = 1, 12 do
		if traveled >= maxLen then
			break
		end
		local hit = workspace:Raycast(o, dir * (maxLen - traveled), params)
		if not hit then
			break
		end
		local inst = hit.Instance
		local g = inst:GetAttribute("Group")
		local skip = not inst:GetAttribute("Solid")
			or (ignore ~= nil and inst:IsDescendantOf(ignore))
			or g == "mover" or g == "doorL" or g == "doorR"
			or inst:GetAttribute("Crumble") ~= nil
		local step = (hit.Position - o).Magnitude
		if not skip then
			return traveled + step, hit.Normal
		end
		traveled += step + 0.05
		o = hit.Position + dir * 0.05
	end
	return maxLen, nil
end

-- Polyline a projectile follows, from the muzzle
function Objects.shotPath(id: string, model: Model, pivot: CFrame): { Vector3 }
	local s = Objects.Shooters[id]
	local origin = pivot * s.muzzle
	local dir = pivot.RightVector
	if s.mode == "fixed" then
		return { origin, origin + dir * s.range }
	elseif s.mode == "ray" then
		local d = Objects.castSolid(origin, dir, s.range, model)
		return { origin, origin + dir * d }
	end
	local points = { origin }
	local left = s.range
	for _ = 1, 6 do
		local d, normal = Objects.castSolid(origin, dir, left, model)
		local stop = math.max(d - 0.7, 0) -- bounce off the surface, not inside it
		origin += dir * stop
		table.insert(points, origin)
		left -= stop
		if not normal or left <= 1 then
			break
		end
		local n = Vector3.new(normal.X, normal.Y, 0).Unit
		dir = (dir - 2 * dir:Dot(n) * n).Unit
	end
	return points
end

function Objects.pathLength(path: { Vector3 }): number
	local total = 0
	for i = 2, #path do
		total += (path[i] - path[i - 1]).Magnitude
	end
	return total
end

-- Position + travel direction at a distance along the path
function Objects.pathPoint(path: { Vector3 }, dist: number): (Vector3, Vector3)
	for i = 2, #path do
		local seg = path[i] - path[i - 1]
		local len = seg.Magnitude
		if dist <= len or i == #path then
			local dir = if len > 0 then seg / len else Vector3.xAxis
			return path[i - 1] + dir * math.min(dist, len), dir
		end
		dist -= len
	end
	return path[1], Vector3.xAxis
end

-- Every projectile currently in flight: { k = shot number, dist = distance travelled }
function Objects.activeShots(id: string, age: number, pathLen: number): { { k: number, dist: number } }
	local s = Objects.Shooters[id]
	local since = age - s.delay
	local out = {}
	if since < 0 then
		return out
	end
	local life = pathLen / s.speed
	local newest = math.floor(since / s.interval)
	local oldest = math.max(0, math.floor((since - life) / s.interval))
	for k = oldest, newest do
		local d = (since - k * s.interval) * s.speed
		if d >= 0 and d <= pathLen then
			table.insert(out, { k = k, dist = d })
		end
	end
	return out
end

function Objects.shotPosition(id: string, path: { Vector3 }, pivot: CFrame, dist: number): (Vector3, Vector3)
	local pos, dir = Objects.pathPoint(path, dist)
	local s = Objects.Shooters[id]
	if s.wave then
		pos += pivot.UpVector * math.sin(dist / s.speed * math.pi * 2 / 1.6) * s.wave
	end
	return pos, dir
end

-- How far a laser reaches before something solid stops it
function Objects.laserLength(model: Model, pivot: CFrame): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list = {}
	for _, name in { "Level", "Objects" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	params.FilterDescendantsInstances = list
	local dir = pivot.RightVector
	local origin = pivot * Vector3.new(1, 0, 0)
	local max = 60
	local traveled = 0
	while traveled < max do
		local hit = workspace:Raycast(origin, dir * (max - traveled), params)
		if not hit then
			break
		end
		if hit.Instance.CanCollide and not hit.Instance:IsDescendantOf(model) then
			return traveled + (hit.Position - origin).Magnitude
		end
		traveled += (hit.Position - origin).Magnitude + 0.05
		origin = hit.Position + dir * 0.05
	end
	return max
end

-- Shared by the client ghost (red/green) and the server (final say).
function Objects.check(def: Def, x: number, y: number, rot: number): (boolean, string?)
	local level = workspace:FindFirstChild("Level")
	local objects = workspace:FindFirstChild("Objects")
	if not level then
		return false, "No level"
	end

	local fp = Objects.footprint(def, rot)
	local bmin = level:GetAttribute("BuildMin") :: Vector3?
	local bmax = level:GetAttribute("BuildMax") :: Vector3?
	if bmin and bmax then
		if x - fp.X / 2 < bmin.X or x + fp.X / 2 > bmax.X or y - fp.Y / 2 < bmin.Y or y + fp.Y / 2 > bmax.Y then
			return false, "Out of bounds"
		end
	end

	if def.id == "bomb" then
		return true, nil
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if objects then { level, objects } else { level }
	local function clear(center: Vector3, size: Vector2): (boolean, string?)
		local hits = workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(size.X - 0.15, size.Y - 0.15, 3), params)
		for _, hit in hits do
			if hit.Name == "SafeZone" then
				return false, "Too close to the start or flag"
			end
		end
		if #hits > 0 then
			return false, "Something's in the way"
		end
		return true, nil
	end
	local ok, why = clear(Vector3.new(x, y, 0), fp)
	if not ok then
		return false, why
	end
	if def.id == "portal" then
		-- the exit ring has to fit too
		local exit = Objects.cframe(x, y, rot) * Vector3.new(Objects.PORTAL_SPAN, 0, 0)
		if bmin and bmax and (exit.X < bmin.X or exit.X > bmax.X or exit.Y < bmin.Y or exit.Y > bmax.Y) then
			return false, "Exit is out of bounds"
		end
		local eok = clear(exit, fp)
		if not eok then
			return false, "The exit is blocked"
		end
	end
	return true, nil
end

--------------------------------------------------------------------------
-- Model building
--------------------------------------------------------------------------

local function add(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
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
	p.Parent = model
	return p
end

local function solid(p: Part): Part
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = true
	p:SetAttribute("Solid", true)
	return p
end

local function deadly(model: Model, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
	local p = add(model, "Hitbox", size, cf, O.Danger, shape)
	p.Transparency = 1
	p.CanTouch = true
	p.CanQuery = true
	p:SetAttribute("Deadly", true)
	return p
end

local function ellipsoid(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = add(model, name, size, cf, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local FACE_CAMERA = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z

local builders: { [string]: (Model) -> () } = {}

local function plankBody(m: Model, withNails: boolean)
	solid(add(m, "Board", Vector3.new(6, 1, DEPTH), CFrame.identity, F.Wood))
	add(m, "Trim", Vector3.new(6.02, 0.22, DEPTH + 0.02), CFrame.new(0, -0.4, 0), F.WoodDark)
	if withNails then
		for _, x in { -2.3, 2.3 } do
			add(m, "Nail", Vector3.new(0.28, 0.28, 0.06), CFrame.new(x, 0.12, FRONT), F.WoodDark)
		end
	end
end

builders.plank = function(m)
	plankBody(m, true)
end

builders.decoy = function(m)
	plankBody(m, false)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p:SetAttribute("Solid", nil)
		end
	end
end

builders.longplank = function(m)
	solid(add(m, "Board", Vector3.new(10, 1, DEPTH), CFrame.identity, F.Wood))
	add(m, "Trim", Vector3.new(10.02, 0.22, DEPTH + 0.02), CFrame.new(0, -0.4, 0), F.WoodDark)
	for _, x in { -4.3, 0, 4.3 } do
		add(m, "Nail", Vector3.new(0.28, 0.28, 0.06), CFrame.new(x, 0.12, FRONT), F.WoodDark)
	end
end

builders.pillar = function(m)
	solid(add(m, "Post", Vector3.new(1, 6, DEPTH), CFrame.identity, F.Wood))
	add(m, "Cap", Vector3.new(1.3, 0.4, DEPTH + 0.2), CFrame.new(0, 2.85, 0), F.WoodDark)
	add(m, "Foot", Vector3.new(1.3, 0.4, DEPTH + 0.2), CFrame.new(0, -2.85, 0), F.WoodDark)
end

builders.trapdoor = function(m)
	add(m, "Frame", Vector3.new(6, 0.3, DEPTH + 0.1), CFrame.new(0, -0.55, 0), O.Metal)
	for _, side in { -1, 1 } do
		local door = solid(add(m, "Door", Vector3.new(2.95, 0.8, DEPTH), CFrame.new(side * 1.5, 0, 0), F.Wood))
		door:SetAttribute("Group", side < 0 and "doorL" or "doorR")
		local hinge = add(m, "Hinge", Vector3.new(0.35, 0.35, 0.06), CFrame.new(side * 2.7, 0, FRONT), O.MetalLight)
		hinge:SetAttribute("Group", side < 0 and "doorL" or "doorR")
	end
	add(m, "Seam", Vector3.new(0.12, 0.82, 0.05), CFrame.new(0, 0, FRONT), F.WoodDark)
end

builders.bumper = function(m)
	local ball = solid(add(m, "Bumper", Vector3.new(3, 3, 3), CFrame.identity, O.Spring, Enum.PartType.Ball))
	ball:SetAttribute("Group", "bumper")
	local ring = add(m, "Ring", Vector3.new(0.3, 3.1, 3.1), FACE_CAMERA, Style.UI.Paper, Enum.PartType.Cylinder)
	ring:SetAttribute("Group", "bumper")
	local dot = add(m, "Dot", Vector3.new(0.32, 1.2, 1.2), FACE_CAMERA, O.Spring, Enum.PartType.Cylinder)
	dot:SetAttribute("Group", "bumper")
end

builders.laser = function(m)
	solid(add(m, "Emitter", Vector3.new(2, 2, 3), CFrame.identity, O.Metal))
	add(m, "Lens", Vector3.new(0.3, 1, 1), CFrame.new(1.05, 0, 0), O.Danger, Enum.PartType.Cylinder)
	add(m, "Vent", Vector3.new(1.4, 0.15, 0.05), CFrame.new(-0.1, 0.4, 1.52), O.MetalLight)
	add(m, "Vent", Vector3.new(1.4, 0.15, 0.05), CFrame.new(-0.1, 0, 1.52), O.MetalLight)
	local beam = add(m, "Beam", Vector3.new(4, 0.3, 0.3), CFrame.new(3.1, 0, 0), O.Danger)
	beam:SetAttribute("Group", "beam")
	beam.CastShadow = false
	beam.Transparency = 0.15
end

builders.punch = function(m)
	solid(add(m, "Housing", Vector3.new(3, 3, 3), CFrame.identity, O.Metal))
	add(m, "Face", Vector3.new(0.1, 2.2, 2.2), CFrame.new(1.52, 0, 0), O.MetalLight)
	add(m, "Warn", Vector3.new(2.4, 0.3, 0.05), CFrame.new(0, 1.05, 1.52), O.Stripe)
	local rod = add(m, "Rod", Vector3.new(3.4, 0.45, 0.45), CFrame.new(0, 0, 0), O.MetalLight)
	rod:SetAttribute("Group", "glove")
	local glove = ellipsoid(m, "Glove", Vector3.new(1.7, 1.8, 1.8), CFrame.new(1.7, 0, 0), O.Danger)
	glove:SetAttribute("Group", "glove")
	local cuff = add(m, "Cuff", Vector3.new(0.4, 1.4, 1.4), CFrame.new(1.0, 0, 0) * FACE_CAMERA * CFrame.Angles(0, math.pi / 2, 0), Style.UI.Paper, Enum.PartType.Cylinder)
	cuff:SetAttribute("Group", "glove")
end

builders.darts = function(m)
	solid(add(m, "Body", Vector3.new(2, 2, 2.6), CFrame.identity, F.WoodDark))
	add(m, "Band", Vector3.new(0.3, 2.04, 2.64), CFrame.new(0.5, 0, 0), O.Metal)
	add(m, "Muzzle", Vector3.new(0.2, 0.7, 0.7), CFrame.new(1.05, 0, 0), O.Rubber, Enum.PartType.Cylinder)
	add(m, "Feather", Vector3.new(0.5, 0.5, 0.05), CFrame.new(-0.4, 0.4, 1.32) * CFrame.Angles(0, 0, math.rad(45)), O.Danger)
end

builders.puck = function(m)
	solid(add(m, "Base", Vector3.new(3, 1.4, 3), CFrame.new(0, -0.3, 0), O.Metal))
	add(m, "Slot", Vector3.new(0.15, 0.5, 2), CFrame.new(1.52, -0.3, 0), O.Rubber)
	add(m, "Stripe", Vector3.new(3.02, 0.25, 0.05), CFrame.new(0, 0.1, 1.52), Style.UI.Cool)
	add(m, "Stack", Vector3.new(0.6, 1.2, 1.2), CFrame.new(-0.6, 0.7, 0) * CFrame.Angles(0, 0, math.pi / 2), O.Rubber, Enum.PartType.Cylinder)
end

builders.plane = function(m)
	solid(add(m, "Base", Vector3.new(2, 0.8, 2.4), CFrame.new(0, -0.6, 0), F.Wood))
	for _, z in { -0.8, 0.8 } do
		add(m, "Post", Vector3.new(0.2, 1.4, 0.2), CFrame.new(0.6, 0.1, z), F.WoodDark)
	end
	add(m, "Band", Vector3.new(0.12, 0.12, 1.8), CFrame.new(0.6, 0.6, 0), O.Spring)
	add(m, "Paper", Vector3.new(1.4, 0.08, 0.9), CFrame.new(-0.1, 0.25, 0) * CFrame.Angles(0, 0, math.rad(8)), Style.UI.Paper)
	add(m, "Fold", Vector3.new(1.4, 0.35, 0.06), CFrame.new(-0.1, 0.12, 0), Style.UI.PaperShade)
end

builders.jetpack = function(m)
	solid(add(m, "Stand", Vector3.new(2, 0.4, 2), CFrame.new(0, -0.8, 0), O.Metal))
	for _, x in { -0.4, 0.4 } do
		local tank = add(m, "Tank", Vector3.new(1.3, 0.75, 0.75), CFrame.new(x, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Style.UI.Cool, Enum.PartType.Cylinder)
		tank:SetAttribute("Group", "float")
		local cap = add(m, "Cap", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, 0.8, 0), O.MetalLight, Enum.PartType.Ball)
		cap:SetAttribute("Group", "float")
		local nozzle = add(m, "Nozzle", Vector3.new(0.3, 0.45, 0.45), CFrame.new(x, -0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), O.Rubber, Enum.PartType.Cylinder)
		nozzle:SetAttribute("Group", "float")
	end
	local strap = add(m, "Strap", Vector3.new(1.2, 0.25, 0.9), CFrame.new(0, 0.35, 0), O.Rubber)
	strap:SetAttribute("Group", "float")
end

builders.portal = function(m)
	local span = Objects.PORTAL_SPAN
	for i, x in { 0, span } do
		local color = if i == 1 then Style.UI.Cool else Style.UI.Accent
		add(m, "Ring", Vector3.new(0.3, 3, 3), CFrame.new(x, 0, 0) * FACE_CAMERA, color, Enum.PartType.Cylinder)
		add(m, "Hole", Vector3.new(0.32, 2.2, 2.2), CFrame.new(x, 0, 0.02) * FACE_CAMERA, Style.UI.Ink, Enum.PartType.Cylinder)
		local swirl = add(m, "Swirl", Vector3.new(0.34, 0.6, 0.6), CFrame.new(x + 0.6, 0, 0.04) * FACE_CAMERA, color, Enum.PartType.Cylinder)
		swirl:SetAttribute("Group", if i == 1 then "swirlA" else "swirlB")
	end
end

builders.coin = function(m)
	local coin = add(m, "Coin", Vector3.new(0.3, 1.8, 1.8), FACE_CAMERA, Style.UI.Gold, Enum.PartType.Cylinder)
	coin:SetAttribute("Group", "coin")
	local inner = add(m, "Inner", Vector3.new(0.34, 1.2, 1.2), FACE_CAMERA, Color3.fromRGB(220, 160, 56), Enum.PartType.Cylinder)
	inner:SetAttribute("Group", "coin")
end

builders.crate = function(m)
	solid(add(m, "Box", Vector3.new(3, 3, DEPTH), CFrame.identity, F.Wood))
	local t = 0.36
	add(m, "Trim", Vector3.new(3, t, 0.06), CFrame.new(0, 1.5 - t / 2, FRONT), F.WoodDark)
	add(m, "Trim", Vector3.new(3, t, 0.06), CFrame.new(0, -1.5 + t / 2, FRONT), F.WoodDark)
	add(m, "Trim", Vector3.new(t, 3, 0.06), CFrame.new(1.5 - t / 2, 0, FRONT), F.WoodDark)
	add(m, "Trim", Vector3.new(t, 3, 0.06), CFrame.new(-1.5 + t / 2, 0, FRONT), F.WoodDark)
	add(m, "Trim", Vector3.new(t, 3.1, 0.05), CFrame.new(0, 0, FRONT) * CFrame.Angles(0, 0, math.rad(45)), F.WoodDark)
end

builders.spring = function(m)
	solid(add(m, "Base", Vector3.new(3, 0.5, 3), CFrame.new(0, -0.75, 0), O.Metal))
	for i = 0, 2 do
		add(m, "Coil", Vector3.new(0.16, 1.5, 1.5), CFrame.new(0, -0.35 + i * 0.32, 0) * CFrame.Angles(0, 0, math.pi / 2), O.MetalLight, Enum.PartType.Cylinder)
	end
	local pad = solid(add(m, "Pad", Vector3.new(3, 0.4, 3), CFrame.new(0, 0.6, 0), O.Spring))
	pad:SetAttribute("Group", "pad")
end

builders.conveyor = function(m)
	local belt = solid(add(m, "Belt", Vector3.new(8, 1, DEPTH), CFrame.identity, O.Rubber))
	belt:SetAttribute("Conveyor", true)
	for _, x in { -4, 4 } do
		add(m, "Roller", Vector3.new(DEPTH + 0.1, 1.1, 1.1), CFrame.new(x, 0, 0) * FACE_CAMERA, O.MetalLight, Enum.PartType.Cylinder)
	end
	for _, x in { -2.2, 0, 2.2 } do
		add(m, "Chevron", Vector3.new(0.8, 0.16, 0.05), CFrame.new(x, 0.17, FRONT) * CFrame.Angles(0, 0, math.rad(-38)), O.Stripe)
		add(m, "Chevron", Vector3.new(0.8, 0.16, 0.05), CFrame.new(x, -0.17, FRONT) * CFrame.Angles(0, 0, math.rad(38)), O.Stripe)
	end
end

builders.mover = function(m)
	local travel = (Objects.ById.mover.travel :: number) + 5
	add(m, "Rail", Vector3.new(travel, 0.3, 0.3), CFrame.new(0, 0, -1.6), O.Rubber)
	for _, x in { -travel / 2, travel / 2 } do
		add(m, "RailEnd", Vector3.new(0.7, 0.7, 0.7), CFrame.new(x, 0, -1.6), O.Metal, Enum.PartType.Ball)
	end
	local deck = solid(add(m, "Deck", Vector3.new(5, 1, DEPTH), CFrame.identity, F.Wood))
	deck:SetAttribute("Group", "mover")
	for _, x in { -2.35, 2.35 } do
		local cap = add(m, "Cap", Vector3.new(0.4, 1.06, DEPTH + 0.06), CFrame.new(x, 0, 0), O.MetalLight)
		cap:SetAttribute("Group", "mover")
	end
end

builders.ice = function(m)
	local slab = solid(add(m, "Slab", Vector3.new(8, 1, DEPTH), CFrame.identity, O.Ice))
	slab:SetAttribute("Surface", "ice")
	for _, x in { -2.6, -2.1, 1.8 } do
		add(m, "Shine", Vector3.new(0.14, 0.7, 0.05), CFrame.new(x, 0, FRONT) * CFrame.Angles(0, 0, math.rad(-30)), Color3.new(1, 1, 1))
	end
end

builders.crumble = function(m)
	local slab = solid(add(m, "Slab", Vector3.new(4, 1, DEPTH), CFrame.identity, O.Crumble))
	slab:SetAttribute("Crumble", true)
	add(m, "Crack", Vector3.new(0.1, 0.8, 0.05), CFrame.new(-0.7, 0, FRONT) * CFrame.Angles(0, 0, math.rad(20)), F.WoodDark)
	add(m, "Crack", Vector3.new(0.1, 0.5, 0.05), CFrame.new(0.9, 0.15, FRONT) * CFrame.Angles(0, 0, math.rad(-35)), F.WoodDark)
end

builders.honey = function(m)
	local slab = solid(add(m, "Slab", Vector3.new(6, 0.8, DEPTH), CFrame.new(0, -0.1, 0), O.Honey))
	slab:SetAttribute("Surface", "honey")
	ellipsoid(m, "Top", Vector3.new(6.2, 0.5, DEPTH + 0.2), CFrame.new(0, 0.25, 0), O.Honey)
	for _, x in { -2.1, 0.4, 2.3 } do
		ellipsoid(m, "Drip", Vector3.new(0.5, 0.9, 0.5), CFrame.new(x, -0.6, 1.4), O.Honey)
	end
end

builders.spikes = function(m)
	solid(add(m, "Base", Vector3.new(4, 0.4, DEPTH), CFrame.new(0, -0.3, 0), O.Metal))
	add(m, "Band", Vector3.new(4.02, 0.12, 0.05), CFrame.new(0, -0.3, FRONT), O.Danger)
	for _, x in { -1.5, -0.5, 0.5, 1.5 } do
		add(m, "Spike", Vector3.new(0.85, 0.85, DEPTH - 0.4), CFrame.new(x, -0.1, 0) * CFrame.Angles(0, 0, math.rad(45)), O.MetalLight)
	end
	-- Slightly smaller than the art: forgiving hitboxes feel fair
	deadly(m, Vector3.new(3.6, 0.7, 3), CFrame.new(0, 0.05, 0))
end

builders.saw = function(m)
	local blade = add(m, "Blade", Vector3.new(0.4, 5, 5), FACE_CAMERA, O.MetalLight, Enum.PartType.Cylinder)
	blade:SetAttribute("Group", "spin")
	for i = 0, 7 do
		local a = i * math.pi / 4
		local tooth = add(m, "Tooth", Vector3.new(0.7, 0.7, 0.3), CFrame.Angles(0, 0, a) * CFrame.new(0, 2.45, 0) * CFrame.Angles(0, 0, math.rad(45)), O.Metal)
		tooth:SetAttribute("Group", "spin")
	end
	local hub = add(m, "Hub", Vector3.new(0.7, 1.4, 1.4), FACE_CAMERA, O.Danger, Enum.PartType.Cylinder)
	hub:SetAttribute("Group", "spin")
	deadly(m, Vector3.new(4.4, 4.4, 4.4), CFrame.identity, Enum.PartType.Ball)
end

builders.hammer = function(m)
	solid(add(m, "Mount", Vector3.new(2, 2, 3), CFrame.identity, O.Metal))
	add(m, "Bolt", Vector3.new(0.3, 0.8, 0.8), CFrame.new(0, 0, 1.9) * FACE_CAMERA, O.MetalLight, Enum.PartType.Cylinder)
	local arm = add(m, "Arm", Vector3.new(0.5, 7, 0.5), CFrame.new(0, -3.5, 1.8), F.WoodDark)
	arm:SetAttribute("Group", "arm")
	local head = add(m, "Head", Vector3.new(3.2, 2, 2.2), CFrame.new(0, -7.5, 1.8), O.Metal)
	head:SetAttribute("Group", "arm")
	local band = add(m, "Band", Vector3.new(0.5, 2.06, 2.26), CFrame.new(0, -7.5, 1.8), O.Danger)
	band:SetAttribute("Group", "arm")
end

builders.fan = function(m)
	solid(add(m, "Housing", Vector3.new(3, 1.2, 3), CFrame.new(0, -0.4, 0), O.Metal))
	add(m, "Grill", Vector3.new(3.02, 0.14, 0.05), CFrame.new(0, -0.4, 1.52), O.MetalLight)
	for i = 0, 2 do
		local blade = add(m, "Blade", Vector3.new(2.6, 0.12, 0.5), CFrame.new(0, 0.35, 0) * CFrame.Angles(0, i * math.pi / 3, 0), O.MetalLight)
		blade:SetAttribute("Group", "fan")
	end
	-- Faint column so players can always see the wind's reach
	local zone = add(m, "Zone", Vector3.new(3, 16, 0.1), CFrame.new(0, 8.5, -1.8), Color3.new(1, 1, 1))
	zone.Transparency = 0.9
	zone.CastShadow = false
	for i = 1, 3 do
		local s = add(m, "Wind", Vector3.new(0.1, 1.8, 0.1), CFrame.new(-1 + (i - 1), 2 + i * 4, 0.5), Color3.new(1, 1, 1))
		s.Transparency = 0.5
		s.CastShadow = false
		s:SetAttribute("Group", "wind")
	end
end

builders.cannon = function(m)
	solid(add(m, "Base", Vector3.new(3, 0.8, 3), CFrame.new(0, -0.6, 0), F.WoodDark))
	solid(add(m, "Barrel", Vector3.new(2.8, 1.4, 1.4), CFrame.new(0.3, 0.3, 0), O.Rubber, Enum.PartType.Cylinder))
	add(m, "Lip", Vector3.new(0.3, 1.7, 1.7), CFrame.new(1.65, 0.3, 0), O.Metal, Enum.PartType.Cylinder)
	for _, x in { -0.8, 0.8 } do
		add(m, "Wheel", Vector3.new(0.35, 1.2, 1.2), CFrame.new(x, -0.7, 1.7) * FACE_CAMERA, F.Wood, Enum.PartType.Cylinder)
	end
end

builders.bomb = function(m)
	add(m, "Ball", Vector3.new(1.6, 1.6, 1.6), CFrame.identity, O.Rubber, Enum.PartType.Ball)
	add(m, "Fuse", Vector3.new(0.2, 0.6, 0.2), CFrame.new(0.3, 0.9, 0) * CFrame.Angles(0, 0, math.rad(-25)), F.WoodDark)
	local r = Config.Objects.BombRadius * 2
	local ring = add(m, "Radius", Vector3.new(0.1, r, r), FACE_CAMERA, O.Danger, Enum.PartType.Cylinder)
	ring.Transparency = 0.8
	ring.CastShadow = false
end

function Objects.build(id: string): Model
	local m = Instance.new("Model")
	m.Name = id
	builders[id](m)
	m.WorldPivot = CFrame.identity
	m:SetAttribute("Id", id)
	return m
end

return Objects
