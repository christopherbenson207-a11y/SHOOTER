--!strict
-- The radio tower's parts (GameConfig.Parts; nights only, workspace Nights set by MatchServer).
--   The tower stands on the hill behind the house (Map.RadioTower: Tower, the cabinet at its
--   foot once imported, CabinetSpot, InstallPoint, Slots.<part>, TopLight). In each lull in
--   Parts.Lulls (and any lull after the last of them while parts are missing) the next part in
--   Parts.Order comes out, unless one is out already: a copy of ReplicatedStorage.Assets.TowerParts.<name>
--   lies on a spot in Map.PartSpots (one not used yet this match if there is one) with an
--   amber glow and a "Pick up" prompt. Whoever picks it up carries it on their back; reaching
--   the cabinet (InstallRadius of InstallPoint) puts it in: it takes its slot and the cabinet's
--   lamp for it turns green. A Beacon catch (BeaconServer fires ServerStorage.DropPart), dying
--   or leaving puts the part back on its spot. A part carried home at night stays carried.
--   With every part in, the top light blinks and MatchServer makes the next night the last.
-- Workspace attributes for the rest of the game: TowerNeed, TowerParts, PartOut (name of the
-- part out, or nil), PartAt (where it lies, nil while carried). On the carrier's character:
-- CarryingPart. Cues on Remotes.Match: PartOut (name), PartIn (name, count, need), TowerDone.
-- Studio testing: the player attribute DebugPickUp picks the part up from anywhere (test tools
-- can't press prompts).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local matchRemote = Remotes:WaitForChild("Match") :: RemoteEvent

local CFG = GameConfig.Parts
local templates = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("TowerParts")
local map = workspace:WaitForChild("Map")
local tower = map:WaitForChild("RadioTower")
local spotsFolder = map:WaitForChild("PartSpots")
local installPoint = tower:WaitForChild("InstallPoint") :: BasePart
local slots = tower:WaitForChild("Slots")
local topLight = tower:WaitForChild("TopLight") :: BasePart

local dropEvent = ServerStorage:FindFirstChild("DropPart") :: BindableEvent?
if not dropEvent then
	local e = Instance.new("BindableEvent")
	e.Name = "DropPart"
	e.Parent = ServerStorage
	dropEvent = e
end

local live = Instance.new("Folder")
live.Name = "TowerPartsLive"
live.Parent = workspace

type State = {
	name: string?, -- the part out (lying or carried)
	spot: BasePart?, -- where it lies / goes back to
	model: Model?, -- the copy in the world or on the carrier's back
	carrier: Player?,
	installed: { [string]: Model },
	usedSpots: { [BasePart]: boolean },
}

local state: State = { installed = {}, usedSpots = {} }
local blinkThread: thread? = nil

local function enabled(): boolean
	return CFG.Enabled == true and workspace:GetAttribute("Nights") == true
end

local function setAllParts(model: Model, fn: (BasePart) -> ())
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

local function copyOf(name: string): Model
	local model = (templates:FindFirstChild(name) :: Model):Clone()
	setAllParts(model, function(p)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
	end)
	return model
end

-- The cabinet's lamp for a part (Lamp1..Lamp4 in Parts.Order), if the cabinet is in.
local function lampFor(name: string): BasePart?
	local index = table.find(CFG.Order, name)
	local lamp = index and tower:FindFirstChild("Lamp" .. index, true)
	return if lamp and lamp:IsA("BasePart") then lamp else nil
end

local function setLamp(name: string, on: boolean)
	local lamp = lampFor(name)
	if lamp then
		lamp.Material = Enum.Material.Neon
		lamp.Color = if on then CFG.LampOn else CFG.LampOff
	end
end

local function setTopLight(on: boolean)
	if blinkThread then
		task.cancel(blinkThread)
		blinkThread = nil
	end
	local light = topLight:FindFirstChildOfClass("PointLight")
	local function show(lit: boolean)
		topLight.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		topLight.Color = if lit then CFG.TopLight else Color3.fromRGB(60, 20, 18)
		if light then
			light.Brightness = if lit then 3 else 0
		end
	end
	show(false)
	if on then
		blinkThread = task.spawn(function()
			while true do
				show(true)
				task.wait(0.9)
				show(false)
				task.wait(0.9)
			end
		end)
	end
end

local function count(): number
	local n = 0
	for _ in state.installed do
		n += 1
	end
	return n
end

local function clearModel()
	if state.model then
		state.model:Destroy()
		state.model = nil
	end
	if state.carrier then
		local character = state.carrier.Character
		if character then
			character:SetAttribute("CarryingPart", nil)
		end
		state.carrier = nil
	end
end

local pickUp: (Player) -> ()

-- Lay the part out on its spot: glowing, with the prompt.
local function layOut()
	local name, spot = state.name, state.spot
	if not name or not spot then
		return
	end
	clearModel()
	local model = copyOf(name)
	model:PivotTo(spot.CFrame)
	local main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	local glow = Instance.new("PointLight")
	glow.Color = CFG.Glow
	glow.Range = 12
	glow.Brightness = 1.6
	glow.Parent = main
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = CFG.Glow
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player)
		pickUp(player)
	end)
	prompt.Parent = main
	model.Parent = live
	state.model = model
	workspace:SetAttribute("PartOut", name)
	workspace:SetAttribute("PartAt", spot.Position)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

pickUp = function(player: Player)
	local name, model = state.name, state.model
	local root = rootOf(player)
	if not name or not model or state.carrier or not root or PlayerHealth.IsDowned(player) then
		return
	end
	if (root.Position - model:GetPivot().Position).Magnitude > CFG.PickupRange then
		return
	end
	clearModel()
	local carried = copyOf(name)
	local _, size = carried:GetBoundingBox()
	carried:PivotTo(root.CFrame * CFrame.new(CFG.CarryOffset - Vector3.new(0, size.Y / 2, 0)))
	setAllParts(carried, function(p)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Anchored = false
	end)
	carried.Name = "CarriedPart"
	carried.Parent = player.Character
	state.model = carried
	state.carrier = player
	;(player.Character :: Model):SetAttribute("CarryingPart", name)
	workspace:SetAttribute("PartAt", nil)
	SoundKit.Play("Pickup/Ammo", { Position = root.Position })
end

-- Back on its spot (a catch, a death, a carrier leaving).
local function putBack(player: Player)
	if state.carrier == player and state.name then
		layOut()
	end
end

local function install()
	local name, carrier = state.name, state.carrier
	if not name or not carrier then
		return
	end
	clearModel()
	local model = copyOf(name)
	local slot = slots:FindFirstChild(name)
	model:PivotTo(if slot and slot:IsA("BasePart") then slot.CFrame else installPoint.CFrame)
	model.Parent = live
	state.installed[name] = model
	state.name = nil
	state.spot = nil
	setLamp(name, true)
	local n, need = count(), #CFG.Order
	workspace:SetAttribute("TowerParts", n)
	workspace:SetAttribute("PartOut", nil)
	workspace:SetAttribute("PartAt", nil)
	SoundKit.Play("Guns/AK/MagSeat", { Position = installPoint.Position, Volume = 1.5 })
	matchRemote:FireAllClients("PartIn", name, n, need)
	if n >= need then
		setTopLight(true)
		SoundKit.Play("Common/WaveClear", { Position = topLight.Position, Volume = 2 })
		matchRemote:FireAllClients("TowerDone")
	end
end

local function pickSpot(): BasePart?
	local fresh, any = {}, {}
	for _, s in spotsFolder:GetChildren() do
		if s:IsA("BasePart") then
			table.insert(any, s)
			if not state.usedSpots[s] then
				table.insert(fresh, s)
			end
		end
	end
	-- Someone's first ever match (MatchServer sets FirstMatch): the match's first part lies on the
	-- spot marked FirstMatch (the Shop, a short trip).
	if next(state.usedSpots) == nil then
		for _, p in game:GetService("Players"):GetPlayers() do
			if p:GetAttribute("InMatch") and p:GetAttribute("FirstMatch") then
				for _, s in any do
					if s:GetAttribute("FirstMatch") then
						return s
					end
				end
			end
		end
	end
	local list = if #fresh > 0 then fresh else any
	return if #list > 0 then list[math.random(#list)] else nil
end

local function onLull(lull: number)
	if not enabled() or state.name then
		return
	end
	local last = CFG.Lulls[#CFG.Lulls]
	if not table.find(CFG.Lulls, lull) and lull <= last then
		return
	end
	local nextName
	for _, name in CFG.Order do
		if not state.installed[name] then
			nextName = name
			break
		end
	end
	local spot = nextName and pickSpot()
	if not nextName or not spot then
		return
	end
	state.name = nextName
	state.spot = spot
	state.usedSpots[spot] = true
	layOut()
	matchRemote:FireAllClients("PartOut", nextName)
end

local function reset()
	clearModel()
	for _, model in state.installed do
		model:Destroy()
	end
	state = { installed = {}, usedSpots = {} }
	for _, name in CFG.Order do
		setLamp(name, false)
	end
	setTopLight(false)
	workspace:SetAttribute("TowerNeed", if CFG.Enabled then #CFG.Order else nil)
	workspace:SetAttribute("TowerParts", 0)
	workspace:SetAttribute("PartOut", nil)
	workspace:SetAttribute("PartAt", nil)
end

workspace:GetAttributeChangedSignal("WaveState"):Connect(function()
	local s = workspace:GetAttribute("WaveState")
	if s == "Waiting" then
		reset()
	elseif s == "Intermission" then
		local wave = workspace:GetAttribute("Wave")
		if typeof(wave) == "number" and wave >= 1 then
			onLull(wave)
		end
	end
end)

;(dropEvent :: BindableEvent).Event:Connect(function(player: Player)
	putBack(player)
end)

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.Died:Once(function()
			putBack(player)
		end)
	end
end

local function onPlayer(player: Player)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DebugPickUp"):Connect(function()
			if player:GetAttribute("DebugPickUp") and state.model and not state.carrier then
				local root = rootOf(player)
				if root then
					root.CFrame = state.model:GetPivot() + Vector3.new(0, 3, 0)
					pickUp(player)
				end
			end
			player:SetAttribute("DebugPickUp", nil)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		putBack(player)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(putBack)

-- The carrier reaching the cabinet.
local nextCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextCheck or not state.carrier then
		return
	end
	nextCheck = now + 0.2
	local root = rootOf(state.carrier)
	if not root then
		return
	end
	local d = root.Position - installPoint.Position
	if Vector3.new(d.X, 0, d.Z).Magnitude <= CFG.InstallRadius and math.abs(d.Y) < 8 then
		install()
	end
end)

reset()
