-- Night ambience on this client: faulty lamps flicker and buzz, wind under everything,
-- and a fear sting when a mob closes in after a quiet spell (GameConfig.Night).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local Sounds = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("Night")

local Night = GameConfig.Night
local LampSettings = Night.Lamps
local StingSettings = Night.Stinger

local function roll(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

-- Lamps ---------------------------------------------------------------------------------

local function setLamp(lamp, k)
	for light, base in lamp.Lights do
		light.Brightness = base * k
	end
	local lit = k > 0.3
	for b in lamp.Beams do
		b.Enabled = lit
	end
	for part, material in lamp.Neon do
		part.Material = if lit then material else Enum.Material.SmoothPlastic
	end
	if lamp.Buzz then
		lamp.Buzz.Volume = lamp.BuzzVolume * (if lit then 1 else 0.15)
	end
end

local function runFaulty(model, lamp)
	while model.Parent do
		task.wait(roll(LampSettings.BurstGap))
		for _ = 1, math.floor(roll(LampSettings.BurstFlicks)) do
			setLamp(lamp, math.random() * 0.25)
			task.wait(roll(LampSettings.FlickTime))
			setLamp(lamp, 0.7 + math.random() * 0.3)
			task.wait(roll(LampSettings.FlickTime))
		end
		if math.random() < LampSettings.DarkChance then
			setLamp(lamp, 0)
			task.wait(roll(LampSettings.DarkTime))
		end
		setLamp(lamp, 1)
	end
end

local function addLamp(model)
	if not model:IsDescendantOf(workspace) or not model:GetAttribute("Faulty") then
		return
	end
	-- Lamps stream in whole (ModelStreamingMode Atomic), but give the parts a moment anyway.
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		model.DescendantAdded:Wait()
		task.wait()
	end
	local lamp = { Lights = {}, Beams = {}, Neon = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("Light") then
			lamp.Lights[d] = d.Brightness
		elseif d:IsA("Beam") then
			lamp.Beams[d] = true
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			lamp.Neon[d] = d.Material
		end
	end
	local holder = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if holder then
		local buzz = Sounds.LampBuzz:Clone()
		buzz.Parent = holder
		buzz:Play()
		lamp.Buzz = buzz
		lamp.BuzzVolume = buzz.Volume
	end
	task.spawn(runFaulty, model, lamp)
end

CollectionService:GetInstanceAddedSignal("Lamp"):Connect(addLamp)
for _, model in CollectionService:GetTagged("Lamp") do
	task.spawn(addLamp, model)
end

-- Wind ----------------------------------------------------------------------------------

local wind = Sounds.Wind:Clone()
wind.Volume = Night.Ambience.WindVolume
wind.Parent = SoundService
wind:Play()

-- Sting ---------------------------------------------------------------------------------

local lastNear = -math.huge -- last time any mob was inside CalmRange
local lastSting = -math.huge

while true do
	task.wait(0.2)
	local camera = workspace.CurrentCamera
	local here = camera.CFrame.Position
	local closest = math.huge
	for _, enemy in CollectionService:GetTagged("Enemy") do
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local root = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and enemy:IsDescendantOf(workspace) then
			closest = math.min(closest, (root.Position - here).Magnitude)
		end
	end
	local now = os.clock()
	if closest < StingSettings.Near and now - lastNear > StingSettings.CalmTime
		and now - lastSting > StingSettings.Cooldown then
		lastSting = now
		SoundKit.Play("Night/Stinger")
	end
	if closest < StingSettings.CalmRange then
		lastNear = now
	end
end
