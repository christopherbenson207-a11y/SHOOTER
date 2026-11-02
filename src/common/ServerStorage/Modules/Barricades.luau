-- Plank barricades (CollectionService tag "Breakable"). Mobs tear the boards (Wood or
-- WoodPlanks parts) off, BoardsPerRip at a time (Call of Duty Zombies' window boards); once no
-- board is left the rest of the barricade collapses and the way is open. A torn board is
-- hidden in place (attribute Torn) and a loose copy flies toward the mob, so Repair and
-- RepairOne can put the originals back. Numbers: GameConfig.Barricades.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Settings = GameConfig.Barricades

local Barricades = {}

local function parts(model)
	if model:IsA("BasePart") then
		return { model }
	end
	local list = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(list, p)
		end
	end
	return list
end

local function intact(part)
	return not part:GetAttribute("Torn")
end

local function isBoard(part)
	return part.Material == Enum.Material.WoodPlanks or part.Material == Enum.Material.Wood
end

-- Throws a loose copy of the part toward fromPos and hides the original.
local function tear(part, fromPos)
	local loose = part:Clone()
	loose:ClearAllChildren()
	for _, tag in loose:GetTags() do
		loose:RemoveTag(tag)
	end
	loose.Anchored = false
	loose.CanCollide = true
	loose.CanQuery = false
	loose.CanTouch = false
	loose.CollisionGroup = "Debris"
	loose.Parent = workspace
	local away = fromPos - part.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.zero
	loose.AssemblyLinearVelocity = away * Settings.ThrowSpeed * (0.7 + math.random() * 0.6) + Vector3.new(0, 6 + math.random() * 6, 0)
	loose.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14
	loose:SetNetworkOwner(nil)
	task.delay(Settings.DebrisTime, function()
		if loose.Parent then
			local fade = TweenService:Create(loose, TweenInfo.new(1), { Transparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			loose:Destroy()
		end
	end)

	part:SetAttribute("Torn", true)
	part:SetAttribute("RestTransparency", part.Transparency)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- A broken barricade costs paths nothing; a whole one costs "Break" (Navigation.Costs).
local function setPathLabel(model, label)
	for _, d in model:GetDescendants() do
		if d:IsA("PathfindingModifier") then
			d.Label = label
		end
	end
end

function Barricades.IsBroken(model)
	return model:GetAttribute("Broken") == true
end

-- Once no board is left the rest of the barricade falls.
local function collapseIfBare(model, fromPos)
	for _, p in parts(model) do
		if intact(p) and isBoard(p) then
			return false
		end
	end
	for _, p in parts(model) do
		if intact(p) then
			tear(p, fromPos)
		end
	end
	SoundKit.Play("World/PlankDrop", { Position = model:GetPivot().Position })
	model:SetAttribute("Broken", true)
	setPathLabel(model, "Open")
	return true
end

-- A bullet into one part of the barricade: it splinters, and once its health is gone it
-- is blown off along the shot. Returns true once the barricade is broken.
function Barricades.Shoot(model, part, hitPos, dir, damage)
	if Barricades.IsBroken(model) or not intact(part) then
		return Barricades.IsBroken(model)
	end
	local health = part:GetAttribute("ShotHealth") or Settings.BoardHealth
	health -= damage
	part:SetAttribute("ShotHealth", health)
	if health > 0 then
		return false
	end
	SoundKit.Play("World/WoodBreak", { Position = hitPos })
	-- tear() throws toward its point, so aim it past the board along the shot.
	tear(part, hitPos + dir * 6)
	return collapseIfBare(model, hitPos + dir * 6)
end

-- Tears the boards nearest fromPos off (BoardsPerRip). Returns true once the barricade is broken.
function Barricades.Rip(model, fromPos)
	if Barricades.IsBroken(model) then
		return true
	end
	for _ = 1, Settings.BoardsPerRip or 1 do
		local best, bestDist = nil, math.huge
		for _, p in parts(model) do
			if intact(p) and isBoard(p) then
				local d = (p.Position - fromPos).Magnitude
				if d < bestDist then
					best, bestDist = p, d
				end
			end
		end
		if not best then
			break
		end
		tear(best, fromPos)
	end
	SoundKit.Play("World/WoodBreak", { Position = model:GetPivot().Position })
	local left = false
	for _, p in parts(model) do
		if intact(p) and isBoard(p) then
			left = true
			break
		end
	end
	if not left then
		for _, p in parts(model) do
			if intact(p) then
				tear(p, fromPos)
			end
		end
		SoundKit.Play("World/PlankDrop", { Position = model:GetPivot().Position })
		model:SetAttribute("Broken", true)
		setPathLabel(model, "Open")
	end
	return not left
end

-- How many boards are torn off.
function Barricades.TornCount(model)
	local n = 0
	for _, p in parts(model) do
		if p:GetAttribute("Torn") then
			n += 1
		end
	end
	return n
end

-- Nails one torn board back on (the lowest first, so the way in closes fastest). Returns
-- the board, or nil if none was torn.
function Barricades.RepairOne(model)
	local best
	for _, p in parts(model) do
		if p:GetAttribute("Torn") and (not best or p.Position.Y < best.Position.Y) then
			best = p
		end
	end
	if not best then
		return nil
	end
	best.Transparency = best:GetAttribute("RestTransparency") or 0
	best.CanCollide = true
	best.CanQuery = true
	best.CanTouch = true
	best:SetAttribute("Torn", nil)
	best:SetAttribute("RestTransparency", nil)
	best:SetAttribute("ShotHealth", nil)
	if model:GetAttribute("Broken") then
		model:SetAttribute("Broken", nil)
		setPathLabel(model, "Break")
	end
	return best
end

-- Puts every torn board back.
function Barricades.Repair(model)
	for _, p in parts(model) do
		if p:GetAttribute("Torn") then
			p.Transparency = p:GetAttribute("RestTransparency") or 0
			p.CanCollide = true
			p.CanQuery = true
			p.CanTouch = true
			p:SetAttribute("Torn", nil)
			p:SetAttribute("RestTransparency", nil)
			p:SetAttribute("ShotHealth", nil)
		end
	end
	model:SetAttribute("Broken", nil)
	setPathLabel(model, "Break")
end

return Barricades
