-- The feel of the game lives here.
--
-- We keep Roblox's own ControlModule (so keyboard, gamepad and the mobile
-- thumbstick + jump button all work for free) but override what it does
-- with the input each frame:
--   * movement is locked to the X axis (2.5D)
--   * coyote time + jump buffering so jumps never feel "eaten"
--   * one air jump ("flap"), refilled on landing or on a wall jump
--   * wall slide + wall jump when you push into a wall in the air
--   * ice keeps your momentum, honey slows you and kills the flap
--   * launch(): springs, hammers, cannons hand us a velocity and we hold
--     its horizontal speed for a moment so the humanoid can't cancel it

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Fx = require(script.Parent.FxController)
local State = require(script.Parent.State)
local Sound = require(script.Parent.SoundController)

local M = Config.Movement
local player = Players.LocalPlayer

local Movement = {}
Movement.enabled = false
Movement.windX = 0 -- horizontal push from fans this frame, set by ObjectController

local airJumpEvent = Instance.new("BindableEvent")
Movement.airJumped = airJumpEvent.Event

local root: BasePart?
local hum: Humanoid?
local controls: any

local inputX = 0
local grounded = false
local lastGrounded = 0
local jumpedSinceGround = false
local jumpWasHeld = false
local bufferedAt = -1
local airJumps = M.AirJumps
local launchUntil = 0
local launchVX = 0
local lastWallDir = 0
local wallUntil = 0
local surface: string? = nil
local lastSurface: string? = nil
local iceVX = 0
local peakFall = 0
local jetUntil = 0
local lastFlame = 0

local rayParams = RaycastParams.new()
rayParams.CollisionGroup = "Players" -- skips every character's hitbox

local function canMove(): boolean
	return Movement.enabled and root ~= nil and hum ~= nil and not (root :: BasePart).Anchored and not (hum :: Humanoid).PlatformStand
end

function Movement.launch(v: Vector3, lock: number)
	if not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
	if lock > 0 then
		launchVX = v.X
		launchUntil = os.clock() + lock
	end
	jumpedSinceGround = true
end

function Movement.root(): BasePart?
	return root
end

-- Jetpack pickup: hold jump to fly for a few seconds
function Movement.giveJetpack(seconds: number)
	jetUntil = os.clock() + seconds
end

function Movement.jetpackActive(): boolean
	return os.clock() < jetUntil
end

-- Portals: pop out the other side, keeping your speed
function Movement.teleport(pos: Vector3)
	if not root then
		return
	end
	local v = root.AssemblyLinearVelocity
	root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = v
end

local function setCharacter(c: Model)
	root = c:WaitForChild("HumanoidRootPart") :: BasePart
	hum = c:WaitForChild("Humanoid") :: Humanoid
	local h = hum :: Humanoid
	for _, st in {
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Seated,
	} do
		h:SetStateEnabled(st, false)
	end
	h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and canMove() then
			jumpedSinceGround = true
			Sound.play("jump", 0.1)
		end
	end)
end

local function onLand(now: number)
	if now - bufferedAt <= M.JumpBuffer and hum then
		hum.Jump = true
	end
	bufferedAt = -1
	if peakFall > 40 then
		Sound.play("land", 0.15)
	end
	peakFall = 0
end

-- Is the jump button held right now? Read from Roblox's ControlModule so
-- keyboard, gamepad and the mobile jump button all behave the same.
local function jumpHeld(): boolean
	local ok, held = pcall(function()
		local c = controls
		local h = false
		if c.activeController and c.activeController.GetIsJumping then
			h = c.activeController:GetIsJumping()
		end
		if c.touchJumpController and c.touchJumpController.GetIsJumping then
			h = h or c.touchJumpController:GetIsJumping()
		end
		return h
	end)
	if ok then
		return held == true
	end
	return UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
end

Movement.jumpHeld = jumpHeld

local onJumpPress: () -> ()

-- Runs right after the ControlModule, so our Move() call wins.
local function control(dt: number)
	if not hum or not root then
		return
	end
	local mv = controls and controls:GetMoveVector() or Vector3.zero
	local x = mv.X
	local ax = math.abs(x)
	if ax < 0.2 then
		x = 0
	elseif ax > 0.6 then
		x = math.sign(x)
	else
		x = math.sign(x) * (ax - 0.2) / 0.4
	end
	inputX = x

	-- A new press is the moment the button goes from up to down. (The old
	-- approach timed gaps between JumpRequest events and ate fast double-taps.)
	local held = jumpHeld()
	if held and not jumpWasHeld then
		onJumpPress()
	end
	jumpWasHeld = held

	if not canMove() then
		hum:Move(Vector3.zero)
		return
	end

	local honey = surface == "honey"
	local speed = M.WalkSpeed * (if honey then M.HoneySpeed else 1)
	hum.JumpPower = M.JumpPower * (if honey then M.HoneyJump else 1)

	local target: number
	if os.clock() < launchUntil then
		target = launchVX
	elseif surface == "ice" and grounded then
		local goal = x * speed + Movement.windX
		iceVX += (goal - iceVX) * math.min(1, dt * M.IceAccel)
		target = iceVX
	else
		target = x * speed + Movement.windX
		iceVX = root.AssemblyLinearVelocity.X
	end

	if math.abs(target) < 0.05 then
		hum.WalkSpeed = speed
		hum:Move(Vector3.zero)
	else
		hum.WalkSpeed = math.abs(target)
		hum:Move(Vector3.new(math.sign(target), 0, 0))
	end
end

local function physics(dt: number)
	if not root or not hum then
		return
	end
	if root.Anchored then
		hum.PlatformStand = false
		return
	end

	-- 2.5D lock
	local p = root.Position
	if math.abs(p.Z) > 0.001 then
		root.CFrame -= Vector3.new(0, 0, p.Z)
	end
	local v = root.AssemblyLinearVelocity
	if v.Z ~= 0 then
		v = Vector3.new(v.X, v.Y, 0)
		root.AssemblyLinearVelocity = v
	end
	if not canMove() then
		return
	end

	local now = os.clock()
	local onFloor = hum.FloorMaterial ~= Enum.Material.Air
	if onFloor then
		if not grounded then
			onLand(now)
		end
		lastGrounded = now
		airJumps = M.AirJumps
		jumpedSinceGround = false
		local hit = workspace:Raycast(p, Vector3.new(0, -3.6, 0), rayParams)
		surface = if hit then hit.Instance:GetAttribute("Surface") :: string? else nil
		lastSurface = surface
	else
		surface = nil
		peakFall = math.max(peakFall, -v.Y)
	end
	grounded = onFloor

	-- Wall slide: only while pushing into a wall in the air
	if not onFloor and inputX ~= 0 then
		local dir = math.sign(inputX)
		local hit = workspace:Raycast(p, Vector3.new(dir * 1.5, 0, 0), rayParams)
		if hit and hit.Instance.CanCollide and math.abs(hit.Normal.X) > 0.7 then
			lastWallDir = dir
			wallUntil = now + 0.1
			if v.Y < -M.WallSlideSpeed then
				root.AssemblyLinearVelocity = Vector3.new(v.X, -M.WallSlideSpeed, 0)
			end
		end
	end

	-- Jetpack: holding jump pushes you up toward a steady climb
	if now < jetUntil and jumpHeld() then
		local cur = root.AssemblyLinearVelocity
		local lift = Config.Objects.JetpackLift
		root.AssemblyLinearVelocity = Vector3.new(cur.X, cur.Y + (lift - cur.Y) * math.min(1, dt * 7), 0)
		if now - lastFlame > 0.05 then
			lastFlame = now
			Fx.puff(p - Vector3.new(0, 2.2, 0), 1, 0.5, Color3.fromRGB(255, 176, 80))
		end
	end
end

function onJumpPress()
	local now = os.clock()
	if not canMove() or not root or not hum then
		return
	end
	-- FloorMaterial lags a frame or two after take-off; trust the humanoid state too
	local st = hum:GetState()
	local airborne = not grounded or st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall
	if not airborne then
		return -- on the ground: the humanoid does the normal jump itself
	end
	local v = root.AssemblyLinearVelocity
	if now < wallUntil and lastWallDir ~= 0 then
		local away = -lastWallDir
		Movement.launch(Vector3.new(away * M.WallJumpPower.X, M.WallJumpPower.Y, 0), M.WallJumpLock)
		airJumps = M.AirJumps
		wallUntil = 0
		Sound.play("jump", 0.1)
	elseif now - lastGrounded <= M.CoyoteTime and not jumpedSinceGround then
		root.AssemblyLinearVelocity = Vector3.new(v.X, M.JumpPower, 0)
		jumpedSinceGround = true
		Sound.play("jump", 0.1)
	elseif airJumps > 0 and lastSurface ~= "honey" then
		airJumps -= 1
		root.AssemblyLinearVelocity = Vector3.new(v.X, M.AirJumpPower, 0)
		jumpedSinceGround = true
		Sound.play("airJump", 0.1)
		airJumpEvent:Fire()
	else
		bufferedAt = now
	end
end

local function tumble()
	if not root or not hum or root.Anchored then
		return
	end
	local facing = if root.CFrame.LookVector.X >= 0 then 1 else -1
	hum.PlatformStand = true
	root.AssemblyLinearVelocity = Vector3.new(-facing * 14, 40, 0)
	root.AssemblyAngularVelocity = Vector3.new(0, 0, facing * 12)
end

local function refreshEnabled()
	local was = Movement.enabled
	Movement.enabled = State.me == "running" and State.phase == "Run"
	if Movement.enabled and not was then
		launchUntil = 0
		jetUntil = 0
		airJumps = M.AirJumps
		bufferedAt = -1
		peakFall = 0
		if hum then
			hum.PlatformStand = false
		end
	end
end

function Movement.init()
	local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	controls = playerModule:GetControls()

	if player.Character then
		task.spawn(setCharacter, player.Character)
	end
	player.CharacterAdded:Connect(setCharacter)

	RunService:BindToRenderStep("SprintControl", Enum.RenderPriority.Input.Value + 1, control)
	RunService.PreSimulation:Connect(physics)

	State.phaseChanged:Connect(refreshEnabled)
	State.meChanged:Connect(function(me)
		refreshEnabled()
		if me == "dead" then
			tumble()
		end
	end)
end

return Movement
