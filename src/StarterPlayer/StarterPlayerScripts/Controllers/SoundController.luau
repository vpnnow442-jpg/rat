-- Every sound in the game goes through here, so swapping in real audio later
-- is a matter of editing this one table.
--
-- PLACEHOLDERS: these are sounds that ship inside the Roblox client.
-- Replace with Creator Store audio ("rbxassetid://123...") before release.

local SoundService = game:GetService("SoundService")

local SOUNDS = {
	jump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, pitch = 1.15 },
	airJump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, pitch = 1.45 },
	land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.35, pitch = 1.1 },
	spring = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.6, pitch = 0.7 },
	bonk = { id = "rbxasset://sounds/collide.wav", volume = 0.7, pitch = 0.8 },
	fail = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.45, pitch = 1.05 },
	splash = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.5, pitch = 1 },
	place = { id = "rbxasset://sounds/clickfast.wav", volume = 0.6, pitch = 0.9 },
	pick = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4, pitch = 1.3 },
	error = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, pitch = 0.6 },
	tick = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35, pitch = 1.6 },
	go = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.2 },
	goal = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.5 },
	points = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4, pitch = 2 },
	bar = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25, pitch = 1.8 },
	stamp = { id = "rbxasset://sounds/collide.wav", volume = 0.45, pitch = 1.3 },
	-- no explosion sound on purpose: the bomb is a soft "poof" (whoosh) only
	poof = { id = "rbxasset://sounds/swoosh.wav", volume = 0.45, pitch = 0.8 },
	cannon = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35, pitch = 0.5 },
	bumper = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.5, pitch = 1.8 },
	whoosh = { id = "rbxasset://sounds/swoosh.wav", volume = 0.4, pitch = 1 },
	grab = { id = "rbxasset://sounds/clickfast.wav", volume = 0.6, pitch = 1.1 },
	crate = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, pitch = 0.65 },
	hover = { id = "rbxasset://sounds/clickfast.wav", volume = 0.15, pitch = 2.2 },
	victory = { id = "rbxasset://sounds/victory.wav", volume = 0.5, pitch = 1 },
}

local SoundController = {}

local group = Instance.new("SoundGroup")
group.Name = "SFX"
group.Volume = 0.8
group.Parent = SoundService

local templates = {} :: { [string]: Sound }

function SoundController.init()
	for name, def in SOUNDS do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.id
		s.Volume = def.volume
		s.PlaybackSpeed = def.pitch
		s.SoundGroup = group
		s.RollOffMaxDistance = 160
		s.RollOffMinDistance = 30
		templates[name] = s
	end
end

-- 2D sound (UI, your own actions). pitch multiplies the base pitch.
function SoundController.play(name: string, pitchJitter: number?, pitch: number?)
	local t = templates[name]
	if not t then
		return
	end
	local s = t:Clone()
	if pitchJitter then
		s.PlaybackSpeed *= 1 + (math.random() - 0.5) * pitchJitter
	end
	if pitch then
		s.PlaybackSpeed *= pitch
	end
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Positional sound (other players, objects)
function SoundController.playAt(name: string, where: BasePart | Attachment, pitchJitter: number?)
	local t = templates[name]
	if not t then
		return
	end
	local s = t:Clone()
	if pitchJitter then
		s.PlaybackSpeed *= 1 + (math.random() - 0.5) * pitchJitter
	end
	s.Parent = where
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

return SoundController
