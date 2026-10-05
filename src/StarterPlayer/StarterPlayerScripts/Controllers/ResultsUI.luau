-- The score table: one bar per player racing toward the finish line.
-- Banked points sit in your animal's colour; this round's points slide in
-- category by category (finish, traps, clutch, own route) for everyone at
-- once, each with a rising note. Readable at a glance, satisfying to watch.

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

local LABELS = { finish = "Finish", trap = "Trap", clutch = "Clutch", route = "Own route" }
local WIDTH = 720
local TRACK_X = 196
local TRACK_W = 430
local ROW_H = 46
local BAR_H = 24

local panel: Frame? = nil
local token = 0

local function speciesColor(species: string?): Color3
	local s = species and Characters.ById[species]
	return if s then s.body else U.Muted
end

function ResultsUI.close()
	token += 1
	if panel then
		local p = panel
		panel = nil
		UI.tween(p, 0.2, { Position = UDim2.new(0.5, 0, 0.5, 40) })
		task.delay(0.2, function()
			p:Destroy()
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
function ResultsUI.show(parent: Instance, rows: { any }, opts: Options)
	ResultsUI.close()
	token += 1
	local myToken = token

	local height = 132 + #rows * ROW_H + 26
	local holder, face = UI.card({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Size = UDim2.fromOffset(WIDTH, height),
		Parent = parent,
	}, 18)
	panel = holder
	UI.tween(holder, 0.32, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)

	UI.label({ Text = opts.title, FontFace = F.Title, TextSize = 30, Position = UDim2.fromOffset(26, 18), Parent = face })
	UI.label({ Text = opts.subtitle, TextSize = 14, TextColor3 = U.Muted, Position = UDim2.fromOffset(26, 58), Parent = face })

	-- Legend, top right
	local legend = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 26),
		Size = UDim2.fromOffset(330, 20),
		Parent = face,
	}, { UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	for i, cat in Style.ScoreOrder do
		local item = UI.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), LayoutOrder = i, Parent = legend }, {
			UI.list(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		})
		UI.new("Frame", { BackgroundColor3 = Style.ScoreColor[cat], Size = UDim2.fromOffset(10, 10), Parent = item }, { UI.corner(3) })
		UI.label({ Text = LABELS[cat], TextSize = 12, TextColor3 = U.InkSoft, FontFace = F.Bold, Parent = item })
	end

	local top = 100
	local target = math.max(opts.target, 1)
	local function px(points: number): number
		return math.clamp(points / target, 0, 1) * TRACK_W
	end

	-- Finish line across all rows, with a little flag tag
	local lineH = #rows * ROW_H
	UI.new("Frame", {
		BackgroundColor3 = U.Ink,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, lineH + 6),
		Position = UDim2.fromOffset(TRACK_X + TRACK_W, top - 4),
		ZIndex = 4,
		Parent = face,
	})
	local tag = UI.pill("FINISH " .. target, U.Ink, U.Paper, 11)
	tag.AnchorPoint = Vector2.new(0.5, 1)
	tag.Position = UDim2.fromOffset(TRACK_X + TRACK_W + 1, top - 6)
	tag.ZIndex = 4
	tag.Parent = face

	type RowUI = { offset: number, segs: Frame, total: TextLabel, gainedLabel: TextLabel, data: any, line: Frame }
	local rowUIs = {} :: { RowUI }

	for i, row in rows do
		local y = top + (i - 1) * ROW_H
		local mine = row.userId == Players.LocalPlayer.UserId
		local isWinner = opts.winners and table.find(opts.winners, row.userId) ~= nil
		local line = UI.new("Frame", {
			BackgroundColor3 = U.PaperShade,
			BackgroundTransparency = if mine then 0 else 1,
			Size = UDim2.new(1, -24, 0, ROW_H - 6),
			Position = UDim2.fromOffset(12, y),
			Parent = face,
		}, { UI.corner(10) })
		if isWinner then
			UI.new("UIStroke", { Color = U.Gold, Thickness = 3, Parent = line })
		end

		UI.label({ Text = tostring(i), FontFace = F.Title, TextSize = 16, TextColor3 = U.Muted, Position = UDim2.fromOffset(12, 10), Parent = line })
		UI.new("Frame", {
			BackgroundColor3 = speciesColor(row.species),
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromOffset(34, 13),
			Parent = line,
		}, { UI.corner(7) })
		UI.label({
			Text = row.name,
			FontFace = F.Bold,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(120, ROW_H - 6),
			Position = UDim2.fromOffset(56, 0),
			Parent = line,
		})

		-- Track + 100-point ticks
		local track = UI.new("Frame", {
			BackgroundColor3 = U.Paper,
			Size = UDim2.fromOffset(TRACK_W, BAR_H),
			Position = UDim2.fromOffset(TRACK_X - 12, (ROW_H - 6 - BAR_H) / 2),
			ClipsDescendants = true,
			Parent = line,
		}, { UI.corner(7), UI.new("UIStroke", { Color = U.Ink, Transparency = 0.85, Thickness = 1 }) })
		for p = 100, target - 1, 100 do
			UI.new("Frame", {
				BackgroundColor3 = U.Ink,
				BackgroundTransparency = 0.9,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(1, BAR_H),
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
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(52, ROW_H - 6),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Parent = line,
		})
		local gainedLabel = UI.label({
			Text = "",
			FontFace = F.Title,
			TextSize = 14,
			TextColor3 = U.Accent,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -66, 0.5, 0),
			Parent = line,
		})
		rowUIs[i] = { offset = banked, segs = segs, total = total, gainedLabel = gainedLabel, data = row, line = line }
	end

	-- Verdict stamp, slammed across the middle
	local function stamp(text: string)
		local s = UI.label({
			Text = text,
			FontFace = F.Title,
			TextSize = 54,
			TextColor3 = U.Bad,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, top + lineH / 2),
			Rotation = -8,
			ZIndex = 10,
			Parent = face,
		})
		UI.new("UIStroke", { Color = U.Paper, Thickness = 4, Parent = s })
		local sc = UI.new("UIScale", { Scale = 2.6, Parent = s })
		UI.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		Sound.play("stamp")
	end

	task.spawn(function()
		task.wait(0.45)
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
					local w = math.max(px(pts), 3)
					local seg = UI.new("Frame", {
						BackgroundColor3 = Style.ScoreColor[cat],
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(0, BAR_H),
						Position = UDim2.fromOffset(r.offset, 0),
						ClipsDescendants = true,
						ZIndex = 2,
						Parent = r.segs,
					})
					if w > 44 and label then
						UI.label({
							Text = label,
							FontFace = F.Bold,
							TextSize = 12,
							TextColor3 = U.Paper,
							Position = UDim2.fromOffset(6, 4),
							ZIndex = 3,
							Parent = seg,
						})
					end
					UI.tween(seg, 0.35, { Size = UDim2.fromOffset(w, BAR_H) }, Enum.EasingStyle.Back)
					r.offset += w
				end
			end
			if any then
				Sound.play("bar", 0, pitch)
				pitch *= 1.12
				task.wait(0.55)
				if myToken ~= token then
					return
				end
			end
		end

		-- Count totals up and flash what each player gained
		for _, r in rowUIs do
			local from = r.data.before or r.data.total
			local to = r.data.total
			local gained = to - from
			if gained > 0 then
				r.gainedLabel.Text = "+" .. gained
				UI.tween(r.gainedLabel, 0.2, { TextTransparency = 0 })
				task.spawn(function()
					for s = 1, 10 do
						task.wait(0.03)
						if not r.total.Parent then
							return
						end
						r.total.Text = tostring(math.floor(from + gained * s / 10))
					end
				end)
			end
			if to >= target then
				UI.new("UIStroke", { Color = U.Gold, Thickness = 3, Parent = r.line })
			end
		end
		Sound.play("points")
	end)
end

return ResultsUI
