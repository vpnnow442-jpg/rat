--!strict
-- Hand-authored layouts, stored as plain data.
-- The same shape will be what community levels save to DataStores later.
--
-- Design rules every layout follows:
--   * start and flag are on solid ground with clear space around them
--   * the bare layout has a few gaps you can't clear without building:
--     the course only works once players add to it (that's the game)
--   * at least two routes somewhere (a high one and a low one), so one
--     player's trap never blocks the only way through
--   * big open air between pieces, because that's where players build
--
-- Reference: single jump ~7 studs high, double jump ~12, ~18 across.

export type Piece = {
	kind: "ground" | "ledge" | "stump" | "tree" | "rock" | "log" | "cliff" | "ice" | "girder" | "pipe" | "conveyor",
	x0: number,
	x1: number,
	top: number,
	speed: number?, -- conveyors: studs/s, negative runs backwards
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
			{ kind = "ground", x0 = 30, x1 = 42, top = 6 },
			{ kind = "stump", x0 = 52, x1 = 57, top = 16 },
			{ kind = "ledge", x0 = 66, x1 = 80, top = 24 },
			{ kind = "ground", x0 = 72, x1 = 96, top = 4 },
			{ kind = "rock", x0 = 112, x1 = 117, top = 12 },
			{ kind = "ground", x0 = 124, x1 = 152, top = 8 },
			{ kind = "stump", x0 = 140, x1 = 145, top = 18 },
			{ kind = "ledge", x0 = 158, x1 = 172, top = 28 },
			{ kind = "ground", x0 = 168, x1 = 186, top = 10 },
			{ kind = "ground", x0 = 204, x1 = 232, top = 16 },
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
			{ kind = "rock", x0 = 74, x1 = 79, top = 2 },
			{ kind = "ground", x0 = 88, x1 = 110, top = 10 },
			{ kind = "ledge", x0 = 100, x1 = 116, top = 28 },
			{ kind = "log", x0 = 124, x1 = 160, top = 14 },
			{ kind = "rock", x0 = 172, x1 = 177, top = 6 },
			{ kind = "ledge", x0 = 168, x1 = 182, top = 30 },
			{ kind = "ground", x0 = 196, x1 = 232, top = 12 },
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
			{ kind = "tree", x0 = 97, x1 = 102, top = 30 },
			{ kind = "tree", x0 = 116, x1 = 124, top = 16 },
			{ kind = "tree", x0 = 136, x1 = 142, top = 26 },
			{ kind = "tree", x0 = 154, x1 = 162, top = 14 },
			{ kind = "tree", x0 = 174, x1 = 180, top = 24 },
			{ kind = "ground", x0 = 198, x1 = 232, top = 18 },
		},
	},
} :: { Layout }

-- MOUNTAIN: snow, cliffs, and natural ice that keeps your momentum
Levels.Mountain = {
	{
		name = "Frosty Ridge",
		world = "Mountain",
		spawn = Vector2.new(0, 12),
		flag = Vector2.new(214, 20),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 68),
		seed = 51,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 12, top = 12 },
			{ kind = "ice", x0 = 26, x1 = 48, top = 8 },
			{ kind = "cliff", x0 = 58, x1 = 64, top = 18 },
			{ kind = "ledge", x0 = 72, x1 = 86, top = 30 },
			{ kind = "ground", x0 = 76, x1 = 98, top = 6 },
			{ kind = "cliff", x0 = 112, x1 = 118, top = 18 },
			{ kind = "ice", x0 = 128, x1 = 152, top = 12 },
			{ kind = "ledge", x0 = 162, x1 = 174, top = 22 },
			{ kind = "cliff", x0 = 180, x1 = 186, top = 14 },
			{ kind = "ground", x0 = 202, x1 = 232, top = 20 },
		},
	},
	{
		name = "Avalanche Pass",
		world = "Mountain",
		spawn = Vector2.new(-2, 22),
		flag = Vector2.new(216, 24),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 72),
		seed = 67,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 10, top = 22 },
			{ kind = "ledge", x0 = 24, x1 = 36, top = 16 },
			{ kind = "ice", x0 = 48, x1 = 68, top = 10 },
			{ kind = "cliff", x0 = 80, x1 = 85, top = 20 },
			{ kind = "ground", x0 = 96, x1 = 120, top = 14 },
			{ kind = "ledge", x0 = 106, x1 = 118, top = 34 },
			{ kind = "cliff", x0 = 132, x1 = 137, top = 22 },
			{ kind = "ice", x0 = 148, x1 = 172, top = 16 },
			{ kind = "cliff", x0 = 184, x1 = 188, top = 28 },
			{ kind = "ground", x0 = 202, x1 = 232, top = 24 },
		},
	},
} :: { Layout }

-- FACTORY: steel girders, pipes, and conveyor belts (some run backwards)
Levels.Factory = {
	{
		name = "Assembly Line",
		world = "Factory",
		spawn = Vector2.new(0, 10),
		flag = Vector2.new(216, 18),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 64),
		seed = 83,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 12, top = 10 },
			{ kind = "conveyor", x0 = 26, x1 = 48, top = 8, speed = 10 },
			{ kind = "pipe", x0 = 58, x1 = 62, top = 18 },
			{ kind = "girder", x0 = 70, x1 = 86, top = 26 },
			{ kind = "conveyor", x0 = 76, x1 = 102, top = 4, speed = -9 },
			{ kind = "pipe", x0 = 114, x1 = 118, top = 14 },
			{ kind = "girder", x0 = 126, x1 = 142, top = 12 },
			{ kind = "conveyor", x0 = 152, x1 = 174, top = 16, speed = 12 },
			{ kind = "girder", x0 = 178, x1 = 190, top = 24 },
			{ kind = "ground", x0 = 204, x1 = 232, top = 18 },
		},
	},
	{
		name = "Pipe Dream",
		world = "Factory",
		spawn = Vector2.new(-2, 18),
		flag = Vector2.new(214, 12),
		buildMin = Vector2.new(-8, -8),
		buildMax = Vector2.new(228, 66),
		seed = 97,
		pieces = {
			{ kind = "ground", x0 = -12, x1 = 10, top = 18 },
			{ kind = "pipe", x0 = 22, x1 = 26, top = 14 },
			{ kind = "girder", x0 = 34, x1 = 50, top = 22 },
			{ kind = "conveyor", x0 = 40, x1 = 70, top = 6, speed = 11 },
			{ kind = "pipe", x0 = 80, x1 = 84, top = 16 },
			{ kind = "girder", x0 = 92, x1 = 108, top = 30 },
			{ kind = "conveyor", x0 = 98, x1 = 126, top = 10, speed = -10 },
			{ kind = "pipe", x0 = 138, x1 = 142, top = 20 },
			{ kind = "girder", x0 = 152, x1 = 170, top = 14 },
			{ kind = "pipe", x0 = 182, x1 = 186, top = 20 },
			{ kind = "ground", x0 = 200, x1 = 232, top = 12 },
		},
	},
} :: { Layout }

function Levels.all(): { Layout }
	local list = {}
	for _, group in { Levels.Forest, Levels.Mountain, Levels.Factory } do
		for _, l in group do
			table.insert(list, l)
		end
	end
	return list
end

return Levels
