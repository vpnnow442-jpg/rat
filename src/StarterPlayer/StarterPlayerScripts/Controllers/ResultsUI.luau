-- The score table, full screen. One fat bar per player racing toward the
-- finish line. Banked points sit in your animal's colour; this round's points
-- slide in category by category (finish, traps, coin, clutch, own route) for
-- everyone at once, each with a rising note.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Style = require(Shared.Style)

local Sound = require(script.Parent.SoundController)
local UI = require(script.Parent.UI)

local U = Style.UI
local F = Style.Font

local ResultsUI = {}

local LABELS = { finish = "Finish", trap = "Trap", coin = "Coin", clutch = "Clutch", route = "Own route" }
local WIDTH = 1040
local TRACK_X = 250
local TRACK_W = 640
local ROW_H = 66
local BAR_H = 36

local gui: ScreenGui
local token = 0

local function speciesColor(species: string?): Color3
	local s = species and Characters.ById[species]
	return if s then s.body else U.Muted
end

function ResultsUI.setVisible(visible: boolean)
	gui.Enabled = visible
end

function ResultsUI.close()
	token += 1
	local bg = gui and gui:FindFirstChild("Backdrop")
	if bg then
		UI.tween(bg :: Frame, 0.3, { Position = UDim2.fromScale(0, 1.05) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.32, function()
			bg:Destroy()
		end)
	end
end

export type Options = {
	title: string,
	subtitle: string,
	verdict: string?,
	target: number,
	winners: { number }?,
}

-- rows: { userId, name, species, before, items = {{cat,label,points}}, total }
function ResultsUI.show(rows: { any }, opts: Options)
	ResultsUI.close()
	token += 1
	local myToken = token

	local backdrop = UI.new("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = U.Paper,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 1.05),
		Parent = gui,
	})
	UI.tween(backdrop, 0.4, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Quad)

	local height = 190 + #rows * ROW_H
	local box = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, height),
		Parent = backdrop,
	})
	local scale = UI.new("UIScale", { Parent = box })
	local vp = workspace.CurrentCamera.ViewportSize
	scale.Scale = math.clamp(math.min((vp.X - 40) / WIDTH, (vp.Y - 40) / height), 0.45, 1.3)

	UI.label({ Text = opts.title, FontFace = F.Title, TextSize = 48, Position = UDim2.fromOffset(0, 0), Parent = box })
	UI.label({ Text = opts.subtitle, TextSize = 18, TextColor3 = U.Muted, Position = UDim2.fromOffset(2, 60), Parent = box })

	local legend = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 20),
		Size = UDim2.fromOffset(520, 24),
		Parent = box,
	}, { UI.list(Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	for i, cat in Style.ScoreOrder do
		local item = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), LayoutOrder = i, Parent = legend }, {
			UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		})
		UI.new("Frame", { BackgroundColor3 = Style.ScoreColor[cat], Size = UDim2.fromOffset(14, 14), Parent = item }, { UI.corner(4) })
		UI.label({ Text = LABELS[cat], TextSize = 15, TextColor3 = U.InkSoft, FontFace = F.Bold, Parent = item })
	end

	local top = 140
	local target = math.max(opts.target, 1)
	local function px(points: number): number
		return math.clamp(points / target, 0, 1) * TRACK_W
	end

	-- Finish line across every row, with a tag on top
	local lineH = #rows * ROW_H
	UI.new("Frame", {
		BackgroundColor3 = U.Ink,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(4, lineH),
		Position = UDim2.fromOffset(TRACK_X + TRACK_W, top),
		ZIndex = 4,
		Parent = box,
	})
	local tag = UI.pill("FINISH  " .. target, U.Ink, U.Paper, 14)
	tag.AnchorPoint = Vector2.new(0.5, 1)
	tag.Position = UDim2.fromOffset(TRACK_X + TRACK_W + 2, top - 6)
	tag.ZIndex = 4
	tag.Parent = box

	type RowUI = { offset: number, segs: Frame, total: TextLabel, gainedLabel: TextLabel, data: any, line: Frame }
	local rowUIs = {} :: { RowUI }

	for i, row in rows do
		local y = top + (i - 1) * ROW_H
		local mine = row.userId == Players.LocalPlayer.UserId
		local isWinner = opts.winners and table.find(opts.winners, row.userId) ~= nil
		local line = UI.new("Frame", {
			BackgroundColor3 = U.PaperShade,
			BackgroundTransparency = if mine then 0 else 1,
			Size = UDim2.new(1, 0, 0, ROW_H - 8),
			Position = UDim2.fromOffset(-60, y),
			Parent = box,
		}, { UI.corner(14) })
		if isWinner then
			UI.new("UIStroke", { Color = U.Gold, Thickness = 4, Parent = line })
		end
		UI.label({ Text = tostring(i), FontFace = F.Title, TextSize = 24, TextColor3 = U.Muted, Position = UDim2.fromOffset(16, 14), Parent = line })
		UI.new("Frame", {
			BackgroundColor3 = speciesColor(row.species),
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.fromOffset(52, 19),
			Parent = line,
		}, { UI.corner(10) })
		UI.label({
			Text = row.name,
			FontFace = F.Bold,
			TextSize = 22,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(160, ROW_H - 8),
			Position = UDim2.fromOffset(82, 0),
			Parent = line,
		})

		local track = UI.new("Frame", {
			BackgroundColor3 = U.Paper,
			Size = UDim2.fromOffset(TRACK_W, BAR_H),
			Position = UDim2.fromOffset(TRACK_X, (ROW_H - 8 - BAR_H) / 2),
			ClipsDescendants = true,
			Parent = line,
		}, { UI.corner(10), UI.new("UIStroke", { Color = U.Ink, Transparency = 0.82, Thickness = 2 }) })
		for p = 100, target - 1, 100 do
			UI.new("Frame", {
				BackgroundColor3 = U.Ink,
				BackgroundTransparency = 0.88,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(2, BAR_H),
				Position = UDim2.fromOffset(px(p), 0),
				ZIndex = 3,
				Parent = track,
			})
		end
		local segs = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = track })
		local banked = px(row.before or 0)
		if banked > 0 then
			UI.new("Frame", {
				BackgroundColor3 = speciesColor(row.species),
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(banked, BAR_H),
				ZIndex = 2,
				Parent = segs,
			})
		end

		local total = UI.label({
			Text = tostring(row.before or row.total),
			FontFace = F.Title,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Right,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(80, ROW_H - 8),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Parent = line,
		})
		local gainedLabel = UI.label({
			Text = "",
			FontFace = F.Title,
			TextSize = 20,
			TextColor3 = U.Accent,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -100, 0.5, 0),
			Parent = line,
		})
		rowUIs[i] = { offset = banked, segs = segs, total = total, gainedLabel = gainedLabel, data = row, line = line }

		-- rows slide in one after another
		task.delay(0.15 + i * 0.06, function()
			if line.Parent then
				UI.tween(line, 0.35, { Position = UDim2.fromOffset(0, y) }, Enum.EasingStyle.Back)
			end
		end)
	end

	local function stamp(text: string)
		local s = UI.label({
			Text = text,
			FontFace = F.Title,
			TextSize = 96,
			TextColor3 = U.Bad,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(WIDTH / 2, top + lineH / 2),
			Rotation = -8,
			ZIndex = 10,
			Parent = box,
		})
		UI.new("UIStroke", { Color = U.Paper, Thickness = 6, Parent = s })
		local sc = UI.new("UIScale", { Scale = 2.6, Parent = s })
		UI.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		Sound.play("stamp")
	end

	task.spawn(function()
		task.wait(0.7)
		if myToken ~= token then
			return
		end
		if opts.verdict == "TOO_EASY" then
			stamp("TOO EASY!")
		elseif opts.verdict == "TOO_HARD" then
			stamp("TOO HARD!")
		end

		local pitch = 1
		for _, cat in Style.ScoreOrder do
			local any = false
			for _, r in rowUIs do
				local pts, label = 0, nil
				for _, it in r.data.items or {} do
					if it.cat == cat then
						pts += it.points
						label = it.label
					end
				end
				if pts > 0 then
					any = true
					local w = math.max(px(pts), 4)
					local seg = UI.new("Frame", {
						BackgroundColor3 = Style.ScoreColor[cat],
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(0, BAR_H),
						Position = UDim2.fromOffset(r.offset, 0),
						ClipsDescendants = true,
						ZIndex = 2,
						Parent = r.segs,
					})
					if w > 60 and label then
						UI.label({
							Text = label,
							FontFace = F.Bold,
							TextSize = 16,
							TextColor3 = U.Paper,
							Position = UDim2.fromOffset(8, 7),
							ZIndex = 3,
							Parent = seg,
						})
					end
					UI.tween(seg, 0.4, { Size = UDim2.fromOffset(w, BAR_H) }, Enum.EasingStyle.Back)
					r.offset += w
				end
			end
			if any then
				Sound.play("bar", 0, pitch)
				pitch *= 1.12
				task.wait(0.6)
				if myToken ~= token then
					return
				end
			end
		end

		for _, r in rowUIs do
			local from = r.data.before or r.data.total
			local to = r.data.total
			local gained = to - from
			if gained > 0 then
				r.gainedLabel.Text = "+" .. gained
				UI.tween(r.gainedLabel, 0.2, { TextTransparency = 0 })
				task.spawn(function()
					for s = 1, 12 do
						task.wait(0.03)
						if not r.total.Parent then
							return
						end
						r.total.Text = tostring(math.floor(from + gained * s / 12))
					end
				end)
			end
			if to >= target then
				UI.new("UIStroke", { Color = U.Gold, Thickness = 4, Parent = r.line })
			end
		end
		Sound.play("points")
	end)
end

function ResultsUI.init(playerGui: Instance)
	gui = UI.new("ScreenGui", {
		Name = "ScoreTable",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 4,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
end

return ResultsUI
