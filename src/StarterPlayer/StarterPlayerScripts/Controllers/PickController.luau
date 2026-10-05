-- The pick box: a crate drops in, pieces pop out onto the table, and
-- everyone grabs one. First click wins. Taken pieces get the grabber's
-- colour and name stamped on them, so you see who snatched what.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)
local Style = require(Shared.Style)

local Hud = require(script.Parent.HudController)
local Sound = require(script.Parent.SoundController)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local U = Style.UI
local F = Style.Font
local W = Style.Forest
local PickEvent = Net.event("Pick")
local player = Players.LocalPlayer

local Pick = {}

type Tile = { button: TextButton, face: Frame, stamp: Frame, stampLabel: TextLabel, stroke: UIStroke, scale: UIScale, taken: number }

local gui: ScreenGui
local crate: Frame?
local tiles = {} :: { Tile }
local myPick: string? = nil

local KIND_COLOR = { route = U.Good, trap = U.Bad, tool = U.Gold }

local function speciesColor(userId: number): Color3
	local s = State.speciesOf[userId]
	local def = s and Characters.ById[s]
	return if def then def.body else U.Muted
end

local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.DisplayName else "?"
end

local function viewport(parent: Instance, id: string)
	local vp = UI.new("ViewportFrame", {
		BackgroundColor3 = U.PaperShade,
		Size = UDim2.new(1, -12, 0, 78),
		Position = UDim2.fromOffset(6, 6),
		Ambient = Color3.fromRGB(170, 166, 160),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ZIndex = 3,
		Parent = parent,
	}, { UI.corner(8) })
	local model = Objects.build(id)
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y * 1.3)
	local d = extent / 2 / math.tan(math.rad(15)) * 1.15 + size.Z / 2
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, size.Y * 0.15, d), cf.Position)
end

local function close()
	if not crate then
		return
	end
	local c = crate
	crate = nil
	table.clear(tiles)
	UI.tween(c, 0.3, { Position = UDim2.new(0.5, 0, -0.6, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.35, function()
		c:Destroy()
	end)
end

local function open(items: { any })
	close()
	myPick = nil
	local count = #items
	local cols = math.min(count, 5)
	local rows = math.ceil(count / cols)
	local tileW, tileH, gap = 116, 132, 12
	local width = cols * tileW + (cols - 1) * gap + 48
	local height = rows * tileH + (rows - 1) * gap + 96

	-- The crate: a wooden frame with a darker rim
	local holder = UI.new("Frame", {
		BackgroundColor3 = W.Wood,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, -0.6, 0),
		Size = UDim2.fromOffset(width, height),
		Parent = gui,
	}, { UI.corner(18), UI.new("UIStroke", { Color = W.WoodDark, Thickness = 5 }) })
	crate = holder
	UI.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = U.Ink,
		BackgroundTransparency = 0.8,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 8),
		ZIndex = 0,
		Parent = holder,
	}, { UI.corner(18) })
	-- plank lines on the crate face
	for i = 1, 3 do
		UI.new("Frame", {
			BackgroundColor3 = W.WoodDark,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.new(0, 0, i / 4, 0),
			ZIndex = 1,
			Parent = holder,
		})
	end
	UI.label({
		Text = "Grab a piece!",
		FontFace = F.Title,
		TextSize = 26,
		TextColor3 = U.Paper,
		Position = UDim2.fromOffset(24, 16),
		ZIndex = 2,
		Parent = holder,
	})
	UI.new("UIStroke", { Color = W.WoodDark, Thickness = 2, Parent = holder:FindFirstChildOfClass("TextLabel") })
	UI.label({
		Text = "First come, first served",
		FontFace = F.Bold,
		TextSize = 14,
		TextColor3 = U.Paper,
		TextTransparency = 0.15,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24),
		ZIndex = 2,
		Parent = holder,
	})

	local grid = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 68),
		Size = UDim2.new(1, -48, 1, -88),
		ZIndex = 2,
		Parent = holder,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(tileW, tileH),
			CellPadding = UDim2.fromOffset(gap, gap),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for i, item in items do
		local def = Objects.ById[item.id]
		local button = UI.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Selectable = true,
			ZIndex = 2,
			Parent = grid,
		})
		local scale = UI.new("UIScale", { Scale = 0, Parent = button })
		local face = UI.new("Frame", {
			BackgroundColor3 = U.Paper,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = button,
		}, { UI.corner(12) })
		local stroke = UI.new("UIStroke", { Color = U.Accent, Thickness = 0, Parent = face })
		viewport(face, item.id)
		UI.new("Frame", {
			BackgroundColor3 = KIND_COLOR[def.kind],
			Size = UDim2.fromOffset(10, 10),
			Position = UDim2.fromOffset(10, 94),
			ZIndex = 3,
			Parent = face,
		}, { UI.corner(5) })
		UI.label({
			Text = def.name,
			FontFace = F.Title,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, -30, 0, 20),
			Position = UDim2.fromOffset(24, 89),
			ZIndex = 3,
			Parent = face,
		})
		UI.label({
			Text = def.blurb,
			TextSize = 11,
			TextColor3 = U.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, -16, 0, 16),
			Position = UDim2.fromOffset(8, 110),
			ZIndex = 3,
			Parent = face,
		})

		-- "Taken" stamp, hidden until someone grabs it
		local stamp = UI.new("Frame", {
			BackgroundColor3 = U.Ink,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = face,
		}, { UI.corner(12) })
		local stampLabel = UI.label({
			Text = "",
			FontFace = F.Title,
			TextSize = 15,
			TextColor3 = U.Paper,
			BackgroundColor3 = U.Ink,
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Rotation = -8,
			ZIndex = 6,
			Parent = stamp,
		})
		UI.corner(8).Parent = stampLabel
		UI.pad(10, 4).Parent = stampLabel

		local tile: Tile = { button = button, face = face, stamp = stamp, stampLabel = stampLabel, stroke = stroke, scale = scale, taken = 0 }
		tiles[i] = tile

		button.MouseEnter:Connect(function()
			if tile.taken == 0 and not myPick then
				UI.tween(scale, 0.12, { Scale = 1.06 })
				UI.tween(stroke, 0.12, { Thickness = 3 })
				Sound.play("hover")
			end
		end)
		button.MouseLeave:Connect(function()
			UI.tween(scale, 0.12, { Scale = 1 })
			UI.tween(stroke, 0.12, { Thickness = 0 })
		end)
		button.Activated:Connect(function()
			if tile.taken ~= 0 or myPick then
				Sound.play("error")
				return
			end
			UI.tween(scale, 0.06, { Scale = 0.92 })
			PickEvent:FireServer(i)
		end)

		-- pop out of the crate one by one
		task.delay(0.25 + i * 0.07, function()
			UI.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			Sound.play("hover")
		end)
	end

	UI.tween(holder, 0.45, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
	Sound.play("crate")
	if UserInputService.GamepadEnabled and tiles[1] then
		task.delay(0.6, function()
			if tiles[1] then
				GuiService.SelectedObject = tiles[1].button
			end
		end)
	end
end

local function update(items: { any })
	for i, item in items do
		local tile = tiles[i]
		if not tile or tile.taken == item.takenBy then
			continue
		end
		tile.taken = item.takenBy
		if item.takenBy == 0 then
			continue
		end
		local mine = item.takenBy == player.UserId
		local color = speciesColor(item.takenBy)
		tile.stamp.BackgroundTransparency = if mine then 0.75 else 0.45
		tile.stampLabel.Text = if mine then "YOURS" else nameOf(item.takenBy)
		tile.stampLabel.BackgroundColor3 = if mine then U.Accent else color
		tile.stampLabel.BackgroundTransparency = 0
		tile.stampLabel.TextTransparency = 0
		tile.stroke.Color = if mine then U.Accent else color
		tile.stroke.Thickness = 3
		-- stamp slams down
		local s = UI.new("UIScale", { Scale = 1.8, Parent = tile.stampLabel })
		UI.tween(s, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.tween(tile.scale, 0.1, { Scale = 1 })
		if mine then
			myPick = items[i].id
			Sound.play("grab")
		else
			Sound.play("pick", 0.2)
		end
	end
end

function Pick.init()
	gui = UI.new("ScreenGui", {
		Name = "PickBox",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = UI.new("UIScale", { Parent = gui })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.Y / 820, vp.X / 900), 0.55, 1.1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- The box arrives just before the "Pick" phase is announced, so open on
	-- the first message and treat every later one as an update.
	Net.event("Box").OnClientEvent:Connect(function(items, pickers: { number })
		if not crate then
			-- only people in this round pick; menu-sitters just watch
			if not table.find(pickers or {}, player.UserId) then
				return
			end
			open(items)
		end
		update(items)
	end)

	State.phaseChanged:Connect(function(phase)
		if phase == "Build" then
			if myPick then
				local def = Objects.ById[myPick]
				Hud.toast("You grabbed: " .. (if def then def.name else myPick))
			end
			close()
		elseif phase ~= "Pick" then
			close()
		end
	end)
end

return Pick
