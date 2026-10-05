-- Loading screen. Runs before anything else, so it can't use the shared
-- modules yet: colours and fonts are repeated here on purpose.
-- Tips teach the core rule while you wait.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local INK = Color3.fromRGB(34, 31, 43)
local PAPER = Color3.fromRGB(250, 246, 238)
local SHADE = Color3.fromRGB(232, 225, 212)
local MUTED = Color3.fromRGB(128, 120, 132)
local ACCENT = Color3.fromRGB(238, 108, 77)
local ANIMALS = {
	Color3.fromRGB(226, 121, 58),
	Color3.fromRGB(138, 136, 146),
	Color3.fromRGB(48, 52, 68),
	Color3.fromRGB(112, 178, 92),
}
local TITLE = Font.fromEnum(Enum.Font.FredokaOne)
local BODY = Font.fromEnum(Enum.Font.BuilderSansBold)

local TIPS = {
	"If everyone reaches the flag, nobody scores.",
	"Trap your friends, but keep the course beatable.",
	"Hold toward a wall in the air, then jump, to wall-jump.",
	"The Trick Plank has no nails. Learn the tell.",
	"Too slow at the pick box? You get the leftovers.",
	"A Bomb clears pieces. Use it to fix a ruined course.",
}

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = PAPER
bg.BorderSizePixel = 0
bg.Parent = gui

local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.46)
center.Size = UDim2.fromOffset(420, 260)
center.BackgroundTransparency = 1
center.Parent = bg
local scale = Instance.new("UIScale")
scale.Parent = center
local function rescale()
	local vp = workspace.CurrentCamera.ViewportSize
	scale.Scale = math.clamp(math.min(vp.X / 700, vp.Y / 600), 0.6, 1.3)
end
rescale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

local function text(str: string, font: Font, size: number, color: Color3, y: number, transparency: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextTransparency = transparency or 0
	l.Text = str
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.fromOffset(420, size + 8)
	l.Parent = center
	return l
end

-- Logo with a hard offset shadow
local logo = Instance.new("Frame")
logo.BackgroundTransparency = 1
logo.Size = UDim2.fromScale(1, 1)
logo.Rotation = -3
logo.Parent = center
for _, spec in { { "Chaos Course", INK, 4, 0.85 }, { "Chaos Course", ACCENT, 0, 0 } } do
	local l = text(spec[1], TITLE, 64, spec[2], 20 + spec[3], spec[4])
	l.Position += UDim2.fromOffset(spec[3], 0)
	l.Parent = logo
end

-- Four animal-coloured dots hopping in a wave
local dots = {}
for i, c in ANIMALS do
	local d = Instance.new("Frame")
	d.BackgroundColor3 = c
	d.Size = UDim2.fromOffset(18, 18)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.new(0.5, (i - 2.5) * 30, 0, 130)
	d.Parent = center
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = d
	dots[i] = d
end

local barBg = Instance.new("Frame")
barBg.BackgroundColor3 = SHADE
barBg.BorderSizePixel = 0
barBg.AnchorPoint = Vector2.new(0.5, 0)
barBg.Position = UDim2.new(0.5, 0, 0, 168)
barBg.Size = UDim2.fromOffset(240, 6)
barBg.Parent = center
local c1 = Instance.new("UICorner")
c1.CornerRadius = UDim.new(1, 0)
c1.Parent = barBg
local bar = Instance.new("Frame")
bar.BackgroundColor3 = INK
bar.BorderSizePixel = 0
bar.Size = UDim2.fromScale(0, 1)
bar.Parent = barBg
local c2 = Instance.new("UICorner")
c2.CornerRadius = UDim.new(1, 0)
c2.Parent = bar

local tip = text(TIPS[math.random(1, #TIPS)], BODY, 16, MUTED, 196)

local t0 = os.clock()
local conn = RunService.RenderStepped:Connect(function()
	local t = os.clock() - t0
	for i, d in dots do
		local hop = math.max(0, math.sin(t * 6 - i * 0.7))
		d.Position = UDim2.new(0.5, (i - 2.5) * 30, 0, 130 - hop * 16)
		d.Size = UDim2.fromOffset(18 + hop * 2, 18 - hop * 3)
	end
end)

-- Rotate tips while we wait
task.spawn(function()
	while gui.Parent do
		task.wait(3.2)
		local nextTip = TIPS[math.random(1, #TIPS)]
		TweenService:Create(tip, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		task.wait(0.2)
		tip.Text = nextTip
		TweenService:Create(tip, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	end
end)

-- Progress: game loaded -> remotes exist -> the level exists; never less than 1.5s
local steps = 0
local function step()
	steps += 1
	TweenService:Create(bar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(steps / 3, 1) }):Play()
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end
step()
ReplicatedStorage:WaitForChild("Remotes", 20)
step()
workspace:WaitForChild("Level", 20)
pcall(function()
	-- give asset requests a moment, but don't hang on them
	local deadline = os.clock() + 3
	while ContentProvider.RequestQueueSize > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
step()
while os.clock() - t0 < 1.5 do
	task.wait(0.05)
end
task.wait(0.3)

player:SetAttribute("Loaded", true)
local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad)
TweenService:Create(bg, fade, { BackgroundTransparency = 1 }):Play()
for _, d in center:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
	elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
		TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.5)
conn:Disconnect()
gui:Destroy()
