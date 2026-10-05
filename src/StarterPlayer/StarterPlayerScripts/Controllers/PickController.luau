-- The pick box. Your whole screen becomes the inside of a wooden crate with
-- 4-7 pieces tossed in at odd angles. No descriptions: you see the object,
-- you grab it. First click wins. Whatever someone else grabs gets yanked
-- out of the crate with their name on it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)
local Style = require(Shared.Style)

local Sound = require(script.Parent.SoundController)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local U = Style.UI
local F = Style.Font
local W = Style.Forest
local PickEvent = Net.event("Pick")
local player = Players.LocalPlayer

local Pick = {}

type Item = {
	button: TextButton,
	vp: ViewportFrame,
	scale: UIScale,
	name: TextLabel,
	shadow: Frame,
	home: UDim2,
	tilt: number,
	taken: number,
}

local gui: ScreenGui
local crate: Frame?
local timerLabel: TextLabel?
local items = {} :: { Item }
local myPick: number? = nil

local PLANK_A = Color3.fromRGB(186, 138, 90)
local PLANK_B = Color3.fromRGB(176, 128, 82)

local function speciesColor(userId: number): Color3
	local s = State.speciesOf[userId]
	local def = s and Characters.ById[s]
	return if def then def.body else U.Muted
end

local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.DisplayName else "Someone"
end

local function fill(vp: ViewportFrame, id: string)
	local model = Objects.build(id)
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y)
	local d = extent / 2 / math.tan(math.rad(15)) * 1.25 + size.Z / 2
	-- slightly from above, like looking down into a box
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, d * 0.35, d), cf.Position)
end

-- Spread n items over the crate floor: a loose grid with jitter, so nothing overlaps
local function scatter(n: number, seed: number): { Vector2 }
	local rng = Random.new(seed)
	local rows = if n <= 4 then 1 else 2
	local cols = math.ceil(n / rows)
	local spots = {}
	for i = 1, n do
		local r = math.floor((i - 1) / cols)
		local c = (i - 1) % cols
		local inRow = if r == rows - 1 then n - cols * (rows - 1) else cols
		local x = 0.12 + 0.76 * ((c + 0.5) / inRow)
		local y = if rows == 1 then 0.55 else 0.4 + r * 0.32
		x += rng:NextNumber(-0.04, 0.04)
		y += rng:NextNumber(-0.05, 0.05)
		spots[i] = Vector2.new(x, y)
	end
	return spots
end

local function close()
	if not crate then
		return
	end
	local c = crate
	crate = nil
	timerLabel = nil
	table.clear(items)
	UI.tween(c, 0.35, { Position = UDim2.fromScale(0, 1.1) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.4, function()
		c:Destroy()
	end)
end

local function open(list: { any }, seed: number)
	close()
	myPick = nil

	local root = UI.new("Frame", {
		BackgroundColor3 = PLANK_A,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, -1.1),
		Parent = gui,
	})
	crate = root

	-- Planks: alternating shades with thin dark gaps
	local planks = 7
	for i = 0, planks - 1 do
		UI.new("Frame", {
			BackgroundColor3 = if i % 2 == 0 then PLANK_A else PLANK_B,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1 / planks),
			Position = UDim2.fromScale(0, i / planks),
			Parent = root,
		})
		UI.new("Frame", {
			BackgroundColor3 = W.WoodDark,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 3),
			Position = UDim2.fromScale(0, i / planks),
			Parent = root,
		})
	end
	-- Crate walls: a dark frame around the edge
	for _, spec in {
		{ UDim2.new(1, 0, 0, 22), UDim2.fromScale(0, 0) },
		{ UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 1, -22) },
		{ UDim2.new(0, 22, 1, 0), UDim2.fromScale(0, 0) },
		{ UDim2.new(0, 22, 1, 0), UDim2.new(1, -22, 0, 0) },
	} do
		UI.new("Frame", { BackgroundColor3 = W.WoodDark, BorderSizePixel = 0, Size = spec[1], Position = spec[2], ZIndex = 2, Parent = root })
	end

	local title = UI.label({
		Text = "Grab one!",
		FontFace = F.Title,
		TextSize = 40,
		TextColor3 = U.Paper,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		ZIndex = 3,
		Parent = root,
	})
	UI.new("UIStroke", { Color = W.WoodDark, Thickness = 3, Parent = title })
	local timer = UI.label({
		Text = "",
		FontFace = F.Title,
		TextSize = 22,
		TextColor3 = U.Paper,
		TextTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		ZIndex = 3,
		Parent = root,
	})
	UI.new("UIStroke", { Color = W.WoodDark, Thickness = 2, Parent = timer })
	timerLabel = timer

	local spots = scatter(#list, seed)
	local rng = Random.new(seed + 1)
	for i, entry in list do
		local def = Objects.ById[entry.id]
		local pos = UDim2.fromScale(spots[i].X, spots[i].Y)
		local tilt = rng:NextNumber(-22, 22)

		-- soft shadow on the crate floor
		local shadow = UI.new("Frame", {
			BackgroundColor3 = U.Ink,
			BackgroundTransparency = 0.78,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos + UDim2.fromScale(0.01, 0.11),
			Size = UDim2.fromScale(0.14, 0.035),
			ZIndex = 3,
			Parent = root,
		}, { UI.corner(999) })

		local button = UI.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromScale(0.26, 0.26),
			Rotation = tilt,
			Selectable = true,
			ZIndex = 4,
			Parent = root,
		}, { UI.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }) })
		local scale = UI.new("UIScale", { Scale = 0, Parent = button })
		local vp = UI.new("ViewportFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Ambient = Color3.fromRGB(176, 168, 158),
			LightColor = Color3.fromRGB(255, 248, 236),
			LightDirection = Vector3.new(-0.3, -1, -0.5),
			ZIndex = 4,
			Parent = button,
		})
		fill(vp, entry.id)
		local name = UI.label({
			Text = def.name,
			FontFace = F.Title,
			TextSize = 20,
			TextColor3 = U.Paper,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.9),
			ZIndex = 5,
			Parent = button,
		})
		local nameStroke = UI.new("UIStroke", { Color = U.Ink, Thickness = 2, Transparency = 1, Parent = name })

		local item: Item = { button = button, vp = vp, scale = scale, name = name, shadow = shadow, home = pos, tilt = tilt, taken = 0 }
		items[i] = item

		local function hover(on: boolean)
			if item.taken ~= 0 or myPick then
				return
			end
			UI.tween(scale, 0.15, { Scale = if on then 1.12 else 1 }, Enum.EasingStyle.Back)
			UI.tween(button, 0.15, { Rotation = if on then 0 else tilt })
			UI.tween(name, 0.12, { TextTransparency = if on then 0 else 1 })
			UI.tween(nameStroke, 0.12, { Transparency = if on then 0 else 1 })
			if on then
				Sound.play("hover")
			end
		end
		button.MouseEnter:Connect(function()
			hover(true)
		end)
		button.MouseLeave:Connect(function()
			hover(false)
		end)
		button.SelectionGained:Connect(function()
			hover(true)
		end)
		button.SelectionLost:Connect(function()
			hover(false)
		end)
		button.Activated:Connect(function()
			if item.taken ~= 0 or myPick then
				Sound.play("error")
				return
			end
			UI.tween(scale, 0.06, { Scale = 0.9 })
			PickEvent:FireServer(i)
		end)

		-- tumble into the crate one after another
		task.delay(0.35 + i * 0.08, function()
			UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			Sound.play("hover", 0.3)
		end)
	end

	UI.tween(root, 0.45, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Quad)
	Sound.play("crate")
	if UserInputService.GamepadEnabled and items[1] then
		task.delay(0.8, function()
			if items[1] then
				GuiService.SelectedObject = items[1].button
			end
		end)
	end
end

local function update(list: { any })
	for i, entry in list do
		local item = items[i]
		if not item or item.taken == entry.takenBy or entry.takenBy == 0 then
			continue
		end
		item.taken = entry.takenBy
		UI.tween(item.name, 0.1, { TextTransparency = 1 })
		item.shadow.Visible = false

		if entry.takenBy == player.UserId then
			-- yours: lift it out toward you and keep it front and centre
			myPick = i
			Sound.play("grab")
			item.button.ZIndex = 8
			item.vp.ZIndex = 8
			UI.tween(item.button, 0.4, { Position = UDim2.fromScale(0.5, 0.86), Rotation = 0 }, Enum.EasingStyle.Back)
			UI.tween(item.scale, 0.4, { Scale = 0.8 }, Enum.EasingStyle.Back)
			for _, other in items do
				if other ~= item and other.taken == 0 then
					UI.tween(other.vp, 0.2, { ImageTransparency = 0.45 })
				end
			end
		else
			-- someone else's: a name tag pops, then it's yanked out of the crate
			Sound.play("pick", 0.2)
			local tag = UI.pill(nameOf(entry.takenBy), speciesColor(entry.takenBy), U.Paper, 16)
			tag.AnchorPoint = Vector2.new(0.5, 0.5)
			tag.Position = item.home
			tag.ZIndex = 9
			tag.Parent = item.button.Parent
			local s = UI.new("UIScale", { Scale = 1.8, Parent = tag })
			UI.tween(s, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			UI.tween(item.button, 0.5, { Position = item.home - UDim2.fromScale(0, 0.7), Rotation = item.tilt * 3 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(1.2, function()
				if tag.Parent then
					UI.tween(tag, 0.3, { BackgroundTransparency = 1 })
					local l = tag:FindFirstChildOfClass("TextLabel")
					if l then
						UI.tween(l, 0.3, { TextTransparency = 1 })
					end
				end
			end)
		end
	end
end

function Pick.init()
	gui = UI.new("ScreenGui", {
		Name = "PickBox",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- The box arrives just before the "Pick" phase is announced, so open on
	-- the first message and treat every later one as an update.
	Net.event("Box").OnClientEvent:Connect(function(list, pickers: { number }, seed: number?)
		if not crate then
			-- only people in this round pick; menu-sitters just watch the level
			if not table.find(pickers or {}, player.UserId) then
				return
			end
			open(list, seed or 1)
		end
		update(list)
	end)

	RunService.Heartbeat:Connect(function()
		if timerLabel and State.phase == "Pick" then
			timerLabel.Text = tostring(math.ceil(State.timeLeft()))
		end
	end)

	State.phaseChanged:Connect(function(phase)
		if phase ~= "Pick" then
			if phase == "Build" and crate then
				task.delay(0.1, close)
			else
				close()
			end
		end
	end)
end

return Pick
