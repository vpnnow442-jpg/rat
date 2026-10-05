-- Everything on screen. Rule of thumb: during a run, only the timer and a
-- small score list are visible. Big moments get a short centred banner,
-- then get out of the way.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Objects = require(Shared.Objects)
local Style = require(Shared.Style)

local Animator = require(script.Parent.CharacterAnimator)
local Fx = require(script.Parent.FxController)
local ResultsUI = require(script.Parent.ResultsUI)
local State = require(script.Parent.State)
local Sound = require(script.Parent.SoundController)
local UI = require(script.Parent.UI)

local U = Style.UI
local F = Style.Font
local player = Players.LocalPlayer

local Hud = {}

-- Wired up by BuildController
Hud.actions = {
	pick = function(_id: string) end,
	rotate = function() end,
	back = function() end,
	place = function() end,
}

local PHASES = {
	Waiting = { "WAITING", U.Muted },
	Intro = { "GET READY", U.InkSoft },
	Pick = { "PICK", U.Gold },
	Build = { "BUILD", U.Accent },
	Countdown = { "READY", U.Gold },
	Run = { "RUN", U.Good },
	Results = { "RESULTS", U.InkSoft },
	Winner = { "WINNER", U.Gold },
}

local KIND = {
	route = { "ROUTE", U.Good },
	trap = { "TRAP", U.Bad },
	tool = { "TOOL", U.Gold },
}

local CAUSE = {
	spikes = "got spiked by",
	saw = "got sawed by",
	laser = "got zapped by",
	darts = "got darted by",
	puck = "got pucked by",
	plane = "got paper-planed by",
	fall = "fell in the river",
	time = "ran out of time",
}

local gui: ScreenGui
local uiScale: UIScale
local roundLabel: TextLabel
local phaseChip: Frame
local phaseText: TextLabel
local timerLabel: TextLabel
local feedFrame: Frame
local centerLabel: TextLabel
local subLabel: TextLabel
local tray: Frame
local hint: TextLabel
local touchBar: Frame
local statusLabel: TextLabel
local toastFrame: Frame
local toastLabel: TextLabel

local bannerToken = 0
local lastTick = -1

local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.DisplayName else "Someone"
end

--------------------------------------------------------------------------
-- Banners & toasts
--------------------------------------------------------------------------

local function banner(text: string, sub: string?, hold: number, size: number?)
	bannerToken += 1
	local token = bannerToken
	centerLabel.Text = text
	centerLabel.TextSize = size or 54
	subLabel.Text = sub or ""
	centerLabel.TextTransparency = 0
	subLabel.TextTransparency = 0
	local stroke = centerLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Transparency = 0
	local s = centerLabel:FindFirstChildOfClass("UIScale") :: UIScale
	s.Scale = 0.6
	UI.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(hold, function()
		if token ~= bannerToken then
			return
		end
		UI.tween(centerLabel, 0.25, { TextTransparency = 1 })
		UI.tween(subLabel, 0.25, { TextTransparency = 1 })
		UI.tween(stroke, 0.25, { Transparency = 1 })
	end)
end

function Hud.toast(text: string, color: Color3?)
	toastLabel.Text = text
	toastFrame.BackgroundColor3 = color or U.Ink
	toastFrame.Visible = true
	toastFrame.BackgroundTransparency = 0
	toastLabel.TextTransparency = 0
	local token = os.clock()
	toastFrame:SetAttribute("Token", token)
	task.delay(2, function()
		if toastFrame:GetAttribute("Token") == token then
			UI.tween(toastFrame, 0.3, { BackgroundTransparency = 1 })
			UI.tween(toastLabel, 0.3, { TextTransparency = 1 })
		end
	end)
end

local function feed(text: string, color: Color3)
	local row = UI.new("Frame", {
		BackgroundColor3 = U.Paper,
		BackgroundTransparency = 0.05,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		Parent = feedFrame,
	}, { UI.corner(8), UI.pad(10, 5) })
	UI.new("Frame", {
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(4, 16),
		Position = UDim2.fromOffset(-6, 0),
		Parent = row,
	}, { UI.corner(2) })
	UI.label({ Text = text, TextSize = 14, FontFace = F.Bold, Parent = row })
	local rows = {}
	for _, c in feedFrame:GetChildren() do
		if c:IsA("Frame") then
			table.insert(rows, c)
		end
	end
	if #rows > 3 then
		rows[1]:Destroy()
	end
	task.delay(3.5, function()
		if row.Parent then
			row:Destroy()
		end
	end)
end

--------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------

local function fitViewport(vp: ViewportFrame, model: Model)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y * 1.3)
	local d = extent / 2 / math.tan(math.rad(15)) * 1.1 + size.Z / 2
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, size.Y * 0.15, d), cf.Position)
end

local function makeCard(id: string, order: number): TextButton
	local def = Objects.ById[id]
	local button = UI.new("TextButton", {
		Name = id,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(156, 150),
		LayoutOrder = order,
		Selectable = true,
	})
	local holder, face = UI.card({ Size = UDim2.fromScale(1, 1), Parent = button }, 14)

	local vp = UI.new("ViewportFrame", {
		BackgroundColor3 = U.PaperShade,
		Size = UDim2.new(1, -16, 0, 100),
		Position = UDim2.fromOffset(8, 8),
		Ambient = Color3.fromRGB(170, 166, 160),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ZIndex = 2,
		Parent = face,
	}, { UI.corner(10) })
	local model = Objects.build(id)
	model.Parent = vp
	fitViewport(vp, model)

	local kind = KIND[def.kind]
	local tag = UI.pill(kind[1], kind[2], U.Paper, 11)
	tag.Position = UDim2.fromOffset(14, 14)
	tag.ZIndex = 3
	tag.Parent = face

	UI.label({
		Text = def.name,
		FontFace = F.Title,
		TextSize = 19,
		Position = UDim2.fromOffset(12, 114),
		ZIndex = 2,
		Parent = face,
	})

	local stroke = UI.new("UIStroke", { Color = U.Accent, Thickness = 0, Parent = face })
	button.MouseEnter:Connect(function()
		UI.tween(holder, 0.12, { Position = UDim2.fromOffset(0, -6) })
		UI.tween(stroke, 0.12, { Thickness = 3 })
	end)
	button.MouseLeave:Connect(function()
		UI.tween(holder, 0.12, { Position = UDim2.fromOffset(0, 0) })
		UI.tween(stroke, 0.12, { Thickness = 0 })
	end)
	button.SelectionGained:Connect(function()
		UI.tween(stroke, 0.12, { Thickness = 3 })
	end)
	button.SelectionLost:Connect(function()
		UI.tween(stroke, 0.12, { Thickness = 0 })
	end)
	button.Activated:Connect(function()
		Hud.actions.pick(id)
	end)
	return button
end

function Hud.showHand(hand: { string }?)
	for _, c in tray:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	if not hand then
		tray.Visible = false
		return
	end
	local first: TextButton? = nil
	for i, id in hand do
		local card = makeCard(id, i)
		card.Parent = tray
		first = first or card
	end
	Hud.setTray(true)
	if UserInputService.GamepadEnabled and first then
		GuiService.SelectedObject = first
	end
end

function Hud.setTray(visible: boolean)
	if visible then
		tray.Visible = true
		tray.Position = UDim2.new(0.5, 0, 1, 220)
		UI.tween(tray, 0.3, { Position = UDim2.new(0.5, 0, 1, -18) }, Enum.EasingStyle.Back)
	else
		UI.tween(tray, 0.2, { Position = UDim2.new(0.5, 0, 1, 220) }).Completed:Once(function()
			if tray.Position.Y.Offset > 100 then
				tray.Visible = false
			end
		end)
	end
end

function Hud.setPlacing(on: boolean)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	hint.Text = if pad
		then "A  place     X  rotate     B  back"
		else "Click  place     R  rotate     Right-click  back"
	hint.Visible = on and not touch
	touchBar.Visible = on and touch
end

function Hud.setStatus(text: string?)
	statusLabel.Text = text or ""
	statusLabel.Visible = text ~= nil
end

--------------------------------------------------------------------------
-- Results / winner: the score table (see ResultsUI)
--------------------------------------------------------------------------

local function showResults(results)
	local verdict = results.verdict
	ResultsUI.show(results.rows, {
		title = if verdict then "Round " .. State.round else "Round " .. State.round .. " results",
		subtitle = if verdict == "TOO_EASY" then "Everyone made it, so nobody scores. Build meaner."
			elseif verdict == "TOO_HARD" then "Nobody made it, so trap points don't count."
			elseif results.multiplier > 1 then "Last round: double points"
			else "First to " .. results.target .. " wins",
		verdict = verdict,
		target = results.target,
	})
end

local function showWinner(extra)
	local standings = extra.standings or {}
	local winners = extra.winners or {}
	local ids = {}
	for _, w in winners do
		table.insert(ids, w.userId)
	end
	local rows = {}
	for _, r in standings do
		table.insert(rows, { userId = r.userId, name = r.name, species = r.species, before = r.total, total = r.total, items = {} })
	end
	local title = if #winners == 0 then "Nobody scored. Rematch?"
		elseif #winners == 1 then winners[1].name .. " wins!"
		else "It's a tie!"
	ResultsUI.show(rows, { title = title, subtitle = "Final standings", target = extra.target or 600, winners = ids })
	Sound.play("victory")
	for _, w in winners do
		local p = Players:GetPlayerByUserId(w.userId)
		local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Fx.confetti(root.Position)
		end
	end
end

--------------------------------------------------------------------------
-- Phase handling
--------------------------------------------------------------------------

local function onPhase(phase: string)
	local p = PHASES[phase] or PHASES.Waiting
	phaseText.Text = p[1]
	phaseChip.BackgroundColor3 = p[2]
	roundLabel.Text = if State.round > 0 then ("ROUND " .. State.round .. "/" .. State.rounds) else State.level:upper()
	lastTick = -1

	if phase ~= "Results" and phase ~= "Winner" then
		ResultsUI.close()
	end
	if phase ~= "Build" then
		Hud.setStatus(nil)
	end

	if phase == "Intro" then
		local target = State.extra.target or 600
		banner(State.level, "First to " .. target .. " wins. Build it mean, keep it beatable.", 3.8, 46)
	elseif phase == "Build" then
		banner(if State.final then "Last build" else "Build", if State.final then "Double points this round" else "Drop your piece in", 1.4, 44)
	elseif phase == "Run" then
		if State.isRunner(player.UserId) then
			banner("GO!", nil, 0.6, 64)
			Sound.play("go")
		end
	elseif phase == "Winner" then
		showWinner(State.extra)
	end
end

local function tick()
	local phase = State.phase
	local left = State.timeLeft()
	local timed = phase == "Pick" or phase == "Build" or phase == "Run"
	timerLabel.Visible = timed
	if timed then
		local secs = math.ceil(left)
		timerLabel.Text = string.format("%d:%02d", secs // 60, secs % 60)
		local urgent = secs <= 5 and secs > 0
		timerLabel.TextColor3 = if urgent then U.Bad else U.Ink
		if urgent and secs ~= lastTick then
			lastTick = secs
			Sound.play("tick")
		end
	elseif phase == "Countdown" then
		local n = math.ceil(left)
		if n ~= lastTick and n > 0 then
			lastTick = n
			banner(tostring(n), nil, 0.7, 64)
			Sound.play("tick")
		end
	end
end

--------------------------------------------------------------------------

local function buildGui()
	gui = UI.new("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	uiScale = UI.new("UIScale", { Parent = gui })
	local function rescale()
		local h = workspace.CurrentCamera.ViewportSize.Y
		uiScale.Scale = math.clamp(h / 900, 0.62, 1.15)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Top pill: ROUND 3/8 | BUILD | 0:14
	local _, top = UI.card({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(300, 40),
		Parent = gui,
	}, 20)
	UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = top
	roundLabel = UI.label({ Text = "", FontFace = F.Bold, TextSize = 14, TextColor3 = U.Muted, LayoutOrder = 1, Parent = top })
	phaseChip = UI.new("Frame", {
		BackgroundColor3 = U.Muted,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		LayoutOrder = 2,
		Parent = top,
	}, { UI.corner(99), UI.pad(10, 3) })
	phaseText = UI.label({ Text = "", FontFace = F.Title, TextSize = 15, TextColor3 = U.Paper, Parent = phaseChip })
	timerLabel = UI.label({ Text = "", FontFace = F.Title, TextSize = 20, LayoutOrder = 3, Parent = top })

	-- Emotes: keys 1-4 on keyboard; small buttons on touch screens only
	if UserInputService.TouchEnabled then
		local row = UI.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -12),
			Size = UDim2.fromOffset(280, 34),
			Parent = gui,
		}, { UI.list(Enum.FillDirection.Horizontal, 6) })
		for i, id in Animator.EMOTES do
			local b = UI.new("TextButton", {
				Text = id:sub(1, 1):upper() .. id:sub(2),
				FontFace = F.Bold,
				TextSize = 13,
				TextColor3 = U.Ink,
				BackgroundColor3 = U.Paper,
				BackgroundTransparency = 0.1,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(60, 30),
				LayoutOrder = i,
				Parent = row,
			}, { UI.corner(99) })
			UI.pressable(b, function()
				Animator.emote(id)
			end)
		end
	end

	local menuButton = UI.new("TextButton", {
		Text = "Menu",
		FontFace = F.Bold,
		TextSize = 14,
		TextColor3 = U.Ink,
		BackgroundColor3 = U.Paper,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(72, 30),
		Parent = gui,
	}, { UI.corner(99) })
	UI.pressable(menuButton, function()
		local ok, res = pcall(function()
			return Net.func("Lobby"):InvokeServer("menu")
		end)
		if ok and typeof(res) == "table" and not res.ok then
			Hud.toast(res.err or "Not right now", U.Bad)
		end
	end)
	State.lobbyChanged:Connect(function()
		menuButton.Visible = State.lobby.mode == "public"
	end)

	feedFrame = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(360, 200),
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right) })

	centerLabel = UI.label({
		Text = "",
		FontFace = F.Title,
		TextSize = 54,
		TextColor3 = U.Paper,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Parent = gui,
	})
	UI.new("UIStroke", { Color = U.Ink, Thickness = 3, Parent = centerLabel })
	UI.new("UIScale", { Parent = centerLabel })
	subLabel = UI.label({
		Text = "",
		FontFace = F.Bold,
		TextSize = 18,
		TextColor3 = U.Paper,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 40),
		Parent = gui,
	})
	UI.new("UIStroke", { Color = U.Ink, Thickness = 2, Parent = subLabel })

	tray = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 220),
		Size = UDim2.fromOffset(156 * 3 + 14 * 2, 150),
		Visible = false,
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })

	hint = UI.label({
		Text = "",
		FontFace = F.Bold,
		TextSize = 15,
		TextColor3 = U.Paper,
		BackgroundColor3 = U.Ink,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Visible = false,
		Parent = gui,
	})
	UI.corner(99).Parent = hint
	UI.pad(16, 8).Parent = hint

	touchBar = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(330, 52),
		Visible = false,
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	for i, spec in { { "Back", U.InkSoft, "back" }, { "Rotate", U.InkSoft, "rotate" }, { "Place", U.Accent, "place" } } do
		local b = UI.new("TextButton", {
			Text = spec[1],
			FontFace = F.Title,
			TextSize = 18,
			TextColor3 = U.Paper,
			BackgroundColor3 = spec[2],
			AutoButtonColor = false,
			Size = UDim2.fromOffset(100, 52),
			LayoutOrder = i,
			Parent = touchBar,
		}, { UI.corner(14) })
		UI.pressable(b, function()
			(Hud.actions :: any)[spec[3]]()
		end)
	end

	statusLabel = UI.label({
		Text = "",
		FontFace = F.Bold,
		TextSize = 16,
		TextColor3 = U.Paper,
		BackgroundColor3 = U.Ink,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Visible = false,
		Parent = gui,
	})
	UI.corner(99).Parent = statusLabel
	UI.pad(16, 8).Parent = statusLabel

	toastFrame = UI.new("Frame", {
		BackgroundColor3 = U.Ink,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -240),
		Visible = false,
		Parent = gui,
	}, { UI.corner(99), UI.pad(14, 6) })
	toastLabel = UI.label({ Text = "", FontFace = F.Bold, TextSize = 15, TextColor3 = U.Paper, Parent = toastFrame })
end

function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
	ResultsUI.setVisible(visible)
end

function Hud.init()
	buildGui()
	ResultsUI.init(player:WaitForChild("PlayerGui"))
	pcall(function()
		local StarterGui = game:GetService("StarterGui")
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	State.phaseChanged:Connect(onPhase)
	RunService.Heartbeat:Connect(tick)

	Net.event("RoundResults").OnClientEvent:Connect(showResults)
	Net.event("Notify").OnClientEvent:Connect(function(text)
		Hud.toast(text)
	end)

	Net.event("Fail").OnClientEvent:Connect(function(userId: number, cause: string, killerId: number?)
		local who = nameOf(userId)
		local text
		local def = Objects.ById[cause]
		if def and killerId then
			if killerId == userId then
				text = who .. " fell for their own " .. def.name
			else
				local verb = CAUSE[cause] or "got wrecked by"
				text = who .. " " .. verb .. " " .. nameOf(killerId) .. "'s " .. def.name
			end
		else
			text = who .. " " .. (CAUSE[cause] or "got taken out")
		end
		feed(text, U.Bad)
		if cause == "fall" then
			Sound.play("splash", 0.1)
		end
		if userId == player.UserId then
			Sound.play("fail", 0.1)
		end
	end)

	Net.event("Finish").OnClientEvent:Connect(function(userId: number, place: number)
		local suffix = ({ "1st", "2nd", "3rd" })[place] or (place .. "th")
		feed(nameOf(userId) .. " reached the flag (" .. suffix .. ")", U.Good)
		local who = Players:GetPlayerByUserId(userId)
		local root = who and who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Fx.confetti(root.Position)
		end
		if userId == player.UserId then
			banner("Made it!", suffix, 1.2, 48)
			Sound.play("victory")
		else
			Sound.play("goal", 0.1)
		end
	end)

	onPhase(State.phase)
end

return Hud
