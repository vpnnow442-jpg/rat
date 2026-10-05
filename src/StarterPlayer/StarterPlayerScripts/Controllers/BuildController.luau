-- Building should take seconds:
--   pick a card -> a ghost follows your pointer, snapped to the grid,
--   green if it fits / red if not -> click to drop it. R rotates, right-click goes back.
-- You also see other builders' ghosts live, which is half the fun
-- (watching someone hover spikes over the shortcut you were planning to use).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)
local Style = require(Shared.Style)

local Camera = require(script.Parent.CameraController)
local Hud = require(script.Parent.HudController)
local Sound = require(script.Parent.SoundController)
local State = require(script.Parent.State)

local PlaceEvent = Net.event("Place")
local PlaceResult = Net.event("PlaceResult")
local Cursor = Net.unreliable("Cursor")

local Build = {}

local hand: { string }? = nil
local selected: string? = nil
local rot = 0
local ghost: Model? = nil
local highlight: Highlight? = nil
local valid = false
local reason: string? = nil
local gx, gy = 0, 0
local waiting = false
local pointer: Vector2? = nil
local stick = Vector2.zero
local lastSend = 0
local ghostFolder: Folder

type Other = { model: Model, id: string, target: CFrame }
local others = {} :: { [number]: Other }

local function makeGhost(id: string, transparency: number): Model
	local m = Objects.build(id)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Transparency = math.max(d.Transparency, transparency)
			end
		end
	end
	m.Parent = ghostFolder
	return m
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	ghost = nil
	highlight = nil
	Camera.building = false
end

local function sendCursor(id: string)
	Cursor:FireServer(id, gx, gy, rot)
end

--------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------

function Build.select(id: string)
	if waiting or not hand or not table.find(hand, id) then
		return
	end
	clearGhost()
	selected = id
	rot = 0
	ghost = makeGhost(id, 0.25)
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.7
	h.OutlineTransparency = 0.1
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = ghost
	highlight = h
	if not pointer then
		local cam = workspace.CurrentCamera
		pointer = cam.ViewportSize / 2
	end
	GuiService.SelectedObject = nil
	Camera.building = true
	Hud.setTray(false)
	Hud.setPlacing(true)
	Sound.play("pick")
end

function Build.back()
	if not selected or waiting then
		return
	end
	clearGhost()
	selected = nil
	sendCursor("")
	Hud.setPlacing(false)
	Hud.setTray(true)
	Sound.play("pick")
end

function Build.rotate()
	if not selected or waiting then
		return
	end
	rot = (rot + 90) % 360
	Sound.play("pick")
end

function Build.place()
	if not selected or waiting then
		return
	end
	if not valid then
		Sound.play("error")
		Hud.toast(reason or "Can't place there", Style.UI.Bad)
		return
	end
	waiting = true
	PlaceEvent:FireServer(selected, gx, gy, rot)
end

local function reset()
	clearGhost()
	hand = nil
	selected = nil
	waiting = false
	Hud.showHand(nil)
	Hud.setPlacing(false)
end

--------------------------------------------------------------------------
-- Pointer -> world
--------------------------------------------------------------------------

local function worldPoint(screen: Vector2): Vector3?
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
	if math.abs(ray.Direction.Z) < 1e-4 then
		return nil
	end
	local t = -ray.Origin.Z / ray.Direction.Z
	if t <= 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function update(dt: number)
	-- Smooth other builders' ghosts toward their latest reported spot
	local a = 1 - math.exp(-dt * 14)
	for _, o in others do
		o.model:PivotTo(o.model:GetPivot():Lerp(o.target, a))
	end

	if not selected or not ghost then
		return
	end
	if stick.Magnitude > 0.2 and pointer then
		local vp = workspace.CurrentCamera.ViewportSize
		local p = pointer + Vector2.new(stick.X, -stick.Y) * 900 * dt
		pointer = Vector2.new(math.clamp(p.X, 0, vp.X), math.clamp(p.Y, 0, vp.Y))
	end
	if UserInputService:GetLastInputType() == Enum.UserInputType.MouseMovement then
		pointer = UserInputService:GetMouseLocation()
	end
	if not pointer then
		return
	end

	-- The build camera follows the cursor across the level
	local vp = workspace.CurrentCamera.ViewportSize
	Camera.pointer = Vector2.new(pointer.X / math.max(vp.X, 1), pointer.Y / math.max(vp.Y, 1))

	local world = worldPoint(pointer)
	if not world then
		return
	end

	local def = Objects.ById[selected]
	gx, gy = Objects.snap(def, world.X, world.Y, rot)
	ghost:PivotTo(Objects.cframe(gx, gy, rot))
	valid, reason = Objects.check(def, gx, gy, rot)
	if highlight then
		local c = if valid then Style.UI.Good else Style.UI.Bad
		highlight.FillColor = c
		highlight.OutlineColor = c
	end

	local now = os.clock()
	if now - lastSend > 0.1 then
		lastSend = now
		sendCursor(selected)
	end
end

--------------------------------------------------------------------------
-- Other builders
--------------------------------------------------------------------------

local function nameTag(model: Model, userId: number)
	local p = Players:GetPlayerByUserId(userId)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 20)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Style.Font.Bold
	label.TextSize = 14
	label.TextColor3 = Style.UI.Paper
	label.Text = if p then p.DisplayName else "?"
	local stroke = Instance.new("UIStroke")
	stroke.Color = Style.UI.Ink
	stroke.Thickness = 1.5
	stroke.Parent = label
	label.Parent = gui
	gui.Adornee = model:FindFirstChildWhichIsA("BasePart")
	gui.Parent = model
end

local function onCursor(userId: number, id: string, x: number, y: number, r: number)
	if userId == 0 then
		for _, o in others do
			o.model:Destroy()
		end
		table.clear(others)
		return
	end
	local o = others[userId]
	if id == "" then
		if o then
			o.model:Destroy()
			others[userId] = nil
		end
		return
	end
	if not Objects.ById[id] then
		return
	end
	local target = Objects.cframe(x, y, r)
	if not o or o.id ~= id then
		if o then
			o.model:Destroy()
		end
		local m = makeGhost(id, 0.55)
		m:PivotTo(target)
		nameTag(m, userId)
		o = { model = m, id = id, target = target }
		others[userId] = o
	end
	(o :: Other).target = target
end

--------------------------------------------------------------------------

function Build.init()
	ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "Ghosts"
	ghostFolder.Parent = workspace

	Hud.actions.pick = Build.select
	Hud.actions.back = Build.back
	Hud.actions.rotate = Build.rotate
	Hud.actions.place = Build.place

	Net.event("Hand").OnClientEvent:Connect(function(newHand: { string }?)
		if newHand then
			reset()
			hand = newHand
			Hud.showHand(newHand)
			Hud.setStatus(nil)
			-- one piece from the box: go straight to placing it
			if #newHand == 1 then
				task.delay(0.35, function()
					if hand == newHand and not selected then
						Build.select(newHand[1])
					end
				end)
			end
		else
			local hadHand = hand ~= nil
			reset()
			if hadHand and State.phase == "Build" then
				Hud.setStatus("Placed! Waiting for the others...")
			end
		end
	end)

	PlaceResult.OnClientEvent:Connect(function(ok: boolean, why: string?)
		waiting = false
		if ok then
			clearGhost()
			selected = nil
			Hud.setPlacing(false)
		else
			Sound.play("error")
			Hud.toast(why or "Can't place there", Style.UI.Bad)
		end
	end)

	Cursor.OnClientEvent:Connect(onCursor)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not selected then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			if not processed then
				pointer = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
			end
			return
		end
		if processed then
			return
		end
		local k = input.KeyCode
		if t == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonA then
			Build.place()
		elseif t == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.Q or k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB then
			Build.back()
		elseif k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonX then
			Build.rotate()
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch and selected and not processed then
			pointer = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return Build
