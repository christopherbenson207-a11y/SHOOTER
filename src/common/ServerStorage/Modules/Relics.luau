-- Endless mode's relics (HORROR-SHOOTER-ENDLESS.md; numbers: GameConfig.Endless). When a round is
-- cleared MatchServer calls Offer: three relics from the pool stand on floor sigils (a candle on a
-- glowing ring) in workspace.Relics. Hold E on one and it's yours for the run; everyone sees the
-- same three and picks their own (StarterPlayerScripts.RelicClient darkens them for you once you've
-- picked). Clear takes them away when the next round starts. A relic lands as player attributes
-- the systems read: RelicDamage, RelicHead, RelicArmor, RelicRegen, RelicPoints (shares added to
-- 1), RelicHealth (flat), Relic_<name> counts, and RelicRound (the round the player last picked in).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Endless
local STATS = { "RelicDamage", "RelicHead", "RelicArmor", "RelicRegen", "RelicPoints", "RelicHealth" }

local Relics = {}

local folder = workspace:FindFirstChild("Relics")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Relics"
	folder.Parent = workspace
end

-- The round the sigils standing now belong to.
local round = 0

function Relics.Reset(player)
	for _, stat in STATS do
		player:SetAttribute(stat, nil)
	end
	for name in CFG.Relics do
		player:SetAttribute("Relic_" .. name, nil)
	end
	player:SetAttribute("RelicRound", nil)
end

function Relics.Apply(player, name)
	local relic = CFG.Relics[name]
	if not relic then
		return
	end
	player:SetAttribute("Relic_" .. name, (player:GetAttribute("Relic_" .. name) or 0) + 1)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if relic.Stat then
		local key = "Relic" .. relic.Stat
		local value = (player:GetAttribute(key) or 0) + relic.Add
		if relic.Cap then
			value = math.min(value, relic.Cap)
		end
		player:SetAttribute(key, value)
		-- More health lands on this life too; PlayerHealth gives every new life RelicHealth.
		if relic.Stat == "Health" and humanoid and humanoid.Health > 0 then
			humanoid.MaxHealth += relic.Add
			humanoid.Health += relic.Add
		end
	end
	if relic.SelfRevives then
		local start = player:GetAttribute("SelfRevivesStart") or GameConfig.Player.Downed.SelfRevives
		player:SetAttribute("SelfRevivesStart", start + relic.SelfRevives)
		if character then
			character:SetAttribute("SelfRevives", (character:GetAttribute("SelfRevives") or 0) + relic.SelfRevives)
		end
	end
end

-- A candle on a glowing ring, in the relic's colour, with the prompt that takes it.
local function sigil(at, relic, name)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Relic", name)

	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, 3.6, 3.6)
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = relic.Color
	ring.Transparency = 0.55
	ring.Parent = model

	local candle = Instance.new("Part")
	candle.Name = "Candle"
	candle.Shape = Enum.PartType.Cylinder
	candle.Size = Vector3.new(1.1, 0.6, 0.6)
	candle.CFrame = CFrame.new(at + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.rad(90))
	candle.Anchored = true
	candle.CanCollide = false
	candle.CanTouch = false
	candle.Material = Enum.Material.SmoothPlastic
	candle.Color = Color3.fromRGB(226, 214, 190)
	candle.Parent = model

	local flame = Instance.new("Part")
	flame.Name = "Flame"
	flame.Shape = Enum.PartType.Ball
	flame.Size = Vector3.new(0.35, 0.35, 0.35)
	flame.Position = at + Vector3.new(0, 1.3, 0)
	flame.Anchored = true
	flame.CanCollide = false
	flame.CanQuery = false
	flame.CanTouch = false
	flame.CastShadow = false
	flame.Material = Enum.Material.Neon
	flame.Color = relic.Color
	flame.Parent = model
	local light = Instance.new("PointLight")
	light.Color = relic.Color
	light.Range = 9
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = flame

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakePrompt"
	prompt.ActionText = relic.Name
	prompt.ObjectText = relic.Text
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = candle
	model.PrimaryPart = candle

	prompt.Triggered:Connect(function(player)
		if not player:GetAttribute("InMatch") or player:GetAttribute("RelicRound") == round then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or character:GetAttribute("Downed") then
			return
		end
		player:SetAttribute("RelicRound", round)
		Relics.Apply(player, name)
		SoundKit.Play("Pickup/Bandage", { Position = candle.Position, Speed = 0.75 })
		Remotes.Match:FireClient(player, "Notice", string.upper(relic.Name) .. "  \u{00B7}  " .. relic.Text)
	end)
	model.Parent = folder
	return model
end

function Relics.Clear()
	folder:ClearAllChildren()
end

-- Three relics from the pool (never the same one twice) on sigils at the given floor points, for
-- the round just cleared.
function Relics.Offer(points, wave)
	Relics.Clear()
	round = wave
	local names = {}
	for name in CFG.Relics do
		table.insert(names, name)
	end
	table.sort(names)
	for i = 1, math.min(CFG.Offer, #names, #points) do
		local pick = table.remove(names, math.random(#names))
		sigil(points[i], CFG.Relics[pick], pick)
	end
	if #points > 0 then
		Remotes.Match:FireAllClients("Notice", "CHOOSE A RELIC")
	end
end

return Relics
