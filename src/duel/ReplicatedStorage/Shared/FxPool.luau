-- Recycles short-lived effect instances (casings, marks, blood drops, tracers, emitters) instead of making a new one
-- for every shot and destroying it after. Get hands back a parked one or makes one; Release parks it (a part far
-- below the map, anchored, still parented, so nothing re-replicates or re-registers) up to Max kept, past that it
-- is destroyed. Items may be instances or tables; kill(item) destroys a table item.

local PARK = CFrame.new(0, -5000, 0)

local FxPool = {}
FxPool.__index = FxPool
FxPool.Park = PARK

-- make() -> item; reset(item) parks it (optional; parts default to anchored at PARK); kill(item) for table items.
function FxPool.new(make, max, reset, kill)
	return setmetatable({ Make = make, Max = max or 100, Reset = reset, Kill = kill, Free = {} }, FxPool)
end

function FxPool:Get()
	return table.remove(self.Free) or self.Make()
end

function FxPool:Release(item)
	local isInstance = typeof(item) == "Instance"
	if isInstance and not item.Parent then
		return -- destroyed elsewhere (a mark on a part that broke)
	end
	if #self.Free >= self.Max then
		if isInstance then
			item:Destroy()
		elseif self.Kill then
			self.Kill(item)
		end
		return
	end
	if self.Reset then
		self.Reset(item)
	elseif isInstance and item:IsA("BasePart") then
		item.Anchored = true
		item.AssemblyLinearVelocity = Vector3.zero
		item.AssemblyAngularVelocity = Vector3.zero
		item.CFrame = PARK
	end
	table.insert(self.Free, item)
end

return FxPool
