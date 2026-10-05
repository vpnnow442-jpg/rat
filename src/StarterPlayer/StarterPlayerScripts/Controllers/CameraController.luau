-- Side-on camera for a 2.5D game.
--   menu     : the level drifts slowly by behind the menu
--   overview : whole level in frame (intro, pick, results)
--   build    : zoomed in and the map follows your cursor: cursor on the left of the
--              screen shows the left of the level, right shows the right. Wheel/pinch zooms.
--   follow   : you, with a little look-ahead in the direction you're moving
--   spectate : once you're out, whoever is still running and furthest along
-- Everything eases toward its goal, so mode changes read as one smooth move.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.State)

local Camera = {}

-- Set by BuildController while you're placing
Camera.building = false
Camera.pointer = Vector2.new(0.5, 0.5) -- cursor position on screen, 0..1
Camera.menuOpen = false

local FOV = 40
local FOLLOW_DIST = 46
local BUILD_MIN, BUILD_DEFAULT = 34, 72

local cam = workspace.CurrentCamera
local focus = Vector3.new(100, 20, 0)
local dist = 120
local lookAhead = 0
local shakeAmp = 0
local spectating: Player? = nil
local failHoldUntil = 0
local buildDist = BUILD_DEFAULT

function Camera.shake(amount: number)
	shakeAmp = math.max(shakeAmp, amount)
end

local function bounds(): (Vector3?, Vector3?)
	local level = workspace:FindFirstChild("Level")
	if not level then
		return nil, nil
	end
	return level:GetAttribute("BuildMin") :: Vector3?, level:GetAttribute("BuildMax") :: Vector3?
end

local function levelFrame(): (Vector3?, number?)
	local bmin, bmax = bounds()
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
	elseif phase == "Build" and Camera.building and ovFocus then
		-- Map the cursor's spot on screen onto the whole level. Because this
		-- depends on screen position (not the world point under the cursor),
		-- holding the mouse still always settles: no runaway scrolling.
		local bmin, bmax = bounds()
		buildDist = math.clamp(buildDist, BUILD_MIN, ovDist :: number)
		if bmin and bmax then
			local vp = cam.ViewportSize
			local halfH = buildDist * math.tan(math.rad(FOV / 2))
			local halfW = halfH * vp.X / math.max(vp.Y, 1)
			local function span(lo: number, hi: number, half: number, t: number): number
				local a, b = lo + half * 0.4, hi - half * 0.4
				if a > b then
					return (lo + hi) / 2
				end
				return a + (b - a) * math.clamp(t, 0, 1)
			end
			local n = Camera.pointer
			goalFocus = Vector3.new(span(bmin.X, bmax.X, halfW, n.X), span(bmin.Y, bmax.Y, halfH, 1 - n.Y), 0)
		end
		goalDist = buildDist
		sharp = 5
	elseif phase == "Winner" then
		local level = workspace:FindFirstChild("Level")
		local flag = level and level:GetAttribute("Flag") :: Vector3?
		if flag then
			goalFocus = flag + Vector3.new(-3, 4, 0)
			goalDist = 34
			sharp = 3
		end
	elseif (phase == "Waiting" or Camera.menuOpen) and ovFocus then
		-- slow drift across the level behind the menu
		local bmin, bmax = bounds()
		local span = if bmin and bmax then (bmax.X - bmin.X) * 0.3 else 40
		goalFocus = (ovFocus :: Vector3) + Vector3.new(math.sin(os.clock() * 0.07) * span, -4, 0)
		goalDist = (ovDist :: number) * 0.5
		sharp = 1.5
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
	RunService:BindToRenderStep("ChaosCamera", Enum.RenderPriority.Camera.Value + 1, update)
	State.meChanged:Connect(function(me)
		if me == "dead" then
			failHoldUntil = os.clock() + 1.1 -- watch your own tumble for a beat
			Camera.shake(0.8)
		end
		spectating = nil
	end)
	State.phaseChanged:Connect(function(phase)
		if phase == "Build" then
			buildDist = BUILD_DEFAULT
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or State.phase ~= "Build" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			buildDist *= if input.Position.Z > 0 then 0.88 else 1.14
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale, _, _, processed)
		if not processed and State.phase == "Build" then
			buildDist /= math.clamp(scale, 0.95, 1.05)
		end
	end)
end

return Camera
