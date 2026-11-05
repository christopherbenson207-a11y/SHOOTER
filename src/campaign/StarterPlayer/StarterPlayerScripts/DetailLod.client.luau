-- Distance detail for map props (ROBLOX-OPTIMIZATION.md). A BasePart tagged "DetailLod" with a
-- number attribute LodFar (studs, at a 70 degree view) stops drawing past that distance: the loose
-- rounds in the MG nests' ammo boxes and the small bolts on the guns cost thousands of triangles
-- each and are a few pixels across from further off. Checked four times a second, not every frame.
local CollectionService = game:GetService("CollectionService")

local TAG = "DetailLod"
local INTERVAL = 0.25

local entries = {} -- [part] = { Far = studs, Hidden = bool }

local function add(inst)
	local far = inst:IsA("BasePart") and inst:GetAttribute("LodFar")
	if typeof(far) == "number" then
		entries[inst] = { Far = far, Hidden = false }
	end
end

for _, inst in CollectionService:GetTagged(TAG) do
	add(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	entries[inst] = nil
end)

while true do
	task.wait(INTERVAL)
	local cam = workspace.CurrentCamera
	if cam then
		local eye = cam.CFrame.Position
		-- Zoomed in (a scope), things count as nearer.
		local zoom = cam.FieldOfView / 70
		for part, e in entries do
			local hide = (part.Position - eye).Magnitude * zoom > e.Far
			if hide ~= e.Hidden then
				e.Hidden = hide
				part.LocalTransparencyModifier = if hide then 1 else 0
			end
		end
	end
end
