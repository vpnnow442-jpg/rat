-- Owns characters: which animal you are, where your body is, whether you can move.
-- Nobody ever "dies" in the Roblox sense; we park and release characters instead,
-- which means no respawn delays and no default death screen.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Config = require(Shared.Config)
local Style = require(Shared.Style)

local PlayerService = {}

PlayerService.species = {} :: { [Player]: string }

local function pickSpecies(): string
	local used = {}
	for _, id in PlayerService.species do
		used[id] = (used[id] or 0) + 1
	end
	local best, bestCount = Characters.List[1].id, math.huge
	for _, s in Characters.List do
		local n = used[s.id] or 0
		-- least-used first, random tiebreak so it isn't always the fox
		if n < bestCount or (n == bestCount and math.random() < 0.5) then
			best, bestCount = s.id, n
		end
	end
	return best
end

local function nameTag(model: Model, player: Player)
	local head = model:FindFirstChild("Head") :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(160, 22)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Style.Font.Title
	label.TextSize = 15
	label.TextColor3 = Style.UI.Paper
	label.Text = player.DisplayName
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.6
	stroke.Color = Style.UI.Ink
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = head
end

function PlayerService.root(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function PlayerService.spawn(player: Player)
	if player.Character then
		player.Character:Destroy()
	end
	local species = PlayerService.species[player] or pickSpecies()
	PlayerService.species[player] = species

	local model = Characters.build(species)
	model.Name = player.Name
	nameTag(model, player)
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true
	model:PivotTo(CFrame.new(Config.World.Hold))
	model.Parent = workspace
	player.Character = model

	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.Died:Connect(function()
		-- Shouldn't happen, but never leave someone without a body
		task.wait(0.5)
		if player.Parent then
			PlayerService.spawn(player)
		end
	end)
end

local function setState(player: Player, cf: CFrame, anchored: boolean)
	local char = player.Character
	local root = PlayerService.root(player)
	if not char or not root then
		return
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(cf)
	if not anchored then
		root.Anchored = false
		root:SetNetworkOwner(player)
	end
end

function PlayerService.park(player: Player)
	setState(player, CFrame.new(Config.World.Hold), true)
	local char = player.Character
	if char then
		char:SetAttribute("FailAt", nil)
		char:SetAttribute("VictoryAt", nil)
	end
end

-- Line up at the start, facing the flag, frozen until release()
function PlayerService.toStart(player: Player, spawn: Vector3, slot: number)
	local pos = spawn + Vector3.new(-((slot - 1) % 4) * 1.6, 2.3, 0)
	setState(player, CFrame.lookAt(pos, pos + Vector3.xAxis), true)
	local char = player.Character
	if char then
		char:SetAttribute("FailAt", nil)
		char:SetAttribute("VictoryAt", nil)
	end
end

function PlayerService.release(player: Player)
	local root = PlayerService.root(player)
	if root then
		root.Anchored = false
		root:SetNetworkOwner(player)
	end
end

function PlayerService.freeze(player: Player)
	local root = PlayerService.root(player)
	if root then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Swap animal. Only called when the player isn't mid-race.
function PlayerService.setSpecies(player: Player, speciesId: string)
	if PlayerService.species[player] == speciesId then
		return
	end
	PlayerService.species[player] = speciesId
	local root = PlayerService.root(player)
	local cf = if root then root.CFrame else CFrame.new(Config.World.Hold)
	local anchored = if root then root.Anchored else true
	PlayerService.spawn(player)
	-- keep them exactly where they were (on the flag after a win, etc.)
	local newRoot = PlayerService.root(player)
	if newRoot and player.Character then
		player.Character:PivotTo(cf)
		newRoot.Anchored = anchored
	end
end

function PlayerService.init()
	Players.CharacterAutoLoads = false
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)

	local function added(player: Player)
		PlayerService.spawn(player)
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		task.spawn(added, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerService.species[player] = nil
	end)
end

return PlayerService
