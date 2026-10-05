-- Procedural animation for every character on screen, run locally on each
-- client from replicated velocity. No animation assets, no network cost.
--
--   idle     : gentle breathing, slow tail wag
--   walk/run : waddle bob, forward lean, feet swing, fast tail
--   jump     : stretch on take-off, squash on landing (spring-driven, so it wobbles)
--   flap     : quick front flip on the air jump
--   fail     : big squash + head shake (the tumble itself is real physics)
--   victory  : happy hops

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Fx = require(script.Parent.FxController)
local Sound = require(script.Parent.SoundController)

local Animator = {}

type Rig = {
	model: Model,
	root: BasePart,
	bodyJoint: Motor6D?,
	neck: Motor6D?,
	hipL: Motor6D?,
	hipR: Motor6D?,
	tail: Motor6D?,
	flipL: Motor6D?,
	flipR: Motor6D?,
	mesh: SpecialMesh?,
	-- state
	squash: number,
	squashVel: number,
	walkPhase: number,
	grounded: boolean,
	lastVY: number,
	flip: number,
	isLocal: boolean,
}

local rigs = {} :: { [Model]: Rig }
local rayParams = RaycastParams.new()
rayParams.CollisionGroup = "Players"

local function find(model: Model, jointName: string): Motor6D?
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == jointName then
			return d
		end
	end
	return nil
end

local function track(model: Model, isLocal: boolean)
	local root = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then
		return
	end
	local body = model:FindFirstChild("Body")
	rigs[model] = {
		model = model,
		root = root,
		bodyJoint = find(model, "BodyJoint"),
		neck = find(model, "Neck"),
		hipL = find(model, "HipL"),
		hipR = find(model, "HipR"),
		tail = find(model, "TailJoint"),
		flipL = find(model, "FlipL"),
		flipR = find(model, "FlipR"),
		mesh = body and body:FindFirstChildOfClass("SpecialMesh"),
		squash = 0,
		squashVel = 0,
		walkPhase = 0,
		grounded = true,
		lastVY = 0,
		flip = 0,
		isLocal = isLocal,
	}
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
end

local function step(dt: number)
	local t = os.clock()
	for model, r in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		local v = r.root.AssemblyLinearVelocity
		local speed = math.abs(v.X)
		local anchored = r.root.Anchored

		-- grounded: short ray down (works for remote characters too)
		local hit = if anchored then nil else workspace:Raycast(r.root.Position, Vector3.new(0, -2.6, 0), rayParams)
		local grounded = anchored or (hit ~= nil and v.Y < 8)

		-- events
		local feet = r.root.Position - Vector3.new(0, 2.2, 0)
		if r.grounded and not grounded and v.Y > 10 then
			r.squashVel += 9 -- take-off stretch
			Fx.puff(feet, 2, 0.7)
		elseif not r.grounded and grounded and r.lastVY < -20 then
			r.squashVel -= math.clamp(-r.lastVY / 8, 4, 12) -- landing squash
			if r.lastVY < -45 then
				Fx.puff(feet, 4, math.clamp(-r.lastVY / 60, 0.8, 1.6))
			end
			if not r.isLocal then
				Sound.playAt("land", r.root, 0.2)
			end
		elseif not grounded and v.Y - r.lastVY > 30 and r.lastVY < 20 then
			r.flip = 1 -- air jump: front flip
			r.squashVel += 6
			if not r.isLocal then
				Sound.playAt("airJump", r.root, 0.1)
			end
		end
		r.grounded = grounded
		r.lastVY = v.Y

		-- squash spring (wobbles back to 0)
		r.squashVel += (-220 * r.squash - 16 * r.squashVel) * dt
		r.squash = math.clamp(r.squash + r.squashVel * dt, -0.6, 0.6)

		local failAt = model:GetAttribute("FailAt")
		local winAt = model:GetAttribute("VictoryAt")
		local breathe = math.sin(t * 2.2) * 0.025

		local s = r.squash
		if r.mesh then
			r.mesh.Scale = Vector3.new(1 - s * 0.35 - breathe * 0.5, 1 + s * 0.45 + breathe, 1 - s * 0.35 - breathe * 0.5)
		end

		-- walk cycle
		local moving = grounded and speed > 1.5 and not anchored
		if moving then
			r.walkPhase += dt * (6 + speed * 0.45)
		end
		local sw = if moving then math.sin(r.walkPhase) else 0
		local bob = if moving then math.abs(math.sin(r.walkPhase)) * 0.22 * math.min(1, speed / 12) else 0
		local lean = if moving then -math.rad(10) * math.min(1, speed / 22) else 0

		-- flip on air jump
		local flipAngle = 0
		if r.flip > 0 then
			r.flip = math.max(0, r.flip - dt * 3.2)
			flipAngle = -(1 - r.flip) * math.pi * 2
			if r.flip == 0 then
				flipAngle = 0
			end
		end

		local hop = 0
		local spin = 0
		if winAt then
			hop = math.abs(math.sin(t * 7)) * 1.1
			spin = math.sin(t * 3.5) * 0.4
		end

		local headShake = 0
		if failAt then
			headShake = math.sin(t * 40) * 0.25
			lean = math.rad(15)
		end

		local airLean = if not grounded then math.clamp(v.Y / 60, -1, 1) * math.rad(-8) else 0

		if r.bodyJoint then
			-- the mesh scales around its centre, so shift it to keep the feet planted
			r.bodyJoint.Transform = CFrame.new(0, s * 0.5 + bob + hop, 0) * CFrame.Angles(lean + airLean + flipAngle, spin, 0)
		end
		if r.neck then
			r.neck.Transform = CFrame.Angles(math.clamp(v.Y / 70, -1, 1) * math.rad(12) - bob * 0.3, headShake, 0)
		end
		if r.hipL and r.hipR then
			local tuck = if grounded then 0 else 0.25
			local plant = -(s * 0.5 + bob) -- undo the body's bob so feet stay on the ground
			r.hipL.Transform = CFrame.new(0, plant + math.max(0, sw) * 0.3 + tuck, -sw * 0.4 - tuck)
			r.hipR.Transform = CFrame.new(0, plant + math.max(0, -sw) * 0.3 + tuck, sw * 0.4 - tuck)
		end
		if r.tail then
			local rate = if moving then 14 else 3
			local amp = if moving then 0.45 else 0.22
			r.tail.Transform = CFrame.Angles(if grounded then 0 else 0.4, math.sin(t * rate) * amp, 0)
		end
		if r.flipL and r.flipR then
			local flap = if not grounded or winAt then math.sin(t * 28) * 0.6 else sw * 0.3
			r.flipL.Transform = CFrame.Angles(0, 0, -flap)
			r.flipR.Transform = CFrame.Angles(0, 0, flap)
		end
	end
end

function Animator.init()
	local localPlayer = Players.LocalPlayer
	local function hook(p: Player)
		if p.Character then
			task.spawn(track, p.Character, p == localPlayer)
		end
		p.CharacterAdded:Connect(function(c)
			track(c, p == localPlayer)
		end)
	end
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	RunService.RenderStepped:Connect(step)
end

return Animator
