-- Tiny UI kit so every panel, label and button shares one look:
-- warm paper cards, ink text, a hard offset shadow (no blur, no gradients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Style = require(ReplicatedStorage.Shared.Style)

local U = Style.UI
local UI = {}

function UI.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.corner(r: number): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r) })
end

function UI.pad(px: number, py: number?): UIPadding
	local y = py or px
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
	})
end

function UI.list(dir: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = dir,
		Padding = UDim.new(0, gap),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = Style.Font.Body,
		TextSize = 16,
		TextColor3 = U.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
	}
	for k, v in props do
		defaults[k] = v
	end
	return UI.new("TextLabel", defaults)
end

-- A card with a hard shadow underneath. Returns (holder, face).
-- Put content in `face`; position/size the holder.
function UI.card(props: { [string]: any }, radius: number?): (Frame, Frame)
	local r = radius or 12
	local holder = UI.new("Frame", { BackgroundTransparency = 1 })
	for k, v in props do
		(holder :: any)[k] = v
	end
	UI.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = U.Ink,
		BackgroundTransparency = 0.82,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 4),
		ZIndex = 0,
		Parent = holder,
	}, { UI.corner(r) })
	local face = UI.new("Frame", {
		Name = "Face",
		BackgroundColor3 = U.Paper,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = holder,
	}, { UI.corner(r) })
	return holder, face
end

function UI.pill(text: string, bg: Color3, fg: Color3?, size: number?): Frame
	local f = UI.new("Frame", {
		BackgroundColor3 = bg,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
	}, { UI.corner(99), UI.pad(8, 3) })
	UI.label({ Text = text, FontFace = Style.Font.Bold, TextSize = size or 13, TextColor3 = fg or U.Paper, Parent = f })
	return f
end

function UI.tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Hover lift + press squish, the same on every button
function UI.pressable(button: GuiButton, onClick: () -> ())
	local scale = button:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.04 })
	end)
	button.MouseLeave:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.18, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(onClick)
end

return UI
