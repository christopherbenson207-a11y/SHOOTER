-- Builds ReplicatedStorage.Assets.Attachments (scopes and gun attachments, 6 Nov 2026) from Toolbox models.
-- Run in Studio Edit (execute_luau or the command bar) in every place that shows guns: lobby, campaign, zombies.
--
-- First insert these free Toolbox models into workspace._AttachStaging (Studio MCP insert_asset, or the Toolbox),
-- named exactly:
--   P_M4M16Attach  8874490274      "M4A1/M16A4 Attachments" (misoessussy): Kobra, Aimpoint, ACOG, PEQ-15, grip
--   P_EXPS3        18950607637     "EXPS3 Holographic Sight" (Regole_CKC)
--   P_SuppPack     82775773095535  "Suppressor Pack" (JaredRocker1234567, credit The WarVet on Sketchfab)
--   P_SniperScope  13348411563     "Sniper scope" (Nashyguy12): Nightforce ATACR
--   P_MiniDot      14822819035     "Red dot sight with real red dot" (Flopparanu)
--   P_FlashHider   5625876991      (no longer used: FlashHider and Choke come from build_muzzle_devices.luau)
-- The script keeps only mesh parts (every script, texture, SurfaceAppearance and decal is dropped), repaints them in
-- the game's palette (owner rule: Toolbox assets retextured until unrecognisable), and saves one model per
-- attachment, at world-gun scale (the scale of Assets.WorldGuns; viewmodels scale them down in Shared.Attachments):
--   PrimaryPart "Mount": the point that sits on the gun (an optic's or grip's rail face, a muzzle device's back end),
--     identity rotation: the attachment points down -Z, up is +Y.
--   Attachment "Sight" on Mount (optics): the sight line. Aiming puts it dead centre.
--   Parts tagged "Body" take the player's camo (Shared.Camo); lenses and reticles are untagged.
-- Re-runnable: it replaces Assets.Attachments. Pass KEEP_STAGING = true to keep the raw inserts.

local KEEP_STAGING = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local staging = workspace:FindFirstChild("_AttachStaging")
assert(staging, "insert the Toolbox models into workspace._AttachStaging first")
local function need(name)
	local m = staging:FindFirstChild(name)
	assert(m, "missing workspace._AttachStaging." .. name)
	return m
end

local PAL = {
	Optic = { Color3.fromRGB(34, 36, 38), Enum.Material.Metal },
	Polymer = { Color3.fromRGB(28, 29, 31), Enum.Material.SmoothPlastic },
	Laser = { Color3.fromRGB(52, 55, 48), Enum.Material.SmoothPlastic },
	Can = { Color3.fromRGB(42, 44, 46), Enum.Material.Metal },
}
local LENS_COLOR = Color3.fromRGB(70, 112, 122)
local RETICLE = Color3.fromRGB(255, 52, 40)

local m4 = need("P_M4M16Attach"):FindFirstChild("M4A1", true)
assert(m4 and m4:FindFirstChild("Attachments"), "P_M4M16Attach: no M4A1.Attachments")
local att = m4.Attachments
local handle = m4:FindFirstChild("Handle")
-- The pack's M4 lies along world X, muzzle toward -X.
local M4_FRAME = CFrame.lookAt(handle.Position, handle.Position + Vector3.new(-1, 0, 0))
local supp = need("P_SuppPack"):FindFirstChild("Suppressor Pack") or need("P_SuppPack")

local function centreFrame(model, forward)
	local c = model:GetBoundingBox()
	return CFrame.lookAt(c.Position, c.Position + forward)
end

-- name, source, frame (world CFrame whose -Z is the attachment's front), mount mode, scale, palette,
-- sight (pre-scale, in the source frame relative to the bounding-box rules below; nil = none), lens test
local SPECS = {
	{ Name = "Kobra", Src = att.Optics["Kobra Sight"], Frame = M4_FRAME, Mount = "Bottom", Scale = 0.7, Pal = "Optic",
		LensNames = { ["Meshes/M4A1_Base.024 (1)"] = true }, SightFrom = "Meshes/M4A1_Base.024 (1)", Reticle = "Dot" },
	{ Name = "RedDot", Src = att.Optics["Aimpoint CompM4"], Frame = M4_FRAME, Mount = "Bottom", Scale = 0.7, Pal = "Optic",
		LensNames = {}, SightAxis = "Meshes/M4A1_Base.040 (1)", Reticle = "Dot" },
	{ Name = "ACOG", Src = att.Optics["Trijicon ACOG Scope"], Frame = M4_FRAME, Mount = "Bottom", Scale = 0.7, Pal = "Optic",
		LensNames = { ["Meshes/M4A1_Base.005 (1)"] = true }, SightAxis = "Meshes/M4A1_Base.035 (1)", Reticle = "Chevron" },
	{ Name = "Holo", Src = need("P_EXPS3"):FindFirstChildWhichIsA("Model") or need("P_EXPS3"), Frame = "Centre", Mount = "Bottom",
		Scale = 1.3, Pal = "Optic", LensNames = { Lense = true }, SightFrom = "Lense", Reticle = "Ring" },
	{ Name = "MiniDot", Src = need("P_MiniDot"), Frame = "Centre", Mount = "Bottom", Scale = 0.45, Pal = "Optic",
		LensNames = {}, SightAt = Vector3.new(0.109, 0.121, -0.135), Reticle = "Dot" }, -- window centre, measured by raycast 5 Nov
	{ Name = "Sniper8x", Src = need("P_SniperScope"):FindFirstChildWhichIsA("Model") or need("P_SniperScope"), Frame = "+X",
		Mount = "Bottom", Scale = 0.4, Pal = "Optic", Rings = true,
		LensNames = { LP_Nightforce_ATACR_4_20x50_F1_Back_Lens = true, LP_Nightforce_ATACR_4_20x50_F1_Front_Lens = true },
		SightAxis = "LP_Nightforce_ATACR_4_20x50_F1_Body" },
	{ Name = "Laser", Src = att["FlashLights/Lasers"]["AN/PEQ-15"], Frame = M4_FRAME, Mount = "Bottom", Scale = 0.55, Pal = "Laser",
		LensNames = {}, Emitter = true },
	{ Name = "VGrip", Src = att.ForeGrips["Vertical Grip"], Frame = M4_FRAME, Mount = "Top", Scale = 0.7, Pal = "Polymer", LensNames = {} },
	{ Name = "SuppRifle", Src = supp:FindFirstChild("Socom_4"), Frame = "+X", Mount = "Rear", Scale = 0.68, Pal = "Can", LensNames = {} },
	{ Name = "SuppPistol", Src = supp:FindFirstChild("Sec9mm_2"), Frame = "+X", Mount = "Rear", Scale = 0.75, Pal = "Can", LensNames = {} },
	{ Name = "SuppSniper", Src = supp:FindFirstChild("PBS5_3"), Frame = "+X", Mount = "Rear", Scale = 0.7, Pal = "Can", LensNames = {} },
	-- FlashHider and Choke are built from parts by build_muzzle_devices.luau (run it after this script).
}

local function plainPart(name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function tidy(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	if p:IsA("TriangleMeshPart") then
		p.CollisionFidelity = Enum.CollisionFidelity.Box
	end
	if p:IsA("MeshPart") then
		p.RenderFidelity = Enum.RenderFidelity.Automatic
	end
end

local function bounds(parts)
	local mn, mx = Vector3.one * 1e9, Vector3.one * -1e9
	for _, p in parts do
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = p.CFrame * Vector3.new(sx * p.Size.X / 2, sy * p.Size.Y / 2, sz * p.Size.Z / 2)
					mn = mn:Min(w)
					mx = mx:Max(w)
				end
			end
		end
	end
	return mn, mx
end

local function build(spec)
	local src = spec.Src
	assert(src, "missing source for " .. spec.Name)
	local frame = spec.Frame
	if frame == "+X" then
		frame = centreFrame(src, Vector3.new(1, 0, 0))
	elseif frame == "+Y" then
		frame = centreFrame(src, Vector3.new(0, 1, 0))
	elseif frame == "Centre" then
		frame = CFrame.new((src:GetBoundingBox()).Position)
	end
	local model = Instance.new("Model")
	model.Name = spec.Name
	local parts, seen, byName = {}, {}, {}
	local pal = PAL[spec.Pal]
	for _, s in src:GetDescendants() do
		if s:IsA("BasePart") and s.Name ~= "the real dot" then
			local key = (if s:IsA("MeshPart") then s.MeshId else s.Name) .. tostring(s.CFrame)
			if not seen[key] then
				seen[key] = true
				local p = s:Clone()
				p:ClearAllChildren() -- scripts, SurfaceAppearances, decals, textures: all Toolbox payload risks
				p.CFrame = frame:ToObjectSpace(s.CFrame)
				if p:IsA("MeshPart") then
					p.TextureID = ""
				elseif p:IsA("UnionOperation") then
					p.UsePartColor = true
				end
				local lens = spec.LensNames[s.Name] == true
				if lens then
					p.Name = "Lens"
					p.Material = Enum.Material.Glass
					p.Color = LENS_COLOR
					p.Transparency = 0.82
				else
					p.Name = "Housing"
					p.Color = pal[1]
					p.Material = pal[2]
					p.Transparency = 0
					p:AddTag("Body")
				end
				tidy(p)
				p.Parent = model
				table.insert(parts, p)
				byName[s.Name] = p
			end
		end
	end
	assert(#parts > 0, "no parts in " .. spec.Name)

	-- sight line (pre-scale, in the attachment's frame)
	local sight = nil
	if spec.SightFrom and byName[spec.SightFrom] then
		sight = byName[spec.SightFrom].Position
	elseif spec.SightAxis and byName[spec.SightAxis] then
		local a = byName[spec.SightAxis].Position
		sight = Vector3.new(a.X, a.Y, 0)
	elseif spec.SightAt then
		sight = spec.SightAt
	end

	-- scope rings: the Nightforce tube has none
	local mn, mx = bounds(parts)
	if spec.Rings then
		local axisY = sight and sight.Y or (mn.Y + mx.Y) / 2
		-- a block from the rail up into the tube, and a band around the tube, so nothing floats (raycast 5 Nov:
		-- the tube is about 0.15 in radius at the rings)
		local tubeR = 0.15
		local x = sight and sight.X or 0
		for i, z in { -0.55, 0.45 } do
			local bottom, top = axisY - 0.37, axisY - 0.1
			local ring = plainPart("Ring" .. i, Vector3.new(0.3, top - bottom, 0.14),
				CFrame.new(x, (bottom + top) / 2, z), pal[1], Enum.Material.Metal)
			ring:AddTag("Body")
			tidy(ring)
			ring.Parent = model
			table.insert(parts, ring)
			local band = plainPart("Band" .. i, Vector3.new(0.14, (tubeR + 0.025) * 2, (tubeR + 0.025) * 2),
				CFrame.new(x, axisY, z) * CFrame.Angles(0, math.pi / 2, 0), pal[1], Enum.Material.Metal)
			band.Shape = Enum.PartType.Cylinder
			band:AddTag("Body")
			tidy(band)
			band.Parent = model
			table.insert(parts, band)
		end
		mn, mx = bounds(parts)
	end

	local mid = (mn + mx) / 2
	local cx = if sight then sight.X else mid.X
	local mount
	if spec.Mount == "Bottom" then
		mount = Vector3.new(cx, mn.Y, mid.Z)
	elseif spec.Mount == "Top" then
		mount = Vector3.new(mid.X, mx.Y, mid.Z)
	else -- Rear: the back end, on the bore axis
		mount = Vector3.new(mid.X, mid.Y, mx.Z)
	end
	for _, p in parts do
		p.CFrame = CFrame.new(-mount) * p.CFrame
	end
	if sight then
		sight -= mount
	end

	local mountPart = plainPart("Mount", Vector3.new(0.05, 0.05, 0.05), CFrame.identity, Color3.new(1, 1, 1), Enum.Material.Plastic)
	mountPart.Transparency = 1
	tidy(mountPart)
	mountPart.Parent = model
	model.PrimaryPart = mountPart
	model:ScaleTo(spec.Scale)
	model:PivotTo(CFrame.identity)

	local s = spec.Scale
	if sight then
		local a = Instance.new("Attachment")
		a.Name = "Sight"
		a.Position = sight * s
		a.Parent = mountPart
		-- reticle: a dot (red dot, reflex, mini dot), dot and ring (holo), chevron post (ACOG)
		if spec.Reticle then
			local dot = plainPart("Reticle", Vector3.one * 0.012, CFrame.new(sight * s), RETICLE, Enum.Material.Neon)
			dot.Shape = Enum.PartType.Ball
			tidy(dot)
			dot.Parent = model
			if spec.Reticle == "Chevron" then
				local post = plainPart("ReticlePost", Vector3.new(0.004, 0.03, 0.004),
					CFrame.new(sight * s + Vector3.new(0, -0.021, 0)), RETICLE, Enum.Material.Neon)
				tidy(post)
				post.Parent = model
			elseif spec.Reticle == "Ring" then
				local holder = plainPart("ReticleRing", Vector3.new(0.07, 0.07, 0.001), CFrame.new(sight * s), RETICLE, Enum.Material.SmoothPlastic)
				holder.Transparency = 1
				tidy(holder)
				local gui = Instance.new("SurfaceGui")
				gui.Name = "Ring"
				gui.Face = Enum.NormalId.Back
				gui.CanvasSize = Vector2.new(128, 128)
				gui.LightInfluence = 0
				gui.Brightness = 2
				gui.Parent = holder
				local ring = Instance.new("Frame")
				ring.Name = "Ring"
				ring.AnchorPoint = Vector2.new(0.5, 0.5)
				ring.Position = UDim2.fromScale(0.5, 0.5)
				ring.Size = UDim2.fromScale(0.86, 0.86)
				ring.BackgroundTransparency = 1
				ring.Parent = gui
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = ring
				local stroke = Instance.new("UIStroke")
				stroke.Color = RETICLE
				stroke.Thickness = 5
				stroke.Parent = ring
				holder.Parent = model
			end
		end
	end
	if spec.Emitter then
		local m2, x2 = bounds((function()
			local t = {}
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") and p.Name == "Housing" then
					table.insert(t, p)
				end
			end
			return t
		end)())
		local e = plainPart("Emitter", Vector3.one * 0.03, CFrame.new((m2.X + x2.X) / 2 + 0.05, (m2.Y + x2.Y) / 2, m2.Z - 0.004),
			RETICLE, Enum.Material.Neon)
		e.Shape = Enum.PartType.Ball
		tidy(e)
		e.Parent = model
	end
	local mn2, mx2 = bounds((function()
		local t = {}
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.Name ~= "Mount" then
				table.insert(t, p)
			end
		end
		return t
	end)())
	model:SetAttribute("Length", mx2.Z - mn2.Z)
	model:SetAttribute("Height", mx2.Y - mn2.Y)
	model:SetAttribute("Width", mx2.X - mn2.X)
	return model
end

local assets = ReplicatedStorage:FindFirstChild("Assets")
assert(assets, "ReplicatedStorage.Assets missing")
local folder = Instance.new("Folder")
folder.Name = "Attachments"
folder:SetAttribute("Credits", "Toolbox: misoessussy (8874490274), Regole_CKC (18950607637), JaredRocker1234567 / "
	.. "The WarVet (82775773095535), Nashyguy12 (13348411563), Flopparanu (14822819035), Verystupid_stickman (5625876991). "
	.. "Retextured by install_attachments.luau.")
local report = {}
for _, spec in SPECS do
	local model = build(spec)
	model.Parent = folder
	table.insert(report, string.format("%s %d parts, %.2f x %.2f x %.2f", spec.Name, #model:GetChildren(),
		model:GetAttribute("Width"), model:GetAttribute("Height"), model:GetAttribute("Length")))
end
local old = assets:FindFirstChild("Attachments")
if old then
	old:Destroy()
end
folder.Parent = assets
if not KEEP_STAGING then
	staging:Destroy()
end
return table.concat(report, "\n")
