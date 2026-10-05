--!strict
-- One palette for UI and world. Flat colors, no gradients, no neon.

local Style = {}

Style.UI = {
	Ink = Color3.fromRGB(34, 31, 43),
	InkSoft = Color3.fromRGB(58, 54, 70),
	Paper = Color3.fromRGB(250, 246, 238),
	PaperShade = Color3.fromRGB(232, 225, 212),
	Muted = Color3.fromRGB(128, 120, 132),
	Accent = Color3.fromRGB(238, 108, 77),
	Good = Color3.fromRGB(82, 170, 110),
	Bad = Color3.fromRGB(214, 76, 76),
	Gold = Color3.fromRGB(240, 184, 72),
	Cool = Color3.fromRGB(92, 150, 220),
}

-- Score categories, in the order they animate into the bar chart
Style.ScoreOrder = { "finish", "trap", "coin", "clutch", "route" }
Style.ScoreColor = {
	finish = Style.UI.Good,
	trap = Style.UI.Bad,
	coin = Style.UI.Gold,
	clutch = Color3.fromRGB(156, 112, 214),
	route = Style.UI.Cool,
}

Style.Font = {
	Title = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.fromEnum(Enum.Font.BuilderSansMedium),
	Bold = Font.fromEnum(Enum.Font.BuilderSansBold),
}

Style.Forest = {
	Grass = Color3.fromRGB(118, 176, 86),
	GrassDark = Color3.fromRGB(92, 150, 72),
	Dirt = Color3.fromRGB(141, 101, 70),
	DirtDark = Color3.fromRGB(112, 80, 58),
	Wood = Color3.fromRGB(196, 146, 96),
	WoodDark = Color3.fromRGB(150, 106, 68),
	Bark = Color3.fromRGB(112, 82, 60),
	Leaf = { Color3.fromRGB(86, 146, 78), Color3.fromRGB(70, 126, 74), Color3.fromRGB(108, 162, 88) },
	Stone = Color3.fromRGB(150, 150, 140),
	Water = Color3.fromRGB(96, 168, 196),
	Hill = Color3.fromRGB(128, 168, 132),
	HillFar = Color3.fromRGB(160, 190, 176),
	Cloud = Color3.fromRGB(252, 250, 246),
}

Style.Mountain = {
	Snow = Color3.fromRGB(240, 244, 248),
	SnowShade = Color3.fromRGB(212, 222, 234),
	Rock = Color3.fromRGB(124, 130, 142),
	RockDark = Color3.fromRGB(96, 102, 114),
	Ice = Color3.fromRGB(176, 220, 236),
	Pine = Color3.fromRGB(58, 98, 82),
	PineDark = Color3.fromRGB(44, 80, 68),
	Peak = Color3.fromRGB(166, 178, 198),
	PeakFar = Color3.fromRGB(196, 206, 222),
	Mist = Color3.fromRGB(232, 238, 244),
}

Style.Factory = {
	Floor = Color3.fromRGB(104, 108, 118),
	Concrete = Color3.fromRGB(132, 130, 128),
	Steel = Color3.fromRGB(122, 130, 142),
	SteelDark = Color3.fromRGB(80, 86, 98),
	Girder = Color3.fromRGB(214, 122, 56),
	GirderDark = Color3.fromRGB(170, 92, 44),
	Hazard = Color3.fromRGB(240, 184, 72),
	Brick = Color3.fromRGB(150, 94, 78),
	BrickDark = Color3.fromRGB(124, 76, 64),
	Pipe = Color3.fromRGB(88, 138, 158),
	Window = Color3.fromRGB(244, 224, 176),
	Belt = Color3.fromRGB(52, 50, 60),
	Goo = Color3.fromRGB(124, 198, 90),
}

-- Shared materials for placed objects so they read as one family
Style.Object = {
	Metal = Color3.fromRGB(96, 100, 112),
	MetalLight = Color3.fromRGB(176, 180, 190),
	Danger = Color3.fromRGB(214, 76, 76),
	Spring = Color3.fromRGB(238, 108, 77),
	Honey = Color3.fromRGB(232, 162, 48),
	Ice = Color3.fromRGB(186, 226, 238),
	Rubber = Color3.fromRGB(52, 50, 60),
	Stripe = Color3.fromRGB(240, 184, 72),
	Crumble = Color3.fromRGB(206, 178, 132),
}

return Style
