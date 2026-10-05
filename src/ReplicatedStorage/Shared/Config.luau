--!strict
-- Every tuning number lives here so playtesting changes are one-line edits.

local Config = {}

Config.Match = {
	MinPlayers = 1, -- 1 so it can be tested solo in Studio
	PointsToWin = 600, -- first across the line wins...
	MaxRounds = 12, -- ...or whoever leads after this many rounds
	LastRoundMultiplier = 2,
	IntroTime = 5,
	PickTime = 12,
	BuildTime = 25,
	CountdownTime = 3,
	RunTime = 60,
	ResultsTime = 8,
	WinnerTime = 10,
	BoxMin = 4, -- the pick box holds 4-7 pieces...
	BoxMax = 7,
	BoxSpare = 1, -- ...but always at least players + this many
}

Config.Scoring = {
	Place = { 100, 75, 50, 25 }, -- 5th and lower get the last value
	Trap = 25, -- per opponent your object takes out
	TrapCap = 75, -- per round, so one trap can't decide the whole match
	Clutch = 15, -- finish with under ClutchWindow seconds left
	ClutchWindow = 5,
	OwnRoute = 15, -- finish after touching a route piece you placed
	Coin = 40, -- grab a coin AND reach the flag with it
}

Config.Movement = {
	WalkSpeed = 22,
	JumpPower = 54,
	AirJumpPower = 46,
	AirJumps = 1,
	CoyoteTime = 0.1,
	JumpBuffer = 0.12,
	WallSlideSpeed = 9,
	WallJumpPower = Vector3.new(26, 50, 0),
	WallJumpLock = 0.18,
	IceAccel = 2.2, -- lower = slipperier
	HoneySpeed = 0.45,
	HoneyJump = 0.6,
}

Config.Objects = {
	SpringPower = 92,
	FanAccel = 150,
	FanMaxSpeed = 55,
	ConveyorSpeed = 14,
	HammerKnock = Vector3.new(62, 34, 0),
	CannonSpeed = 24,
	CannonInterval = 2.6,
	CannonKnock = Vector3.new(58, 30, 0),
	CrumbleDelay = 0.55,
	CrumbleRespawn = 3.5,
	BombRadius = 5,
	BumperKnock = 70,
	PunchKnock = Vector3.new(82, 26, 0),
	JetpackTime = 3,
	JetpackLift = 30,
}

-- 2.5D: everything lives on the Z = 0 plane, the camera looks down -Z.
Config.World = {
	KillY = -12,
	Hold = Vector3.new(0, 80, 420), -- behind the camera, where parked characters wait
	GoalMinTime = 1.5, -- anti-teleport sanity check
}

return Config
