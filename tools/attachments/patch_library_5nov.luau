-- One-off patch for an already-installed Assets.Attachments library (5 Nov 2026), so places installed before the
-- fixes match a fresh install_attachments.luau run. Safe to run twice. Edit mode.
--   MiniDot: body was 0.048 off the bore and the dot/sight sat above the window; centred, dot in the window.
--   Sniper8x: rings floated under the tube; each ring now reaches into the tube and gets a band around it.
local lib = game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("Attachments")
local out = {}

local M = lib:FindFirstChild("MiniDot")
if M and not M:GetAttribute("SightFixed") then
	local mp = M.PrimaryPart
	local sight = Vector3.new(0, 0.089, -0.06)
	for _, d in M:GetDescendants() do
		if d:IsA("BasePart") and d ~= mp then
			if d.Name == "Reticle" then
				d.CFrame = mp.CFrame * CFrame.new(sight)
			else
				d.CFrame = mp.CFrame * CFrame.new(-0.048, 0, 0) * mp.CFrame:ToObjectSpace(d.CFrame)
			end
		end
	end
	mp.Sight.Position = sight
	M:SetAttribute("SightFixed", true)
	table.insert(out, "MiniDot fixed")
end

local S = lib:FindFirstChild("Sniper8x")
if S and not S:GetAttribute("RingsFixed") then
	local mp = S.PrimaryPart
	local axisY = mp.Sight.Position.Y
	for i = 1, 2 do
		local ring = S:FindFirstChild("Ring" .. i)
		if ring then
			local z = mp.CFrame:ToObjectSpace(ring.CFrame).Z
			local top = axisY - 0.04
			ring.Size = Vector3.new(ring.Size.X, top, ring.Size.Z)
			ring.CFrame = mp.CFrame * CFrame.new(0, top / 2, z)
			local band = ring:Clone()
			band.Name = "Band" .. i
			band.Shape = Enum.PartType.Cylinder
			band.Size = Vector3.new(0.056, 0.14, 0.14)
			band.CFrame = mp.CFrame * CFrame.new(0, axisY, z) * CFrame.Angles(0, math.pi / 2, 0)
			for _, c in band:GetChildren() do
				c:Destroy()
			end
			band.Parent = S
		end
	end
	S:SetAttribute("RingsFixed", true)
	table.insert(out, "Sniper8x rings fixed")
end
return table.concat(out, ", ")
