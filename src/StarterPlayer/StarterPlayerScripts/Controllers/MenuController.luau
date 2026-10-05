-- Main menu + party screen. Shown over the live level drifting by behind it.
--
-- Public server: PLAY joins the next round. CREATE PARTY makes a private room
-- with a 5-letter code. JOIN WITH CODE hops into a friend's room.
-- Party server : the code, who's here, INVITE, and START (host only).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Net = require(Shared.Net)
local Style = require(Shared.Style)

local Camera = require(script.Parent.CameraController)
local Hud = require(script.Parent.HudController)
local Sound = require(script.Parent.SoundController)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local U = Style.UI
local F = Style.Font
local LobbyFn = Net.func("Lobby")
local player = Players.LocalPlayer

local Menu = {}

local gui: ScreenGui
local column: Frame
local content: Frame
local message: TextLabel
local visible = false
local busy = false
local renderedKey = ""

local function call(action: string, arg: any?): boolean
	if busy then
		return false
	end
	busy = true
	local ok, result = pcall(function()
		return LobbyFn:InvokeServer(action, arg)
	end)
	busy = false
	if not ok or typeof(result) ~= "table" then
		Menu.say("Something went wrong. Try again.", true)
		return false
	end
	if not result.ok then
		Menu.say(result.err or "Couldn't do that", true)
		Sound.play("error")
		return false
	end
	return true
end

function Menu.say(text: string, bad: boolean?)
	message.Text = text
	message.TextColor3 = if bad then U.Bad else U.InkSoft
	message.TextTransparency = 0
	local t = os.clock()
	message:SetAttribute("T", t)
	task.delay(3.5, function()
		if message:GetAttribute("T") == t then
			UI.tween(message, 0.3, { TextTransparency = 1 })
		end
	end)
end

--------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------

local function button(text: string, sub: string?, primary: boolean, order: number, onClick: () -> ()): TextButton
	local b = UI.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if primary then U.Accent else U.Paper,
		Size = UDim2.new(1, -8, 0, if sub then 58 else 48),
		LayoutOrder = order,
		Parent = content,
	}, { UI.corner(14) })
	if not primary then
		UI.new("UIStroke", { Color = U.Ink, Transparency = 0.8, Thickness = 2, Parent = b })
	end
	UI.label({
		Text = text,
		FontFace = F.Title,
		TextSize = if primary then 24 else 19,
		TextColor3 = if primary then U.Paper else U.Ink,
		Position = UDim2.fromOffset(18, if sub then 8 else 12),
		Parent = b,
	})
	if sub then
		UI.label({
			Text = sub,
			TextSize = 13,
			TextColor3 = if primary then U.Paper else U.Muted,
			TextTransparency = if primary then 0.15 else 0,
			Position = UDim2.fromOffset(18, 34),
			Parent = b,
		})
	end
	UI.pressable(b, function()
		Sound.play("pick")
		onClick()
	end)
	return b
end

local function heading(text: string, order: number)
	UI.label({ Text = text, FontFace = F.Bold, TextSize = 13, TextColor3 = U.Muted, LayoutOrder = order, Parent = content })
end

local function animalPicker(order: number)
	heading("YOUR ANIMAL", order)
	local row = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 74),
		LayoutOrder = order + 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Horizontal, 8) })
	local mine = State.speciesOf[player.UserId]
	for i, s in Characters.List do
		local tile = UI.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = U.PaperShade,
			Size = UDim2.fromOffset(70, 74),
			LayoutOrder = i,
			Parent = row,
		}, { UI.corner(12) })
		local stroke = UI.new("UIStroke", { Color = U.Accent, Thickness = if s.id == mine then 3 else 0, Parent = tile })
		local vp = UI.new("ViewportFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -16),
			Ambient = Color3.fromRGB(180, 176, 170),
			LightColor = Color3.fromRGB(255, 250, 240),
			LightDirection = Vector3.new(-0.5, -1, 0.4),
			Parent = tile,
		})
		local model = Characters.build(s.id)
		model.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.Parent = vp
		vp.CurrentCamera = cam
		local cf = (model.PrimaryPart :: BasePart).CFrame
		-- three-quarter view of the face (faces point toward local -Z)
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(6, 2.2, -8), cf.Position + Vector3.new(0, 0.2, 0))
		UI.label({
			Text = s.name,
			FontFace = F.Bold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Parent = tile,
		})
		UI.pressable(tile, function()
			Sound.play("pick")
			if call("species", s.id) then
				stroke.Thickness = 3
			end
		end)
	end
end

local function codeEntry(order: number)
	local row = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = order,
		Parent = content,
	})
	local box = UI.new("TextBox", {
		Text = "",
		PlaceholderText = "ROOM CODE",
		ClearTextOnFocus = false,
		FontFace = F.Title,
		TextSize = 22,
		TextColor3 = U.Ink,
		PlaceholderColor3 = U.Muted,
		BackgroundColor3 = U.Paper,
		Size = UDim2.new(1, -86, 1, 0),
		Parent = row,
	}, { UI.corner(14), UI.new("UIStroke", { Color = U.Ink, Transparency = 0.8, Thickness = 2 }) })
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = box.Text:upper():gsub("[^%w]", ""):sub(1, 5)
		if clean ~= box.Text then
			box.Text = clean
		end
	end)
	local go = UI.new("TextButton", {
		Text = "Join",
		FontFace = F.Title,
		TextSize = 19,
		TextColor3 = U.Paper,
		BackgroundColor3 = U.InkSoft,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 78, 1, 0),
		Parent = row,
	}, { UI.corner(14) })
	local function submit()
		if #box.Text ~= 5 then
			Menu.say("Codes are 5 letters", true)
			return
		end
		Menu.say("Joining " .. box.Text .. "...")
		call("join", box.Text)
	end
	UI.pressable(go, submit)
	box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
end

--------------------------------------------------------------------------
-- Screens
--------------------------------------------------------------------------

local function clear()
	for _, c in content:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function publicScreen()
	clear()
	button("Play", "Jump into the next round", true, 1, function()
		if call("play") then
			Sound.play("go")
		end
	end)
	button("Create party", "Private room with a code for friends", false, 2, function()
		Menu.say("Creating your party...")
		call("create")
	end)
	heading("HAVE A CODE?", 3)
	codeEntry(4)
	animalPicker(5)
end

local function partyScreen()
	clear()
	local L = State.lobby
	local isHost = L.hostId == player.UserId

	heading("PARTY CODE", 1)
	UI.label({
		Text = (L.code or "-----"):gsub(".", "%0 "):sub(1, -2),
		FontFace = F.Title,
		TextSize = 44,
		TextColor3 = U.Accent,
		LayoutOrder = 2,
		Parent = content,
	})
	UI.label({ Text = "Friends type this in to join you", TextSize = 13, TextColor3 = U.Muted, LayoutOrder = 3, Parent = content })

	heading("IN THE PARTY (" .. #L.members .. ")", 4)
	local list = UI.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 5,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 4) })
	for i, m in L.members do
		local row = UI.new("Frame", {
			BackgroundColor3 = U.PaperShade,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = i,
			Parent = list,
		}, { UI.corner(9) })
		local s = m.species and Characters.ById[m.species]
		UI.new("Frame", {
			BackgroundColor3 = if s then s.body else U.Muted,
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromOffset(10, 9),
			Parent = row,
		}, { UI.corner(7) })
		UI.label({ Text = m.name, FontFace = F.Bold, TextSize = 15, Position = UDim2.fromOffset(32, 6), Parent = row })
		if m.userId == L.hostId then
			local tag = UI.pill("HOST", U.Gold, U.Ink, 11)
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(1, -8, 0.5, 0)
			tag.Parent = row
		end
	end

	if isHost then
		button("Start match", "Everyone here plays", true, 6, function()
			if call("start") then
				Sound.play("go")
			end
		end)
	else
		UI.label({ Text = "Waiting for the host to start...", FontFace = F.Bold, TextSize = 15, TextColor3 = U.InkSoft, LayoutOrder = 6, Parent = content })
	end
	button("Invite friends", nil, false, 7, function()
		local ok = pcall(function()
			if not SocialService:CanSendGameInviteAsync(player) then
				error("can't invite")
			end
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = "Join my Chaos Course party!"
			options.LaunchData = L.code or ""
			SocialService:PromptGameInvite(player, options)
		end)
		if not ok then
			Menu.say("Invites aren't available here. Share the code instead!", true)
		end
	end)
	animalPicker(8)
	local leave = button("Leave party", nil, false, 10, function()
		Menu.say("Heading back...")
		call("leave")
	end)
	leave.Size = UDim2.new(1, 0, 0, 40)
end

--------------------------------------------------------------------------

local function shouldShow(): boolean
	local L = State.lobby
	if L.mode == "party" then
		return not L.inMatch
	end
	return not State.queued()
end

local function refresh()
	local show = shouldShow()
	local L = State.lobby
	-- only rebuild when something visible actually changed
	local key = L.mode .. tostring(L.code) .. tostring(L.hostId) .. #L.members .. tostring(State.speciesOf[player.UserId])
	for _, m in L.members do
		key ..= m.name .. tostring(m.species)
	end
	if show and key ~= renderedKey then
		renderedKey = key
		if L.mode == "party" then
			partyScreen()
		else
			publicScreen()
		end
	end

	if show ~= visible then
		visible = show
		Camera.menuOpen = show
		Hud.setVisible(not show)
		if show then
			gui.Enabled = true
			column.Position = UDim2.new(0, -460, 0.5, 0)
			UI.tween(column, 0.45, { Position = UDim2.new(0, 48, 0.5, 0) }, Enum.EasingStyle.Back)
		else
			UI.tween(column, 0.3, { Position = UDim2.new(0, -460, 0.5, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(0.3, function()
				if not visible then
					gui.Enabled = false
				end
			end)
		end
	end
end

local function buildGui()
	gui = UI.new("ScreenGui", {
		Name = "Menu",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = UI.new("UIScale", { Parent = gui })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(vp.Y / 860, 0.6, 1.15)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local holder, face = UI.card({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -460, 0.5, 0),
		Size = UDim2.fromOffset(400, 680),
		Parent = gui,
	}, 22)
	column = holder

	-- Logo: two words, slight tilt, hard shadow. No gradients, no glow.
	local logo = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(340, 120),
		Position = UDim2.fromOffset(30, 22),
		Rotation = -3,
		Parent = face,
	})
	for _, spec in { { "Chaos", U.Accent, 0 }, { "Course", U.Ink, 54 } } do
		UI.label({ Text = spec[1], FontFace = F.Title, TextSize = 60, TextColor3 = U.Ink, TextTransparency = 0.85, Position = UDim2.fromOffset(3, spec[3] + 4), Parent = logo })
		UI.label({ Text = spec[1], FontFace = F.Title, TextSize = 60, TextColor3 = spec[2], Position = UDim2.fromOffset(0, spec[3]), Parent = logo })
	end
	local dots = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 14),
		Position = UDim2.fromOffset(34, 150),
		Parent = face,
	}, { UI.list(Enum.FillDirection.Horizontal, 6) })
	for _, s in Characters.List do
		UI.new("Frame", { BackgroundColor3 = s.body, Size = UDim2.fromOffset(14, 14), Parent = dots }, { UI.corner(7) })
	end
	UI.label({
		Text = "Build the course. Ruin it for your friends. Race it.",
		TextSize = 14,
		TextColor3 = U.Muted,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(340, 20),
		Position = UDim2.fromOffset(32, 172),
		Parent = face,
	})

	content = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(30, 206),
		Size = UDim2.new(1, -52, 1, -250),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = U.Muted,
		Parent = face,
	}, { UI.list(Enum.FillDirection.Vertical, 10), UI.pad(2, 4) })

	message = UI.label({
		Text = "",
		FontFace = F.Bold,
		TextSize = 14,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, -60, 0, 32),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 30, 1, -12),
		Parent = face,
	})
end

function Menu.init()
	buildGui()
	-- wait for the loading screen to finish (or give up after a while)
	local waited = 0
	while not player:GetAttribute("Loaded") and waited < 12 do
		waited += task.wait(0.1)
	end
	State.lobbyChanged:Connect(refresh)
	refresh()
end

return Menu
