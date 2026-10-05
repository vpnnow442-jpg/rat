-- Side-on camera for a 2.5D game.
--   overview : whole level in frame (intro, build, results)
--   follow   : you, with a little look-ahead in the direction you're moving
--   spectate : once you're out, follow whoever is still running and furthest along
-- Everything eases toward its goal so mode changes read as one smooth move.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local State = require(script.Parent.State)

local Camera = {}

local FOV = 40
local FOLLOW_DIST = 46

local cam = workspace.CurrentCamera
local focus = Vector3.new(60, 20, 0)
local dist = 100
local lookAhead = 0
local shakeAmp = 0
local spectating: Player? = nil
local failHoldUntil = 0

function Camera.shake(amount: number)
	shakeAmp = math.max(shakeAmp, amount)
end

local function levelFrame(): (Vector3?, number?)
	local level = workspace:FindFirstChild("Level")
	if not level then
		return nil, nil
	end
	local bmin = level:GetAttribute("BuildMin") :: Vector3?
	local bmax = level:GetAttribute("BuildMax") :: Vector3?
	if not bmin or not bmax then
		return nil, nil
	end
	local center = (bmin + bmax) / 2
	local w = bmax.X - bmin.X + 8
	local h = bmax.Y - bmin.Y + 8
	local vp = cam.ViewportSize
	local aspect = vp.X / math.max(vp.Y, 1)
	local t = math.tan(math.rad(FOV / 2))
	local d = math.max((h / 2) / t, (w / 2) / (t * aspect))
	return Vector3.new(center.X, center.Y, 0), d
end

local function rootOf(p: Player): BasePart?
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function pickSpectate(): Player?
	local best, bestX = nil, -math.huge
	for _, id in State.runners do
		local p = Players:GetPlayerByUserId(id)
		local r = p and rootOf(p)
		if p and r and p ~= Players.LocalPlayer and not r.Anchored and r.Position.Y > -50 then
			local fail = p.Character and p.Character:GetAttribute("FailAt")
			if not fail and r.Position.X > bestX then
				best, bestX = p, r.Position.X
			end
		end
	end
	return best
end

local function update(dt: number)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	cam.FieldOfView = FOV

	local goalFocus, goalDist = focus, dist
	local sharp = 4

	local ovFocus, ovDist = levelFrame()
	local me = rootOf(Players.LocalPlayer)
	local phase = State.phase

	if (phase == "Countdown" or phase == "Run") and me and (State.me == "running" or os.clock() < failHoldUntil) then
		local vx = me.AssemblyLinearVelocity.X
		lookAhead += (math.clamp(vx * 0.3, -7, 7) - lookAhead) * math.min(1, dt * 2)
		goalFocus = me.Position + Vector3.new(lookAhead, 3, 0)
		goalDist = FOLLOW_DIST
		sharp = if phase == "Countdown" then 3 else 9
	elseif phase == "Run" then
		if not spectating or not spectating.Parent or (spectating.Character and spectating.Character:GetAttribute("FailAt")) then
			spectating = pickSpectate()
		end
		local r = spectating and rootOf(spectating)
		if r and not r.Anchored then
			goalFocus = r.Position + Vector3.new(0, 3, 0)
			goalDist = FOLLOW_DIST + 8
			sharp = 5
		elseif ovFocus then
			goalFocus, goalDist = ovFocus, ovDist :: number
		end
	elseif phase == "Winner" then
		local level = workspace:FindFirstChild("Level")
		local flag = level and level:GetAttribute("Flag") :: Vector3?
		if flag then
			goalFocus = flag + Vector3.new(-3, 4, 0)
			goalDist = 34
			sharp = 3
		end
	elseif ovFocus then
		goalFocus, goalDist = ovFocus, ovDist :: number
		sharp = 3
	end

	local a = 1 - math.exp(-dt * sharp)
	focus = focus:Lerp(goalFocus, a)
	dist += (goalDist - dist) * a

	local shake = Vector3.zero
	if shakeAmp > 0.01 then
		shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shakeAmp
		shakeAmp *= math.exp(-dt * 14)
	end

	local eye = focus + Vector3.new(0, dist * 0.06, dist)
	cam.CFrame = CFrame.lookAt(eye + shake, focus + shake)
end

function Camera.init()
	RunService:BindToRenderStep("SprintCamera", Enum.RenderPriority.Camera.Value + 1, update)
	State.meChanged:Connect(function(me)
		if me == "dead" then
			failHoldUntil = os.clock() + 1.1 -- watch your own tumble for a beat
			Camera.shake(0.8)
		end
		spectating = nil
	end)
end

return Camera
