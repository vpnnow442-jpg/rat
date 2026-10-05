--!strict
-- Hand-authored layouts, stored as plain data.
-- The same shape will be what community levels save to DataStores later.
--
-- Design rules every layout follows:
--   * start and flag are on solid ground with clear space around them
--   * the bare layout is beatable with a double jump, but not comfortably
--   * there is open air above and between pieces for players to build in

export type Piece = {
	kind: "ground" | "stump" | "tree" | "rock" | "log",
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
		name = "Mossy Hollow",
		world = "Forest",
		spawn = Vector2.new(2, 10),
		flag = Vector2.new(108, 14),
		buildMin = Vector2.new(-6, -8),
		buildMax = Vector2.new(120, 44),
		seed = 11,
		pieces = {
			{ kind = "ground", x0 = -8, x1 = 10, top = 10 },
			{ kind = "ground", x0 = 24, x1 = 36, top = 6 },
			{ kind = "stump", x0 = 48, x1 = 53, top = 14 },
			{ kind = "ground", x0 = 64, x1 = 78, top = 8 },
			{ kind = "ground", x0 = 94, x1 = 122, top = 14 },
		},
	},
	{
		name = "Fallen Log",
		world = "Forest",
		spawn = Vector2.new(0, 12),
		flag = Vector2.new(106, 10),
		buildMin = Vector2.new(-6, -8),
		buildMax = Vector2.new(120, 44),
		seed = 23,
		pieces = {
			{ kind = "ground", x0 = -8, x1 = 8, top = 12 },
			{ kind = "log", x0 = 20, x1 = 56, top = 6 },
			{ kind = "rock", x0 = 68, x1 = 75, top = 3 },
			{ kind = "ground", x0 = 90, x1 = 122, top = 10 },
		},
	},
	{
		name = "Canopy Run",
		world = "Forest",
		spawn = Vector2.new(0, 20),
		flag = Vector2.new(110, 18),
		buildMin = Vector2.new(-6, -8),
		buildMax = Vector2.new(120, 48),
		seed = 37,
		pieces = {
			{ kind = "ground", x0 = -8, x1 = 8, top = 20 },
			{ kind = "tree", x0 = 22, x1 = 30, top = 14 },
			{ kind = "tree", x0 = 40, x1 = 46, top = 22 },
			{ kind = "tree", x0 = 58, x1 = 66, top = 12 },
			{ kind = "tree", x0 = 78, x1 = 85, top = 20 },
			{ kind = "ground", x0 = 98, x1 = 122, top = 18 },
		},
	},
} :: { Layout }

return Levels
