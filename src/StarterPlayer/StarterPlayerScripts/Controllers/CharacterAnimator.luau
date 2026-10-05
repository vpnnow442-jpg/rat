-- Procedural animation for every character on screen, run locally on each
-- client from replicated velocity. No animation assets, no network cost.
--
--   always   : breathing, blinking, ear twitches
--   idle     : looks around, now and then glances at the camera
--   walk/run : waddle bob, forward lean, feet swing, fast tail, kicked-up dust
--   turn     : skid puff when you reverse direction at speed
--   jump     : stretch on take-off, squash on landing (spring-driven, so it wobbles)
--   flap     : quick front flip on the air jump
--   wall     : lean off the wall, feet braced, dust scraping down it
--   falling  : legs flail when you're dropping fast
--   hit      : sudden knockback -> backflip tumble with speed lines
--   ledge    : standing at an edge -> nervous wobble
--   fail     : a burst in your colour, squash, head shake (the tumble is real physics)
--   victory  : happy hops with the odd flip
--   emotes   : wave, dance, laugh, sit (keys 1-4 or the HUD buttons)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Net = require(Shared.Net)

local Fx = require(script.Parent.FxController)
local Sound = require(script.Parent.SoundController)

local Animator = {}

Animator.EMOTES = { "wave", "dance", "laugh", "sit" }

type Eye = { part: BasePart, size: Vector3 }
type Rig = {
	model: Model,
	root: BasePart,
	color: Color3,
	bodyJoint: Motor6D?,
	neck: Motor6D?,
	hipL: Motor6D?,
	hipR: Motor6D?,
	tail: Motor6D?,
	flipL: Motor6D?,
	flipR: Motor6D?,
	mesh: SpecialMesh?,
	eyes: { Eye },
	ears: { { weld: Weld, c0: CFrame } },
	-- state
	squash: number,
	squashVel: number,
	walkPhase: number,
	grounded: boolean,
	lastV: Vector3,
	flip: number,
	tumble: number,
	idleTime: number,
	nextBlink: number,
	nextTwitch: number,
	twitchUntil: number,
	nextDust: number,
	lastFail: number?,
	hopCount: number,
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
	local species = Characters.ById[model:GetAttribute("Species") :: string? or ""]
	local eyes = {}
	local ears = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			table.insert(eyes, { part = d, size = d.Size })
		elseif d:IsA("Weld") and d.Part1 and d.Part1.Name == "Ear" then
			table.insert(ears, { weld = d, c0 = d.C0 })
		end
	end
	local now = os.clock()
	rigs[model] = {
		model = model,
		root = root,
		color = if species then species.body else Color3.new(1, 1, 1),
		bodyJoint = find(model, "BodyJoint"),
		neck = find(model, "Neck"),
		hipL = find(model, "HipL"),
		hipR = find(model, "HipR"),
		tail = find(model, "TailJoint"),
		flipL = find(model, "FlipL"),
		flipR = find(model, "FlipR"),
		mesh = body and body:FindFirstChildOfClass("SpecialMesh"),
		eyes = eyes,
		ears = ears,
		squash = 0,
		squashVel = 0,
		walkPhase = 0,
		grounded = true,
		lastV = Vector3.zero,
		flip = 0,
		tumble = 0,
		idleTime = 0,
		nextBlink = now + math.random() * 3,
		nextTwitch = now + 2 + math.random() * 4,
		twitchUntil = 0,
		nextDust = 0,
		lastFail = nil,
		hopCount = 0,
		isLocal = isLocal,
	}
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)

	-- Only you see this: a little bouncing marker so you never lose yourself
	if isLocal then
		local head = model:WaitForChild("Head", 5) :: BasePart?
		if head then
			local gui = Instance.new("BillboardGui")
			gui.Name = "YouMarker"
			gui.Size = UDim2.fromOffset(60, 34)
			gui.StudsOffset = Vector3.new(0, 4.6, 0)
			gui.MaxDistance = 1000
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.Adornee = head
			local label = Instance.new("TextLabel")
			label.Name = "Arrow"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
			label.TextSize = 16
			label.TextColor3 = Color3.fromRGB(238, 108, 77)
			label.Text = "YOU\n\u{25BC}"
			label.LineHeight = 0.8
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(250, 246, 238)
			stroke.Thickness = 2
			stroke.Parent = label
			label.Parent = gui
			gui.Parent = head
			task.spawn(function()
				while gui.Parent do
					gui.StudsOffset = Vector3.new(0, 4.6 + math.abs(math.sin(os.clock() * 4)) * 0.4, 0)
					task.wait()
				end
			end)
		end
	end
end

local function step(dt: number)
	local t = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, r in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		local root = r.root
		local v = root.AssemblyLinearVelocity
		local speed = math.abs(v.X)
		local anchored = root.Anchored
		local pos = root.Position
		local facing = if root.CFrame.LookVector.X >= 0 then 1 else -1
		local feet = pos - Vector3.new(0, 2.2, 0)

		-- grounded: short ray down (works for remote characters too)
		local hit = if anchored then nil else workspace:Raycast(pos, Vector3.new(0, -2.6, 0), rayParams)
		local grounded = anchored or (hit ~= nil and v.Y < 8)

		-- ---------- events ----------
		local dv = v - r.lastV
		if not anchored and math.abs(dv.X) > 45 and not grounded then
			-- sudden sideways shove: we got hit by something
			r.tumble = 1
			r.squashVel -= 6
			Fx.streak(pos, v)
		elseif r.grounded and not grounded and v.Y > 10 then
			r.squashVel += 9 -- take-off stretch
			Fx.puff(feet, 2, 0.7)
		elseif not r.grounded and grounded and r.lastV.Y < -20 then
			r.squashVel -= math.clamp(-r.lastV.Y / 8, 4, 12) -- landing squash
			if r.lastV.Y < -45 then
				Fx.puff(feet, 4, math.clamp(-r.lastV.Y / 60, 0.8, 1.6))
			end
			if not r.isLocal then
				Sound.playAt("land", root, 0.2)
			end
		elseif not grounded and dv.Y > 30 and r.lastV.Y < 20 then
			r.flip = 1 -- air jump: front flip
			r.squashVel += 6
			Fx.puff(feet, 2, 0.6)
			if not r.isLocal then
				Sound.playAt("airJump", root, 0.1)
			end
		end
		-- skid when reversing at speed
		if grounded and not anchored and math.sign(v.X) ~= math.sign(r.lastV.X) and math.abs(r.lastV.X) > 14 then
			Fx.puff(feet, 3, 0.8)
		end
		r.grounded = grounded
		r.lastV = v

		-- squash spring (wobbles back to 0)
		r.squashVel += (-220 * r.squash - 16 * r.squashVel) * dt
		r.squash = math.clamp(r.squash + r.squashVel * dt, -0.6, 0.6)

		local failAt = model:GetAttribute("FailAt") :: number?
		local winAt = model:GetAttribute("VictoryAt") :: number?
		if failAt and failAt ~= r.lastFail then
			r.lastFail = failAt
			r.squashVel -= 10
			Fx.burst(pos, r.color, 10)
			Fx.puff(pos, 5, 1.4)
		end

		-- emotes (cancelled by moving)
		local emote: string? = nil
		local emoteAt = model:GetAttribute("EmoteAt") :: number?
		if emoteAt and serverNow - emoteAt < 2.6 and speed < 2 and grounded then
			emote = model:GetAttribute("Emote") :: string?
		end

		local s = r.squash
		local breathe = math.sin(t * 2.2) * 0.025
		if r.mesh then
			r.mesh.Scale = Vector3.new(1 - s * 0.35 - breathe * 0.5, 1 + s * 0.45 + breathe, 1 - s * 0.35 - breathe * 0.5)
		end

		-- ---------- blink & ear twitch ----------
		local squint = if failAt then 0.3 else 1
		-- eyes close for 0.12s at each blink time, then the next blink is scheduled
		local eyeY = squint
		if t >= r.nextBlink then
			if t <= r.nextBlink + 0.12 then
				eyeY = 0.12
			else
				r.nextBlink = t + 2 + math.random() * 3.5
			end
		end
		for _, e in r.eyes do
			e.part.Size = Vector3.new(e.size.X, e.size.Y * eyeY, e.size.Z)
		end
		if t > r.nextTwitch then
			r.nextTwitch = t + 3 + math.random() * 4
			r.twitchUntil = t + 0.18
		end
		local twitch = if t < r.twitchUntil then math.sin((r.twitchUntil - t) * 50) * 0.35 else 0
		for i, ear in r.ears do
			local side = if i % 2 == 0 then 1 else -1
			ear.weld.C0 = ear.c0 * CFrame.Angles(0, 0, twitch * side)
		end

		-- ---------- locomotion ----------
		local moving = grounded and speed > 1.5 and not anchored
		if moving then
			r.walkPhase += dt * (6 + speed * 0.45)
			r.idleTime = 0
			if speed > 16 and t > r.nextDust then
				r.nextDust = t + 0.22
				Fx.puff(feet - Vector3.new(facing * 0.8, 0, 0), 1, 0.5)
			end
		elseif grounded then
			r.idleTime += dt
		else
			r.idleTime = 0
		end
		local sw = if moving then math.sin(r.walkPhase) else 0
		local bob = if moving then math.abs(math.sin(r.walkPhase)) * 0.22 * math.min(1, speed / 12) else 0
		local lean = if moving then -math.rad(10) * math.min(1, speed / 22) else 0
		local airLean = if not grounded then math.clamp(v.Y / 60, -1, 1) * math.rad(-8) else 0
		local headPitch = math.clamp(v.Y / 70, -1, 1) * math.rad(12) - bob * 0.3
		local headYaw = 0
		local footL, footR = Vector3.zero, Vector3.zero -- (up, forward) offsets
		local flapAmp = 0
		local hop, spin, sink = 0, 0, 0
		local tailRate = if moving then 14 else 3
		local tailAmp = if moving then 0.45 else 0.22

		if moving then
			footL = Vector3.new(0, math.max(0, sw) * 0.3, -sw * 0.4)
			footR = Vector3.new(0, math.max(0, -sw) * 0.3, sw * 0.4)
			flapAmp = sw * 0.3
		end

		-- wall slide: falling slowly with a wall in front
		if not grounded and not anchored and v.Y < -3 and v.Y > -16 then
			local wall = workspace:Raycast(pos, Vector3.new(facing * 1.6, 0, 0), rayParams)
			if wall and wall.Instance.CanCollide then
				lean = math.rad(14) -- lean back off the wall
				footL = Vector3.new(0.2, 0, -0.35) -- braced against it
				footR = Vector3.new(0.4, 0, -0.35)
				headPitch = math.rad(-10)
				if t > r.nextDust then
					r.nextDust = t + 0.08
					Fx.puff(wall.Position + Vector3.new(-facing * 0.2, -0.6, 0.4), 1, 0.45)
				end
			end
		end

		-- falling fast: flail
		if not grounded and v.Y < -50 then
			footL = Vector3.new(0.2 + math.sin(t * 32) * 0.2, 0, math.sin(t * 32) * 0.35)
			footR = Vector3.new(0.2 - math.sin(t * 32) * 0.2, 0, -math.sin(t * 32) * 0.35)
			flapAmp = math.sin(t * 30) * 0.8
			headPitch = math.rad(-18)
		elseif not grounded then
			footL = footL + Vector3.new(0.25, 0, -0.25) -- tucked
			footR = footR + Vector3.new(0.25, 0, -0.25)
			flapAmp = math.sin(t * 24) * 0.5
		end

		-- idle: look around, sometimes glance at the camera; teeter at edges
		if grounded and not moving and not emote and not winAt and not failAt then
			if r.idleTime > 2.5 then
				local cycle = (r.idleTime % 7)
				if cycle < 2 then
					headYaw = math.sin(cycle * math.pi) * -0.6 * facing -- toward the camera
				else
					headYaw = math.sin(r.idleTime * 0.9) * 0.45
				end
			end
			if not anchored then
				local ahead = workspace:Raycast(pos + Vector3.new(facing * 1.2, 0, 0), Vector3.new(0, -3, 0), rayParams)
				if not ahead then
					lean = math.sin(t * 9) * math.rad(12) - math.rad(6)
					flapAmp = math.sin(t * 18) * 0.9
					headPitch = math.rad(-15)
				end
			end
		end

		-- emotes
		if emote == "wave" then
			spin = math.sin(t * 8) * 0.35
			headYaw = -0.5 * facing
			flapAmp = math.sin(t * 16) * 1
			footL = Vector3.new(math.max(0, math.sin(t * 8)) * 0.3, 0, 0)
		elseif emote == "dance" then
			bob = math.abs(math.sin(t * 9)) * 0.35
			spin = math.sin(t * 4.5) * 0.9
			footL = Vector3.new(math.max(0, math.sin(t * 9)) * 0.35, 0, 0)
			footR = Vector3.new(math.max(0, -math.sin(t * 9)) * 0.35, 0, 0)
			flapAmp = math.sin(t * 9) * 0.8
			tailRate, tailAmp = 18, 0.6
		elseif emote == "laugh" then
			bob = math.abs(math.sin(t * 22)) * 0.1
			headPitch = math.rad(22) + math.sin(t * 22) * 0.08
			lean = math.rad(8)
		elseif emote == "sit" then
			sink = -0.75
			footL = Vector3.new(0.75, 0, -0.45)
			footR = Vector3.new(0.75, 0, -0.45)
			tailRate, tailAmp = 6, 0.4
		end

		-- air-jump flip
		local flipAngle = 0
		if r.flip > 0 then
			r.flip = math.max(0, r.flip - dt * 3.2)
			flipAngle = if r.flip > 0 then -(1 - r.flip) * math.pi * 2 else 0
		end
		-- hit tumble (backflip, faster)
		if r.tumble > 0 then
			r.tumble = math.max(0, r.tumble - dt * 2.4)
			flipAngle += if r.tumble > 0 then (1 - r.tumble) * math.pi * 2 else 0
		end

		-- victory: hops, every third one a flip
		if winAt then
			local phase = (t * 1.6) % 1
			hop = math.sin(phase * math.pi) * 1.3
			if phase < 0.05 and r.hopCount ~= math.floor(t * 1.6) then
				r.hopCount = math.floor(t * 1.6)
				if r.hopCount % 3 == 0 then
					r.flip = 1
				end
			end
			spin = math.sin(t * 3.5) * 0.3
			flapAmp = math.sin(t * 20) * 1
			tailRate, tailAmp = 16, 0.6
		end

		local headShake = 0
		if failAt then
			headShake = math.sin(t * 40) * 0.25
			lean = math.rad(15)
		end

		-- ---------- apply ----------
		if r.bodyJoint then
			-- the mesh scales around its centre, so shift it to keep the feet planted
			r.bodyJoint.Transform = CFrame.new(0, s * 0.5 + bob + hop + sink, 0) * CFrame.Angles(lean + airLean + flipAngle, spin, 0)
		end
		if r.neck then
			r.neck.Transform = CFrame.Angles(headPitch, headYaw + headShake, 0)
		end
		if r.hipL and r.hipR then
			local plant = -(s * 0.5 + bob + sink) -- undo the body's bob so feet stay on the ground
			r.hipL.Transform = CFrame.new(0, plant + footL.X, footL.Z)
			r.hipR.Transform = CFrame.new(0, plant + footR.X, footR.Z)
		end
		if r.tail then
			r.tail.Transform = CFrame.Angles(if grounded then 0 else 0.4, math.sin(t * tailRate) * tailAmp, 0)
		end
		if r.flipL and r.flipR then
			r.flipL.Transform = CFrame.Angles(0, 0, -flapAmp)
			r.flipR.Transform = CFrame.Angles(0, 0, flapAmp)
		end
	end
end

local EmoteEvent: RemoteEvent? = nil
local lastEmote = 0

function Animator.emote(id: string)
	if not EmoteEvent or os.clock() - lastEmote < 0.6 then
		return
	end
	lastEmote = os.clock()
	EmoteEvent:FireServer(id)
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

	EmoteEvent = Net.event("Emote")
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local i = table.find(keys, input.KeyCode)
		if i then
			Animator.emote(Animator.EMOTES[i])
		end
	end)
end

return Animator
