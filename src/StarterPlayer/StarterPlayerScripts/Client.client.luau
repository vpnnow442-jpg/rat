-- Client entry point. Controllers are plain modules; order matters only here.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Controllers = script.Parent:WaitForChild("Controllers")

local State = require(Controllers.State)
local Sound = require(Controllers.SoundController)
local Fx = require(Controllers.FxController)
local Hud = require(Controllers.HudController)
local Camera = require(Controllers.CameraController)
local Movement = require(Controllers.MovementController)
local Objects = require(Controllers.ObjectController)
local Pick = require(Controllers.PickController)
local Build = require(Controllers.BuildController)
local Animator = require(Controllers.CharacterAnimator)
local Menu = require(Controllers.MenuController)

State.init() -- first: everyone else reads State
Sound.init()
Fx.init()
Hud.init()
Camera.init()
Movement.init()
Objects.init()
Pick.init()
Build.init()
Animator.init()
task.spawn(Menu.init) -- waits for the loading screen to finish
