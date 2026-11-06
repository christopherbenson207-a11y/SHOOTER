-- The story of Operation Last Light (horror-shooter/war/WAR-V2-CONTRACTS.md). HOUND's transport is
-- shot down over the valley (Modules.CrashIntro). Captain HALE, HOUND's commander, is badly hurt in
-- the crash. The squad fights up the valley for medicine for him: morphine at the fuel depot, blood
-- at the town clinic by the plaza. It gets there too late and HALE dies. On the way to the LZ the
-- rest of HOUND is cut down one by one, and only the players get on the bird.
--   The casualty: HALE on a stretcher, a plain R15 laid on its back with a field dressing (anchored,
--   nothing collides or stops a ray), set down wherever the squad holds (Story.Carry).
--   Medicine: Story.Medicine puts a med case at one of a group's spots, a different one each run.
--   A player takes it and carries it to HALE; if they go down it drops where they fell. WarServer
--   runs the job in its warUntil and cleans it up after.
--   Lines: the radio text for the story's beats, by key (WarServer's say falls back to these).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundKit = require(ReplicatedStorage.Shared.SoundKit)

local Story = {}

Story.Commander = "HALE"

Story.Lines = {
	Wake = "HOUND, sound off! The bird's down. HALE's hit bad.",
	NeedMorphine = "Doc here. HALE's bleeding out. The depot up the road had a med station. Find me medicine.",
	Carried = "We're carrying HALE up behind you. Keep moving.",
	SearchMorphine = "Depot's ours. The medicine's in there somewhere, follow the marker.",
	Taken = "Got the meds. Get them to Doc, now!",
	Dropped = "The meds are down! Someone grab them!",
	MorphineIn = "Medicine's in. He's still bleeding inside. The clinic on the plaza will have blood.",
	SearchBlood = "Plaza's clear. Check the clinic, follow the marker. Blood bags, plasma, anything.",
	BloodIn = "Blood's going in. Come on, Captain, stay with me.",
	HaleDead = "He's gone. HALE's gone. We finish what he started.",
	NoHelp = "No more birds coming in for us. It's just HOUND now.",
	LastStand = "They're everywhere! Get to the pad, we'll hold them off!",
	Alone = "It's just you now. Get on that bird.",
}

local MED_WHITE = Color3.fromRGB(214, 216, 210)
local MED_GREEN = Color3.fromRGB(46, 140, 72)
local CANVAS = Color3.fromRGB(86, 92, 62)
local POLE = Color3.fromRGB(58, 52, 44)

local folder = nil
local hale = nil -- { Model, Prompt, Cover, Dead }

local function root()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "Story"
		folder.Parent = workspace
	end
	return folder
end

local function block(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local roomParams = OverlapParams.new()
roomParams.FilterType = Enum.RaycastFilterType.Exclude
roomParams.RespectCanCollide = true

-- What the ground and room checks look through: the story's own parts, soldiers, effects, players.
local function ignoreList()
	local list = { root() }
	for _, name in { "Squad", "Hostiles", "Fx" } do
		table.insert(list, workspace:FindFirstChild(name))
	end
	for _, p in Players:GetPlayers() do
		table.insert(list, p.Character)
	end
	return list
end

-- The floor under pos. The ray starts only 2.5 studs up: from higher it found the ROOF of the depot
-- office and the pharmacy (4 Nov 2026), and the medicine sat up there out of reach.
local function ground(pos)
	groundParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(pos + Vector3.new(0, 2.5, 0), Vector3.new(0, -30, 0), groundParams)
	return if hit then hit.Position else pos
end

-- Open ground for the stretcher near pos (lying along look): the nearest spot, out in rings 3 studs
-- apart, with nothing solid in the box it lies in and about level with pos.
local function openGround(pos, look)
	local turn = if look.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, look) else CFrame.identity
	roomParams.FilterDescendantsInstances = ignoreList()
	local first = nil
	for ring = 0, 4 do
		local count = if ring == 0 then 1 else 8
		for i = 1, count do
			local a = i / count * math.pi * 2
			local g = ground(pos + Vector3.new(math.cos(a), 0, math.sin(a)) * ring * 3)
			first = first or g
			local box = CFrame.new(g + Vector3.new(0, 1.9, 0)) * turn
			if math.abs(g.Y - pos.Y) < 4 and #workspace:GetPartBoundsInBox(box, Vector3.new(4, 3, 8.5), roomParams) == 0 then
				return g
			end
		end
	end
	return first
end

local function standing(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and not c:GetAttribute("Downed")
end

-- HALE ------------------------------------------------------------------------------------------------

local function buildHale(at)
	local model = Instance.new("Model")
	model.Name = "HALE"
	local base = CFrame.new(at)
	-- The stretcher: two poles and the canvas between them, a hand's height off the snow.
	block(model, "Canvas", Vector3.new(2.3, 0.12, 6.4), base * CFrame.new(0, 0.55, 0), CANVAS, Enum.Material.Fabric)
	for _, x in { -1.2, 1.2 } do
		local pole = block(model, "Pole", Vector3.new(0.22, 0.22, 7.6), base * CFrame.new(x, 0.55, 0), POLE, Enum.Material.Wood)
		pole.Shape = Enum.PartType.Cylinder
		pole.Size = Vector3.new(7.6, 0.22, 0.22)
		pole.CFrame = base * CFrame.new(x, 0.55, 0) * CFrame.Angles(0, math.rad(90), 0)
	end
	for _, z in { -2.6, 2.6 } do
		for _, x in { -1.2, 1.2 } do
			block(model, "Leg", Vector3.new(0.2, 0.5, 0.2), base * CFrame.new(x, 0.25, z), POLE, Enum.Material.Wood)
		end
	end
	-- The captain, on his back, face up, head toward +Z.
	local lineup = ReplicatedStorage.Assets:FindFirstChild("AttireLineup")
	local source = lineup and (lineup:FindFirstChild("WoodlandSoldier") or lineup:FindFirstChildWhichIsA("Model"))
	if source then
		local body = source:Clone()
		body.Name = "Body"
		for _, d in body:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Constraint") or d:IsA("NoCollisionConstraint")
				or d:IsA("WrapTarget") or d:IsA("ValueBase") or d:IsA("HumanoidDescription") or d:IsA("BodyPartDescription")
				or d:IsA("FaceControls") or d:IsA("Status") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
		end
		local hum = body:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum.EvaluateStateMachine = false
		end
		local hrp = body:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Transparency = 1
			body.PrimaryPart = hrp
		end
		body:PivotTo(base * CFrame.new(0, 1.15, -0.2) * CFrame.Angles(math.rad(90), 0, 0))
		body.Parent = model
		local torso = body:FindFirstChild("UpperTorso") or body:FindFirstChild("Torso")
		if torso then
			-- A field dressing across the chest.
			block(model, "Dressing", Vector3.new(2.05, 0.5, 0.5), torso.CFrame * CFrame.new(0, -0.15, -0.3), MED_WHITE, Enum.Material.Fabric)
		end
	end
	local anchor = block(model, "Anchor", Vector3.new(2.4, 1.2, 6.4), base * CFrame.new(0, 1, 0), MED_WHITE)
	anchor.Transparency = 1
	model.PrimaryPart = anchor
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Give medicine"
	prompt.ObjectText = "Captain HALE"
	prompt.HoldDuration = 2.5
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	-- Shown even beside a door or crate prompt on the same key.
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Enabled = false
	prompt.Parent = anchor
	model.Parent = root()
	return { Model = model, Prompt = prompt, Dead = false }
end

-- HALE laid down on open ground near pos (head toward face), or moved there.
function Story.Carry(pos, face)
	local look = if face then Vector3.new(face.X - pos.X, 0, face.Z - pos.Z) else Vector3.new(0, 0, -1)
	local at = openGround(pos, look)
	local cf = if look.Magnitude > 0.1 then CFrame.lookAt(at, at + look) else CFrame.new(at)
	if not hale or not hale.Model.Parent then
		hale = buildHale(at)
	end
	hale.Model:PivotTo(cf * CFrame.new(0, 1, 0))
	return hale.Model
end

function Story.HalePosition()
	return hale and hale.Model.Parent and hale.Model.PrimaryPart.Position
end

-- HALE dies: a blanket over him and the prompt gone.
function Story.Die()
	if not hale or hale.Dead then
		return
	end
	hale.Dead = true
	hale.Prompt.Enabled = false
	local anchor = hale.Model.PrimaryPart
	block(hale.Model, "Blanket", Vector3.new(2.5, 0.35, 6.2), anchor.CFrame * CFrame.new(0, 0.55, 0), CANVAS, Enum.Material.Fabric)
	local body = hale.Model:FindFirstChild("Body")
	if body then
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Head" then
				d.Transparency = 1
			end
		end
	end
	local dressing = hale.Model:FindFirstChild("Dressing")
	if dressing then
		dressing:Destroy()
	end
end

function Story.HaleDead()
	return hale ~= nil and hale.Dead
end

-- Medicine ---------------------------------------------------------------------------------------------

local function buildCase(at)
	local model = Instance.new("Model")
	model.Name = "MedCase"
	local base = CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local box = block(model, "Case", Vector3.new(1.8, 0.9, 1.1), base * CFrame.new(0, 0.45, 0), MED_WHITE)
	block(model, "Band", Vector3.new(1.84, 0.22, 1.14), base * CFrame.new(0, 0.62, 0), MED_GREEN)
	block(model, "CrossA", Vector3.new(0.6, 0.06, 0.18), base * CFrame.new(0, 0.92, 0), MED_GREEN)
	block(model, "CrossB", Vector3.new(0.18, 0.06, 0.6), base * CFrame.new(0, 0.92, 0), MED_GREEN)
	block(model, "Handle", Vector3.new(0.7, 0.16, 0.16), base * CFrame.new(0, 1.0, 0), Color3.fromRGB(40, 40, 40))
	local glow = Instance.new("PointLight")
	glow.Color = MED_GREEN
	glow.Range = 9
	glow.Brightness = 0.9
	glow.Shadows = false
	glow.Parent = box
	model.PrimaryPart = box
	-- Seen through the walls of whatever it's hidden in, so the marker leads to something.
	local mark = Instance.new("Highlight")
	mark.FillColor = MED_GREEN
	mark.FillTransparency = 0.6
	mark.OutlineColor = Color3.fromRGB(235, 255, 240)
	mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	mark.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"
	prompt.ObjectText = "Medicine"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Parent = box
	model.Parent = root()
	return model, prompt
end

-- A search for medicine (what: "Medicine" or "Blood") hidden at one of spots (parts or Vector3s).
-- say(key) is WarServer's radio. Returns a job: job.Done() true once it has reached HALE, job.Target()
-- where the objective marker belongs and its words, job.Clean() removes the case.
function Story.Medicine(spots, what, say)
	local points = {}
	for _, s in spots do
		table.insert(points, if typeof(s) == "Vector3" then s else s.Position)
	end
	local pick = points[math.random(#points)] or Vector3.zero
	local job = { Carrier = nil, Delivered = false, What = what }
	-- exactly on the hand-placed spot (a random nudge put it through walls and outside)
	local at = ground(pick)
	if at.Y > pick.Y + 1.5 then
		warn("WarStory: medicine landed above its spot, using the spot", pick, at)
		at = pick
	end
	local case, takePrompt = buildCase(at)
	job.Case = case

	local function drop(at)
		job.Carrier = nil
		job.Dropped = true
		case:PivotTo(CFrame.new(ground(at) + Vector3.new(0, 0.45, 0)))
		case.Parent = root()
		takePrompt.Enabled = true
		if hale then
			hale.Prompt.Enabled = false
		end
	end

	takePrompt.Triggered:Connect(function(player)
		if job.Carrier or job.Delivered or not standing(player) then
			return
		end
		job.Carrier = player
		takePrompt.Enabled = false
		case.Parent = nil
		player:SetAttribute("CarryingMeds", what)
		SoundKit.Play("Pickup/Ammo", { Position = pick })
		if hale then
			hale.Prompt.ObjectText = "Captain HALE"
			hale.Prompt.ActionText = if what == "Blood" then "Give blood" else "Give medicine"
			hale.Prompt.Enabled = true
		end
		say("Taken")
	end)

	local haleConn = hale and hale.Prompt.Triggered:Connect(function(player)
		if player ~= job.Carrier or job.Delivered or not standing(player) then
			return
		end
		job.Delivered = true
		job.Carrier = nil
		player:SetAttribute("CarryingMeds", nil)
		hale.Prompt.Enabled = false
	end)

	function job.Done()
		local carrier = job.Carrier
		if carrier and (not carrier.Parent or not standing(carrier)) then
			local r = carrier.Character and carrier.Character:FindFirstChild("HumanoidRootPart")
			if carrier.Parent then
				carrier:SetAttribute("CarryingMeds", nil)
			end
			drop(if r then r.Position else pick)
			say("Dropped")
		end
		return job.Delivered
	end

	-- Where the marker goes and the line to show (nil keeps the step's own search line).
	function job.Target()
		if job.Carrier then
			local at = Story.HalePosition()
			return at and at + Vector3.new(0, 3, 0), "DELIVER THE " .. string.upper(what) .. " TO " .. Story.Commander
		end
		if job.Delivered then
			return nil
		end
		local box = case.PrimaryPart
		local at = box and box.Position + Vector3.new(0, 2.5, 0)
		return at, if job.Dropped then "PICK UP THE " .. string.upper(what) .. " AND GET IT TO " .. Story.Commander else nil
	end

	function job.Clean()
		if haleConn then
			haleConn:Disconnect()
		end
		if job.Carrier and job.Carrier.Parent then
			job.Carrier:SetAttribute("CarryingMeds", nil)
		end
		if hale then
			hale.Prompt.Enabled = false
		end
		case:Destroy()
	end

	return job
end

-- A new run: HALE at the crash site (pos), alive.
function Story.Start(pos, face)
	Story.Clear()
	Story.Carry(pos, face)
end

function Story.Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	hale = nil
	for _, p in Players:GetPlayers() do
		p:SetAttribute("CarryingMeds", nil)
	end
end

return Story
