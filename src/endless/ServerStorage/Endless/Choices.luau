-- "Pick one" on the floor: a candle on a glowing ring per option, in the option's colour (the lobby
-- Endless relic sigils). Hold the prompt on one to take it. Relics after a round and the ascension
-- altar's boosts both use it. Everything is world parts and ProximityPrompts; no screen UI.
--   Choices.Offer(spec) -> handle with :Clear()
--     spec.Points   floor positions, one per option
--     spec.Options  list of {Id, Name, Text, Color}
--     spec.For      a Player: only they may take one (the offer closes on their pick); nil: anyone
--     spec.Group, spec.Round  read by clients to darken what you can't take (EndlessFx)
--     spec.Hold     prompt hold time
--     spec.OnPick(player, option) -> true to close the whole offer
--     spec.Expires, spec.OnExpire  seconds until the offer closes by itself, and what happens then
-- Model attributes: Choice (option id), For (UserId or 0), Group, Round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)

local Choices = {}

local function folder()
	local f = workspace:FindFirstChild("Choices")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Choices"
		f.Parent = workspace
	end
	return f
end

local function sigil(at: Vector3, option, spec)
	local model = Instance.new("Model")
	model.Name = option.Id
	model:SetAttribute("Choice", option.Id)
	model:SetAttribute("For", if spec.For then spec.For.UserId else 0)
	model:SetAttribute("Group", spec.Group or "")
	model:SetAttribute("Round", spec.Round or 0)

	local function part(name, shape, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local ring = part("Ring", Enum.PartType.Cylinder, Vector3.new(0.08, 3.6, 3.6), CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), option.Color, Enum.Material.Neon)
	ring.Transparency = 0.55
	ring.CanQuery = false
	ring.CastShadow = false
	local candle = part("Candle", Enum.PartType.Cylinder, Vector3.new(1.1, 0.6, 0.6), CFrame.new(at + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(226, 214, 190), Enum.Material.SmoothPlastic)
	local flame = part("Flame", Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(at + Vector3.new(0, 1.3, 0)), option.Color, Enum.Material.Neon)
	flame.CanQuery = false
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = option.Color
	light.Range = 9
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = flame
	local prompt = Util.Prompt(candle, option.Name, option.Text, spec.Hold or 0.6, 8)
	prompt.Name = "TakePrompt"
	model.PrimaryPart = candle
	model.Parent = folder()
	return model, prompt
end

function Choices.Offer(spec)
	local handle = { Models = {}, Closed = false }
	function handle:Clear()
		if self.Closed then
			return
		end
		self.Closed = true
		for _, m in self.Models do
			m:Destroy()
		end
		table.clear(self.Models)
	end
	for i, option in spec.Options do
		local at = spec.Points[i]
		if at then
			local model, prompt = sigil(at, option, spec)
			table.insert(handle.Models, model)
			prompt.Triggered:Connect(function(player)
				if handle.Closed or (spec.For and player ~= spec.For) then
					return
				end
				Sfx.Play("Pickup/Bandage", { Position = at, Speed = 0.75 })
				if spec.OnPick(player, option) then
					handle:Clear()
				end
			end)
		end
	end
	if spec.Expires then
		task.delay(spec.Expires, function()
			if not handle.Closed then
				handle:Clear()
				if spec.OnExpire then
					spec.OnExpire()
				end
			end
		end)
	end
	return handle
end

-- Everything on the floor goes (run over).
function Choices.ClearAll()
	folder():ClearAllChildren()
end

return Choices
