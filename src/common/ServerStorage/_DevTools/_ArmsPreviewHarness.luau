-- Edit-mode preview of the pistol viewmodel and avatar arms in front of a fixed camera
-- at (0, 300, 0) looking -Z. Dev tool only; delete with workspace._ArmsPreview when done.
-- opts: Mode "hip" | "aim", ReloadT (0-1), Empty (bool).
return function(opts)
	local RS = game:GetService("ReplicatedStorage")
	local cached = require(RS.Shared.GameConfig)
	local fresh = require(RS.Shared.GameConfig:Clone())
	for k, v in fresh.ViewArms do
		cached.ViewArms[k] = v
	end
	for k, v in fresh.Guns.Pistol do
		cached.Guns.Pistol[k] = v
	end
	local ViewArms = require(game.StarterPlayer.StarterPlayerScripts.ViewArms:Clone())
	local gun = cached.Guns.Pistol

	local old = workspace:FindFirstChild("_ArmsPreview")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "_ArmsPreview"
	folder.Parent = workspace

	local function deg(v)
		return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
	end
	local function ease(t)
		return t * t * (3 - 2 * t)
	end
	local function sample(keys, name, t)
		local list = {}
		for _, k in keys do
			if k[name] ~= nil then
				table.insert(list, k)
			end
		end
		if #list == 0 then
			return nil
		end
		if t <= list[1].T then
			return list[1][name]
		end
		for i = 2, #list do
			if t <= list[i].T then
				local a, b = list[i - 1], list[i]
				return a[name] + (b[name] - a[name]) * ease(math.clamp((t - a.T) / math.max(b.T - a.T, 1e-4), 0, 1))
			end
		end
		return list[#list][name]
	end

	local C = CFrame.new(0, 300, 0)
	local vm = RS.Assets.ViewModels.Pistol:Clone()
	vm.Parent = folder
	local root = vm.PrimaryPart
	local aim = if opts.Mode == "aim" then 1 else 0
	local hipCF = CFrame.new(gun.HipOffset) * deg(gun.HipAngles)
	local aimCF = CFrame.new(0, 0, -gun.AimDistance) * root.AimPoint.CFrame:Inverse()

	local gunCF, handCF, slide, magMode = CFrame.identity, CFrame.identity, 0, "Gun"
	if opts.ReloadT then
		local keys = if opts.Empty then gun.ReloadAnim.Empty else gun.ReloadAnim.Tactical
		local t = opts.ReloadT
		gunCF = CFrame.new(sample(keys, "GunPos", t) or Vector3.zero) * deg(sample(keys, "GunRot", t) or Vector3.zero)
		local pivot = root.LeftGrip.Position
		handCF = CFrame.new(sample(keys, "HandPos", t) or Vector3.zero) * CFrame.new(pivot) * deg(sample(keys, "HandRot", t) or Vector3.zero) * CFrame.new(-pivot)
		slide = sample(keys, "Slide", t) or 0
		for _, k in keys do
			if k.T <= t and k.Mag then
				magMode = if k.Mag == "Drop" then "Hidden" else k.Mag
			end
		end
	end
	local rootCF = C * hipCF:Lerp(aimCF, aim) * gunCF
	local slideCF = CFrame.new(0, 0, slide * gun.SlideTravel)

	local parts, cfs = {}, {}
	for _, p in vm:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local group = p:GetAttribute("VmGroup")
			local offset = root.CFrame:ToObjectSpace(p.CFrame)
			local cf = rootCF * offset
			if group == "Slide" then
				cf = rootCF * slideCF * offset
			elseif group == "Mag" and magMode == "Hand" then
				local base = offset * Vector3.new(0, -p.Size.Y / 2, 0)
				cf = rootCF * handCF * CFrame.new(root.LeftGrip.Position - base) * offset
			end
			if group == "Mag" and magMode == "Hidden" then
				p.Transparency = 1
			end
			p.Anchored = true
			table.insert(parts, p)
			table.insert(cfs, cf)
		end
	end
	local rightGrip, leftGrip = root.RightGrip.CFrame, root.LeftGrip.CFrame
	workspace:BulkMoveTo(parts, cfs)
	root.CFrame = rootCF
	root.Transparency = 1

	local arms = ViewArms.new(game.ServerStorage._DevTools._ArmsPreviewRig, vm)
	arms:Update(C, rootCF * rightGrip, rootCF * handCF * leftGrip, aim)
	workspace.CurrentCamera.FieldOfView = cached.Camera.HipFov + (gun.AimFov - cached.Camera.HipFov) * aim

	local out = {}
	for _, n in { "RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm" } do
		local p = vm:FindFirstChild(n)
		local v = C:PointToObjectSpace(p.Position)
		table.insert(out, string.format("%s (%.2f,%.2f,%.2f) len %.2f", n, v.X, v.Y, v.Z, p.Size.Y))
	end
	return table.concat(out, "\n")
end
