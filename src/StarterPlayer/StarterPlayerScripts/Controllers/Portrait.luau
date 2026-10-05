-- Little animal-head portraits (ViewportFrames) used for cursors and tags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)

local Portrait = {}

-- A transparent ViewportFrame showing just the head of a species, in a
-- three-quarter view. Size it however you like.
function Portrait.head(speciesId: string?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(190, 184, 176)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-0.5, -1, 0.4)
	vp.Interactable = false
	local model = Characters.build(speciesId or Characters.List[1].id)
	model.Parent = vp
	local head = model:FindFirstChild("Head") :: BasePart?
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vp
	vp.CurrentCamera = cam
	local target = if head then head.Position + Vector3.new(0, 0.25, -0.2) else Vector3.zero
	cam.CFrame = CFrame.lookAt(target + Vector3.new(3.2, 0.9, -4.6), target)
	return vp
end

return Portrait
