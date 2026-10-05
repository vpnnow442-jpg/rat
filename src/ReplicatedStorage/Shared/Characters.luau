--!strict
-- The cast. Every animal shares the exact same hitbox (HumanoidRootPart);
-- everything you see is massless decoration animated by the client.

local Config = require(script.Parent.Config)

export type Species = {
	id: string,
	name: string,
	body: Color3,
	belly: Color3,
	feet: Color3,
	ears: ("pointy" | "round")?,
	earColor: Color3?,
	earTip: Color3?,
	snout: ("long" | "short" | "beak")?,
	snoutColor: Color3?,
	mask: Color3?,
	bulgyEyes: boolean?,
	flippers: boolean?,
	tail: ("bushy" | "ringed")?,
	tailTip: Color3?,
}

local Characters = {}

local NOSE = Color3.fromRGB(40, 34, 38)
local EYE = Color3.fromRGB(28, 24, 30)

Characters.List = {
	{
		id = "fox", name = "Fox",
		body = Color3.fromRGB(226, 121, 58), belly = Color3.fromRGB(250, 240, 228), feet = Color3.fromRGB(70, 52, 48),
		ears = "pointy", earTip = Color3.fromRGB(70, 52, 48),
		snout = "long", snoutColor = Color3.fromRGB(250, 240, 228),
		tail = "bushy", tailTip = Color3.fromRGB(250, 240, 228),
	},
	{
		id = "raccoon", name = "Raccoon",
		body = Color3.fromRGB(138, 136, 146), belly = Color3.fromRGB(212, 208, 204), feet = Color3.fromRGB(60, 58, 66),
		ears = "round", earColor = Color3.fromRGB(110, 108, 118),
		snout = "short", snoutColor = Color3.fromRGB(212, 208, 204),
		mask = Color3.fromRGB(56, 54, 64),
		tail = "ringed", tailTip = Color3.fromRGB(56, 54, 64),
	},
	{
		id = "penguin", name = "Penguin",
		body = Color3.fromRGB(48, 52, 68), belly = Color3.fromRGB(248, 246, 240), feet = Color3.fromRGB(240, 160, 60),
		snout = "beak", snoutColor = Color3.fromRGB(240, 160, 60),
		flippers = true,
	},
	{
		id = "frog", name = "Frog",
		body = Color3.fromRGB(112, 178, 92), belly = Color3.fromRGB(214, 230, 164), feet = Color3.fromRGB(92, 150, 76),
		bulgyEyes = true,
	},
} :: { Species }

Characters.ById = {} :: { [string]: Species }
for _, s in Characters.List do
	Characters.ById[s.id] = s
end

local function piece(model: Model, name: string, size: Vector3, color: Color3, ball: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if ball then
		p.Shape = Enum.PartType.Ball
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = model
	return p
end

local function weld(p0: BasePart, p1: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = p0
	w.Part1 = p1
	w.C0 = c0
	w.Parent = p1
end

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame?): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1 or CFrame.identity
	m.Parent = p0
	return m
end

-- Builds a ready-to-use character model. Local -Z is "forward".
function Characters.build(speciesId: string): Model
	local s = Characters.ById[speciesId] or Characters.List[1]
	local model = Instance.new("Model")
	model.Name = s.name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(1.8, 2.4, 1.8)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	root.CanTouch = true
	root.CollisionGroup = "Players"
	root.Parent = model
	model.PrimaryPart = root

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 1
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.UseJumpPower = true
	hum.JumpPower = Config.Movement.JumpPower
	hum.WalkSpeed = Config.Movement.WalkSpeed
	hum.Parent = model

	local body = piece(model, "Body", Vector3.new(2.4, 2.4, 2.4), s.body)
	motor("BodyJoint", root, body, CFrame.new(0, -0.7, 0))

	local head = piece(model, "Head", Vector3.new(2, 1.9, 1.9), s.body)
	motor("Neck", body, head, CFrame.new(0, 1.45, -0.45))

	-- Belly patch
	if s.flippers then
		weld(body, piece(model, "Belly", Vector3.new(1.9, 2, 1.2), s.belly), CFrame.new(0, -0.1, -0.62))
	else
		weld(body, piece(model, "Belly", Vector3.new(1.5, 1.6, 0.9), s.belly), CFrame.new(0, -0.15, -0.8))
	end

	-- Feet (animated)
	for i, x in { -0.45, 0.45 } do
		local foot = piece(model, i == 1 and "FootL" or "FootR", Vector3.new(0.5, 0.4, 0.8), s.feet)
		motor(i == 1 and "HipL" or "HipR", body, foot, CFrame.new(x, -1.25, -0.15))
	end

	-- Face
	if s.mask then
		weld(head, piece(model, "Mask", Vector3.new(1.9, 0.5, 1.5), s.mask), CFrame.new(0, 0.2, -0.35))
	end
	for _, side in { -1, 1 } do
		if s.bulgyEyes then
			local white = piece(model, "EyeWhite", Vector3.new(0.8, 0.8, 0.8), Color3.new(1, 1, 1), true)
			weld(head, white, CFrame.new(side * 0.5, 0.85, -0.35))
			weld(head, piece(model, "Eye", Vector3.new(0.12, 0.4, 0.34), EYE), CFrame.new(side * 0.88, 0.9, -0.45))
		else
			weld(head, piece(model, "Eye", Vector3.new(0.12, 0.42, 0.3), EYE), CFrame.new(side * 0.95, 0.2, -0.45))
			weld(head, piece(model, "Shine", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1), true), CFrame.new(side * 1.0, 0.3, -0.5))
		end
	end

	if s.snout == "long" then
		weld(head, piece(model, "Snout", Vector3.new(0.8, 0.7, 1.2), s.snoutColor or s.belly), CFrame.new(0, -0.2, -0.95))
		weld(head, piece(model, "Nose", Vector3.new(0.32, 0.32, 0.32), NOSE, true), CFrame.new(0, -0.05, -1.55))
	elseif s.snout == "short" then
		weld(head, piece(model, "Snout", Vector3.new(0.8, 0.6, 0.8), s.snoutColor or s.belly), CFrame.new(0, -0.25, -0.8))
		weld(head, piece(model, "Nose", Vector3.new(0.28, 0.28, 0.28), NOSE, true), CFrame.new(0, -0.1, -1.18))
	elseif s.snout == "beak" then
		weld(head, piece(model, "Beak", Vector3.new(0.5, 0.35, 0.9), s.snoutColor or s.feet), CFrame.new(0, -0.15, -1.0))
	end

	-- Ears
	for _, side in { -1, 1 } do
		if s.ears == "pointy" then
			local ear = piece(model, "Ear", Vector3.new(0.35, 1.1, 0.7), s.earColor or s.body)
			weld(head, ear, CFrame.new(side * 0.45, 1.0, 0.1) * CFrame.Angles(0, 0, math.rad(-side * 15)))
			weld(ear, piece(model, "EarTip", Vector3.new(0.37, 0.45, 0.5), s.earTip or s.body), CFrame.new(0, 0.38, 0))
		elseif s.ears == "round" then
			weld(head, piece(model, "Ear", Vector3.new(0.3, 0.7, 0.7), s.earColor or s.body), CFrame.new(side * 0.55, 0.85, 0.1))
		end
		if s.flippers then
			local flipper = piece(model, "Flipper", Vector3.new(0.3, 1.2, 0.6), s.body)
			motor(side < 0 and "FlipL" or "FlipR", body, flipper, CFrame.new(side * 1.15, -0.1, 0) * CFrame.Angles(0, 0, math.rad(side * 20)))
		end
	end

	-- Tail (animated)
	if s.tail then
		local tail = piece(model, "Tail", Vector3.new(0.9, 0.9, 2), s.body)
		motor("TailJoint", body, tail, CFrame.new(0, -0.2, 1.0) * CFrame.Angles(math.rad(35), 0, 0), CFrame.new(0, 0, -0.9))
		weld(tail, piece(model, "TailTip", Vector3.new(0.78, 0.78, 0.7), s.tailTip or s.belly), CFrame.new(0, 0, 0.75))
		if s.tail == "ringed" then
			weld(tail, piece(model, "Ring", Vector3.new(0.96, 0.96, 0.25), s.tailTip or s.belly), CFrame.new(0, 0, -0.15))
		end
	end

	model:SetAttribute("Species", s.id)
	return model
end

return Characters
