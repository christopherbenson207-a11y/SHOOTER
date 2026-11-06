-- Builds the FlashHider and Choke attachment models out of plain parts (5 Nov 2026) into
-- ReplicatedStorage.Assets.Attachments, replacing any older ones. Run in Edit mode in every place that has the
-- library; install_attachments.luau carries the same builder, so a fresh install matches.
-- Why: the Toolbox flash hider was a union that the install rescale stretched, and it rendered on its side (bore
-- pointing up). Built here, the bore runs along -Z from the Mount at z = 0, like every other muzzle device.
-- Parts named Housing carry the Body tag, so camos cover them; the slots, ports and bore stay dark.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lib = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Attachments")

local METAL = Color3.fromRGB(42, 44, 46)
local DARK = Color3.fromRGB(8, 8, 9)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis is X; this turns it onto Z

local function part(model, name, shape, size, cf, color, body)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if body then Enum.Material.Metal else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	if body then
		p:AddTag("Body")
	end
	p.Parent = model
	return p
end

local function tube(model, name, length, dia, z, color, body)
	return part(model, name, Enum.PartType.Cylinder, Vector3.new(length, dia, dia), CFrame.new(0, 0, z) * ALONG_Z, color, body)
end

local function newModel(name)
	local old = lib:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	local mount = part(model, "Mount", Enum.PartType.Block, Vector3.new(0.05, 0.05, 0.05), CFrame.identity, Color3.new(1, 1, 1), false)
	mount.Material = Enum.Material.Plastic
	mount.Transparency = 1
	model.PrimaryPart = mount
	return model
end

local function finish(model, length, dia)
	model:SetAttribute("Length", length)
	model:SetAttribute("Height", dia)
	model:SetAttribute("Width", dia)
	model.Parent = lib
end

-- Flash hider: a short collar, then a birdcage body with four slots, open at the front.
do
	local m = newModel("FlashHider")
	tube(m, "Housing", 0.03, 0.07, -0.015, METAL, true)
	tube(m, "Housing", 0.09, 0.078, -0.075, METAL, true)
	for i = 0, 3 do
		local a = math.rad(45 + 90 * i)
		local r = 0.0375
		part(m, "Slot", Enum.PartType.Block, Vector3.new(0.014, 0.006, 0.06),
			CFrame.new(math.cos(a) * r, math.sin(a) * r, -0.088) * CFrame.Angles(0, 0, a + math.pi / 2), DARK, false)
	end
	tube(m, "Bore", 0.004, 0.044, -0.119, DARK, false)
	finish(m, 0.12, 0.078)
end

-- Choke: a knurled collar, then a longer tube with two port rings, slightly narrower at the front.
do
	local m = newModel("Choke")
	tube(m, "Housing", 0.025, 0.086, -0.0125, METAL, true)
	tube(m, "Housing", 0.075, 0.076, -0.0625, METAL, true)
	tube(m, "Housing", 0.03, 0.07, -0.115, METAL, true)
	tube(m, "Port", 0.008, 0.078, -0.055, DARK, false)
	tube(m, "Port", 0.008, 0.078, -0.08, DARK, false)
	tube(m, "Bore", 0.004, 0.05, -0.129, DARK, false)
	finish(m, 0.13, 0.086)
end

return "FlashHider and Choke built"
