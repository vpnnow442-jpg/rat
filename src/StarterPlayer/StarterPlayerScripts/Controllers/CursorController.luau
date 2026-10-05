-- While you pick from the box or place a piece, your mouse becomes your
-- animal's head with your name under it. Over the box you also see everyone
-- else's cursor drifting around, so you can watch them go for "your" piece.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Net = require(Shared.Net)
local Style = require(Shared.Style)

local Camera = require(script.Parent.CameraController)
local Pick = require(script.Parent.PickController)
local Portrait = require(script.Parent.Portrait)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local U = Style.UI
local player = Players.LocalPlayer
local PickCursor = Net.unreliable("PickCursor")

local CursorController = {}

type Other = { frame: Frame, target: Vector2, pos: Vector2 }

local gui: ScreenGui
local mine: Frame? = nil
local mineSpecies: string? = nil
local others = {} :: { [number]: Other }
local hidSystemCursor = false
local lastSend = 0

local function make(species: string?, name: string): Frame
	local s = species and Characters.ById[species]
	local frame = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(120, 92),
		Interactable = false,
		ZIndex = 50,
	})
	-- the tip sits exactly on the pointer
	UI.new("Frame", {
		BackgroundColor3 = U.Paper,
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromOffset(-6, -6),
		Rotation = 45,
		Interactable = false,
		ZIndex = 51,
		Parent = frame,
	}, { UI.new("UIStroke", { Color = U.Ink, Thickness = 2 }) })
	local vp = Portrait.head(species)
	vp.Size = UDim2.fromOffset(58, 58)
	vp.Position = UDim2.fromOffset(4, 2)
	vp.ZIndex = 52
	vp.Parent = frame
	local tag = UI.label({
		Text = name,
		FontFace = Style.Font.Title,
		TextSize = 13,
		TextColor3 = U.Paper,
		BackgroundColor3 = if s then s.body else U.InkSoft,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(10, 60),
		Interactable = false,
		ZIndex = 53,
		Parent = frame,
	})
	UI.corner(99).Parent = tag
	UI.pad(7, 2).Parent = tag
	return frame
end

local function usingMouse(): boolean
	local t = UserInputService:GetLastInputType()
	return UserInputService.MouseEnabled
		and t ~= Enum.UserInputType.Touch
		and not t.Name:find("Gamepad")
end

local function update(dt: number)
	-- my cursor
	local active = usingMouse()
		and not Camera.menuOpen
		and ((State.phase == "Pick" and Pick.isOpen()) or (State.phase == "Build" and Camera.building))
	local species = State.speciesOf[player.UserId]
	if mine and species ~= mineSpecies then
		mine:Destroy()
		mine = nil
	end
	if active then
		local me = mine
		if not me then
			mineSpecies = species
			me = make(species, player.DisplayName)
			me.Parent = gui
			mine = me
		end
		local m = UserInputService:GetMouseLocation()
		me.Visible = true
		me.Position = UDim2.fromOffset(m.X, m.Y)
		UserInputService.MouseIconEnabled = false
		hidSystemCursor = true

		if State.phase == "Pick" and os.clock() - lastSend > 0.08 then
			lastSend = os.clock()
			local vp = workspace.CurrentCamera.ViewportSize
			PickCursor:FireServer(m.X / math.max(vp.X, 1), m.Y / math.max(vp.Y, 1))
		end
	else
		if mine then
			mine.Visible = false
		end
		if hidSystemCursor then
			UserInputService.MouseIconEnabled = true
			hidSystemCursor = false
		end
	end

	-- everyone else's cursor over the pick box
	local showOthers = State.phase == "Pick" and Pick.isOpen()
	local a = 1 - math.exp(-dt * 14)
	for _, o in others do
		o.frame.Visible = showOthers
		o.pos = o.pos:Lerp(o.target, a)
		o.frame.Position = UDim2.fromScale(o.pos.X, o.pos.Y)
	end
end

function CursorController.init()
	gui = UI.new("ScreenGui", {
		Name = "Cursors",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	PickCursor.OnClientEvent:Connect(function(userId: number, nx: number, ny: number)
		if userId == 0 then
			for _, o in others do
				o.frame:Destroy()
			end
			table.clear(others)
			return
		end
		local o = others[userId]
		local target = Vector2.new(nx, ny)
		if not o then
			local p = Players:GetPlayerByUserId(userId)
			local frame = make(State.speciesOf[userId], if p then p.DisplayName else "?")
			frame.Parent = gui
			o = { frame = frame, target = target, pos = target }
			others[userId] = o
		end
		(o :: Other).target = target
	end)

	RunService.RenderStepped:Connect(update)
end

return CursorController
