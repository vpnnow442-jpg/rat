--!strict
-- Hand-authored layouts, stored as plain data.
-- The same shape will be what community levels save to DataStores later.
--
-- Design rules every layout follows:
--   * start and flag are on solid ground with clear space around them
--   * the bare layout is beatable with double jumps, but never comfortably
--   * at least two routes somewhere (a high one and a low one), so one
--     player's trap never blocks the only way through
--   * big open air between pieces, because that's where players build
--
-- Reference: single jump ~7 studs high, double jump ~12, ~18 across.

export type Piece = {
	kind: "ground" | "ledge" | "stump" | "tree" | "rock" | "log",
	x0: number,
	x1: number,
	top: number,
}

export type Layout = {
	name: string,
	world: string,
	spawn: Vector2, -- point on the start ledge surface
	flag: Vector2, -- point on the goal ledge surface
	buildMin: Vector2,
	buildMax: Vector2,
	pieces: { Piece },
	seed: number,
}

local Levels = {}

Levels.Forest = {
	{
		-- Low meadow path vs. a high ledge route over the middle
		name = "Mossy Hollow",
		world = "Forest",
		spawn = Vector2.new(0, 10),
		flag = Vector2.new(214, 16),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 64),
		seed = 11,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 12, top = 10 },
			{ kind = "ground", x0 = 26, x1 = 40, top = 6 },
			{ kind = "stump", x0 = 52, x1 = 57, top = 16 },
			{ kind = "ledge", x0 = 66, x1 = 80, top = 24 },
			{ kind = "ground", x0 = 72, x1 = 96, top = 4 },
			{ kind = "rock", x0 = 108, x1 = 114, top = 12 },
			{ kind = "ground", x0 = 124, x1 = 152, top = 8 },
			{ kind = "stump", x0 = 140, x1 = 145, top = 18 },
			{ kind = "ledge", x0 = 158, x1 = 172, top = 28 },
			{ kind = "ground", x0 = 168, x1 = 186, top = 10 },
			{ kind = "ground", x0 = 200, x1 = 232, top = 16 },
		},
	},
	{
		-- Two long logs, a rocky dip, and an overhang that rewards the brave
		name = "Fallen Log",
		world = "Forest",
		spawn = Vector2.new(-2, 12),
		flag = Vector2.new(212, 12),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 64),
		seed = 23,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 10, top = 12 },
			{ kind = "log", x0 = 22, x1 = 60, top = 6 },
			{ kind = "rock", x0 = 70, x1 = 76, top = 2 },
			{ kind = "ground", x0 = 88, x1 = 110, top = 10 },
			{ kind = "ledge", x0 = 100, x1 = 116, top = 28 },
			{ kind = "log", x0 = 124, x1 = 160, top = 14 },
			{ kind = "rock", x0 = 172, x1 = 177, top = 6 },
			{ kind = "ledge", x0 = 168, x1 = 182, top = 30 },
			{ kind = "ground", x0 = 192, x1 = 232, top = 12 },
		},
	},
	{
		-- Treetop hopping: lots of height changes, lots of places to build
		name = "Canopy Run",
		world = "Forest",
		spawn = Vector2.new(-2, 20),
		flag = Vector2.new(214, 18),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 68),
		seed = 37,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 8, top = 20 },
			{ kind = "tree", x0 = 20, x1 = 28, top = 14 },
			{ kind = "tree", x0 = 38, x1 = 44, top = 24 },
			{ kind = "tree", x0 = 56, x1 = 64, top = 12 },
			{ kind = "tree", x0 = 76, x1 = 82, top = 22 },
			{ kind = "tree", x0 = 94, x1 = 102, top = 30 },
			{ kind = "tree", x0 = 116, x1 = 124, top = 16 },
			{ kind = "tree", x0 = 136, x1 = 142, top = 26 },
			{ kind = "tree", x0 = 154, x1 = 162, top = 14 },
			{ kind = "tree", x0 = 174, x1 = 180, top = 24 },
			{ kind = "ground", x0 = 194, x1 = 232, top = 18 },
		},
	},
} :: { Layout }

return Levels
