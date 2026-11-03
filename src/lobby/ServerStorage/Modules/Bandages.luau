-- Bandages: applying one from the inventory (ServerStorage.Modules.Inventory, item "Bandage")
-- (character attributes "Bandaging", "BandageDone" = the server time it finishes, and
-- "BandagePart" = the limb being wrapped, for StarterPlayerScripts.BandageView), and the wraps
-- left on the body. Each hit records a wound on a limb (PlayerHealth calls RecordWound).
-- Like Back 4 Blood's trauma damage, a wound holds back TraumaShare of the hit: health only
-- regenerates up to MaxHealth minus the open trauma (character attribute "Trauma", drawn on
-- the health bar). A bandage wraps the oldest open wound, clears its trauma and heals Heal.
-- Wraps are parts named "Bandage" inside the limb, so everyone sees them and ViewArms copies
-- the arm ones onto the viewmodel. Remotes.Bandage:FireServer() starts one,
-- FireServer("Cancel") stops it (the bandage isn't used up).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Inventory = require(script.Parent.Inventory)
local Classes = require(ReplicatedStorage.Shared.Classes)
-- Bandage challenge count (DATA, menu revamp): Modules.Progression, required on first use.
local progressionModule
local function progression()
	if progressionModule == nil then
		local m = script.Parent:FindFirstChild("Progression")
		local ok, P = false, nil
		if m then
			ok, P = pcall(require, m)
		end
		progressionModule = if ok and type(P) == "table" then P else false
	end
	return progressionModule or nil
end
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Bandages

local Bandages = {}

local wounds = setmetatable({}, { __mode = "k" }) -- [character] = { { Part, Trauma }, oldest first }
local active = setmetatable({}, { __mode = "k" }) -- [character] = the bandage going on now

local LIMBS = {
	R15 = {
		-- Forearms only: that's the part of the arm you see in first person.
		Arm = { Left = { "LeftLowerArm" }, Right = { "RightLowerArm" } },
		Leg = { Left = { "LeftUpperLeg", "LeftLowerLeg" }, Right = { "RightUpperLeg", "RightLowerLeg" } },
		Torso = { "UpperTorso", "LowerTorso" },
		Head = { "Head" },
	},
	R6 = {
		Arm = { Left = { "Left Arm" }, Right = { "Right Arm" } },
		Leg = { Left = { "Left Leg" }, Right = { "Right Leg" } },
		Torso = { "Torso" },
		Head = { "Head" },
	},
}

local function pickWeighted(weights)
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = math.random() * total
	for name, w in weights do
		roll -= w
		if roll <= 0 then
			return name
		end
	end
	return next(weights)
end

-- Where a hit from fromPos lands: a weighted area, on the side the hit came from.
local function woundPart(character, fromPos)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	local rig = LIMBS[if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"]
	local area = rig[pickWeighted(CFG.WoundWeights)]
	local list = area
	if area.Left then
		local side = if fromPos and root.CFrame:PointToObjectSpace(fromPos).X < 0 then "Left" else "Right"
		list = area[side]
	end
	return list[math.random(#list)]
end

local function traumaOf(character)
	local total = 0
	for _, wound in wounds[character] or {} do
		total += wound.Trauma
	end
	return math.min(total, CFG.TraumaMax)
end

local function publish(character)
	character:SetAttribute("Trauma", traumaOf(character))
end

-- How much health the open wounds hold back from regenerating.
function Bandages.Trauma(character)
	return traumaOf(character)
end

-- amount: the damage of the hit (0 for a hit taken while down).
function Bandages.RecordWound(character, fromPos, amount)
	local name = woundPart(character, fromPos)
	if name and character:FindFirstChild(name) then
		wounds[character] = wounds[character] or {}
		table.insert(wounds[character], { Part = name, Trauma = (amount or 0) * CFG.TraumaShare })
		publish(character)
	end
end

-- Wraps a band round the part: a cylinder along a limb, a flat band round the torso.
local function wrap(part)
	local band = Instance.new("Part")
	band.Name = "Bandage"
	band.Material = Enum.Material.Fabric
	band.Color = CFG.Color:Lerp(Color3.fromRGB(150, 60, 50), math.random() * 0.12)
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Massless = true
	band.TopSurface = Enum.SurfaceType.Smooth
	band.BottomSurface = Enum.SurfaceType.Smooth
	local size = part.Size
	local isTorso = part.Name:find("Torso") ~= nil
	local isHead = part.Name == "Head"
	local height = if isHead then 0.32 else math.clamp(size.Y * 0.4, 0.3, 0.8)
	-- Not two wraps in the same spot: slide along the limb.
	local used = #part:GetChildren()
	local along = if isHead then size.Y * 0.18 else ((math.random() - 0.5) * 0.5 * (size.Y - height))
	along += (used % 3 - 1) * 0.05
	if isTorso then
		band.Shape = Enum.PartType.Block
		band.Size = Vector3.new(size.X + 0.06, height, size.Z + 0.06)
		band.CFrame = part.CFrame * CFrame.new(0, along, 0)
	else
		band.Shape = Enum.PartType.Cylinder
		local d = math.max(size.X, size.Z) + 0.06
		band.Size = Vector3.new(height, d, d)
		band.CFrame = part.CFrame * CFrame.new(0, along, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
	band:SetAttribute("Along", along / size.Y)
	band:SetAttribute("Torso", isTorso)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = band
	weld.Part1 = part
	weld.Parent = band
	band.Parent = part
	return band
end

local function count(player)
	return Inventory.Count(player, "Bandage")
end

local function stop(character)
	active[character] = nil
	character:SetAttribute("Bandaging", nil)
	character:SetAttribute("BandageDone", nil)
	character:SetAttribute("BandagePart", nil)
end

local function apply(player, action)
	local character = player.Character
	if not character then
		return
	end
	if action == "Cancel" then
		if active[character] then
			stop(character)
		end
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or count(player) <= 0 then
		return
	end
	if active[character] or character:GetAttribute("Downed") or character:GetAttribute("Devoured") then
		return
	end
	if humanoid.Health >= humanoid.MaxHealth and traumaOf(character) <= 0 then
		return
	end
	-- The oldest open wound, or (hurt with no wound on record) a spot picked like a hit.
	local list = wounds[character]
	local wound = list and list[1] or { Part = woundPart(character, nil), Trauma = 0 }
	if not wound.Part then
		return
	end
	local job = { Wound = wound }
	active[character] = job
	character:SetAttribute("Bandaging", true)
	character:SetAttribute("BandageDone", workspace:GetServerTimeNow() + CFG.ApplyTime)
	character:SetAttribute("BandagePart", wound.Part)
	local head = character:FindFirstChild("Head") or character.PrimaryPart
	SoundKit.Play("Bandage/Rip", { Parent = head })
	task.delay(0.35, function()
		if active[character] == job then
			SoundKit.Play("Bandage/Wrap", { Parent = head })
		end
	end)
	task.delay(CFG.ApplyTime, function()
		if active[character] ~= job or not character.Parent then
			return
		end
		stop(character)
		if humanoid.Health <= 0 or character:GetAttribute("Downed") or not Inventory.Take(player, "Bandage", 1) then
			return
		end
		local open = wounds[character]
		local i = open and table.find(open, wound)
		if i then
			table.remove(open, i)
		end
		publish(character)
		local ceiling = humanoid.MaxHealth - traumaOf(character)
		humanoid.Health = math.max(humanoid.Health, math.min(ceiling, humanoid.Health + CFG.Heal * Classes.Perk(player, "BandageHeal")))
		local P = progression()
		if P and P.Event then
			task.spawn(pcall, P.Event, player, "Bandage")
		end
		local part = character:FindFirstChild(wound.Part)
		if part then
			wrap(part)
		end
	end)
end

-- Going down stops a bandage half-way (it isn't used up).
local function cancelOnDown(character)
	character:SetAttribute("Trauma", 0)
	character:GetAttributeChangedSignal("Downed"):Connect(function()
		if character:GetAttribute("Downed") and active[character] then
			stop(character)
		end
	end)
end

function Bandages.Start()
	local function onPlayer(player)
		player.CharacterAdded:Connect(cancelOnDown)
		if player.Character then
			cancelOnDown(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Remotes.Bandage.OnServerEvent:Connect(apply)
end

return Bandages
